#!/bin/bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
design_review="$repo_root/commands/design-review.md"
reviewer="$repo_root/agents/reviewer.md"
refuter="$repo_root/agents/refuter.md"
eval_command="$repo_root/commands/eval.md"

grep -F -- '--depth=standard|deep' "$design_review"
grep -F -- '既定は `--depth=standard`' "$design_review"
grep -F -- '`--depth=deep`' "$design_review"
grep -F -- 'high/mid がなければ refuter を起動しない' "$design_review"
grep -F -- 'standard では反証後の high/mid を直接報告する' "$design_review"
grep -F -- '指摘なしの場合は' "$reviewer"
grep -F -- '1行だけ' "$reviewer"
grep -F -- '引用箇所と必要最小限の関連パス' "$refuter"
grep -F -- '`--depth=deep`' "$eval_command"
