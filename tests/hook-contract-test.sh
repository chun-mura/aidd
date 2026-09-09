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
