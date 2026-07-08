#!/bin/bash
# UserPromptSubmit hook: log aidd command usage and prompt history for /aidd:retro.
# Non-blocking: always exit 0, never fail the prompt submission.
input=$(cat)

STATE_DIR="$HOME/.claude/aidd"
USAGE_FILE="$STATE_DIR/usage.json"
MAX_LOG=200

mkdir -p "$STATE_DIR" 2>/dev/null

prompt=$(printf '%s' "$input" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get('prompt', ''))
except Exception:
    print('')
" 2>/dev/null)

[ -z "$prompt" ] && exit 0

python3 - "$USAGE_FILE" "$prompt" "$MAX_LOG" <<'PYEOF' 2>/dev/null
import json, re, sys
from datetime import datetime, timezone

usage_file, prompt, max_log = sys.argv[1], sys.argv[2], int(sys.argv[3])

try:
    with open(usage_file) as f:
        data = json.load(f)
except Exception:
    data = {}

data.setdefault("command_counts", {})
data.setdefault("prompt_log", [])

match = re.search(r"/aidd:([a-zA-Z0-9_-]+)", prompt)
if match:
    cmd = match.group(1)
    data["command_counts"][cmd] = data["command_counts"].get(cmd, 0) + 1

data["prompt_log"].append({
    "ts": datetime.now(timezone.utc).isoformat(),
    "text": prompt[:120],
})
data["prompt_log"] = data["prompt_log"][-max_log:]

with open(usage_file, "w") as f:
    json.dump(data, f)
PYEOF

exit 0
