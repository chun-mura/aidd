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
trap 'chmod -R u+rwx "$tmp_dir" 2>/dev/null; rm -rf "$tmp_dir"' EXIT

# --- the listing snippet: the memory directory is built inside the snippet, never copied --------
# The snippet finds <config dir>/projects/<key>/memory from the git common directory, so the test
# runs it inside a fake repository. The config dir path holds a quote, a Python triple quote, a
# command substitution and backquotes, none of which may run (a "pwned" file would appear).
export GIT_CONFIG_NOSYSTEM=1 HOME="$tmp_dir/home"
mkdir -p "$HOME"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
config="$tmp_dir/cfg'q\"\"\"\$(touch pwned)\`touch pwned\`"
# A non-ASCII letter and a character outside the BMP (two UTF-16 units) exercise the key rule.
proj="$tmp_dir/proj é😀"
git init -q --template= -b main "$proj"
git -C "$proj" commit -q --allow-empty -m 'chore: base'
key_for() {  # the key rule, computed independently: one "-" per UTF-16 unit of a non-alnum char
  python3 -c '
import sys
print("".join(c if c.isascii() and c.isalnum() else "-" * (len(c.encode("utf-16-le")) // 2)
              for c in sys.argv[1]))' "$1"
}
key=$(key_for "$proj")
[ "$key" = "$(key_for "$tmp_dir")-proj----" ] || { echo "unexpected key: $key" >&2; exit 1; }
memory="$config/projects/$key/memory"
mkdir -p "$memory" "$tmp_dir/outside"
sed -n '/^# auto memory intake: list feedback memories/,/^PY$/p' "$skill" > "$tmp_dir/list.sh"
grep -Fq 'python3 -I - <<' "$tmp_dir/list.sh" || { echo "listing snippet not found in $skill" >&2; exit 1; }
run_listing() {  # run_listing DIR [SHELL [CONFIG_DIR]] -> stdout; stderr to $tmp_dir/list.err
  (cd "$1" && env -u CLAUDE_PROJECT_DIR CLAUDE_CONFIG_DIR="${3:-$config}" "${2:-bash}" "$tmp_dir/list.sh" \
    2> "$tmp_dir/list.err")
}
expect_skip() {  # expect_skip DIR CONFIG_DIR REASON: exit 2, empty stdout, the reason, no path
  local status=0 out
  out=$(run_listing "$1" bash "$2") || status=$?
  if ! { [ "$status" -eq 2 ] && [ -z "$out" ] && grep -Fq -- "$3" "$tmp_dir/list.err"; }; then
    printf 'expected a skip (%s): status=%s out=%s err=%s\n' "$3" "$status" "$out" "$(cat "$tmp_dir/list.err")" >&2
    exit 1
  fi
  if grep -Fq "$tmp_dir" "$tmp_dir/list.err"; then
    echo "listing snippet printed a path on skip" >&2
    exit 1
  fi
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
# Unparsed (no frontmatter, never closed, BOM before ---) and unreadable files are counted.
printf '\xef\xbb\xbf---\ntype: feedback\noriginSessionId: %s\n---\n' "$sess_b" > "$memory/bom.md"
memory_file "$memory/unreadable.md" 'type: feedback' "originSessionId: $sess_b"
chmod 000 "$memory/unreadable.md"
# A trailing comment and quotes are removed from values, as asset-audit reads them.
sess_c=cccccccc-cccc-4ccc-8ccc-cccccccccccc
memory_file "$memory/cmt.md" 'type: feedback # a note' "originSessionId: \"$sess_c\""
# Entries that could forge a line, point outside, or repeat a file through a link: skipped and counted (4).
memory_file "$memory/tab	name.md" 'type: feedback' "originSessionId: $sess_b"
memory_file "$memory/new
line.md" 'type: feedback' "originSessionId: $sess_b"
memory_file "$tmp_dir/outside/target.md" 'type: feedback' "originSessionId: $sess_b"
ln -s "$tmp_dir/outside/target.md" "$memory/link.md"
ln -s fb-nested.md "$memory/link-inside.md"

listing=$(run_listing "$proj")
rows=$(printf '%s\t%s\n' \
  "$sess_c" "$memory/cmt.md" \
  "$sess_b" "$memory/fb-nested.md" \
  "$sess_a" "$memory/fb-old.md" \
  "$cur" "$memory/fb-top.md")
expected="$rows
scanned 17 file(s), 4 feedback (done)"
if [ "$listing" != "$expected" ]; then
  printf 'listing snippet output differs.\n--- got\n%s\n--- expected\n%s\n' "$listing" "$expected" >&2
  exit 1
fi
for line in '4 feedback memories have no originSessionId in the UUID form' '4 entries are skipped' \
    '1 file(s) could not be read' '3 file(s) have no frontmatter that opens and closes with ---'; do
  grep -Fq -- "$line" "$tmp_dir/list.err" \
    || { echo "listing snippet did not report '$line': $(cat "$tmp_dir/list.err")" >&2; exit 1; }
done
if grep -Fq BODY_SENTINEL <<<"$listing$(cat "$tmp_dir/list.err")" || grep -Fq -e "$memory" -e '.md' "$tmp_dir/list.err"; then
  echo "listing snippet printed a memory body or the name of a skipped memory" >&2
  exit 1
fi
[ ! -e "$proj/pwned" ] && [ ! -e "$tmp_dir/pwned" ]
# zsh (the default shell on macOS) runs the snippet the same way.
if command -v zsh > /dev/null; then
  [ "$(run_listing "$proj" zsh)" = "$expected" ] || { echo "listing snippet differs under zsh" >&2; exit 1; }
fi
# A worktree and a subdirectory of the repository share the one memory directory.
git -C "$proj" worktree add -q "$tmp_dir/wt" -b wt
mkdir -p "$proj/sub"
[ "$(run_listing "$tmp_dir/wt")" = "$expected" ] || { echo "a worktree did not reach the same memory" >&2; exit 1; }
[ "$(run_listing "$proj/sub")" = "$expected" ] || { echo "a subdirectory did not reach the same memory" >&2; exit 1; }

# A config dir holding a newline, the old heredoc delimiter and a command, or a tab: nothing is
# read and nothing runs.
for bad in "$tmp_dir/cfg
AIDD_MEMORY_DIR_END
touch pwned" "$tmp_dir/cfg	tab"; do
  mkdir -p "$bad/projects/$key/memory"
  cp "$memory/fb-nested.md" "$memory/MEMORY.md" "$bad/projects/$key/memory/"
  expect_skip "$proj" "$bad" 'holds a control or format character; intake skipped'
  [ ! -e "$proj/pwned" ] && [ ! -e "$tmp_dir/pwned" ]
done

# Outside git, a common directory not ending in .git, no directory, no MEMORY.md, a directory
# that resolves elsewhere: each stops with its reason and reads nothing.
mkdir -p "$tmp_dir/nogit"
expect_skip "$tmp_dir/nogit" "$config" 'not inside a git repository'
git init -q --bare "$tmp_dir/bare.git"
expect_skip "$tmp_dir/bare.git" "$config" 'does not end in .git'
git init -q --template= "$tmp_dir/other"
expect_skip "$tmp_dir/other" "$config" 'no auto memory directory where Claude Code would put it'
mkdir -p "$config/projects/$(key_for "$tmp_dir/other")/memory"
cp "$memory/fb-nested.md" "$config/projects/$(key_for "$tmp_dir/other")/memory/"
expect_skip "$tmp_dir/other" "$config" 'has no MEMORY.md'
git init -q --template= "$tmp_dir/linked"
mkdir -p "$tmp_dir/elsewhere/memory"
cp "$memory/fb-nested.md" "$memory/MEMORY.md" "$tmp_dir/elsewhere/memory/"
mkdir -p "$config/projects/$(key_for "$tmp_dir/linked")"
ln -s "$tmp_dir/elsewhere/memory" "$config/projects/$(key_for "$tmp_dir/linked")/memory"
expect_skip "$tmp_dir/linked" "$config" 'resolves outside'

# An empty memory directory is told apart from a failure: exit 0 and the done line with 0.
git init -q --template= "$tmp_dir/empty"
mkdir -p "$config/projects/$(key_for "$tmp_dir/empty")/memory"
: > "$config/projects/$(key_for "$tmp_dir/empty")/memory/MEMORY.md"
[ "$(run_listing "$tmp_dir/empty")" = "scanned 0 file(s), 0 feedback (done)" ] \
  || { echo "an empty memory directory did not print the done line" >&2; exit 1; }

# A failure while listing exits 1 with nothing on stdout (no partial list, no done line).
git init -q --template= "$tmp_dir/broken"
broken="$config/projects/$(key_for "$tmp_dir/broken")/memory"
mkdir -p "$broken"
cp "$memory/fb-nested.md" "$memory/MEMORY.md" "$broken/"
chmod 300 "$broken"
status=0
out=$(run_listing "$tmp_dir/broken") || status=$?
chmod 700 "$broken"
if ! { [ "$status" -eq 1 ] && [ -z "$out" ] && grep -Fq 'listing failed' "$tmp_dir/list.err"; }; then
  echo "a listing failure was not exit 1 with empty stdout: $status $out" >&2
  exit 1
fi
key_of() { awk -F '\t' -v f="$memory/$1" '$2 == f {print $1}' <<<"$listing"; }

# --- a ledger with one merged observation from session A -------------------------------------
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
