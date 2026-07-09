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
import fcntl, json, os, re, sys
from datetime import datetime, timezone

usage_file, prompt, max_log = sys.argv[1], sys.argv[2], int(sys.argv[3])
lock_file = usage_file + ".lock"
now = datetime.now(timezone.utc).isoformat()

with open(lock_file, "w") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)

    try:
        with open(usage_file) as f:
            data = json.load(f)
    except Exception:
        data = {}

    data.setdefault("command_counts", {})
    data.setdefault("last_seen", {})
    data.setdefault("prompt_log", [])

    match = re.search(r"/aidd:([a-zA-Z0-9_-]+)", prompt)
    if match:
        cmd = match.group(1)
        data["command_counts"][cmd] = data["command_counts"].get(cmd, 0) + 1
        data["last_seen"][cmd] = now

    data["prompt_log"].append({"ts": now, "text": prompt[:120]})
    data["prompt_log"] = data["prompt_log"][-max_log:]

    tmp_file = usage_file + ".tmp"
    old_umask = os.umask(0o077)
    try:
        with open(tmp_file, "w") as f:
            json.dump(data, f)
        os.replace(tmp_file, usage_file)
    finally:
        os.umask(old_umask)
PYEOF

exit 0
