#!/bin/bash
# Contract test for the auto memory intake of /aidd:incident-retro (#105): run the listing snippet
# from skills/incident-retro/SKILL.md against a fake memory directory, then write the observations
# through scripts/learnings.py and check that candidates alone counts them: another session's
# imported observation counts only once merged, and a re-import adds no count. No real memory is read.
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
skill="$repo_root/skills/incident-retro/SKILL.md"
script="$repo_root/scripts/learnings.py"
# An explicit template keeps TMPDIR honored (macOS mktemp -d alone ignores it).
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/aidd-memory-intake-test.XXXXXX")
tmp_dir=$(cd "$tmp_dir" && pwd -P)
trap 'rm -rf "$tmp_dir"' EXIT

# --- the listing snippet: feedback files with a UUID originSessionId only, frontmatter only -----
# The config dir path holds a quote: the snippet takes the path inside Python, never via the shell.
config="$tmp_dir/cfg'q"
memory="$config/projects/-fake-project/memory"
mkdir -p "$memory" "$tmp_dir/outside"
sed -n '/^# auto memory intake: list feedback memories/,/^PY$/p' "$skill" > "$tmp_dir/list.sh"
grep -Fq '<memory-dir>' "$tmp_dir/list.sh" || { echo "listing snippet not found in $skill" >&2; exit 1; }
run_listing() {  # run_listing MEMORY_DIR -> stdout; stderr to $tmp_dir/list.err
  python3 -c 'import sys; print(open(sys.argv[1]).read().replace("<memory-dir>", sys.argv[2]), end="")' \
    "$tmp_dir/list.sh" "$1" > "$tmp_dir/list-run.sh"
  CLAUDE_CONFIG_DIR="$config" bash "$tmp_dir/list-run.sh" 2> "$tmp_dir/list.err"
}

cur=11111111-1111-4111-8111-111111111111
sess_a=aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa
sess_b=bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb
memory_file() {  # memory_file PATH FRONTMATTER_LINES...
  local path=$1
  shift
  { printf -- '---\n'; printf '%s\n' "$@"; printf -- '---\n\nBODY_SENTINEL do not print this.\n'; } > "$path"
}
printf '%s\n' '- [x](fb-nested.md) — BODY_SENTINEL' > "$memory/MEMORY.md"
# The nested shape seen in this environment, and the top-level shape the docs describe.
memory_file "$memory/fb-nested.md" 'name: a' 'description: b' 'metadata:' '  node_type: memory' '  type: feedback' \
  "  originSessionId: $sess_b"
memory_file "$memory/fb-old.md" 'name: c' 'metadata:' '  type: feedback' "  originSessionId: $sess_a"
memory_file "$memory/fb-top.md" 'name: d' 'type: feedback' "originSessionId: $cur"
# Feedback without a usable originSessionId: not taken in, counted on stderr without its name.
memory_file "$memory/fb-nokey-1.md" 'name: e' 'type: feedback'
memory_file "$memory/fb-nokey-2.md" 'name: f' 'metadata:' '  type: feedback'
memory_file "$memory/fb-inject.md" 'type: feedback' "originSessionId: x'; touch $tmp_dir/pwned; '"
memory_file "$memory/fb-upper.md" 'type: feedback' 'originSessionId: AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA'
# Keys deeper than metadata:, or inside a block scalar, are not frontmatter keys.
memory_file "$memory/deep-scalar.md" 'name: g' 'description: |' '  type: feedback' "  originSessionId: $sess_b"
memory_file "$memory/deep-meta.md" 'name: h' 'metadata:' '  notes:' '    type: feedback' \
  "    originSessionId: $sess_b" '  node_type: memory'
memory_file "$memory/other-map.md" 'name: i' 'extra:' '  type: feedback' "  originSessionId: $sess_b"
memory_file "$memory/proj.md" 'name: j' 'metadata:' '  type: project' "  originSessionId: $sess_b"
memory_file "$memory/user.md" 'name: k' 'type: user' "originSessionId: $sess_b"
printf '%s\n' 'type: feedback' 'BODY_SENTINEL no frontmatter.' > "$memory/nofm.md"
printf '%s\n' '---' 'type: feedback' "originSessionId: $sess_b" 'BODY_SENTINEL never closed.' > "$memory/open.md"
printf '%s\n' '---' 'type: feedback' "originSessionId: $sess_b" '---' > "$memory/notes.txt"
# Entries that could forge a line, point outside, or repeat a file through a link: skipped and counted (4).
memory_file "$memory/tab	name.md" 'type: feedback' "originSessionId: $sess_b"
memory_file "$memory/new
line.md" 'type: feedback' "originSessionId: $sess_b"
memory_file "$tmp_dir/outside/target.md" 'type: feedback' "originSessionId: $sess_b"
ln -s "$tmp_dir/outside/target.md" "$memory/link.md"
ln -s fb-nested.md "$memory/link-inside.md"

listing=$(run_listing "$memory")
expected=$(printf '%s\t%s\n' \
  "$sess_b" "$memory/fb-nested.md" \
  "$sess_a" "$memory/fb-old.md" \
  "$cur" "$memory/fb-top.md")
if [ "$listing" != "$expected" ]; then
  printf 'listing snippet output differs.\n--- got\n%s\n--- expected\n%s\n' "$listing" "$expected" >&2
  exit 1
fi
grep -Eq '^4 feedback memories have no originSessionId in the UUID form' "$tmp_dir/list.err" \
  || { echo "listing snippet did not report 4 memories without a usable ID: $(cat "$tmp_dir/list.err")" >&2; exit 1; }
grep -Eq '^4 entries are skipped' "$tmp_dir/list.err" \
  || { echo "listing snippet did not report 4 skipped entries: $(cat "$tmp_dir/list.err")" >&2; exit 1; }
if grep -Fq BODY_SENTINEL <<<"$listing$(cat "$tmp_dir/list.err")" || grep -Fq -e "$memory" -e '.md' "$tmp_dir/list.err"; then
  echo "listing snippet printed a memory body or the name of a skipped memory" >&2
  exit 1
fi
[ ! -e "$tmp_dir/pwned" ]

# A directory outside <config dir>/projects/<name>/memory is not read at all.
mkdir -p "$tmp_dir/elsewhere/memory"
cp "$memory/fb-nested.md" "$tmp_dir/elsewhere/memory/"
if out=$(run_listing "$tmp_dir/elsewhere/memory"); then
  echo "listing snippet read a directory outside the auto memory layout" >&2
  exit 1
fi
[ -z "$out" ] && grep -Fq 'not an auto memory directory' "$tmp_dir/list.err"
key_of() { awk -F '\t' -v f="$memory/$1" '$2 == f {print $1}' <<<"$listing"; }

# --- a ledger with one merged observation from session A -------------------------------------
export GIT_CONFIG_NOSYSTEM=1 HOME="$tmp_dir/home"
mkdir -p "$HOME"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
repo="$tmp_dir/repo"
git init -q --template= -b main "$repo"
git -C "$repo" commit -q --allow-empty -m 'chore: base'
git -C "$repo" config aidd.learnings true
learnings() { python3 -I "$script" "$1" --repo "$repo" "${@:2}"; }
observation() {  # observation SOURCE SIGNATURE
  python3 -c '
import json, sys
print(json.dumps({"source": sys.argv[1], "scope": "tool", "status": "observed",
                  "signature": sys.argv[2], "fact": "A plain observation for the test.", "evidence": []}))
' "$1" "$2"
}
merge() { git -C "$repo" add .aidd/learnings && git -C "$repo" commit -qm 'docs: ledger'; }
observation incident-retro 'git stash' | learnings add --session-id "$sess_a" > /dev/null
merge

sessions_of() {  # sessions_of FILE SIGNATURE -> sessions count (0 when absent)
  python3 -c '
import json, sys
for line in open(sys.argv[1], encoding="utf-8"):
    row = json.loads(line)
    if row["signature"] == sys.argv[2]:
        print(row["sessions"]); break
else:
    print(0)
' "$1" "$2"
}

# The signatures the model would give each listed memory.
sig_of() {
  case $1 in
    fb-nested.md | fb-old.md) echo 'git stash' ;;
    fb-top.md) echo 'Edit' ;;
  esac
}

# --- write the approved memory observations with their own session ---------------------------
for name in fb-nested.md fb-old.md fb-top.md; do
  path=$(observation auto-memory "$(sig_of "$name")" | learnings add --session-id "$(key_of "$name")")
  python3 -I - "$repo/$path" "$memory" "$(key_of "$name")" <<'PYEOF'
import json, sys
raw = open(sys.argv[1], encoding="utf-8").read()
data = json.loads(raw)
assert data["source"] == "auto-memory" and data["evidence"] == [], data
assert sys.argv[2] not in raw and sys.argv[3] not in raw, "a memory path or raw session ID reached the ledger"
PYEOF
done

# --- candidates is the only counter --------------------------------------------------------------
# Before merge, the memory from session B is someone else's unmerged observation: git stash stays at
# one session (A, also the session of fb-old), so it is not a candidate yet.
learnings candidates --session-id "$cur" --signature 'gh pr create --fill' > "$tmp_dir/c1"
if grep -Fq '"git stash"' "$tmp_dir/c1"; then
  echo "an unmerged memory observation from another session was counted" >&2
  exit 1
fi
learnings candidates --all --session-id "$cur" > "$tmp_dir/c1all"
[ "$(sessions_of "$tmp_dir/c1all" 'git stash')" -eq 1 ]
# A memory written in this session counts as this session's observation.
[ "$(sessions_of "$tmp_dir/c1all" 'Edit')" -eq 1 ]

# Once merged, it counts: git stash is in sessions A and B.
merge
learnings candidates --session-id 22222222-2222-4222-8222-222222222222 > "$tmp_dir/c2"
grep -F '"signature": "git stash"' "$tmp_dir/c2"
[ "$(sessions_of "$tmp_dir/c2" 'git stash')" -eq 2 ]

# Importing the same memory again adds a file but no count (same session).
observation auto-memory 'git stash' | learnings add --session-id "$(key_of fb-nested.md)" > /dev/null
merge
learnings candidates --all > "$tmp_dir/c3"
[ "$(sessions_of "$tmp_dir/c3" 'git stash')" -eq 2 ]

echo "incident-retro memory intake test passed"
