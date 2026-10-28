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
