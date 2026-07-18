#!/bin/bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)

[ ! -e "$repo_root/skills/parallel-investigation/SKILL.md" ]
grep -F '終了条件' "$repo_root/skills/review-loop/SKILL.md"
grep -F '棄却済み指摘' "$repo_root/skills/review-loop/SKILL.md"
grep -F 'Agent 4 にはセキュリティ観点を含めない' "$repo_root/commands/design-review.md"
grep -F 'Agent 6' "$repo_root/templates/design-perspectives.md.template"
if grep -Fq '## セキュリティ' "$repo_root/templates/design-perspectives.md.template"; then
  exit 1
fi
