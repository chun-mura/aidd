#!/bin/bash
# Write/Edit/NotebookEdit guard for new files: unreadable names, and assets aidd already has.
# Every check concerns a file that does not exist yet, so an existing target (or a non-matching
# path) exits with no output.
# No `if` filter in hooks.json on purpose: the checks match file names at any location, and
# asset directories both under the project and under ~/.claude, which one permission rule per
# handler cannot express.
input=$(cat)
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"

PY_CODE=$(cat <<'PYEOF'
import fnmatch, json, os, sys

# Claude Code has no built-in sandbox read-deny list (sandbox.filesystem.denyRead defaults to
# unset), so these are the names commonly put in denyRead / Read() deny rules. A file created
# under one of them cannot be read back by sandboxed commands (git add, tests, cat).
# Patterns use the sandbox path syntax; see patterns_for() for how each form is resolved.
DEFAULT_UNREADABLE = [
    ".env", ".env.*", "*.env",
    "*.pem", "*.key", "*.p12", "*.pfx", "*.jks", "*.keystore",
    "id_rsa*", "id_dsa*", "id_ecdsa*", "id_ed25519*", "authorized_keys", "known_hosts",
    "*credential*", "*secret*", "*token*.json", "*token*.txt",
    ".npmrc", ".pypirc", ".netrc", "*htpasswd*", "*kubeconfig*",
    "*service_account*.json", "*serviceaccount*.json",
    "/**/.ssh/**", "/**/.gnupg/**",
]

try:
    event = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)

tool_input = event.get("tool_input") or {}
raw_path = tool_input.get("file_path") or tool_input.get("notebook_path")
if not isinstance(raw_path, str) or not raw_path:
    sys.exit(0)
cwd = event.get("cwd") or os.getcwd()
path = os.path.expanduser(raw_path)
if not os.path.isabs(path):
    path = os.path.join(cwd, path)
path = os.path.normpath(path)
if os.path.lexists(path):
    sys.exit(0)


def deny(reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }}, ensure_ascii=False))
    sys.exit(0)


def patterns_for(pattern):
    """Return (kind, globs) for one pattern in the sandbox path syntax.

    A trailing "/" or "/**" marks a directory, and every path entry also covers what is under it,
    as denyRead does. "~/" is the home directory, "/" and "//" are absolute, and "./" or no prefix
    is relative to the hook input's cwd. A single name without "/" matches the file name at any
    depth, or, marked as a directory, a directory of that name at any depth under cwd.
    """
    is_dir = pattern.endswith("/**") or pattern.endswith("/")
    body = pattern[:-3] if pattern.endswith("/**") else pattern
    body = body.rstrip("/") or "/"
    if body == "~" or body.startswith("~/"):
        base = os.path.expanduser("~") + body[1:]
    elif body.startswith("/"):
        base = "/" + body.lstrip("/")
    elif "/" in body:
        base = os.path.normpath(os.path.join(cwd, body))
    elif is_dir:
        base = os.path.normpath(os.path.join(cwd, "**", body))
    else:
        return "name", [body]
    globs = []
    for glob in (base, base.rstrip("/") + "/*"):
        # fnmatch's "*" already crosses "/", so only the zero-directory case of "/**/" is added.
        globs += [glob, glob.replace("/**/", "/")]
    return "path", globs


def unreadable_name_guard():
    if os.environ.get("AIDD_DISABLE_UNREADABLE_NAME_GUARD") == "1":
        return
    override = os.environ.get("AIDD_UNREADABLE_NAME_PATTERNS")
    patterns = [p for p in override.split(":") if p] if override else DEFAULT_UNREADABLE
    name = os.path.basename(path)
    for pattern in patterns:
        kind, globs = patterns_for(pattern)
        subject = path if kind == "path" else name
        if any(fnmatch.fnmatchcase(subject, glob) for glob in globs):
            deny(
                f"aidd: '{name}' matches '{pattern}', a name sandboxed commands are commonly "
                "denied reading, so git, tests, and shell tools could not read the file after "
                "it is created. Pick a name that does not match. If this project's sandbox does "
                "not deny it, the user can set AIDD_UNREADABLE_NAME_PATTERNS (colon-separated) "
                "or AIDD_DISABLE_UNREADABLE_NAME_GUARD=1."
            )


def asset_overlap():
    # A consumer-side asset that duplicates an aidd one gets fixed in one place and goes stale in
    # the other, so the model is shown aidd's list at the moment of creation. Judging overlap is
    # left to the model; only an identical name is refused.
    if os.environ.get("AIDD_DISABLE_ASSET_OVERLAP") == "1":
        return
    kinds = os.environ.get("AIDD_ASSET_OVERLAP_DIRS") or "hooks:skills:commands:rules:agents"
    parts = path.split("/")
    hit = None
    for i in range(len(parts) - 2, 0, -1):
        if parts[i - 1] == ".claude" and parts[i] in kinds.split(":"):
            hit = i
            break
    if hit is None:
        return
    kind, first = parts[hit], parts[hit + 1]
    # A skill is its directory: a new file inside an existing skill is not a new asset.
    if kind == "skills" and hit + 1 < len(parts) - 1 and os.path.lexists("/".join(parts[:hit + 2])):
        return
    try:
        with open(os.path.join(sys.argv[1], "hooks", "asset-index.json"), encoding="utf-8") as f:
            index = json.load(f)
    except Exception:
        return
    plugin = index.get("plugin", "aidd")
    assets = index.get("assets", [])
    name = first if kind == "skills" else os.path.splitext(first)[0]
    same_kind = {"commands": ("command", "skill"), "skills": ("command", "skill"), "agents": ("agent",)}.get(kind, ())
    if os.environ.get("AIDD_ASSET_OVERLAP_DENY_SAME_NAME") != "0":
        for a in assets:
            if a.get("kind") in same_kind and a.get("name") == name:
                deny(
                    f"aidd: {plugin}:{name} ({a['kind']}) already exists: {a.get('description', '')} "
                    f"Use it instead of creating a same-named copy. If it falls short, file a request "
                    f"against {plugin} rather than forking it locally."
                )
    listing = "\n".join(f"- {a['kind']} {plugin}:{a['name']}: {a.get('description', '')}" for a in assets)
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "additionalContext": (
            f"aidd: a new {kind[:-1]} is being created. If one of these {plugin} assets covers "
            f"the same role, use it instead of creating a new one, or file a request against "
            f"{plugin}:\n{listing}"
        ),
    }}, ensure_ascii=False))


unreadable_name_guard()
asset_overlap()
PYEOF
)

printf '%s' "$input" | python3 -c "$PY_CODE" "$PLUGIN_ROOT" 2>/dev/null

exit 0
