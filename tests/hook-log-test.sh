#!/bin/bash
# Contract for templates/aidd-hook-log.sh: it records a consumer hook's firing without
# changing what the hook does (stdin, stdout, stderr, exit code).
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
wrapper="$repo_root/templates/aidd-hook-log.sh"
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

[ -x "$wrapper" ]

project_dir="$tmp_dir/my project"
mkdir -p "$project_dir"
state_dir="$tmp_dir/aidd"
project_key=$(printf '%s' "$project_dir" | tr -c 'A-Za-z0-9' '-')
log_dir="$state_dir/projects/$project_key/hook-log"

# A fake consumer hook: echoes stdin to stdout, writes a marker to stderr, exits with $1.
fake_hook="$tmp_dir/fake-hook.sh"
cat > "$fake_hook" <<'EOF'
#!/bin/bash
cat
echo "hook-stderr" >&2
exit "$1"
EOF
chmod +x "$fake_hook"

run_wrapped() {
  local id=$1
  shift
  CLAUDE_PROJECT_DIR="$project_dir" AIDD_TEST_STATE_DIR="$state_dir" \
    bash "$wrapper" "$id" "$@"
}

input='{"hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{"file_path":"a b.txt"}}'

# stdout/stderr pass through byte-exact, including a trailing newline in stdin.
printf '%s\n\n' "$input" | run_wrapped format "$fake_hook" 0 > "$tmp_dir/out" 2> "$tmp_dir/err"
printf '%s\n\n' "$input" > "$tmp_dir/expected"
cmp "$tmp_dir/out" "$tmp_dir/expected"
[ "$(cat "$tmp_dir/err")" = "hook-stderr" ]
[ -e "$log_dir/.since" ]
tail -n 1 "$log_dir/format.jsonl" | grep -F '"event":"PostToolUse","status":"ok","exit":0'

# Exit 2 (a deliberate block) is returned as-is and is not an error.
set +e
printf '%s' "$input" | run_wrapped guard "$fake_hook" 2 > /dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 2 ]
tail -n 1 "$log_dir/guard.jsonl" | grep -F '"status":"block","exit":2'

# Any other non-zero exit is returned as-is and recorded as an error line.
set +e
printf '%s' "$input" | run_wrapped lint "$fake_hook" 1 > /dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 1 ]
tail -n 1 "$log_dir/lint.jsonl" | grep -F '"status":"error","exit":1'

# A missing hook command is a broken hook: error line, bash's 127 passed through.
set +e
printf '%s' "$input" | run_wrapped gone "$tmp_dir/does-not-exist.sh" > /dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 127 ]
grep -F '"status":"error","exit":127' "$log_dir/gone.jsonl"

# A hook that exits without reading stdin must not gain a broken-pipe message from the wrapper.
big_input=$(python3 -c 'import json; print(json.dumps({"hook_event_name":"PreToolUse","x":"y"*300000}))')
printf '%s' "$big_input" | run_wrapped quiet true > "$tmp_dir/out" 2> "$tmp_dir/err"
[ ! -s "$tmp_dir/out" ]
[ ! -s "$tmp_dir/err" ]
tail -n 1 "$log_dir/quiet.jsonl" | grep -F '"event":"PreToolUse","status":"ok"'

# The hook id becomes a file name, so path characters are neutralized.
printf '%s' "$input" | run_wrapped '../escape' "$fake_hook" 0 > /dev/null 2>&1
[ ! -e "$state_dir/projects/$project_key/escape.jsonl" ]
[ -e "$log_dir/.._escape.jsonl" ]

# Opt-out: the hook still runs unchanged, nothing is recorded.
rm -rf "$state_dir"
out=$(printf '%s' "$input" | AIDD_DISABLE_HOOK_LOG=1 run_wrapped format "$fake_hook" 0 2>/dev/null)
[ "$out" = "$input" ]
[ ! -e "$state_dir" ]

# Misuse (no command to wrap) fails non-blocking (exit 1, not 2).
set +e
printf '%s' "$input" | bash "$wrapper" only-id > /dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 1 ]
