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

# Skill / subagent invocations carry the command name in tool_input, not in a prompt.
printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Skill","tool_input":{"skill":"aidd:adr"}}' | \
  AIDD_TEST_STATE_DIR="$tmp_dir/aidd" bash "$usage_log"
printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Task","tool_input":{"prompt":"run aidd:autonomous-review on the branch"}}' | \
  AIDD_TEST_STATE_DIR="$tmp_dir/aidd" bash "$usage_log"
python3 - "$tmp_dir/aidd/usage.json" <<'PYEOF'
import json, sys
data = json.load(open(sys.argv[1]))
assert data["command_counts"]["adr"] == 1
assert data["command_counts"]["autonomous-review"] == 1
assert "adr" in data["last_seen"]
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
