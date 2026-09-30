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
[ -e "$log_dir/format.since" ]
# A start line is written before the hook runs, and the end line after it.
[ "$(wc -l < "$log_dir/format.jsonl" | tr -d ' ')" -eq 2 ]
head -n 1 "$log_dir/format.jsonl" | grep -F '"event":"PostToolUse","status":"start"}'
tail -n 1 "$log_dir/format.jsonl" | grep -F '"event":"PostToolUse","status":"ok","exit":0'

# Recording start is per hook: a hook wrapped later gets its own marker, and an existing
# marker is never refreshed by later firings.
touch -t 202001010000 "$log_dir/format.since"
printf '%s' "$input" | run_wrapped format "$fake_hook" 0 > /dev/null 2>&1
[ -n "$(find "$log_dir/format.since" -mmin +1440)" ]
[ ! -e "$log_dir/guard.since" ]

# Exit 2 (a deliberate block) is returned as-is and is not an error.
set +e
printf '%s' "$input" | run_wrapped guard "$fake_hook" 2 > /dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 2 ]
tail -n 1 "$log_dir/guard.jsonl" | grep -F '"status":"block","exit":2'
[ -e "$log_dir/guard.since" ]

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
# With SIGPIPE at its default the writer just dies silently, so the case is only meaningful
# where SIGPIPE is ignored and the write fails with EPIPE instead.
big_input=$(python3 -c 'import json; print(json.dumps({"hook_event_name":"PreToolUse","x":"y"*300000}))')
( trap '' PIPE; printf '%s' "$big_input" | run_wrapped quiet true > "$tmp_dir/out" 2> "$tmp_dir/err" )
[ ! -s "$tmp_dir/out" ]
[ ! -s "$tmp_dir/err" ]
tail -n 1 "$log_dir/quiet.jsonl" | grep -F '"event":"PreToolUse","status":"ok"'

# Terminating the wrapper (a hook timeout) stops the wrapped hook too, records a killed line,
# and the wrapper dies of the same signal, as the unwrapped hook would. The wrapper is started
# from python with default signal dispositions, as Claude Code starts hooks: a background job
# of this script would inherit INT ignored, which no trap can undo.
run_killed() {
  CLAUDE_PROJECT_DIR="$project_dir" AIDD_TEST_STATE_DIR="$state_dir" python3 - "$1" "$wrapper" "$2" "$tmp_dir/marker-$2" "$input" <<'EOF'
import os, signal, subprocess, sys, time
sig, wrapper, hook_id, marker, data = sys.argv[1:]
signal.signal(signal.SIGINT, signal.SIG_DFL)
p = subprocess.Popen(["bash", wrapper, hook_id, "bash", "-c", "sleep 2; touch '%s'" % marker],
                     stdin=subprocess.PIPE)
p.stdin.write(data.encode())
p.stdin.close()
time.sleep(0.5)
p.send_signal(getattr(signal, "SIG" + sig))
rc = p.wait()
time.sleep(2.5)
sys.exit(0 if rc == -getattr(signal, "SIG" + sig) and not os.path.exists(marker) else 1)
EOF
}
run_killed TERM slow
head -n 1 "$log_dir/slow.jsonl" | grep -F '"status":"start"}'
tail -n 1 "$log_dir/slow.jsonl" | grep -F '"status":"killed","exit":143'
# bash starts background commands with INT ignored, so INT must still stop the hook.
run_killed INT interrupted
tail -n 1 "$log_dir/interrupted.jsonl" | grep -F '"status":"killed","exit":130'
run_killed HUP hangup
tail -n 1 "$log_dir/hangup.jsonl" | grep -F '"status":"killed","exit":129'

# SIGKILL can't be trapped: only the start line remains, so the audit still sees the firing.
printf '%s' "$input" | CLAUDE_PROJECT_DIR="$project_dir" AIDD_TEST_STATE_DIR="$state_dir" \
  bash "$wrapper" hard bash -c 'sleep 2' &
pid=$!
sleep 0.5
kill -KILL "$pid"
wait "$pid" 2>/dev/null || true
[ "$(wc -l < "$log_dir/hard.jsonl" | tr -d ' ')" -eq 1 ]
grep -F '"status":"start"}' "$log_dir/hard.jsonl"

# Concurrent firings that trim the same oversized log must not clobber each other's copy.
python3 -c 'import sys; open(sys.argv[1], "w").write(("{\"ts\":\"2020-01-01T00:00:00Z\",\"event\":\"E\",\"status\":\"error\",\"exit\":1,\"pad\":\"" + "p" * 300 + "\"}\n") * 1000)' "$log_dir/busy.jsonl"
for _ in $(seq 30); do
  printf '%s' "$input" | run_wrapped busy true > /dev/null 2>&1 &
done
wait
[ "$(wc -l < "$log_dir/busy.jsonl" | tr -d ' ')" -ge 1000 ]
[ -z "$(find "$log_dir" -name 'busy.jsonl.*')" ]

# One key per repository: a hook run from a worktree session, one from the main checkout,
# and /aidd:asset-audit's own snippet (no CLAUDE_PROJECT_DIR, cwd in the worktree) agree.
git_env=(env -u CLAUDE_PROJECT_DIR GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1)
repo="$tmp_dir/repo"
mkdir -p "$repo"
"${git_env[@]}" git -C "$repo" init -q
"${git_env[@]}" git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
"${git_env[@]}" git -C "$repo" worktree add -q "$tmp_dir/wt"
wt_state="$tmp_dir/wt-state"
printf '%s' "$input" | CLAUDE_PROJECT_DIR="$repo" AIDD_TEST_STATE_DIR="$wt_state" bash "$wrapper" a true
printf '%s' "$input" | CLAUDE_PROJECT_DIR="$tmp_dir/wt" AIDD_TEST_STATE_DIR="$wt_state" bash "$wrapper" b true
(cd "$tmp_dir/wt/" && printf '%s' "$input" | env -u CLAUDE_PROJECT_DIR AIDD_TEST_STATE_DIR="$wt_state" bash "$wrapper" c true)
[ "$(find "$wt_state/projects" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" -eq 1 ]
wt_key=$(basename "$(find "$wt_state/projects" -mindepth 1 -maxdepth 1)")
audit_md="$repo_root/commands/asset-audit.md"
[ "$(grep -cF 'rev-parse --path-format=absolute --git-common-dir' "$audit_md")" -eq 2 ]
audit_key=$(cd "$tmp_dir/wt" && env -u CLAUDE_PROJECT_DIR bash -c "$(awk '/^project_root=/{p=1} p{print} /^project_key=/{exit}' "$audit_md"); printf '%s' \"\$project_key\"")
[ "$audit_key" = "$wt_key" ]

# The audit's step 2 counts only failures within the interval (an old error no longer keeps
# the hook a fix candidate) and reports start lines that no end line follows.
fake_home="$tmp_dir/home"
audit_log_dir="$fake_home/.claude/aidd/projects/$wt_key/hook-log"
mkdir -p "$audit_log_dir"
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > "$audit_log_dir/lint.jsonl" <<EOF
{"ts":"2020-01-01T00:00:00Z","event":"PostToolUse","status":"error","exit":1}
{"ts":"$now","event":"PostToolUse","status":"start"}
{"ts":"$now","event":"PostToolUse","status":"error","exit":1}
{"ts":"$now","event":"PostToolUse","status":"start"}
{"ts":"$now","event":"PostToolUse","status":"start"}
{"ts":"$now","event":"PostToolUse","status":"killed","exit":143}
EOF
step2=$(awk '/^\*\*2\./{p=1} p && /^```bash/{q=1; next} q && /^```/{exit} q{print}' "$audit_md")
(cd "$tmp_dir/wt" && env -u CLAUDE_PROJECT_DIR HOME="$fake_home" AIDD_AUDIT_INTERVAL_DAYS=08 bash -c "$step2") |
  grep -Fx 'lint.jsonl error=1 killed=1 unpaired_start=1'

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
