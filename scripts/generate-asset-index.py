#!/usr/bin/env python3
"""Generate the bundled aidd asset index and the strict prompt-hook template.

Run at release time (after adding, removing, or renaming a command, skill, agent, or hook):
    python3 scripts/generate-asset-index.py          # rewrite both outputs
    python3 scripts/generate-asset-index.py --check  # exit 1 if either output is stale

Component locations come from .claude-plugin/plugin.json; scripts/asset_index.py reads them, and
write-guard.sh reads other plugins with the same module.
"""
import json
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asset_index  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INDEX_PATH = "hooks/asset-index.json"
TEMPLATE_PATH = "templates/asset-overlap-prompt-hook.json.template"
KINDS = ["hooks", "skills", "commands", "rules", "agents"]


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


def rel(path):
    return asset_index.rel(ROOT, path)


def render(obj):
    return json.dumps(obj, ensure_ascii=False, indent=2) + "\n"


def main():
    index = asset_index.build_index(ROOT)
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
