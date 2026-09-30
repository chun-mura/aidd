#!/bin/bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
dispatcher="$repo_root/hooks/scripts/tool-reminder.sh"
usage_log="$repo_root/hooks/scripts/usage-log.sh"
tmp_dir=$(mktemp -d)
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

# write-guard.sh: Write/Edit/NotebookEdit dispatcher. Only files that do not exist yet are checked.
write_guard="$repo_root/hooks/scripts/write-guard.sh"
[ -x "$write_guard" ]
project="$tmp_dir/project"
mkdir -p "$project/src"

run_write_guard() {
  local tool=$1 key=$2 path=$3
  printf '{"hook_event_name":"PreToolUse","tool_name":"%s","cwd":"%s","tool_input":{"%s":"%s"}}' \
    "$tool" "$project" "$key" "$path" | bash "$write_guard"
}

# A new file whose name sandboxed commands are commonly denied reading is refused.
out=$(run_write_guard Write file_path "$project/.env.local")
printf '%s' "$out" | python3 -c 'import json,sys; o=json.load(sys.stdin)["hookSpecificOutput"]; assert o["permissionDecision"]=="deny", o; assert ".env.local" in o["permissionDecisionReason"]'
run_write_guard NotebookEdit notebook_path "$project/secret-analysis.ipynb" | grep -F '"deny"'
# Patterns containing "/" match the whole path, not just the file name.
run_write_guard Write file_path "$tmp_dir/home/.ssh/config" | grep -F '"deny"'

# An existing file is left alone: the name already exists, so refusing gains nothing.
# The relative form also checks that a relative file path is resolved against the hook input's cwd.
touch "$project/src/existing.key"
[ -z "$(run_write_guard Edit file_path "$project/src/existing.key")" ]
[ -z "$(run_write_guard Edit file_path "src/existing.key")" ]
# An absolute pattern matches a relative file path only once the path is resolved against cwd.
AIDD_UNREADABLE_NAME_PATTERNS="$project/config/*.draft" run_write_guard Write file_path "config/prod.draft" | grep -F '"deny"'

# Patterns follow the sandbox path syntax of denyRead / credentials.files: "~/" is home, "/" and
# "//" are absolute, "./" or no prefix is relative to cwd, and a directory entry (with or without a
# trailing "/" or "/**") covers everything under it.
guard_home="$tmp_dir/home"
# `! cmd` is exempt from `set -e`, so the negative cases assert empty output instead.
guard_with() {
  HOME="$guard_home" AIDD_UNREADABLE_NAME_PATTERNS=$1 run_write_guard Write file_path "$2"
}
denied_with() {
  guard_with "$1" "$2" | grep -qF '"deny"'
}
denied_with '~/.aws/*' "$guard_home/.aws/config"
denied_with '~/.aws' "$guard_home/.aws/config"
[ -z "$(guard_with '~/.aws' "$guard_home/.awsx/config")" ]
denied_with '//**/.env' "$project/.env"
denied_with '~/**/.env' "$guard_home/.env"
denied_with "$guard_home/.aws" "$guard_home/.aws/config"
denied_with "$guard_home/.aws/" "$guard_home/.aws/nested/config"
denied_with "$guard_home/.aws/**" "$guard_home/.aws/config"
# A single directory name matches that directory at any depth under cwd.
denied_with 'secrets/**' "$project/secrets/a.txt"
denied_with 'secrets/' "$project/pkg/secrets/a.txt"
[ -z "$(guard_with 'secrets/**' "$tmp_dir/elsewhere/secrets/a.txt")" ]
# A relative pattern with "/" is anchored at cwd.
denied_with './config/*.draft' "$project/config/a.draft"
denied_with 'config/*.draft' "$project/config/a.draft"
[ -z "$(guard_with 'config/*.draft' "$project/pkg/config/a.draft")" ]

# Paths that match nothing produce no output.
[ -z "$(run_write_guard Write file_path "$project/src/main.py")" ]
[ -z "$(printf '{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{}}' | bash "$write_guard")" ]

# The pattern list is replaceable, and the guard can be turned off.
[ -z "$(AIDD_UNREADABLE_NAME_PATTERNS='*.draft' run_write_guard Write file_path "$project/.env")" ]
AIDD_UNREADABLE_NAME_PATTERNS='*.draft:*.tmp' run_write_guard Write file_path "$project/notes.tmp" | grep -F "'*.tmp'"
[ -z "$(AIDD_DISABLE_UNREADABLE_NAME_GUARD=1 run_write_guard Write file_path "$project/.env")" ]

# Wired as one handler for all three tools, filtered in the script rather than by `if`
# (the checks match names at any location, which one permission rule cannot express).
python3 - "$repo_root/hooks/hooks.json" <<'PYEOF'
import json, sys
hooks = json.load(open(sys.argv[1]))["hooks"]["PreToolUse"]
entries = [e for e in hooks if any("write-guard.sh" in h.get("command", "") for h in e["hooks"])]
assert len(entries) == 1, entries
assert entries[0]["matcher"] == "Write|Edit|NotebookEdit", entries[0]
assert all("if" not in h for h in entries[0]["hooks"]), entries[0]
PYEOF

# write-guard.sh asset overlap: a new consumer-side asset gets aidd's asset list as context;
# only an identical command/skill/agent name is refused.
context_of() { python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])'; }
decision_of() { python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"].get("permissionDecision", "none"))'; }

out=$(run_write_guard Write file_path "$project/.claude/commands/deploy-check.md")
[ "$(printf '%s' "$out" | decision_of)" = none ]
printf '%s' "$out" | context_of | grep -F 'aidd:design-review'
printf '%s' "$out" | context_of | grep -F 'agent aidd:reviewer'
# The whole list must stay under the 10,000-character additionalContext cap, past which Claude
# Code replaces it with a file path and a preview.
[ "$(printf '%s' "$out" | context_of | wc -c)" -lt 10000 ]
# User-level assets under ~/.claude are covered too (the script matches the path segment).
run_write_guard Write file_path "$tmp_dir/home/.claude/skills/pr-helper/SKILL.md" | context_of | grep -F 'aidd:'
# Hooks and rules have no namespace clash, so a same-named one only gets the list.
[ "$(run_write_guard Write file_path "$project/.claude/hooks/usage-log.sh" | decision_of)" = none ]

# Same name as an aidd command/skill (they share the slash namespace) or agent: refused.
out=$(run_write_guard Write file_path "$project/.claude/commands/design-review.md")
[ "$(printf '%s' "$out" | decision_of)" = deny ]
printf '%s' "$out" | grep -F 'aidd:design-review'
[ "$(run_write_guard Write file_path "$project/.claude/skills/adr/SKILL.md" | decision_of)" = deny ]
[ "$(run_write_guard Write file_path "$project/.claude/agents/reviewer.md" | decision_of)" = deny ]
[ "$(AIDD_ASSET_OVERLAP_DENY_SAME_NAME=0 run_write_guard Write file_path "$project/.claude/agents/reviewer.md" | decision_of)" = none ]
# A subdirectory is not the asset name: commands/adr/new.md is /adr:new, and an agent is named by
# its frontmatter, so both only get the list. A skill is still named by its directory.
out=$(run_write_guard Write file_path "$project/.claude/commands/adr/new.md")
[ "$(printf '%s' "$out" | decision_of)" = none ]
printf '%s' "$out" | context_of | grep -F 'aidd:adr'
[ "$(run_write_guard Write file_path "$project/.claude/agents/reviewer/extra.md" | decision_of)" = none ]
[ "$(run_write_guard Write file_path "$project/.claude/skills/adr/references/notes.md" | decision_of)" = deny ]

# Existing assets are out of scope: an existing file, or a new file inside an existing skill.
mkdir -p "$project/.claude/commands" "$project/.claude/skills/local-skill"
touch "$project/.claude/commands/design-review.md" "$project/.claude/skills/local-skill/SKILL.md"
[ -z "$(run_write_guard Edit file_path "$project/.claude/commands/design-review.md")" ]
[ -z "$(run_write_guard Write file_path "$project/.claude/skills/local-skill/reference.md")" ]
# A path outside the asset directories, even under .claude/, is silent.
[ -z "$(run_write_guard Write file_path "$project/.claude/notes/commands.md")" ]

# Target directories are configurable, and the check can be turned off.
[ -z "$(AIDD_ASSET_OVERLAP_DIRS=skills run_write_guard Write file_path "$project/.claude/commands/new-one.md")" ]
[ -z "$(AIDD_DISABLE_ASSET_OVERLAP=1 run_write_guard Write file_path "$project/.claude/commands/new-one.md")" ]

# The list is read from ${CLAUDE_PLUGIN_ROOT}; a missing list fails open with no output.
mkdir -p "$tmp_dir/fake-plugin/hooks"
printf '{"plugin":"fake","assets":[{"kind":"command","name":"only-here","description":"x"}]}' > "$tmp_dir/fake-plugin/hooks/asset-index.json"
CLAUDE_PLUGIN_ROOT="$tmp_dir/fake-plugin" run_write_guard Write file_path "$project/.claude/commands/new-one.md" | context_of | grep -F 'fake:only-here'
[ -z "$(CLAUDE_PLUGIN_ROOT="$tmp_dir/nowhere" run_write_guard Write file_path "$project/.claude/commands/new-one.md")" ]

# The bundled list and the strict prompt-hook template must match the real assets.
python3 "$repo_root/scripts/generate-asset-index.py" --check
# CI runs the same check, since it does not run tests/*.sh.
grep -F 'run: python3 scripts/generate-asset-index.py --check' "$repo_root/.github/workflows/validate.yml"

# The generator takes component locations from plugin.json, not from fixed directories:
# `commands` and `agents` replace the default scan, `skills` adds to it. A stale output fails --check.
fixture="$tmp_dir/fixture-plugin"
mkdir -p "$fixture/.claude-plugin" "$fixture/scripts" "$fixture/hooks" "$fixture/templates" \
  "$fixture/commands" "$fixture/cmds" "$fixture/agents" "$fixture/custom-agents" \
  "$fixture/skills/base-skill" "$fixture/extra/more-skill"
cp "$repo_root/scripts/generate-asset-index.py" "$fixture/scripts/"
printf '{"name":"fx","commands":["./cmds"],"agents":["./custom-agents/picked.md"],"skills":["./extra"]}' > "$fixture/.claude-plugin/plugin.json"
printf -- '---\ndescription: ignored\n---\n' > "$fixture/commands/default-cmd.md"
printf -- '---\ndescription: declared command\n---\n' > "$fixture/cmds/declared-cmd.md"
printf -- '---\nname: default-agent\ndescription: ignored\n---\n' > "$fixture/agents/default-agent.md"
printf -- '---\nname: picked\ndescription: declared agent\n---\n' > "$fixture/custom-agents/picked.md"
printf -- '---\nname: base-skill\ndescription: default skill\n---\n' > "$fixture/skills/base-skill/SKILL.md"
printf -- '---\nname: more-skill\ndescription: added skill\n---\n' > "$fixture/extra/more-skill/SKILL.md"
python3 "$fixture/scripts/generate-asset-index.py"
python3 - "$fixture/hooks/asset-index.json" <<'PYEOF'
import json, sys
index = json.load(open(sys.argv[1]))
names = {(a["kind"], a["name"]) for a in index["assets"]}
assert index["plugin"] == "fx", index
assert names == {("command", "declared-cmd"), ("agent", "picked"), ("skill", "base-skill"), ("skill", "more-skill")}, names
PYEOF
python3 "$fixture/scripts/generate-asset-index.py" --check
printf -- '---\ndescription: added later\n---\n' > "$fixture/cmds/added-later.md"
if python3 "$fixture/scripts/generate-asset-index.py" --check 2>/dev/null; then
  echo "stale asset index was not detected" >&2
  exit 1
fi

# The strict prompt hook ships only as a template (off by default): it is never wired into
# hooks.json, targets Write (Edit cannot create files), and narrows each asset directory by `if`.
python3 - "$repo_root/templates/asset-overlap-prompt-hook.json.template" "$repo_root/hooks/hooks.json" <<'PYEOF'
import json, sys
template = json.load(open(sys.argv[1]))
groups = template["hooks"]["PreToolUse"]
assert [g["matcher"] for g in groups] == ["Write"], groups
handlers = groups[0]["hooks"]
assert {h["if"] for h in handlers} == {f"Edit(**/.claude/{k}/**)" for k in ["hooks", "skills", "commands", "rules", "agents"]}, handlers
for h in handlers:
    assert h["type"] == "prompt" and "$ARGUMENTS" in h["prompt"] and h["continueOnBlock"] is True, h
    assert "aidd:design-review" in h["prompt"], h
assert "prompt" not in open(sys.argv[2]).read()
PYEOF
