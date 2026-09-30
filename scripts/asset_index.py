"""Read a plugin's commands, skills, agents, and hooks (name and description) from its directory.

Shared by scripts/generate-asset-index.py (aidd's bundled list, at release time) and
hooks/scripts/write-guard.sh (plugins named in AIDD_ASSET_OVERLAP_PLUGINS, at run time), so both
read a plugin the same way.

Component locations come from .claude-plugin/plugin.json, following the plugin manifest rules:
`skills` adds to the default skills/ scan, `commands` and `agents` replace their default scans,
and `hooks` is loaded together with hooks/hooks.json. Directories are never assumed beyond that.
The manifest is optional; without one the default layout is scanned and the plugin is named after
its directory, as Claude Code does for --plugin-dir.
"""
import json
import os
import re

MANIFEST = ".claude-plugin/plugin.json"


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
    for line in (match.group(1) if match else "").splitlines():
        m = re.match(r"([A-Za-z_-]+):\s*(.*)", line)
        if m:
            fields[m.group(1)] = m.group(2).strip().strip("\"'")
    return fields


def md_entry(kind, path, default_name):
    fm = frontmatter(path)
    return {"kind": kind, "name": fm.get("name") or default_name, "description": fm.get("description", "")}


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
    out = []
    for entry in as_list(declared) or ["./commands"]:
        path = rel(root, entry)
        if os.path.isdir(path):
            files = sorted(os.path.join(path, f) for f in os.listdir(path) if f.endswith(".md"))
        else:
            files = [path] if os.path.isfile(path) else []
        for f in files:
            out.append(md_entry("command", f, os.path.splitext(os.path.basename(f))[0]))
    return out


def skills(root, manifest):
    out = []
    for entry in ["./skills"] + as_list(manifest.get("skills")):
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
        files = [rel(root, p) for p in declared]
    else:
        base = rel(root, "./agents")
        files = sorted(os.path.join(base, f) for f in os.listdir(base) if f.endswith(".md")) if os.path.isdir(base) else []
    return [md_entry("agent", f, os.path.splitext(os.path.basename(f))[0]) for f in files if os.path.isfile(f)]


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
    assets = commands(root, manifest) + skills(root, manifest) + agents(root, manifest) + hooks(root, manifest)
    return {"plugin": manifest["name"], "assets": assets}
