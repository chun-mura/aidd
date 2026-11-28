#!/bin/bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
src="$repo_root/.codex/agents"

python3 "$repo_root/scripts/generate-codex-agents.py" --check

for name in aidd-reviewer aidd-refuter aidd-design-arbiter aidd-scout aidd-security-reviewer aidd-source-verifier; do
  file="$src/$name.toml"
  test -f "$file"
  grep -F -- "name = \"$name\"" "$file"
  grep -F -- "description = " "$file"
  grep -F -- "developer_instructions = " "$file"
  if grep -E '^(model|tools|sandbox_mode) ' "$file"; then
    echo "unexpected extra key in $file" >&2
    exit 1
  fi
done

# Filename must match the name field; no leftover Claude-only agent names.
for file in "$src"/*.toml; do
  base=$(basename "$file" .toml)
  grep -F -- "name = \"$base\"" "$file"
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

bash "$repo_root/scripts/install-codex-agents.sh" --dest "$tmp"
bash "$repo_root/scripts/install-codex-agents.sh" --check --dest "$tmp"

echo stale >> "$tmp/aidd-reviewer.toml"
if bash "$repo_root/scripts/install-codex-agents.sh" --check --dest "$tmp"; then
  echo "expected stale check to fail" >&2
  exit 1
fi

rm -f "$tmp/aidd-scout.toml"
if bash "$repo_root/scripts/install-codex-agents.sh" --check --dest "$tmp"; then
  echo "expected missing check to fail" >&2
  exit 1
fi

project=$(mktemp -d)
trap 'rm -rf "$tmp" "$project"' EXIT
(
  cd "$project"
  bash "$repo_root/scripts/install-codex-agents.sh" --project
)
test -f "$project/.codex/agents/aidd-reviewer.toml"
cmp -s "$src/aidd-reviewer.toml" "$project/.codex/agents/aidd-reviewer.toml"

# --- Codex: a shell read of autonomous-review's SKILL.md is denied (#225) -------------------------
# Codex has no Skill tool. Its model starts a skill by reading the SKILL.md with a shell command, and
# allow_implicit_invocation: false does not stop that (codex-cli 0.163.0). Codex ignores ask, so the
# Bash hook denies. Kept here, beside the other Codex-only contracts, rather than in hook-contract-test.sh.
gate_tmp=$(mktemp -d)
trap 'rm -rf "$tmp" "$project" "$gate_tmp"' EXIT
python3 - "$repo_root/hooks/hooks.json" <<'PYEOF'
import json, sys
pre = json.load(open(sys.argv[1]))["hooks"]["PreToolUse"]
bash = [e for e in pre if e["matcher"] == "Bash"]
assert len(bash) == 1, bash
commands = [h["command"] for h in bash[0]["hooks"]]
# tool-reminder keeps position 0 (Codex trusts a hook by its position); skill-gate is appended.
assert commands[0].endswith('/hooks/scripts/tool-reminder.sh"'), commands
assert commands[1].endswith('/hooks/scripts/skill-gate.sh"'), commands
assert len(commands) == 2, commands
PYEOF
mkdir -p "$gate_tmp/copy/skills/autonomous-review" "$gate_tmp/work"
cp "$repo_root/skills/autonomous-review/SKILL.md" "$gate_tmp/copy/skills/autonomous-review/SKILL.md"
ln -s "$repo_root/skills/autonomous-review" "$gate_tmp/alias-dir"
nopy_bin="$gate_tmp/nopy-bin"
mkdir -p "$nopy_bin"
for tool in bash cat grep dirname mkdir date mv rm printf tr; do
  src_tool=$(command -v "$tool" 2>/dev/null || true)
  [ -n "$src_tool" ] && [ "${src_tool#/}" != "$src_tool" ] && ln -sf "$src_tool" "$nopy_bin/$tool"
done
PATH="$nopy_bin" "$nopy_bin/bash" -c '! command -v python3'
python3 - "$repo_root" "$gate_tmp" "$nopy_bin" <<'PYEOF'
import json, os, subprocess, sys

root, tmp, nopy_bin = sys.argv[1:4]
gate = os.path.join(root, "hooks", "scripts", "skill-gate.sh")
state = os.path.join(tmp, "state")
own = os.path.join(root, "skills", "autonomous-review", "SKILL.md")
work = os.path.join(tmp, "work")


def run(command, cwd=work, extra=None, env_extra=None, path=None):
    # The shape of a Codex PreToolUse(Bash) event (tests/fixtures/hooks/codex/PreToolUse.bash-git-add-all.json).
    event = {"session_id": "s225", "turn_id": "t225", "cwd": cwd, "hook_event_name": "PreToolUse",
             "model": "gpt-test", "permission_mode": "default", "tool_name": "Bash",
             "tool_input": {"command": command, **(extra or {})}, "tool_use_id": "exec-225"}
    env = dict(os.environ, AIDD_TEST_STATE_DIR=state, **(env_extra or {}))
    argv = ["bash", gate]
    if path:
        env["PATH"] = path
        argv = [os.path.join(path, "bash"), gate]
    proc = subprocess.run(argv, input=json.dumps(event).encode(), stdout=subprocess.PIPE, env=env)
    assert proc.returncode == 0, (command, proc.returncode)
    return proc.stdout.decode()


def denied(out, case):
    o = json.loads(out)["hookSpecificOutput"]
    assert o["permissionDecision"] == "deny", (case, o)
    reason = o["permissionDecisionReason"]
    assert "シェル" in reason and "$aidd:autonomous-review" in reason, (case, reason)
    return True


deny_cases = [
    ("absolute cat", f"cat {own}", {}),
    ("sed range", f"sed -n '1,220p' '{own}'", {}),
    ("relative from cwd", "cat skills/autonomous-review/SKILL.md", {"cwd": root}),
    ("glob over every skill", f"cat {root}/skills/*/SKILL.md", {}),
    ("cd into the directory", f"cd {root}/skills/autonomous-review && cat SKILL.md", {}),
    ("python open", f"python3 -c \"print(open('{own}').read())\"", {}),
    ("plugin root variable", "cat \"$CLAUDE_PLUGIN_ROOT/skills/autonomous-review/SKILL.md\"",
     {"env": {"CLAUDE_PLUGIN_ROOT": root}}),
    ("link to the directory", f"cat {tmp}/alias-dir/SKILL.md", {}),
    ("workdir in the skill directory", "cat SKILL.md", {"extra": {"workdir": os.path.dirname(own)}}),
    ("file under the directory", f"cat {root}/skills/autonomous-review/agents/openai.yaml", {}),
]
for case, command, opts in deny_cases:
    out = run(command, cwd=opts.get("cwd", work), extra=opts.get("extra"), env_extra=opts.get("env"))
    assert out, case
    denied(out, case)
# An argv-list command is judged the same way.
denied(run(["bash", "-lc", f"cat {own}"]), "argv list")
# A case-insensitive filesystem (macOS default) opens the same file under another spelling.
upper = os.path.join(root, "SKILLS", "Autonomous-Review", "skill.md")
if os.path.exists(upper):
    denied(run(f"cat {upper}"), "case spelling")

pass_cases = [
    ("another skill", f"cat {root}/skills/adr/SKILL.md"),
    ("listing the skills", f"ls {root}/skills"),
    ("a copy outside the plugin", f"cat {tmp}/copy/skills/autonomous-review/SKILL.md"),
    ("unrelated command", "git status --short"),
    ("name in a message only", "git commit -m 'docs: mention autonomous-review'"),
]
for case, command in pass_cases:
    assert run(command) == "", case
counts = json.load(open(os.path.join(state, "skill-gate.json")))["counts"]
expected = len(deny_cases) + 1 + (1 if os.path.exists(upper) else 0)
assert counts == {"deny_shell_read": expected}, counts

# Without python3: a command naming the skill fails closed with deny (Codex treats ask as a failed hook
# and runs the command); a command without the name or "skill" exits before python is looked for.
denied(run(f"cat {own}", path=nopy_bin), "no python")
assert run("ls -la", path=nopy_bin) == ""
# The Skill tool still asks.
proc = subprocess.run(["bash", gate], input=json.dumps({"hook_event_name": "PreToolUse", "tool_name": "Skill",
                      "tool_input": {"skill": "aidd:autonomous-review"}}).encode(), stdout=subprocess.PIPE,
                      env=dict(os.environ, AIDD_TEST_STATE_DIR=state))
assert json.loads(proc.stdout)["hookSpecificOutput"]["permissionDecision"] == "ask"
print("codex shell-read gate: OK")
PYEOF
