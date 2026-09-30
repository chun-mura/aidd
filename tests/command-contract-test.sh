#!/bin/bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
design_review="$repo_root/commands/design-review.md"
reviewer="$repo_root/agents/reviewer.md"
refuter="$repo_root/agents/refuter.md"
eval_command="$repo_root/commands/eval.md"
review_loop="$repo_root/skills/review-loop/SKILL.md"
adr_command="$repo_root/commands/adr.md"

grep -F -- '--depth=standard|deep' "$design_review"
grep -F -- '既定は `--depth=standard`' "$design_review"
grep -F -- '`--depth=deep`' "$design_review"
grep -F -- 'high/mid がなければ refuter を起動しない' "$design_review"
grep -F -- 'standard では反証後の high/mid を直接報告する' "$design_review"
grep -F -- '指摘なしの場合は' "$reviewer"
grep -F -- '1行だけ' "$reviewer"
grep -F -- '引用箇所と必要最小限の関連パス' "$refuter"
grep -F -- '`--depth=deep`' "$eval_command"
grep -F -- '--review-delta' "$design_review"
grep -F -- '差分と必要な周辺文脈' "$design_review"
grep -F -- '全体再レビュー' "$design_review"
grep -F -- '初回を含めて最大3ラウンド' "$review_loop"
grep -F -- 'deferred mid' "$review_loop"
grep -F -- '`/aidd:issue-split`' "$review_loop"
grep -F -- '`.aidd/review-dismissed.md` への理由つき追記' "$review_loop"
grep -F -- '追跡先が確定しない指摘は `deferred mid` にできず' "$review_loop"
grep -F -- '全ソースの最大番号 +1' "$adr_command"
grep -F -- 'git symbolic-ref --quiet refs/remotes/origin/HEAD' "$adr_command"
grep -F -- 'refs/remotes/origin/' "$adr_command"
grep -F -- '検討した代替案' "$adr_command"

# incident-retro picks the first matching tier, so the ADR tier must come before the rule
# tier (a design decision also reads as a rule with judgment), and deferred work is folded
# into the code tier instead of being a trailing tier that the code tier already shadows.
incident_retro="$repo_root/commands/incident-retro.md"
adr_line=$(grep -n '^[0-9]\. \*\*決定とその理由を残すもの\*\*' "$incident_retro" | cut -d: -f1)
rule_line=$(grep -n '^[0-9]\. \*\*判断を伴う規則\*\*' "$incident_retro" | cut -d: -f1)
[ -n "$adr_line" ] && [ -n "$rule_line" ] && [ "$adr_line" -lt "$rule_line" ]
grep -F -- '今すぐ直せない・直さないなら、その作業は `/aidd:issue-split` か issue に委ねる' "$incident_retro"
if grep -Fq -- '**今すぐ直せない作業**' "$incident_retro"; then
  exit 1
fi

# asset-audit must not silently continue when its state write fails (e.g. under the sandbox),
# or the SessionStart nudge never stops.
grep -F -- '書き込みに失敗したら黙って続けない' "$repo_root/commands/asset-audit.md"
