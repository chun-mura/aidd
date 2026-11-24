#!/bin/bash
# Normalize Codex/Cursor hook input, call one aidd script, and convert the reply back.
# Always exits 0: Cursor treats a non-zero hook as a deny of the tool itself.
input=$(cat)
# Cursor sends every Read here for skill-gate.sh; only one SKILL.md matters, so skip python for a Read
# that surely is not that file. It exits only for an absolute path that exists, has no .., and is shown by
# [ -ef ] (links and the filesystem's case rules) to be another file, or when there is no file_path.
# Everything else goes to python and the gate, which also compares the text-normalized path: a missing path,
# .., a relative or ~ path, the skill name in any case, a backslash (JSON escapes), more than one file_path.
gate_may_read() {  # 0 when the input may Read this plugin's skills/autonomous-review/SKILL.md
  local rest=$1 path='' n=0 re='"file_path"[[:space:]]*:[[:space:]]*"([^"]*)"'
  case "$rest" in *\\*) return 0 ;; esac
  shopt -s nocasematch
  case "$rest" in *autonomous-review*) shopt -u nocasematch; return 0 ;; esac
  shopt -u nocasematch
  while [[ $rest =~ $re ]]; do
    n=$((n + 1))
    path=${BASH_REMATCH[1]}
    rest=${rest#*"${BASH_REMATCH[0]}"}
  done
  [ "$n" -le 1 ] || return 0
  [ -n "$path" ] || return 1
  [ "${path#/}" != "$path" ] || return 0
  # A trailing / or /. goes to python too: macOS stat sometimes finds a file behind "file/".
  case "$path" in */../* | */.. | */ | */.) return 0 ;; esac
  [ -e "$path" ] || return 0
  [ "$path" -ef "$(dirname "$0")/../../skills/autonomous-review/SKILL.md" ]
}
case "${1-}" in
  skill-gate.sh | */skill-gate.sh)
    gate_may_read "$input" || exit 0 ;;
esac
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
        specific = value.get("hookSpecificOutput")
        if specific is not None:
            if not isinstance(specific, dict):
                return ("bad", None)
            for key in ("permissionDecisionReason", "additionalContext"):
                if specific.get(key) is not None and not isinstance(specific[key], str):
                    return ("bad", None)
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
    denied = False
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
            denied = True
            text = reason_of(value)
            if text and text not in denials:
                denials.append(text)
        ctx = additional_of(value)
        if ctx and ctx not in contexts:
            contexts.append(ctx)
    if denied:
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
        return json.dumps({"additional_context": merged}, ensure_ascii=True)
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
        }, ensure_ascii=True)
    ctx = specific.get("additionalContext")
    if isinstance(ctx, str) and ctx:
        key = "agent_message" if event_name == "PreToolUse" else "additional_context"
        return json.dumps({key: ctx}, ensure_ascii=True)
    return ""


def convert_claude(merged):
    if merged is None:
        return ""
    if isinstance(merged, str):
        return merged if merged.endswith("\n") else merged + "\n"
    if isinstance(merged, dict):
        return json.dumps(merged, ensure_ascii=True)
    return None


def call_script(payload, skip):
    if not target:
        return "missing"
    if not os.path.isfile(target) or not os.access(target, os.X_OK):
        return "missing"
    env = os.environ.copy()
    env["CLAUDE_PLUGIN_ROOT"] = plugin_root
    try:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    except UnicodeError:
        # A lone surrogate (JSON.stringify writes one as \ud800) has no UTF-8 form. Pass it escaped,
        # so the script still judges the input (a Read of the gated SKILL.md must not slip through).
        data = json.dumps(payload).encode("ascii")
    try:
        proc = subprocess.run(
            [target],
            input=data,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            env=env,
        )
    except OSError:
        return "failed"
    parsed = parse_script_output(proc.stdout.decode("utf-8", "replace"))
    if proc.returncode != 0:
        skip("script_signaled" if proc.returncode < 0 else "script_nonzero_exit")
        if parsed[0] == "json" and is_deny(parsed[1]):
            return parsed
        return ("empty", None)
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
    if not cwd and orig_tool == "Read" and os.path.basename(target) == "skill-gate.sh":
        cwd = "/"  # the gate needs no cwd for an absolute path and already tries / for a relative one
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
                continue
            one = dict(normalized)
            one["tool_name"] = "Write"
            one["tool_input"] = {"file_path": abs_path(path, cwd)}
            got = call_script(one, skip)
            if got == "missing":
                skip("missing_script")
                continue
            if got == "failed":
                skip("script_failed")
                continue
            if got == "bad":
                skip("bad_output")
                continue
            results.append(got)
    else:
        got = call_script(normalized, skip)
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
