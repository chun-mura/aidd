#!/bin/bash
# UserPromptSubmit hook: log aidd command usage for /aidd:retro.
# Non-blocking: always exit 0, never fail the prompt submission.
# Records command counts and last-seen timestamps only.
# Opt-out: set AIDD_DISABLE_USAGE_LOG=1 (shell env or settings.json "env").
[ "$AIDD_DISABLE_USAGE_LOG" = "1" ] && exit 0
input=$(cat)

STATE_DIR="${AIDD_TEST_STATE_DIR:-$HOME/.claude/aidd}"
USAGE_FILE="$STATE_DIR/usage.json"

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

python3 - "$USAGE_FILE" "$prompt" <<'PYEOF' 2>/dev/null
import fcntl, json, os, re, sys
from datetime import datetime, timezone

usage_file, prompt = sys.argv[1], sys.argv[2]
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

    match = re.search(r"/aidd:([a-zA-Z0-9_-]+)", prompt)
    if match:
        cmd = match.group(1)
        data["command_counts"][cmd] = data["command_counts"].get(cmd, 0) + 1
        data["last_seen"][cmd] = now

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
