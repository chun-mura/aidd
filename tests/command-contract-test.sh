#!/bin/bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
design_review="$repo_root/skills/design-review/SKILL.md"
reviewer="$repo_root/agents/reviewer.md"
refuter="$repo_root/agents/refuter.md"
eval_command="$repo_root/skills/eval/SKILL.md"
review_loop="$repo_root/skills/review-loop/SKILL.md"
adr_command="$repo_root/skills/adr/SKILL.md"
issue_implement="$repo_root/skills/issue-implement/SKILL.md"
design_doc="$repo_root/skills/design-doc/SKILL.md"
test_perspectives="$repo_root/skills/test-perspectives/SKILL.md"

grep -F -- '--depth=standard|deep' "$design_review"
grep -F -- '既定は `--depth=standard`' "$design_review"
grep -F -- '`--depth=deep`' "$design_review"
grep -F -- 'high/mid がなければ refuter を起動しない' "$design_review"
grep -F -- 'standard では反証後の high/mid を直接報告する' "$design_review"
grep -F -- '指摘なしの場合は' "$reviewer"
grep -F -- '1行だけ' "$reviewer"
grep -F -- '引用箇所と必要最小限の関連パス' "$refuter"
grep -F -- '`--depth=deep`' "$eval_command"
grep -F -- 'arbiter に渡す前に偽指摘を取り除く' "$eval_command"
grep -F -- '偽指摘の棄却率' "$eval_command"
grep -F -- 'reviewer の high/mid が0件でも' "$eval_command"
grep -F -- '判定エージェントを2体' "$eval_command"
grep -F -- '引用のない判定は無効' "$eval_command"
grep -F -- 'ノイズ率' "$eval_command"
grep -F -- '--review-delta' "$design_review"
grep -F -- '差分と必要な周辺文脈' "$design_review"
grep -F -- '全体再レビュー' "$design_review"
# Agent 2 covers the data model and the design-level part of performance (#85).
# N+1 is decided in the implementation, so the perspective must exclude it explicitly.
grep -F -- 'スキーマを緩める選択に、理由と検討した代替案' "$design_review"
# design-doc asks for a rationale only for schema-loosening choices, so the review must
# not ask for one on ordinary type choices (#93).
grep -F -- 'それ以外の型の選択には根拠の記載を求めない' "$design_review"
if grep -Fq -- '型の選択と正規化に根拠があるか' "$design_review"; then
  exit 1
fi
grep -F -- 'インデックスの前提' "$design_review"
grep -F -- '件数の上限なく全件を読む経路' "$design_review"
grep -F -- 'N+1 などクエリの実装で決まることは扱わない' "$design_review"
# Agent 2 checks concurrent access only when the design shows it, and design-doc asks for the
# countermeasure in the same section, so the two stay one-to-one (#3).
grep -F -- '競合・二重実行・破損への対策 (排他、冪等、楽観ロック、原子的な書き込みなど) が書かれているか' "$design_review"
grep -F -- '同時アクセスが設計書から読み取れない場合は推測で指摘しない' "$design_review"
grep -F -- '競合・二重実行・破損への対策 (排他、冪等、楽観ロック、原子的な書き込みなど) を書く' "$design_doc"
# Storing sensitive data goes to Agent 6, not Agent 2, because security stays in one agent (#3).
grep -F -- '機微情報 (個人情報・プロンプト・認証情報など) をファイル・ログ・キャッシュに保存する場合' "$design_review"
grep -F -- 'stored in files, logs, or caches that other users or processes may read' "$repo_root/agents/security-reviewer.md"
grep -F -- 'または機微情報をファイル・ログ・キャッシュに保存する場合は、レビュー結果の最後に実装後の `/security-review`' "$design_review"
grep -F -- 'or store sensitive data in files, logs, or caches. Launched' "$repo_root/agents/security-reviewer.md"
grep -F -- '初回を含めて最大3ラウンド' "$review_loop"
grep -F -- 'deferred mid' "$review_loop"
grep -F -- '`/aidd:issue-split`' "$review_loop"
grep -F -- '`.aidd/review-dismissed.md` への理由つき追記' "$review_loop"
grep -F -- '追跡先が確定しない指摘は `deferred mid` にできず' "$review_loop"
grep -F -- '全ソースの最大番号 +1' "$adr_command"
grep -F -- 'git symbolic-ref --quiet refs/remotes/origin/HEAD' "$adr_command"
grep -F -- 'refs/remotes/origin/' "$adr_command"
grep -F -- '検討した代替案' "$adr_command"
grep -F -- '| 観点 (優先度) | テスト (ファイル:テスト名) | 前提を壊して落ちたか | 未実装の理由 |' "$issue_implement"
grep -F -- 'must の観点は全件' "$issue_implement"
# issue-implement checks the diff against the placement that design-doc writes, so both
# sides of that contract must stay.
grep -F -- 'コンポーネントごとにコード上の配置 (ディレクトリ・ファイル) を書く' "$design_doc"
# design-review Agent 1 checks that placement too, so a design doc that omits it does not
# pass review and leave issue-implement without a placement to check against (#95).
grep -F -- 'コンポーネントごとにコード上の配置 (ディレクトリ・ファイル) が書かれているか' "$design_review"
grep -F -- '既存の構造から外れる配置に理由が書かれているか' "$design_review"
grep -F -- '設計書の「構成と責務」に書かれた配置と照らす' "$issue_implement"
grep -F -- '責務の集中は行数ではなく、この責務の割り当てで判定する' "$issue_implement"
grep -F -- 'どのコンポーネントにも割り当てていない責務' "$issue_implement"
grep -F -- '差分の周りの既存の構造を配置とみなし' "$issue_implement"
grep -F -- '**同じ形の箇所に広げる**' "$issue_implement"
grep -F -- '当てなかった箇所を一覧にして 6 (完了条件) の deferred に回す' "$issue_implement"
grep -F -- '**テストや項目を消すとき**' "$issue_implement"
grep -F -- '代わりのテスト (または不要とした理由) を完了報告に書く' "$issue_implement"
grep -F -- '既定のテスト実行から外れたテスト' "$issue_implement"
# issue-implement section 5 adds the sibling-coverage review that autonomous-review runs, and
# must not stack it on top of autonomous-review, which already includes it.
grep -F -- '**横展開のレビュー**: 差分が守りの処理 (認可・所有の確認、入力の検証、ログに出す値の形、例外の扱い) を足す・直す・共通の関数に切り出す' "$issue_implement"
grep -F -- '同じ形の呼び出し元と兄弟の処理 (同じ種類のエンドポイント・ハンドラ・action) に同じ処理が当たっているか' "$issue_implement"
grep -F -- 'silent-failure-hunter・/security-review・横展開のレビューは重ねない' "$issue_implement"
# test-perspectives carries the failure-path, removal and sibling-authz perspectives that
# issue-implement 4-5 / 4-6 rely on (#92).
grep -F -- '失敗の分岐では、送出される型だけでなく、その後に起きるべきこと (ロックの解放、残りの要素の処理の続行、部分失敗の後の再実行での回復) を観点にする' "$test_perspectives"
grep -F -- 'コメントや docstring が「再実行で回復する」「呼び出し元が再試行する」などと主張していれば、その主張そのものを観点にする' "$test_perspectives"
grep -F -- '項目・挙動を消す・改名する変更では、それを参照する既存テスト (既定の実行から外れた E2E なども含む) と、消すテストが守っていた性質を観点にする' "$test_perspectives"
grep -F -- '同じ形の既存のエンドポイントにも同じ確認があるかを含む' "$test_perspectives"

# incident-retro picks the first matching tier, so the ADR tier must come before the rule
# tier (a design decision also reads as a rule with judgment), and deferred work is folded
# into the code tier instead of being a trailing tier that the code tier already shadows.
incident_retro="$repo_root/skills/incident-retro/SKILL.md"
adr_line=$(grep -n '^[0-9]\. \*\*決定とその理由を残すもの\*\*' "$incident_retro" | cut -d: -f1)
rule_line=$(grep -n '^[0-9]\. \*\*判断を伴う規則\*\*' "$incident_retro" | cut -d: -f1)
[ -n "$adr_line" ] && [ -n "$rule_line" ] && [ "$adr_line" -lt "$rule_line" ]
grep -F -- '今すぐ直せない・直さないなら、その作業は `/aidd:issue-split` か issue に委ねる' "$incident_retro"
if grep -Fq -- '**今すぐ直せない作業**' "$incident_retro"; then
  exit 1
fi

# doctor's sandbox check only warns (running without the sandbox is allowed), and it must
# report whether a GitHub token is set without ever printing the token (#96).
doctor="$repo_root/skills/doctor/SKILL.md"
grep -F -- '**token の値は表示しない**' "$doctor"
grep -F -- '結果は WARN にとどめ、FAIL にしない' "$doctor"
if grep -Eq -- 'echo[^#]*\$\{?(GH|GITHUB)_TOKEN|print\([^)]*environ[^)]*TOKEN' "$doctor"; then
  echo "doctor prints a token value" >&2
  exit 1
fi
# Run the item 9 snippet against throwaway settings and dummy tokens: it must warn without
# FAIL, and print neither a token nor a non-boolean sandbox.enabled value.
doctor_tmp=$(mktemp -d "${TMPDIR:-/tmp}/aidd-doctor-test.XXXXXX")
trap 'rm -rf "$doctor_tmp"' EXIT
sed -n '/^# Item 9:/,/^PY$/p' "$doctor" > "$doctor_tmp/item9.sh"
mkdir -p "$doctor_tmp/cfg" "$doctor_tmp/proj/.claude"
printf '%s\n' '{"sandbox": {"enabled": {"leak": "SETTINGS_SENTINEL"}, "excludedCommands": ["gh *"]}}' \
  > "$doctor_tmp/proj/.claude/settings.json"
# A module in the consumer project must not shadow the standard library (python3 -I).
printf '%s\n' 'print("SHADOW_SENTINEL")' > "$doctor_tmp/proj/glob.py"
run_item9() {
  (cd "$doctor_tmp/proj" && env -u GH_TOKEN -u GITHUB_TOKEN "$@" CLAUDE_CONFIG_DIR="$doctor_tmp/cfg" \
    CLAUDE_PROJECT_DIR="$doctor_tmp/proj" bash "$doctor_tmp/item9.sh" 2>&1)
}
out=$(run_item9)
grep -Fq -- 'sandbox gh: WARN' <<<"$out" || { echo "doctor item 9 did not print 'sandbox gh: WARN': $out" >&2; exit 1; }
if grep -Eq -- 'FAIL|SETTINGS_SENTINEL|SHADOW_SENTINEL' <<<"$out"; then
  echo "doctor item 9 failed or printed a settings value: $out" >&2
  exit 1
fi
out=$(run_item9 GH_TOKEN=DUMMY_TOKEN_SENTINEL)
grep -Fq -- 'sandbox gh: OK' <<<"$out" || { echo "doctor item 9 did not print 'sandbox gh: OK': $out" >&2; exit 1; }
out="$out
$(run_item9 GITHUB_TOKEN=DUMMY_TOKEN_SENTINEL)"
if grep -Eq -- 'FAIL|DUMMY_TOKEN_SENTINEL' <<<"$out"; then
  echo "doctor item 9 failed or printed a token: $out" >&2
  exit 1
fi

# asset-audit must not silently continue when its state write fails (e.g. under the sandbox),
# or the SessionStart nudge never stops.
grep -F -- '書き込みに失敗したら黙って続けない' "$repo_root/skills/asset-audit/SKILL.md"

# Every eval case has planted false findings (high/mid only), and every planted ID has
# its refutation evidence in the key, so the refuter's discrimination can be scored.
for case_file in "$repo_root"/tests/eval/cases/*.md; do
  name=$(basename "$case_file" .md)
  planted="$repo_root/tests/eval/planted/$name.md"
  key="$repo_root/tests/eval/keys/$name.md"
  [ -f "$planted" ]
  ids=$(grep -oE '^\| PL-[A-Z]+[0-9]+ ' "$planted" | tr -d '| ')
  [ -n "$ids" ]
  # `! cmd` never trips set -e, so fail explicitly on a low/unknown severity row.
  if grep -E '^\| PL-' "$planted" | grep -qvE '^\| PL-[A-Z]+[0-9]+ \| (high|mid) \|'; then
    echo "planted finding with non high/mid severity: $planted" >&2
    exit 1
  fi
  grep -F -- '## 偽指摘 (refuter の弁別力測定)' "$key"
  for id in $ids; do grep -qE "^\| $id \|" "$key"; done
done
