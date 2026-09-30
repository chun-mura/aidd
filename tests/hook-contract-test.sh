#!/bin/bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
dispatcher="$repo_root/hooks/scripts/tool-reminder.sh"
usage_log="$repo_root/hooks/scripts/usage-log.sh"
# An explicit template keeps TMPDIR honored (macOS mktemp -d alone ignores it).
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/aidd-hook-test.XXXXXX")
tmp_dir=$(cd "$tmp_dir" && pwd -P)  # git reports physical paths (/tmp is a symlink on macOS)
trap 'rm -rf "$tmp_dir"' EXIT

[ -x "$dispatcher" ]

run_hook() {
  local event=$1
  local command=$2
  printf '{"hook_event_name":"%s","tool_input":{"command":"%s"}}' "$event" "$command" | \
    AIDD_TEST_STATE_DIR="$tmp_dir/aidd" bash "$dispatcher"
}

[ -z "$(run_hook PreToolUse 'git status')" ]
run_hook PreToolUse 'git commit -m test' | grep -F '/aidd:test-perspectives'
run_hook PreToolUse 'gh issue create --title test' | grep -F 'タイトルと本文は日本語'
run_hook PostToolUse 'git push origin main' | grep -F 'open PR'

# --- Git-aware checks: fake hook input against throwaway repositories --------------------------
export HOME="$tmp_dir/home"
mkdir -p "$HOME"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export GIT_CONFIG_NOSYSTEM=1

# hook EVENT CWD COMMAND [SESSION]: runs the dispatcher on a well-formed payload.
hook() {
  python3 -c '
import json, sys
print(json.dumps({"hook_event_name": sys.argv[1], "cwd": sys.argv[2], "session_id": sys.argv[4],
                  "tool_name": "Bash", "tool_input": {"command": sys.argv[3]}}))
' "$1" "$2" "$3" "${4-session-a}" | AIDD_TEST_STATE_DIR="$tmp_dir/aidd" bash "$dispatcher"
}

# Each call must produce at most one JSON document; decision_of prints its permissionDecision.
json_count() { python3 -c 'import sys; print(sum(1 for l in sys.stdin if l.strip()))'; }
decision_of() {
  python3 -c '
import json, sys
text = sys.stdin.read().strip()
print(json.loads(text)["hookSpecificOutput"].get("permissionDecision", "none") if text else "empty")
'
}

repo="$tmp_dir/repo"
git init -q --template= -b main "$repo"
echo base > "$repo/app.sh"
git -C "$repo" add app.sh
git -C "$repo" commit -qm 'chore: base'
git -C "$repo" switch -qc feat
mkdir -p "$repo/src"
echo code > "$repo/src/a.sh"
echo code > "$repo/src/b.sh"
git -C "$repo" add src
git -C "$repo" commit -qm 'feat: code'
git -C "$repo" switch -qc docs-only main
mkdir -p "$repo/docs"
echo doc > "$repo/docs/x.md"
git -C "$repo" add docs
git -C "$repo" commit -qm 'docs: x'
git -C "$repo" switch -q main

# #19: the PR's branch is --head, not the cwd's HEAD (cwd is on main, which has no diff).
out=$(hook PreToolUse "$repo" 'gh pr create --base main --head feat --title t --body b')
printf '%s\n' "$out" | grep -F '/aidd:autonomous-review --base main --head feat'
printf '%s\n' "$out" | grep -F 'src/a.sh, src/b.sh'
# It warns without denying, and shares one JSON reply with the Japanese-language nudge.
[ "$(printf '%s\n' "$out" | json_count)" = 1 ]
[ "$(printf '%s\n' "$out" | decision_of)" = none ]
printf '%s\n' "$out" | grep -F 'タイトルと本文は日本語'
# Without --head, the checked-out branch is the PR's branch; wrappers and cd are seen through.
git -C "$repo" switch -q feat
hook PreToolUse "$tmp_dir" "cd $repo && rtk gh pr create --title t" | grep -F -- '--head feat'
git -C "$repo" switch -q main
# Docs-only branches stay quiet apart from the language nudge.
out=$(hook PreToolUse "$repo" 'gh pr create --head docs-only')
if printf '%s\n' "$out" | grep -Fq 'autonomous-review'; then exit 1; fi
# The file list is capped.
AIDD_REVIEW_LIST_LIMIT=1 hook PreToolUse "$repo" 'gh pr create --head=feat' | grep -F 'src/a.sh ほか 1 件'
# Opt-out.
out=$(AIDD_DISABLE_REVIEW_BEFORE_PR=1 hook PreToolUse "$repo" 'gh pr create --head feat')
if printf '%s\n' "$out" | grep -Fq 'autonomous-review'; then exit 1; fi
# Evidence for the branch silences it.
mkdir -p "$repo/.aidd/autonomous-review/run1"
printf '{"head":"feat","head_sha":null}' > "$repo/.aidd/autonomous-review/run1/state.json"
out=$(hook PreToolUse "$repo" 'gh pr create --head feat')
if printf '%s\n' "$out" | grep -Fq 'autonomous-review'; then exit 1; fi
rm -rf "$repo/.aidd"
# A command that only mentions gh pr create in a quoted string is not an invocation.
[ -z "$(hook PreToolUse "$repo" 'echo "gh pr create --head feat"')" ]
# Evidence also matches by head_sha / head_sha_after_fixes (the branch may have been renamed).
feat_sha=$(git -C "$repo" rev-parse feat)
mkdir -p "$repo/.aidd/autonomous-review/run1"
printf '{"head":"renamed","head_sha":"%s"}' "$feat_sha" > "$repo/.aidd/autonomous-review/run1/state.json"
out=$(hook PreToolUse "$repo" 'gh pr create --head feat')
if printf '%s\n' "$out" | grep -Fq 'autonomous-review'; then exit 1; fi
printf '{"head":"renamed","head_sha":"0000000","head_sha_after_fixes":"%s"}' "$feat_sha" > "$repo/.aidd/autonomous-review/run1/state.json"
out=$(hook PreToolUse "$repo" 'gh pr create --head feat')
if printf '%s\n' "$out" | grep -Fq 'autonomous-review'; then exit 1; fi
rm -rf "$repo/.aidd"
# Evidence written in any worktree counts, whichever worktree (or the main tree) opens the PR.
git -C "$repo" worktree add -q "$tmp_dir/wt-a" feat
git -C "$repo" worktree add -q --detach "$tmp_dir/wt-b" main
mkdir -p "$tmp_dir/wt-a/.aidd/autonomous-review/run1"
printf '{"head":"feat","head_sha":"%s"}' "$feat_sha" > "$tmp_dir/wt-a/.aidd/autonomous-review/run1/state.json"
for cwd in "$repo" "$tmp_dir/wt-a" "$tmp_dir/wt-b"; do
  out=$(hook PreToolUse "$cwd" 'gh pr create --head feat --base main')
  if printf '%s\n' "$out" | grep -Fq 'autonomous-review'; then exit 1; fi
done
git -C "$repo" worktree remove --force "$tmp_dir/wt-a"
git -C "$repo" worktree remove --force "$tmp_dir/wt-b"
# Without --base, origin/HEAD or AIDD_REVIEW_BASE, main then master is the base.
master_repo="$tmp_dir/master-repo"
git init -q --template= -b master "$master_repo"
echo base > "$master_repo/app.sh"
git -C "$master_repo" add app.sh
git -C "$master_repo" commit -qm 'chore: base'
git -C "$master_repo" switch -qc feat
echo code > "$master_repo/app.sh"
git -C "$master_repo" commit -qam 'feat: code'
hook PreToolUse "$master_repo" 'gh pr create --head feat' | grep -F -- '--base master --head feat'
# When no base resolves, it says so instead of staying silent.
git -C "$master_repo" branch -qm master trunk
hook PreToolUse "$master_repo" 'gh pr create --head feat' | grep -F '基点ブランチ (main / master) を解決できない'

# Comments and compound statements: a word-initial # starts a comment that ends at the newline
# (the next line is still a command); a # inside a word or quotes does not; commands after
# then/do/{/! are still seen.
hook PreToolUse "$repo" 'cd /x#y && git commit -m x' | grep -F '/aidd:test-perspectives'
hook PreToolUse "$repo" 'if true; then git commit -m x; fi' | grep -F '/aidd:test-perspectives'
hook PreToolUse "$repo" $'git status # check\ngit commit -m x' | grep -F '/aidd:test-perspectives'
hook PreToolUse "$repo" $'npm test # run\ngh pr create --head docs-only' | grep -F 'タイトルと本文は日本語'
hook PreToolUse "$repo" 'echo "#x"; gh issue create -t t' | grep -F 'タイトルと本文は日本語'
[ -z "$(hook PreToolUse "$repo" 'echo x # git commit -m x')" ]

# Commands that are not git or gh never start python, even when cwd or transcript_path
# contains "git" / "gh"; a git on a later line of the command still does.
fake_bin="$tmp_dir/fake-bin"
mkdir -p "$fake_bin"
real_python=$(command -v python3)
printf '#!/bin/bash\ntouch "%s/python-started"\nexec "%s" "$@"\n' "$tmp_dir" "$real_python" > "$fake_bin/python3"
chmod +x "$fake_bin/python3"
fast_path() {
  printf '{"hook_event_name":"PreToolUse","cwd":"/work/git/light-door","transcript_path":"/home/.claude/gh/t.jsonl","tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" | \
    PATH="$fake_bin:$PATH" AIDD_TEST_STATE_DIR="$tmp_dir/aidd" bash "$dispatcher"
}
rm -f "$tmp_dir/python-started"
[ -z "$(fast_path 'ls -la light-door')" ]
[ ! -e "$tmp_dir/python-started" ]
fast_path 'npm test\ngit commit -m x' | grep -F '/aidd:test-perspectives'
[ -e "$tmp_dir/python-started" ]

# #21 (1): git operations that lose uncommitted work, and staging that names nothing, are denied.
# The lists pin the boundary: joined flags, git -C, wrappers, env prefixes, cd and joined
# commands are seen through; quoted text, heredoc bodies and values of -m are not commands.
expect_deny() {
  local c
  for c in "$@"; do
    [ "$(hook PreToolUse "$repo" "$c" | decision_of)" = deny ] || { echo "not denied: $c" >&2; exit 1; }
  done
}
expect_allow() {
  local c
  for c in "$@"; do
    [ "$(hook PreToolUse "$repo" "$c" | decision_of)" != deny ] || { echo "denied: $c" >&2; exit 1; }
  done
}
expect_deny 'git stash' 'git stash push -m wip' 'git stash pop' 'git stash -u' \
  'rtk git stash' "git -C $repo stash" 'cd src && git stash' 'git status; git stash' \
  "$(printf 'git status\ngit stash')" '(git stash)' \
  'git reset --hard HEAD~1' 'git checkout -- app.sh' 'git checkout .' 'git checkout main -- app.sh' \
  'git restore app.sh' 'git restore --staged --worktree app.sh' 'git restore -SW app.sh' \
  'git clean -fd' 'git clean --force' \
  'git add -A' 'git add .' 'git add -u' 'git add --all' 'git add -Av' 'git add -- .' "git -C $repo add ." \
  'git commit -am msg' 'git commit -a -m msg' 'git commit --all -m msg' 'FOO=1 git commit -vam msg' \
  'env GIT_EDITOR=true git commit -a' 'git -c core.editor=true commit -a' \
  "$(printf 'git status # c\ngit stash')" 'curl http://x/#a && git stash' 'if true; then git reset --hard; fi' \
  'git checkout app.sh' 'git checkout HEAD app.sh' 'git checkout -f main' 'git checkout --force main' \
  'git switch -f main' 'git switch --discard-changes main' \
  'git commit -S -a' 'git commit -u -a' 'git commit -Skey -a' \
  'git add ./' 'git add :' 'git add :/' 'git add ":(top)"' 'git add ":/."' 'cd src && git add ..' 'cd src && git add ../..'
expect_allow 'git stash list' 'git stash show -p' 'git reset --soft HEAD~1' 'git reset app.sh' \
  'git checkout -b topic' 'git checkout main' 'git checkout -' 'git checkout -b topic main' \
  'git switch feat' 'git switch -c topic' 'git restore --staged app.sh' 'git restore -S app.sh' \
  'git clean -n' 'git clean -nd' 'git clean --dry-run -f' 'git add src/a.sh' 'git add -p' \
  'git add ./app.sh' 'cd src && git add ../app.sh' 'git add ":(top)app.sh"' \
  'git commit -m "fix -a flag"' 'git commit -ma' 'git commit -F msg.txt' 'git commit -m msg -- app.sh' \
  'git commit -S -m msg' 'git commit -u -m msg' \
  'echo "git stash"' 'grep -r "git reset --hard" docs' \
  "$(printf 'git commit -F - <<EOF\ngit stash\nEOF')" \
  "$(printf "git commit -m \"\$(cat <<'EOF'\nfeat: x\n\ndon't git add -A\nEOF\n)\"")"
# Known misses (not a shell parser): a nested shell, and a wrapper not on the list.
expect_allow "bash -c 'git stash'" 'chronic git stash'
AIDD_COMMAND_WRAPPERS='chronic,sudo -E' expect_deny 'chronic git stash' 'sudo -E git stash'
AIDD_DISABLE_GIT_SAFETY=1 expect_allow 'git stash' 'git commit -am msg'
# Two denials and an injected reminder in one command come back as one JSON reply.
out=$(hook PreToolUse "$repo" 'git stash && git add -A && git commit -m msg')
[ "$(printf '%s\n' "$out" | json_count)" = 1 ]
python3 - "$out" <<'PYEOF'
import json, sys
reply = json.loads(sys.argv[1])["hookSpecificOutput"]
assert reply["permissionDecision"] == "deny", reply
assert "git stash" in reply["permissionDecisionReason"], reply
assert "git add -A" in reply["permissionDecisionReason"], reply
assert "/aidd:test-perspectives" in reply["additionalContext"], reply
PYEOF

# #21 (2): a main tree used by another live session warns once per other session.
shared="$tmp_dir/shared"
git init -q --template= -b main "$shared"
git -C "$shared" commit -q --allow-empty -m 'chore: base'
[ -z "$(hook PreToolUse "$shared" 'git status' session-x)" ]
out=$(hook PreToolUse "$shared" 'git status' session-y)
printf '%s\n' "$out" | grep -F "主ツリー $shared"
printf '%s\n' "$out" | grep -F "$shared/.claude/worktrees/<name>"
[ "$(printf '%s\n' "$out" | decision_of)" = none ]
[ -z "$(hook PreToolUse "$shared" 'git log' session-y)" ]
hook PreToolUse "$shared" 'git log' session-x | grep -F '主ツリー'
# Once per peer means once while the peer stays active, not once per TTL.
python3 - "$tmp_dir/aidd/main-tree.json" <<'PYEOF'
import json, sys, time
data = json.load(open(sys.argv[1]))
for key in data["warned"]:
    data["warned"][key] = time.time() - 31 * 60
json.dump(data, open(sys.argv[1], "w"))
PYEOF
[ -z "$(hook PreToolUse "$shared" 'git log' session-y)" ]
[ -z "$(hook PreToolUse "$shared" 'git log' session-x)" ]
# A linked worktree is not the main tree.
git -C "$shared" worktree add -q "$tmp_dir/shared-wt" -b wt
[ -z "$(hook PreToolUse "$tmp_dir/shared-wt" 'git status' session-z)" ]
# Occupancy expires, and the warning can be switched off.
python3 - "$tmp_dir/aidd/main-tree.json" <<'PYEOF'
import json, sys
data = json.load(open(sys.argv[1]))
for sessions in data["trees"].values():
    for s in sessions:
        sessions[s] = 0
json.dump(data, open(sys.argv[1], "w"))
PYEOF
[ -z "$(hook PreToolUse "$shared" 'git status' session-w)" ]
[ -z "$(AIDD_DISABLE_MAIN_TREE_WARNING=1 hook PreToolUse "$shared" 'git status' session-v)" ]
AIDD_WORKTREE_DIR=/elsewhere hook PreToolUse "$shared" 'git status' session-u | grep -F '/elsewhere/<name>'

# #21 (3): gh issue create needs this session's gh issue list --search first.
out=$(hook PreToolUse "$repo" 'gh issue create --title t' session-s1)
[ "$(printf '%s\n' "$out" | json_count)" = 1 ]
[ "$(printf '%s\n' "$out" | decision_of)" = deny ]
printf '%s\n' "$out" | grep -F 'gh issue list --search'
printf '%s\n' "$out" | grep -F 'タイトルと本文は日本語'
[ -z "$(hook PostToolUse "$repo" 'gh issue list --search "hook dup"' session-s1)" ]
[ "$(hook PreToolUse "$repo" 'gh issue create --title t' session-s1 | decision_of)" = none ]
# Another session's search, or a list without --search, does not count.
hook PostToolUse "$repo" 'gh issue list --label bug' session-s2
[ "$(hook PreToolUse "$repo" 'gh issue create --title t' session-s2 | decision_of)" = deny ]
hook PostToolUse "$repo" 'rtk gh issue list -S dup --state all' session-s3
[ "$(hook PreToolUse "$repo" 'gh issue create --title t' session-s3 | decision_of)" = none ]
# A search in the same command is recorded only after this check runs.
[ "$(hook PreToolUse "$repo" 'gh issue list --search x && gh issue create' session-s4 | decision_of)" = deny ]
# Searches expire.
python3 - "$tmp_dir/aidd/issue-search.json" <<'PYEOF'
import json, sys, time
data = json.load(open(sys.argv[1]))
data["session-s1\t"] = time.time() - 31 * 60
json.dump(data, open(sys.argv[1], "w"))
PYEOF
[ "$(hook PreToolUse "$repo" 'gh issue create --title t' session-s1 | decision_of)" = deny ]
[ "$(AIDD_ISSUE_SEARCH_TTL_MINUTES=60 hook PreToolUse "$repo" 'gh issue create' session-s1 | decision_of)" = none ]
[ "$(AIDD_DISABLE_ISSUE_SEARCH_GATE=1 hook PreToolUse "$repo" 'gh issue create' session-s9 | decision_of)" = none ]
# Without a session id there is nothing to match the search against, so it does not deny.
[ "$(hook PreToolUse "$repo" 'gh issue create' '' | decision_of)" = none ]
# The search counts only for the repository it searched: -R / --repo (also before the group,
# where gh accepts it), else the cwd's origin remote.
repo_a="$tmp_dir/repo-a"
repo_b="$tmp_dir/repo-b"
git init -q --template= -b main "$repo_a"
git init -q --template= -b main "$repo_b"
git -C "$repo_a" remote add origin git@github.com:Owner/A.git
git -C "$repo_b" remote add origin https://github.com/owner/b
hook PostToolUse "$repo_a" 'gh issue list --search dup' session-r1
[ "$(hook PreToolUse "$repo_a" 'gh issue create -t t' session-r1 | decision_of)" = none ]
[ "$(hook PreToolUse "$repo_b" 'gh issue create -t t' session-r1 | decision_of)" = deny ]
[ "$(hook PreToolUse "$repo_b" 'gh issue create -R owner/a -t t' session-r1 | decision_of)" = none ]
[ "$(hook PreToolUse "$repo_b" 'gh -R github.com/owner/a issue create -t t' session-r1 | decision_of)" = none ]
hook PostToolUse "$repo_a" 'gh issue list -R owner/zzz --search dup' session-r2
[ "$(hook PreToolUse "$repo_a" 'gh issue create -t t' session-r2 | decision_of)" = deny ]
[ "$(hook PreToolUse "$repo_a" 'gh --repo owner/zzz issue create -t t' session-r2 | decision_of)" = none ]
hook PostToolUse "$repo_b" 'gh --repo=owner/a issue list -S dup' session-r3
[ "$(hook PreToolUse "$repo_a" 'gh issue create -t t' session-r3 | decision_of)" = none ]
# A global -R / --repo before the group does not hide gh issue create from the checks.
[ "$(hook PreToolUse "$repo_a" 'gh -R o/r issue create -t x' session-r4 | decision_of)" = deny ]
[ "$(hook PreToolUse "$repo_a" 'gh --repo o/r issue create -t x' session-r4 | decision_of)" = deny ]
hook PreToolUse "$repo_a" 'gh -R o/r pr create -t x' session-r4 | grep -F 'タイトルと本文は日本語'

# #27: with AIDD_REQUIRED_LABEL_PREFIX set, gh issue create needs a label with that prefix.
# session-s3 searched above, so only the label check decides here.
label_hook() { AIDD_REQUIRED_LABEL_PREFIX=priority: hook PreToolUse "$repo" "$1" session-s3; }
out=$(label_hook 'gh issue create --title t')
[ "$(printf '%s\n' "$out" | decision_of)" = deny ]
printf '%s\n' "$out" | grep -F 'priority: で始まるラベルが無い'
[ "$(label_hook 'gh issue create --label bug' | decision_of)" = deny ]
[ "$(label_hook 'gh issue create --label priority:P2' | decision_of)" = none ]
[ "$(label_hook 'gh issue create --label=priority:P3' | decision_of)" = none ]
[ "$(label_hook 'gh issue create -l bug,priority:P1' | decision_of)" = none ]
[ "$(label_hook 'gh issue create -l bug -l priority:P1' | decision_of)" = none ]
# A global -R / --repo before the group does not skip the label check.
AIDD_DISABLE_ISSUE_SEARCH_GATE=1 label_hook 'gh -R o/r issue create -t x' | grep -F 'priority: で始まるラベルが無い'
AIDD_DISABLE_ISSUE_SEARCH_GATE=1 label_hook 'gh --repo o/r issue create -t x' | grep -F 'priority: で始まるラベルが無い'
[ "$(AIDD_DISABLE_ISSUE_SEARCH_GATE=1 label_hook 'gh -R o/r issue create -l priority:P2' | decision_of)" = none ]
# Unset means off, so repositories without such labels can still file issues.
[ "$(hook PreToolUse "$repo" 'gh issue create --title t' session-s3 | decision_of)" = none ]
# Missing search and missing label: both reasons in one denial.
out=$(AIDD_REQUIRED_LABEL_PREFIX=priority: hook PreToolUse "$repo" 'gh issue create' session-s8)
[ "$(printf '%s\n' "$out" | json_count)" = 1 ]
printf '%s\n' "$out" | grep -F 'gh issue list --search' | grep -F 'priority: で始まるラベル'

usage_input='{"prompt":"/aidd:design-review sample"}'
printf '%s' "$usage_input" | AIDD_TEST_STATE_DIR="$tmp_dir/aidd" bash "$usage_log"
python3 - "$tmp_dir/aidd/usage.json" <<'PYEOF'
import json, sys
data = json.load(open(sys.argv[1]))
assert data["command_counts"]["design-review"] == 1
assert "prompt_log" not in data
PYEOF

printf '%s' "$usage_input" | AIDD_TEST_STATE_DIR="$tmp_dir/aidd" AIDD_PROMPT_LOG=1 bash "$usage_log"
python3 - "$tmp_dir/aidd/usage.json" <<'PYEOF'
import json, sys
data = json.load(open(sys.argv[1]))
assert data["command_counts"]["design-review"] == 2
assert "prompt_log" not in data
PYEOF

# The Skill tool names the command exactly, so the key is read, not pattern-matched.
# This is also the path a subagent's own invocation takes (plugin hooks fire in subagents).
printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"aidd:adr","args":"aidd:retro is only mentioned here"}}' | \
  AIDD_TEST_STATE_DIR="$tmp_dir/aidd" bash "$usage_log"
python3 - "$tmp_dir/aidd/usage.json" <<'PYEOF'
import json, sys
data = json.load(open(sys.argv[1]))
assert data["command_counts"]["adr"] == 1
assert "retro" not in data["command_counts"]
assert "adr" in data["last_seen"]
PYEOF

# Free text that merely mentions a command is not an invocation. Counting it made one run
# register four times (parent prompt, Agent dispatch, subagent Skill call, task notification).
printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Agent","tool_input":{"prompt":"run aidd:autonomous-review on the branch"}}' | \
  AIDD_TEST_STATE_DIR="$tmp_dir/aidd" bash "$usage_log"
printf '%s' '{"prompt":"aidd:design-doc をあとで使うか検討する"}' | AIDD_TEST_STATE_DIR="$tmp_dir/aidd" bash "$usage_log"
python3 - "$tmp_dir/aidd/usage.json" <<'PYEOF'
import json, sys
data = json.load(open(sys.argv[1]))
assert "autonomous-review" not in data["command_counts"], data["command_counts"]
assert "design-doc" not in data["command_counts"], data["command_counts"]
PYEOF

# Names without a backing command/skill file are not commands.
printf '%s' '{"prompt":"/aidd:aut"}' | AIDD_TEST_STATE_DIR="$tmp_dir/aidd" bash "$usage_log"
python3 - "$tmp_dir/aidd/usage.json" <<'PYEOF'
import json, sys
data = json.load(open(sys.argv[1]))
assert "aut" not in data["command_counts"]
PYEOF

# prompt_log left behind by pre-0.25.0 installs is dropped, not carried forward.
python3 - "$tmp_dir/aidd/usage.json" <<'PYEOF'
import json, sys
data = json.load(open(sys.argv[1]))
data["prompt_log"] = [{"ts": "2026-01-01T00:00:00+00:00", "text": "secret prompt fragment"}]
json.dump(data, open(sys.argv[1], "w"))
PYEOF
printf '%s' '{"prompt":"no aidd command here"}' | AIDD_TEST_STATE_DIR="$tmp_dir/aidd" bash "$usage_log"
python3 - "$tmp_dir/aidd/usage.json" <<'PYEOF'
import json, sys
data = json.load(open(sys.argv[1]))
assert "prompt_log" not in data
PYEOF

# A payload larger than ARG_MAX must still be recorded: it is read from stdin, not argv.
python3 - "$usage_log" "$tmp_dir/aidd" <<'PYEOF'
import json, os, subprocess, sys
usage_log, state_dir = sys.argv[1], sys.argv[2]
payload = json.dumps({
    "hook_event_name": "PreToolUse",
    "tool_name": "Skill",
    "tool_input": {"skill": "aidd:design-doc", "args": "x" * 1_200_000},
})
assert len(payload) > 1_048_576
subprocess.run(
    ["bash", usage_log],
    input=payload.encode(),
    check=True,
    env=dict(os.environ, AIDD_TEST_STATE_DIR=state_dir),
)
data = json.load(open(os.path.join(state_dir, "usage.json")))
assert data["command_counts"]["design-doc"] == 1, data["command_counts"]
PYEOF

# The PreToolUse matcher must be anchored: unanchored "Skill" also matches ListSkills and
# SearchSkills, firing this hook on unrelated tools.
python3 - "$repo_root/hooks/hooks.json" <<'PYEOF'
import json, sys
hooks = json.load(open(sys.argv[1]))["hooks"]["PreToolUse"]
matchers = [entry["matcher"] for entry in hooks]
assert "^Skill$" in matchers, matchers
PYEOF
