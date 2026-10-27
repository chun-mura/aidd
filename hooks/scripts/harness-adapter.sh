#!/bin/bash
# Normalize Codex/Cursor hook input, call one aidd script, and convert the reply back.
# Always exits 0: Cursor treats a non-zero hook as a deny of the tool itself.
input=$(cat)
state_dir="${AIDD_TEST_STATE_DIR:-$HOME/.claude/aidd}"
if ! command -v python3 >/dev/null 2>&1; then
  mkdir -p "$state_dir" 2>/dev/null || true
  skip_path="$state_dir/adapter-skips.json"
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || true)
  if [ ! -s "$skip_path" ]; then
    if printf '{"entries":[{"harness":"","harness_version":"","event":"","tool_name":"","reason":"no_python3","count":1,"last_seen":"%s"}]}\n' "$ts" > "$skip_path.tmp"; then
      mv "$skip_path.tmp" "$skip_path" || rm -f "$skip_path.tmp"
    fi
  fi
  exit 0
fi
script_dir=$(cd "$(dirname "$0")" && pwd)
plugin_root=$(cd "$script_dir/../.." && pwd)
target="${1-}"
if [ -n "$target" ] && [ "${target#/}" = "$target" ]; then
  target="$script_dir/$target"
fi

PY_CODE=$(cat <<'PYEOF'
import fcntl, json, os, subprocess, sys
from datetime import datetime, timezone

plugin_root, state_dir, target = sys.argv[1], sys.argv[2], sys.argv[3]
raw = sys.stdin.read()

EVENT_MAP = {
    "preToolUse": "PreToolUse",
    "postToolUse": "PostToolUse",
    "postToolUseFailure": "PostToolUseFailure",
    "sessionStart": "SessionStart",
}


def now():
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def record_skip(harness, harness_version, event, tool_name, reason):
    try:
        os.makedirs(state_dir, exist_ok=True)
        path = os.path.join(state_dir, "adapter-skips.json")
        with open(path + ".lock", "w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            try:
                with open(path, encoding="utf-8") as f:
                    data = json.load(f)
            except Exception:
                data = {}
            if not isinstance(data, dict):
                data = {}
            entries = data.get("entries")
            if not isinstance(entries, list):
                entries = []
                data["entries"] = entries
            key = (harness, harness_version, event, tool_name, reason)
            for item in entries:
                if (
                    item.get("harness") == key[0]
                    and item.get("harness_version") == key[1]
                    and item.get("event") == key[2]
                    and item.get("tool_name") == key[3]
                    and item.get("reason") == key[4]
                ):
                    item["count"] = int(item.get("count") or 0) + 1
                    item["last_seen"] = now()
                    break
            else:
                entries.append({
                    "harness": harness,
                    "harness_version": harness_version,
                    "event": event,
                    "tool_name": tool_name,
                    "reason": reason,
                    "count": 1,
                    "last_seen": now(),
                })
            old_umask = os.umask(0o077)
            try:
                with open(path + ".tmp", "w", encoding="utf-8") as f:
                    json.dump(data, f, ensure_ascii=False)
                os.replace(path + ".tmp", path)
            finally:
                os.umask(old_umask)
    except Exception:
        return


def top_keys(value):
    return set(value) if isinstance(value, dict) else set()


def is_cursor(event):
    keys = top_keys(event)
    if "cursor_version" in keys:
        return True
    name = event.get("hook_event_name")
    return isinstance(name, str) and name[:1].islower()


def resolve_cwd(event):
    cwd = event.get("cwd")
    if isinstance(cwd, str) and cwd.strip():
        return cwd
    env_cwd = os.environ.get("CURSOR_PROJECT_DIR")
    if env_cwd and env_cwd.strip():
        return env_cwd
    roots = event.get("workspace_roots")
    if isinstance(roots, list) and roots and isinstance(roots[0], str) and roots[0].strip():
        return roots[0]
    return ""


def extract_new_paths(command):
    if not isinstance(command, str) or "***" not in command:
        return None
    paths = []
    for line in command.splitlines():
        if line.startswith("*** Add File:"):
            paths.append(line[len("*** Add File:"):].strip())
        elif line.startswith("*** Move to:"):
            paths.append(line[len("*** Move to:"):].strip())
    return paths


def abs_path(path, cwd):
    path = os.path.expanduser(path)
    if not os.path.isabs(path):
        path = os.path.join(cwd, path)
    return os.path.normpath(path)


def normalize(event, cwd):
    out = dict(event)
    for key in ("user_email", "generation_id", "cursor_version", "workspace_roots"):
        out.pop(key, None)
    name = out.get("hook_event_name")
    if name in EVENT_MAP:
        out["hook_event_name"] = EVENT_MAP[name]
    if out.get("tool_name") == "Shell":
        out["tool_name"] = "Bash"
    out["cwd"] = cwd
    return out


def parse_script_output(text):
    if not text:
        return ("empty", None)
    try:
        value = json.loads(text)
    except Exception:
        return ("text", text)
    if isinstance(value, dict):
        return ("json", value)
    return ("bad", None)


def reason_of(obj):
    specific = obj.get("hookSpecificOutput") or {}
    return specific.get("permissionDecisionReason") or ""


def additional_of(obj):
    specific = obj.get("hookSpecificOutput") or {}
    ctx = specific.get("additionalContext")
    return ctx if isinstance(ctx, str) else ""


def is_deny(obj):
    specific = obj.get("hookSpecificOutput") or {}
    return specific.get("permissionDecision") == "deny"


def merge_results(results, event_name):
    denials = []
    contexts = []
    texts = []
    for kind, value in results:
        if kind == "empty":
            continue
        if kind == "text":
            if value and value not in texts:
                texts.append(value)
            continue
        if kind != "json":
            return None
        if is_deny(value):
            text = reason_of(value)
            if text and text not in denials:
                denials.append(text)
        ctx = additional_of(value)
        if ctx and ctx not in contexts:
            contexts.append(ctx)
    if denials:
        specific = {
            "hookEventName": event_name or "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": "\n".join(denials),
        }
        if contexts:
            specific["additionalContext"] = "\n".join(contexts)
        return {"hookSpecificOutput": specific}
    if contexts:
        return {"hookSpecificOutput": {
            "hookEventName": event_name or "PreToolUse",
            "additionalContext": "\n".join(contexts),
        }}
    if len(texts) == 1:
        return texts[0]
    if texts:
        return "\n".join(texts)
    if len(results) == 1 and results[0][0] == "json":
        return results[0][1]
    return None


def convert_cursor(merged, event_name):
    if merged is None:
        return ""
    if isinstance(merged, str):
        return json.dumps({"additional_context": merged}, ensure_ascii=False)
    if not isinstance(merged, dict):
        return None
    specific = merged.get("hookSpecificOutput") or {}
    if specific.get("permissionDecision") == "deny":
        reason = specific.get("permissionDecisionReason") or ""
        ctx = specific.get("additionalContext")
        agent = reason
        if isinstance(ctx, str) and ctx:
            agent = (reason + "\n" + ctx) if reason else ctx
        return json.dumps({
            "permission": "deny",
            "user_message": reason,
            "agent_message": agent,
        }, ensure_ascii=False)
    ctx = specific.get("additionalContext")
    if isinstance(ctx, str) and ctx:
        key = "agent_message" if event_name == "PreToolUse" else "additional_context"
        return json.dumps({key: ctx}, ensure_ascii=False)
    return ""


def convert_claude(merged):
    if merged is None:
        return ""
    if isinstance(merged, str):
        return merged if merged.endswith("\n") else merged + "\n"
    if isinstance(merged, dict):
        return json.dumps(merged, ensure_ascii=False)
    return None


def call_script(payload):
    if not target:
        return "missing"
    if not os.path.isfile(target) or not os.access(target, os.X_OK):
        return "missing"
    env = os.environ.copy()
    env["CLAUDE_PLUGIN_ROOT"] = plugin_root
    try:
        proc = subprocess.run(
            [target],
            input=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            env=env,
        )
    except OSError:
        return "failed"
    parsed = parse_script_output(proc.stdout.decode("utf-8", "replace"))
    if parsed[0] == "bad":
        return "bad"
    return parsed


def main():
    try:
        event = json.loads(raw)
    except Exception:
        event = None
    if not isinstance(event, dict):
        record_skip("codex", "", "", "", "invalid_json")
        return

    cursor = is_cursor(event)
    harness = "cursor" if cursor else "codex"
    harness_version = event.get("cursor_version") if cursor and isinstance(event.get("cursor_version"), str) else ""
    orig_event = event.get("hook_event_name") if isinstance(event.get("hook_event_name"), str) else ""
    orig_tool = event.get("tool_name") if isinstance(event.get("tool_name"), str) else ""

    def skip(reason):
        record_skip(harness, harness_version, orig_event, orig_tool, reason)

    if not target or not os.path.isfile(target) or not os.access(target, os.X_OK):
        skip("missing_script")
        return

    cwd = resolve_cwd(event)
    if not cwd:
        skip("no_cwd")
        return

    normalized = normalize(event, cwd)
    event_name = normalized.get("hook_event_name") or ""
    results = []

    if orig_tool == "apply_patch":
        command = (normalized.get("tool_input") or {}).get("command")
        paths = extract_new_paths(command)
        if paths is None:
            skip("unparsed_patch")
            return
        for path in paths:
            if not path:
                skip("unparsed_patch")
                return
            one = dict(normalized)
            one["tool_name"] = "Write"
            one["tool_input"] = {"file_path": abs_path(path, cwd)}
            got = call_script(one)
            if got == "missing":
                skip("missing_script")
                return
            if got == "failed":
                skip("script_failed")
                return
            if got == "bad":
                skip("bad_output")
                return
            results.append(got)
    else:
        got = call_script(normalized)
        if got == "missing":
            skip("missing_script")
            return
        if got == "failed":
            skip("script_failed")
            return
        if got == "bad":
            skip("bad_output")
            return
        results.append(got)

    merged = merge_results(results, event_name)
    if cursor:
        out = convert_cursor(merged, event_name)
    else:
        out = convert_claude(merged)
    if out is None:
        skip("bad_output")
        return
    if out:
        sys.stdout.write(out if out.endswith("\n") else out + "\n")


try:
    main()
except Exception:
    record_skip("codex", "", "", "", "bad_output")
PYEOF
)

printf '%s' "$input" | python3 -I -c "$PY_CODE" "$plugin_root" "$state_dir" "$target" 2>/dev/null || true
exit 0
