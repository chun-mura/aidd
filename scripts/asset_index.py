"""Read a plugin's commands, skills, agents, and hooks (name and description) from its directory.

Shared by scripts/generate-asset-index.py (aidd's bundled list, at release time) and
hooks/scripts/write-guard.sh (plugins named in AIDD_ASSET_OVERLAP_PLUGINS, at run time), so both
read a plugin the same way.

Component locations come from .claude-plugin/plugin.json, following the plugin manifest rules:
`skills` adds to the default skills/ scan, `commands` and `agents` replace their default scans,
and `hooks` is loaded together with hooks/hooks.json. Directories are never assumed beyond that.
The manifest is optional; without one the default layout is scanned and the plugin is named after
its directory, as Claude Code does for --plugin-dir.

Names follow the standard layout: a SKILL.md at the plugin root is a single skill when there is no
skills/ directory and no `skills` key, and a subfolder of the default commands/ or agents/ adds a
`<subfolder>:` segment in front of the file name (or its frontmatter `name`).
"""
import json
import os
import re
import unicodedata

MANIFEST = ".claude-plugin/plugin.json"
# The plugins-reference `name` rule: no spaces, "@", ":", path separators, control characters, or
# bidirectional-formatting characters (the last two are Unicode categories Cc and Cf).
NAME_FORBIDDEN = set(" @:/\\")


def as_list(value):
    if value is None:
        return []
    return value if isinstance(value, list) else [value]


def rel(root, path):
    return os.path.normpath(os.path.join(root, path))


def frontmatter(path):
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except OSError:
        return {}
    match = re.match(r"---\n(.*?)\n---", text, re.S)
    fields = {}
    lines = (match.group(1) if match else "").splitlines()
    i = 0
    while i < len(lines):
        m = re.match(r"([A-Za-z_-]+):\s*(.*)", lines[i])
        i += 1
        if not m:
            continue
        value = m.group(2).strip()
        # A YAML block scalar (| or >, with optional chomping and indentation indicators) takes the
        # following indented or blank lines: `|` keeps the line breaks and `>` folds them into spaces.
        block = re.fullmatch(r"([|>])(?:[+-]?[1-9]?|[1-9][+-])(?:\s+#.*)?", value)
        if block:
            body = []
            while i < len(lines) and (not lines[i].strip() or lines[i][:1] in " \t"):
                body.append(lines[i].strip())
                i += 1
            value = ("\n" if block.group(1) == "|" else " ").join(body).strip()
        else:
            value = value.strip("\"'")
        fields[m.group(1)] = value
    return fields


def md_entry(kind, path, default_name, prefix=""):
    fm = frontmatter(path)
    return {"kind": kind, "name": prefix + (fm.get("name") or default_name), "description": fm.get("description", "")}


def md_tree(base):
    """Return (path, "<subfolder>:" prefix) for every .md file under base, subfolders included."""
    out = []
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames.sort()
        sub = os.path.relpath(dirpath, base)
        prefix = "" if sub == "." else sub.replace(os.sep, ":") + ":"
        out += [(os.path.join(dirpath, f), prefix) for f in sorted(filenames) if f.endswith(".md")]
    return out


def commands(root, manifest):
    declared = manifest.get("commands")
    if isinstance(declared, dict):
        out = []
        for name, spec in declared.items():
            desc = spec.get("description")
            if desc is None and spec.get("source"):
                desc = frontmatter(rel(root, spec["source"])).get("description", "")
            out.append({"kind": "command", "name": name, "description": desc or ""})
        return out
    if not declared:
        # The default commands/ directory: a subfolder adds a segment (commands/db/migrate.md is db:migrate).
        base = rel(root, "./commands")
        files = md_tree(base) if os.path.isdir(base) else []
    else:
        # A declared directory is scanned flat: the docs describe it only as a directory of flat
        # .md command files.
        files = []
        for entry in as_list(declared):
            path = rel(root, entry)
            if os.path.isdir(path):
                files += [(os.path.join(path, f), "") for f in sorted(os.listdir(path)) if f.endswith(".md")]
            elif os.path.isfile(path):
                files.append((path, ""))
    return [md_entry("command", f, os.path.splitext(os.path.basename(f))[0], prefix) for f, prefix in files]


def skills(root, manifest):
    out = []
    entries = ["./skills"] + as_list(manifest.get("skills"))
    # A SKILL.md at the plugin root loads as one skill only without skills/ and without a `skills` key.
    if (os.path.isfile(rel(root, "SKILL.md")) and not os.path.isdir(rel(root, "./skills"))
            and "skills" not in manifest):
        entries = ["."]
    for entry in entries:
        path = rel(root, entry)
        if os.path.isfile(os.path.join(path, "SKILL.md")):
            dirs = [path]
        elif os.path.isdir(path):
            dirs = sorted(
                os.path.join(path, d) for d in os.listdir(path)
                if os.path.isfile(os.path.join(path, d, "SKILL.md"))
            )
        else:
            dirs = []
        for d in dirs:
            out.append(md_entry("skill", os.path.join(d, "SKILL.md"), os.path.basename(d)))
    return out


def agents(root, manifest):
    declared = as_list(manifest.get("agents"))
    if declared:
        # A file listed in the manifest loads without subfolder names.
        files = [(rel(root, p), "") for p in declared]
    else:
        # The default agents/ directory loads recursively: each subfolder adds a segment, and a
        # frontmatter name replaces only the file name (agents/review/security.md is review:security).
        base = rel(root, "./agents")
        files = md_tree(base) if os.path.isdir(base) else []
    return [md_entry("agent", f, os.path.splitext(os.path.basename(f))[0], prefix) for f, prefix in files if os.path.isfile(f)]


def hooks(root, manifest):
    configs = []
    default = rel(root, "hooks/hooks.json")
    if os.path.isfile(default):
        configs.append(json.load(open(default, encoding="utf-8")))
    for entry in as_list(manifest.get("hooks")):
        configs.append(json.load(open(rel(root, entry), encoding="utf-8")) if isinstance(entry, str) else entry)
    events = {}
    for config in configs:
        for event, groups in (config.get("hooks", config) or {}).items():
            for group in groups:
                for handler in group.get("hooks", []):
                    m = re.search(r"\$\{CLAUDE_PLUGIN_ROOT\}\"?/([^\"\s]+)", handler.get("command", ""))
                    if m:
                        events.setdefault(m.group(1), []).append(event)
    out = []
    for script, evs in sorted(events.items()):
        desc = ""
        try:
            with open(rel(root, script), encoding="utf-8") as f:
                for line in f:
                    if line.startswith("#!"):
                        continue
                    if line.startswith("#"):
                        desc = line.lstrip("# ").strip()
                    break
        except OSError:
            pass
        name = os.path.splitext(os.path.basename(script))[0]
        out.append({"kind": "hook", "name": name, "description": f"[{', '.join(sorted(set(evs)))}] {desc}"})
    return out


def valid_name(name):
    return isinstance(name, str) and bool(name) and not any(
        c in NAME_FORBIDDEN or unicodedata.category(c) in ("Cc", "Cf") for c in name
    )


def build_index(root):
    """Return {"plugin", "assets"}; raises on an unreadable manifest or component file."""
    path = rel(root, MANIFEST)
    if os.path.isfile(path):
        with open(path, encoding="utf-8") as f:
            manifest = json.load(f)
        if not isinstance(manifest, dict) or not manifest.get("name"):
            raise ValueError(f"{MANIFEST} has no name")
    else:
        manifest = {"name": os.path.basename(os.path.normpath(root))}
    # Claude Code does not load a plugin whose name breaks the naming rule. The name is not echoed,
    # since it is the part that failed the check.
    if not valid_name(manifest["name"]):
        raise ValueError("plugin name breaks the plugins-reference naming rule")
    assets = commands(root, manifest) + skills(root, manifest) + agents(root, manifest) + hooks(root, manifest)
    return {"plugin": manifest["name"], "assets": assets}
