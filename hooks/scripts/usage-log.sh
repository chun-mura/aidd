#!/bin/bash
# UserPromptSubmit + PreToolUse(Skill/Task) hook: log aidd command usage for /aidd:retro.
# Non-blocking: always exit 0, never fail the prompt submission or the tool call.
# Records command counts and last-seen timestamps only.
# Opt-out: set AIDD_DISABLE_USAGE_LOG=1 (shell env or settings.json "env").
[ "$AIDD_DISABLE_USAGE_LOG" = "1" ] && exit 0
input=$(cat)

STATE_DIR="${AIDD_TEST_STATE_DIR:-$HOME/.claude/aidd}"
USAGE_FILE="$STATE_DIR/usage.json"
PLUGIN_ROOT=$(cd "$(dirname "$0")/../.." && pwd)

mkdir -p "$STATE_DIR" 2>/dev/null

python3 - "$USAGE_FILE" "$PLUGIN_ROOT" "$input" <<'PYEOF' 2>/dev/null
import fcntl, json, os, re, sys
from datetime import datetime, timezone

usage_file, plugin_root, raw = sys.argv[1], sys.argv[2], sys.argv[3]
now = datetime.now(timezone.utc).isoformat()

try:
    event = json.loads(raw)
except Exception:
    event = {}

# Both entry paths name the command as "aidd:<name>": the typed prompt on UserPromptSubmit,
# and the tool arguments when an agent invokes it via Skill or hands it to a subagent (Task).
# A single run may match on both paths, so command_counts is an upper bound; /aidd:retro
# judges staleness by last_seen.
haystacks = [event.get("prompt") or ""]
tool_input = event.get("tool_input")
if tool_input is not None:
    haystacks.append(json.dumps(tool_input, ensure_ascii=False))

names = set()
for text in haystacks:
    names.update(re.findall(r"aidd:([a-zA-Z0-9_-]+)", text))

# Only names backed by an actual asset are counted; a typo or half-typed string is not a command.
known = set()
try:
    known.update(
        os.path.splitext(f)[0]
        for f in os.listdir(os.path.join(plugin_root, "commands"))
        if f.endswith(".md")
    )
except OSError:
    pass
skills_dir = os.path.join(plugin_root, "skills")
try:
    known.update(
        d for d in os.listdir(skills_dir) if os.path.isdir(os.path.join(skills_dir, d))
    )
except OSError:
    pass
names &= known

lock_file = usage_file + ".lock"
with open(lock_file, "w") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)

    try:
        with open(usage_file) as f:
            data = json.load(f)
    except Exception:
        data = {}

    data.setdefault("command_counts", {})
    data.setdefault("last_seen", {})

    # prompt_log was removed in 0.25.0 but survives in existing installs, keeping prompt
    # fragments on disk after the feature was gone. Drop it wherever this hook runs.
    changed = data.pop("prompt_log", None) is not None

    for cmd in names:
        data["command_counts"][cmd] = data["command_counts"].get(cmd, 0) + 1
        data["last_seen"][cmd] = now
        changed = True

    if changed:
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
