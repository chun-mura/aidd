#!/bin/bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)

[ ! -e "$repo_root/skills/parallel-investigation/SKILL.md" ]
grep -F '終了条件' "$repo_root/skills/review-loop/SKILL.md"
grep -F '棄却済み指摘' "$repo_root/skills/review-loop/SKILL.md"
grep -F 'Agent 4 にはセキュリティ観点を含めない' "$repo_root/skills/design-review/SKILL.md"
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

# The AI section must not demand design review / test perspectives for every change (#127).
# Lane and risk rules stay in issue-implement; the template only points there, and keeps #2
# (no design review gate on unrelated commits).
if grep -Fq '設計・実装方針の提示前: `/aidd:design-review`' "$claude_template" \
  || grep -Fq 'コミット前: `/aidd:test-perspectives`' "$claude_template"; then
  exit 1
fi
grep -F '`/aidd:issue-implement <番号>`' "$claude_template"
grep -F '「レーン判定」' "$claude_template"
grep -F '## 3. レーン判定' "$repo_root/skills/issue-implement/SKILL.md"
grep -F 'Issue を使わない開発' "$claude_template"
grep -F '実装前: `/aidd:test-perspectives`' "$claude_template"
# Every skill the template names must exist.
for skill in $(grep -o '/aidd:[a-z-]*' "$claude_template" | sed 's|/aidd:||' | sort -u); do
  [ -f "$repo_root/skills/$skill/SKILL.md" ]
done
