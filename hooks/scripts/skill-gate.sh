#!/bin/bash
# PreToolUse(Skill) hook, and Cursor Read via harness-adapter: ask before the model starts autonomous-review.
# The decision is printed before the best-effort count, and the script always exits 0:
# a hook that fails to run lets the Skill through (measured), so nothing here may fail first.
# Fail-closed: input that cannot be judged but names the skill gets an ask.
# Counts per decision kind go to ~/.claude/aidd/skill-gate.json (opt-out: AIDD_DISABLE_USAGE_LOG=1).

STATE_DIR="${AIDD_TEST_STATE_DIR:-$HOME/.claude/aidd}"
PLUGIN_ROOT=$(cd "$(dirname "$0")/../.." && pwd -P)
payload=$(cat)

ASK_REASON="autonomous-review の実行にはユーザーの許可が必要です。許可すると、リポジトリのコードと差分を外部の Codex に送り、指摘に応じてコードを修正し、品質ゲートを実行します。時間がかかります。"
DENY_REASON="autonomous-review はモデルからは起動できません。ユーザーに /autonomous-review を手で実行するよう依頼してください。"

PY_CODE=$(cat <<'PYEOF'
import json, os, sys, urllib.parse

plugin_root, ask_reason, deny_reason = sys.argv[1:4]

def reply(decision, reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": decision,
        "permissionDecisionReason": reason,
    }}, ensure_ascii=False))

event = json.loads(sys.stdin.read())
tool_input = event.get("tool_input")
if not isinstance(tool_input, dict):
    sys.exit(3)  # cannot judge: the shell falls back to the raw-text check

if event.get("tool_name") == "Skill":
    skill = tool_input.get("skill")
    if not isinstance(skill, str):
        sys.exit(3)
    if skill.strip().lstrip("/").lower().split(":")[-1] == "autonomous-review":
        reply("ask", ask_reason)
elif event.get("tool_name") == "Read":
    # Cursor loads a skill by reading its SKILL.md. Only this plugin's copy is refused,
    # so editing the aidd repository itself in Cursor keeps working.
    # Compare the files, not the strings: a case-insensitive filesystem (macOS default) or a link
    # opens the same SKILL.md under another spelling.
    path = tool_input.get("file_path")
    own = os.path.join(plugin_root, "skills", "autonomous-review", "SKILL.md")
    if isinstance(path, str) and path:
        if path.startswith("file://"):
            # Cursor opens a file URI as the percent-decoded path it names, before ~ and cwd.
            parts = urllib.parse.urlsplit(path)
            if parts.netloc.lower() in ("", "localhost"):
                path = urllib.parse.unquote(parts.path)
        path = os.path.expanduser(path)
        cwd = event.get("cwd")
        if isinstance(cwd, str) and cwd:
            path = os.path.join(cwd, path)  # a relative path is the reader's, not this hook's
        def same(candidate):
            try:
                return os.path.samefile(candidate, own)
            except (OSError, ValueError):
                return False  # nothing there to read, or not a path (NUL)
        # The reader may resolve the path as text (a missing directory before .., or past PATH_MAX),
        # so a path that names the SKILL.md only once normalized is refused too.
        if same(path) or same(os.path.normpath(path)):
            reply("deny", deny_reason)
PYEOF
)

kind=""
out=""
status=1
if command -v python3 >/dev/null 2>&1; then
  out=$(printf '%s' "$payload" | python3 -I -c "$PY_CODE" "$PLUGIN_ROOT" "$ASK_REASON" "$DENY_REASON" 2>/dev/null)
  status=$?
fi
if [ "$status" -eq 0 ]; then
  if [ -n "$out" ]; then
    printf '%s\n' "$out"
    case "$out" in
      *'"permissionDecision": "ask"'*) kind=ask ;;
      *'"permissionDecision": "deny"'*) kind=deny_cursor_read ;;
    esac
  fi
elif printf '%s' "$payload" | grep -qi 'autonomous-review'; then
  # A Read can only come from Cursor, which ignores ask, so failing closed there means deny.
  if printf '%s' "$payload" | tr -d '\r\n' | grep -q '"tool_name"[[:space:]]*:[[:space:]]*"Read"'; then
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$DENY_REASON"
  else
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' "$ASK_REASON"
  fi
  kind=ask_failclosed
fi

# Best-effort count, after the decision is out. Any failure here is ignored.
if [ -n "$kind" ] && [ "$AIDD_DISABLE_USAGE_LOG" != "1" ] && command -v python3 >/dev/null 2>&1; then
  python3 -I - "$STATE_DIR" "$kind" >/dev/null 2>&1 <<'PYEOF' || true
import fcntl, json, os, sys
from datetime import datetime, timezone

state_dir, kind = sys.argv[1], sys.argv[2]
os.makedirs(state_dir, exist_ok=True)
path = os.path.join(state_dir, "skill-gate.json")
with open(path + ".lock", "w") as lock:
    # Never wait: the decision is already out, and a hook killed at its timeout counts as failed.
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    try:
        with open(path) as f:
            data = json.load(f)
    except Exception:
        data = {}
    if not isinstance(data, dict):
        data = {}
    counts = data.get("counts") if isinstance(data.get("counts"), dict) else {}
    seen = data.get("last_seen") if isinstance(data.get("last_seen"), dict) else {}
    counts[kind] = counts.get(kind, 0) + 1
    seen[kind] = datetime.now(timezone.utc).isoformat()
    old_umask = os.umask(0o077)
    try:
        with open(path + ".tmp", "w") as f:
            json.dump({"counts": counts, "last_seen": seen}, f)
        os.replace(path + ".tmp", path)
    finally:
        os.umask(old_umask)
PYEOF
fi

exit 0
