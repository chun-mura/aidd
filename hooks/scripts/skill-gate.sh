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
import json, os, re, sys, urllib.parse

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
    def expand_home(p):  # Cursor expands only a leading ~ alone or before / or \ (not ~user)
        return re.sub(r"^~(?=$|/|\\)", lambda _: os.path.expanduser("~"), p)
    if isinstance(path, str) and path:
        # Node opens a lone surrogate (JSON.stringify sends it as \ud800) as U+FFFD, so read it the same way.
        path = re.sub("[\ud800-\udfff]", "\ufffd", path)
        candidates = [path]
        if path.startswith("file://"):
            # Cursor opens a file URI as the path it names (Node fileURLToPath, WHATWG URL rules), and the
            # raw text itself when that conversion throws, before ~ and cwd. Check both. For the URI, follow
            # those rules erring toward the SKILL.md: drop tabs and newlines and trailing controls and spaces,
            # read "\\" as "/", ignore the host, query and fragment, and percent-decode.
            rest = re.sub(r"[\t\n\r]", "", path).rstrip("".join(map(chr, range(0x21))))
            rest = rest[len("file://"):].replace("\\", "/")
            if "/" in rest:
                candidates.append(urllib.parse.unquote(re.split(r"[?#]", rest[rest.index("/"):], maxsplit=1)[0]))
        cwd = event.get("cwd")
        if isinstance(cwd, str):
            cwd = re.sub("[\ud800-\udfff]", "\ufffd", cwd)  # the adapter's cwd may carry one too
        def same(candidate):
            try:
                return os.path.samefile(candidate, own)
            except (OSError, ValueError):
                return False  # nothing there to read, or not a path (NUL)
        for candidate in candidates:
            candidate = expand_home(candidate)
            if isinstance(cwd, str) and cwd:
                candidate = os.path.join(cwd, candidate)  # a relative path is the reader's, not this hook's
            # The reader may resolve the path as text (a missing directory before .., or past PATH_MAX),
            # so a path that names the SKILL.md only once normalized is refused too.
            if same(candidate) or same(os.path.normpath(candidate)):
                reply("deny", deny_reason)
                break
        else:
            raw = expand_home(path)
            if not os.path.isabs(raw):
                # Cursor resolves a relative path (and a file URI it cannot convert) from its workspace when it
                # has one root, the roots' common parent when they share one, and else its own process cwd (a GUI
                # app's is usually /). The Read event has no cwd; the adapter fills in the first root. So try every
                # base Cursor could use: / and each ancestor of cwd. Drop the leading .. (they only pick the base)
                # and refuse when the rest names the SKILL.md from any of them.
                rest = os.path.normpath(raw).split("/")
                while rest and rest[0] == "..":
                    rest.pop(0)
                rest = "/".join(rest)
                bases = ["/"]
                if isinstance(cwd, str) and os.path.isabs(cwd):
                    base = os.path.normpath(cwd)
                    while base not in bases:
                        bases.append(base)
                        base = os.path.dirname(base)
                if any(same(os.path.join(base, rest)) for base in bases):
                    reply("deny", deny_reason)
PYEOF
)

kind=""
out=""
status=1
if command -v python3 >/dev/null 2>&1; then
  # -X utf8: harnesses speak UTF-8. Under a non-UTF-8 locale, python would decode this code and
  # its input by the locale and fail to print a Japanese verdict, losing it (#184).
  out=$(printf '%s' "$payload" | python3 -I -X utf8 -c "$PY_CODE" "$PLUGIN_ROOT" "$ASK_REASON" "$DENY_REASON" 2>/dev/null)
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
