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
ai_section=$(awk '/^## AI運用/{on=1; next} on && /^## /{on=0} on' "$claude_template")
[ -n "$ai_section" ]
# Reworded one-size rules must fail too, anywhere in the template: no skill tied to the
# commit step, and design-review only through the lane decision.
if grep -F 'コミット前' "$claude_template" | grep -Fq '/aidd:'; then
  exit 1
fi
if grep -F '/aidd:design-review' "$claude_template" | grep -Fvq 'レーン'; then
  exit 1
fi
printf '%s\n' "$ai_section" | grep -F 'design-review をコミットの必須条件にはしない'
printf '%s\n' "$ai_section" | grep -F '`/aidd:issue-implement <番号>`'
printf '%s\n' "$ai_section" | grep -F '「レーン判定」（aidd プラグインの `skills/issue-implement/SKILL.md`）'
grep -F '## 3. レーン判定' "$repo_root/skills/issue-implement/SKILL.md"
printf '%s\n' "$ai_section" | grep -F 'Issue を使わない開発'
# Before implementation the diff is empty, so the target must be passed as an argument.
printf '%s\n' "$ai_section" | grep -F '実装前: `/aidd:test-perspectives <設計書のパス、または変更内容の説明>`'
# Every skill the template names must exist.
for skill in $(grep -o '/aidd:[a-z-]*' "$claude_template" | sed 's|/aidd:||' | sort -u); do
  [ -f "$repo_root/skills/$skill/SKILL.md" ]
done
