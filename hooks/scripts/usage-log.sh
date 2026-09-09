#!/bin/bash
# UserPromptSubmit + PreToolUse(Skill) hook: log aidd command usage for /aidd:retro.
# Non-blocking: always exit 0, never fail the prompt submission or the tool call.
# Records command counts and last-seen timestamps only.
# Opt-out: set AIDD_DISABLE_USAGE_LOG=1 (shell env or settings.json "env").
[ "$AIDD_DISABLE_USAGE_LOG" = "1" ] && exit 0

STATE_DIR="${AIDD_TEST_STATE_DIR:-$HOME/.claude/aidd}"
USAGE_FILE="$STATE_DIR/usage.json"
PLUGIN_ROOT=$(cd "$(dirname "$0")/../.." && pwd)

mkdir -p "$STATE_DIR" 2>/dev/null

# The payload stays on stdin. Passing it as an argument breaks past ARG_MAX (a subagent
# prompt can carry a whole diff), and exec would fail silently, dropping the record.
PY_CODE=$(cat <<'PYEOF'
import fcntl, json, os, re, sys
from datetime import datetime, timezone

usage_file, plugin_root = sys.argv[1], sys.argv[2]
now = datetime.now(timezone.utc).isoformat()

try:
    event = json.loads(sys.stdin.read())
except Exception:
    event = {}

names = set()
tool_input = event.get("tool_input") or {}

# Only actual invocations are counted, on the two paths that identify one:
#   - the Skill tool, which names the command in tool_input.skill (this also covers a
#     subagent's own invocation, since plugin hooks fire inside subagents)
#   - a prompt that starts with the slash command
# Scanning free text for "aidd:<name>" was tried and reverted: a single run counted 4 times
# (parent prompt, Agent dispatch prompt, the subagent's Skill call, task notification),
# and a prompt that merely discusses a command is not a use of it.
if event.get("tool_name") == "Skill":
    skill = tool_input.get("skill")
    if isinstance(skill, str) and skill.startswith("aidd:"):
        names.add(skill[len("aidd:"):])
else:
    match = re.match(r"\s*/aidd:([a-zA-Z0-9_-]+)", event.get("prompt") or "")
    if match:
        names.add(match.group(1))

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
)

python3 -c "$PY_CODE" "$USAGE_FILE" "$PLUGIN_ROOT" 2>/dev/null

exit 0
