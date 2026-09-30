#!/usr/bin/env python3
"""Generate the bundled aidd asset index and the strict prompt-hook template.

Run at release time (after adding, removing, or renaming a command, skill, agent, or hook):
    python3 scripts/generate-asset-index.py          # rewrite both outputs
    python3 scripts/generate-asset-index.py --check  # exit 1 if either output is stale

Component locations come from .claude-plugin/plugin.json, following the plugin manifest rules:
`skills` adds to the default skills/ scan, `commands` and `agents` replace their default scans,
and `hooks` is loaded together with hooks/hooks.json. Directories are never assumed beyond that.
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INDEX_PATH = "hooks/asset-index.json"
TEMPLATE_PATH = "templates/asset-overlap-prompt-hook.json.template"
KINDS = ["hooks", "skills", "commands", "rules", "agents"]


def as_list(value):
    if value is None:
        return []
    return value if isinstance(value, list) else [value]


def rel(path):
    return os.path.normpath(os.path.join(ROOT, path))


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


def commands(manifest):
    declared = manifest.get("commands")
    if isinstance(declared, dict):
        out = []
        for name, spec in declared.items():
            desc = spec.get("description")
            if desc is None and spec.get("source"):
                desc = frontmatter(rel(spec["source"])).get("description", "")
            out.append({"kind": "command", "name": name, "description": desc or ""})
        return out
    out = []
    for entry in as_list(declared) or ["./commands"]:
        path = rel(entry)
        if os.path.isdir(path):
            files = sorted(os.path.join(path, f) for f in os.listdir(path) if f.endswith(".md"))
        else:
            files = [path] if os.path.isfile(path) else []
        for f in files:
            out.append(md_entry("command", f, os.path.splitext(os.path.basename(f))[0]))
    return out


def skills(manifest):
    out = []
    for entry in ["./skills"] + as_list(manifest.get("skills")):
        path = rel(entry)
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


def agents(manifest):
    declared = as_list(manifest.get("agents"))
    if declared:
        files = [rel(p) for p in declared]
    else:
        base = rel("./agents")
        files = sorted(os.path.join(base, f) for f in os.listdir(base) if f.endswith(".md")) if os.path.isdir(base) else []
    return [md_entry("agent", f, os.path.splitext(os.path.basename(f))[0]) for f in files if os.path.isfile(f)]


def hooks(manifest):
    configs = []
    default = rel("hooks/hooks.json")
    if os.path.isfile(default):
        configs.append(json.load(open(default, encoding="utf-8")))
    for entry in as_list(manifest.get("hooks")):
        configs.append(json.load(open(rel(entry), encoding="utf-8")) if isinstance(entry, str) else entry)
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
            with open(rel(script), encoding="utf-8") as f:
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


def build_index():
    manifest = json.load(open(rel(".claude-plugin/plugin.json"), encoding="utf-8"))
    assets = commands(manifest) + skills(manifest) + agents(manifest) + hooks(manifest)
    return {"plugin": manifest["name"], "assets": assets}


def build_template(index):
    lines = "\n".join(f"- {a['kind']} {index['plugin']}:{a['name']}: {a['description']}" for a in index["assets"])
    prompt = (
        "You guard a project against re-creating assets that the installed aidd plugin already provides. "
        "Hook input: $ARGUMENTS\n\n"
        "If tool_input.file_path is not inside a .claude/hooks, .claude/skills, .claude/commands, "
        ".claude/rules, or .claude/agents directory, respond {\"ok\": true}.\n"
        "Otherwise read tool_input.content and decide whether the new asset's role substantially overlaps "
        "one of these aidd assets:\n" + lines + "\n\n"
        "If it overlaps, respond {\"ok\": false, \"reason\": \"<the aidd asset to use instead, and: if it "
        "falls short, file a request against aidd rather than creating a local copy>\"}. "
        "If it does not overlap, respond {\"ok\": true}."
    )
    handlers = [
        {"type": "prompt", "if": f"Edit(**/.claude/{kind}/**)", "prompt": prompt, "continueOnBlock": True}
        for kind in KINDS
    ]
    return {"hooks": {"PreToolUse": [{"matcher": "Write", "hooks": handlers}]}}


def render(obj):
    return json.dumps(obj, ensure_ascii=False, indent=2) + "\n"


def main():
    index = build_index()
    outputs = {INDEX_PATH: render(index), TEMPLATE_PATH: render(build_template(index))}
    if "--check" in sys.argv[1:]:
        stale = []
        for path, content in outputs.items():
            try:
                current = open(rel(path), encoding="utf-8").read()
            except OSError:
                current = None
            if current != content:
                stale.append(path)
        if stale:
            print("stale: " + ", ".join(stale) + " (run python3 scripts/generate-asset-index.py)", file=sys.stderr)
            return 1
        return 0
    for path, content in outputs.items():
        with open(rel(path), "w", encoding="utf-8") as f:
            f.write(content)
    return 0


if __name__ == "__main__":
    sys.exit(main())
