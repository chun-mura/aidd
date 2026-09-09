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

# The comment rule must keep both halves: the placement principle and the concrete
# counterexamples. The referenced source measured the principle alone as the weaker version.
claude_template="$repo_root/templates/CLAUDE.md.template"
grep -F 'コードには How、テストコードには What、コミットログには Why、コードコメントには Why not' "$claude_template"
grep -F 'それ以外は上記の置き場所へ移す' "$claude_template"
grep -F '実況型' "$claude_template"
grep -F '変更履歴' "$claude_template"
grep -F 'fixes JIRA-1234' "$claude_template"
