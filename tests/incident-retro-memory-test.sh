#!/bin/bash
# Contract test for the auto memory intake of /aidd:incident-retro (#105): run the listing snippet
# from skills/incident-retro/SKILL.md against a fake memory directory, then walk the documented
# skip / count / write steps through scripts/learnings.py, and check that the in-run count equals
# what the script counts once the observations are merged. No real memory is read.
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
skill="$repo_root/skills/incident-retro/SKILL.md"
script="$repo_root/scripts/learnings.py"
# An explicit template keeps TMPDIR honored (macOS mktemp -d alone ignores it).
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/aidd-memory-intake-test.XXXXXX")
tmp_dir=$(cd "$tmp_dir" && pwd -P)
trap 'rm -rf "$tmp_dir"' EXIT

# --- the listing snippet: feedback files only, frontmatter only --------------------------------
memory="$tmp_dir/memory"
mkdir -p "$memory"
sed -n '/^# auto memory intake: list feedback memories/,/^PY$/p' "$skill" > "$tmp_dir/list.sh"
grep -Fq '<memory-dir>' "$tmp_dir/list.sh" || { echo "listing snippet not found in $skill" >&2; exit 1; }

cur=11111111-1111-4111-8111-111111111111
sess_a=aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa
sess_b=bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb
memory_file() {  # memory_file NAME FRONTMATTER_LINES...
  local name=$1
  shift
  { printf -- '---\n'; printf '%s\n' "$@"; printf -- '---\n\nBODY_SENTINEL do not print this.\n'; } \
    > "$memory/$name"
}
printf '%s\n' '- [x](fb-nested.md) — BODY_SENTINEL' > "$memory/MEMORY.md"
# The nested shape seen in this environment, and the top-level shape the docs describe.
memory_file fb-nested.md 'name: a' 'description: b' 'metadata:' '  node_type: memory' '  type: feedback' \
  "  originSessionId: $sess_b"
memory_file fb-old.md 'name: c' 'metadata:' '  type: feedback' "  originSessionId: $sess_a"
memory_file fb-top.md 'name: d' 'type: feedback'
memory_file fb-cur.md 'name: e' 'metadata:' '  type: feedback' "  originSessionId: $cur"
memory_file proj.md 'name: f' 'metadata:' '  type: project' "  originSessionId: $sess_b"
memory_file user.md 'name: g' 'type: user'
printf '%s\n' 'type: feedback' 'BODY_SENTINEL no frontmatter.' > "$memory/nofm.md"
printf '%s\n' '---' 'type: feedback' 'BODY_SENTINEL frontmatter never closed.' > "$memory/open.md"
printf '%s\n' '---' 'type: feedback' '---' > "$memory/notes.txt"

sed "s|<memory-dir>|$memory|" "$tmp_dir/list.sh" > "$tmp_dir/list-run.sh"
listing=$(bash "$tmp_dir/list-run.sh")
expected=$(printf '%s\t%s\n' \
  "$cur" "$memory/fb-cur.md" \
  "$sess_b" "$memory/fb-nested.md" \
  "$sess_a" "$memory/fb-old.md" \
  "auto-memory:$memory/fb-top.md" "$memory/fb-top.md")
if [ "$listing" != "$expected" ]; then
  printf 'listing snippet output differs.\n--- got\n%s\n--- expected\n%s\n' "$listing" "$expected" >&2
  exit 1
fi
if grep -Fq BODY_SENTINEL <<<"$listing"; then
  echo "listing snippet printed a memory body" >&2
  exit 1
fi
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
observation incident-retro 'git stash' | learnings add --session-id "$sess_a" > /dev/null
git -C "$repo" add .aidd/learnings
git -C "$repo" commit -qm 'docs: ledger'

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

# The signatures the model would give each feedback memory, and this session's incident.
sig_of() {
  case $1 in
    fb-nested.md | fb-old.md) echo 'git stash' ;;
    fb-top.md) echo 'gh pr create --fill' ;;
    fb-cur.md) echo 'Edit' ;;
  esac
}
incident='gh pr create --fill'

# --- skip memories already in the ledger: equal sessions with and without the memory's key ----
learnings candidates --all > "$tmp_dir/k0"
new=()
for name in fb-cur.md fb-nested.md fb-old.md fb-top.md; do
  learnings candidates --all --session-id "$(key_of "$name")" --signature "$(sig_of "$name")" > "$tmp_dir/k1"
  if [ "$(sessions_of "$tmp_dir/k1" "$(sig_of "$name")")" != "$(sessions_of "$tmp_dir/k0" "$(sig_of "$name")")" ]; then
    new+=("$name")
  fi
done
[ "${new[*]}" = "fb-cur.md fb-nested.md fb-top.md" ] || { echo "already-imported check kept: ${new[*]}" >&2; exit 1; }

# --- count in this run: this session's signatures through candidates, plus one per other key ---
args=(--signature "$incident")
for name in "${new[@]}"; do
  [ "$(key_of "$name")" = "$cur" ] && args+=(--signature "$(sig_of "$name")")
done
learnings candidates --all --session-id "$cur" "${args[@]}" > "$tmp_dir/c"
in_run() {  # in_run SIGNATURE -> sessions counted in this run
  local count keys=() name
  count=$(sessions_of "$tmp_dir/c" "$1")
  for name in "${new[@]}"; do
    [ "$(sig_of "$name")" = "$1" ] && [ "$(key_of "$name")" != "$cur" ] && keys+=("$(key_of "$name")")
  done
  [ "${#keys[@]}" -gt 0 ] && count=$((count + $(printf '%s\n' "${keys[@]}" | sort -u | wc -l)))
  echo "$count"
}
# Repeated in memory and the ledger, and in memory and this session: promotion candidates.
[ "$(in_run 'git stash')" -eq 2 ]
[ "$(in_run 'gh pr create --fill')" -eq 2 ]
# Seen once, in a memory written in this session: not a candidate.
[ "$(in_run 'Edit')" -eq 1 ]
# The memory's own session is not counted by the script before merge, so the addition is needed.
[ "$(sessions_of "$tmp_dir/c" 'git stash')" -eq 1 ]

# --- write the approved observations, then merge: the script alone gives the same counts -------
for name in "${new[@]}"; do
  path=$(observation auto-memory "$(sig_of "$name")" | learnings add --session-id "$(key_of "$name")")
  python3 -I - "$repo/$path" "$memory" <<'PYEOF'
import json, sys
raw = open(sys.argv[1], encoding="utf-8").read()
data = json.loads(raw)
assert data["source"] == "auto-memory" and data["evidence"] == [], data
assert sys.argv[2] not in raw and "auto-memory:" not in raw, "the memory path reached the ledger"
PYEOF
done
observation incident-retro "$incident" | learnings add --session-id "$cur" > /dev/null
git -C "$repo" add .aidd/learnings
git -C "$repo" commit -qm 'docs: ledger'
learnings candidates --all --session-id 22222222-2222-4222-8222-222222222222 > "$tmp_dir/merged"
for sig in 'git stash' 'gh pr create --fill' 'Edit'; do
  [ "$(sessions_of "$tmp_dir/merged" "$sig")" -eq "$(in_run "$sig")" ] \
    || { echo "in-run count for '$sig' differs from the merged count" >&2; exit 1; }
done

# A later run does not import the same memories again.
learnings candidates --all > "$tmp_dir/k0"
for name in fb-cur.md fb-nested.md fb-top.md; do
  learnings candidates --all --session-id "$(key_of "$name")" --signature "$(sig_of "$name")" > "$tmp_dir/k1"
  [ "$(sessions_of "$tmp_dir/k1" "$(sig_of "$name")")" = "$(sessions_of "$tmp_dir/k0" "$(sig_of "$name")")" ] \
    || { echo "$name would be imported twice" >&2; exit 1; }
done

echo "incident-retro memory intake test passed"
