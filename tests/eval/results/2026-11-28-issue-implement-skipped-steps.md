# 非対話の issue-implement が直行レーンで工程を省く原因と修正の確認 — 2026-11-28 (#222)

#133 (PR #221) の `/aidd:eval develop` で、直行レーンのケース `slugify-fix` の2試行が、`aidd:test-perspectives` と `superpowers:requesting-code-review` の Skill を起動せずに `done` になった。#196 の修正後の 0.95.0 の測定 (`2026-11-28-model-invocable-skills.md`) では3回とも起動していた。両者の stream-json を読んで違いを調べ、手順と outcome の検査を直し、同じケースで直す前と後を2試行ずつ動かした。**各2試行なので、率は参考値である**。

## 結論

- 省いた2試行は、どちらも完了報告に省いた理由を書いていた: 「`/aidd:test-perspectives`・`superpowers:*` の各 skill: 予算を抑えるため起動せず」(試行1)、「予算の都合で起動せず、同じ手順を手で行いました」(試行2)
- `claude -p --max-budget-usd <N>` を付けると、モデルの文脈に `USD budget: $0/$<N>; $<N> remaining` が入る (下の「予算の表示の確認」)。#133 の試行は上限 4 USD、0.95.0 の測定は上限 10 USD で、実際の費用はどちらも 0.6〜1.4 USD だった
- issue-implement と test-perspectives の SKILL.md は、0.95.0 の測定のコミット (`e0d9115`) と #133 のコミット (`dd9aea8`) で同じ (`git diff --stat` が空)。違いは hook (`tool-reminder.sh` の git の拒否) だけで、この2つの Skill の起動には関わらない
- 原因: 手順に「省かない」と書いておらず、表示された予算を理由にモデルが Skill を省き、自分で代わりをして `done` を書けた。outcome の検査も工程を見ていなかった。上限の額 (4 USD と 10 USD) とケース (slugify と wordfreq) のどちらが効いたかは分けていない (下の「分けていないこと」)
- 修正 (0.107.0): 手順の 4 の冒頭に、テスト観点とコードレビューはレーンに関わらず省かず、差分の小ささや表示された予算は理由にならず、実行できなければ `blocked/required_check_not_run` で止める、と書いた。`aidd:reviewer` などの agent の直接の dispatch はコードレビューに数えない。`outcome.json` の `done` に `completion.test_perspectives` と `code_review` (`ran` だけ) と、実在する `artifacts.test_perspectives` を必須にした (#223 の `security_review` と同じ仕組み)
- 直す前 (0.106.0) の2試行は不合格 (1試行はコードレビューを、もう1試行は両方を省いた。後者は「予算を考えて呼んでいません」と書いた)。直した後 (0.107.0) の2試行は、どちらも test-perspectives・TDD・requesting-code-review の Skill を起動し、合格した

## 記録の比較 (stream-json)

| 実行 | aidd | 上限 | Skill | agent | 費用 | 完了報告の省いた理由 |
|---|---|---|---|---|---|---|
| 0.95.0 小1 (`m196b/small1`) | 0.95.0 | 10 USD | test-perspectives, TDD, requesting-code-review | general-purpose, silent-failure-hunter, aidd:reviewer | 1.2164 | — |
| 0.95.0 小2 (`m196b/small2`) | 0.95.0 | 10 USD | test-perspectives, requesting-code-review | general-purpose, silent-failure-hunter, aidd:reviewer ×2 | 1.4167 | — |
| #133 slugify-fix 試行1 | 0.99.0 | 4 USD | なし | aidd:reviewer | 0.6033 | 予算を抑えるため |
| #133 slugify-fix 試行2 | 0.99.0 | 4 USD | なし | aidd:reviewer | 0.5639 | 予算の都合で |

- 上限は、0.95.0 の測定を起動したセッションの記録 (`--max-budget-usd 10`) と、`2026-11-28-develop.md` の測定条件 (slugify-fix 4 USD) から取った
- どちらも CLI 2.1.332、`claude-opus-5-5`、superpowers 6.1.1、`--permission-mode acceptEdits --allowedTools Bash`、stdin は `/dev/null`、HOME は分離していない。init の skills と slash_commands に `aidd:test-perspectives` と `superpowers:requesting-code-review` は4回とも出ていた (起動できなかったのではない)
- #133 の2試行は、最初の Bash でサンドボックスの初期化に失敗し、以後サンドボックスの外で動いた。0.95.0 の測定には無い違いだが、工程の選び方に関わる記録は無い
- 思考の内容は stream-json で空になっていて読めない。省いた理由は完了報告の文だけが根拠

## 予算の表示の確認

`claude -p "...budget...?" --model haiku --max-budget-usd 0.3` (Claude Code 2.1.332、費用 0.0059 USD) に、文脈に予算の記述があるかを尋ねると、`USD budget: $0/$0.3; $0.3 remaining` を引用した。

## 直す前と後の測定 (slugify-fix、上限 4 USD)

PR #221 の `tests/eval/develop/` (凍結 `038c6f20…`) と `skills/eval/SKILL.md` の staging・collect・grade のブロックをそのまま使った。PR #221 はまだ main に無いので、評価する aidd のコミットに PR #221 の評価用ファイルを重ねた使い捨てのリポジトリを作り、そこを `<repo>` にした。D5 の凍結と照合は省いた (`SHA256SUMS` はコミットするファイルのハッシュだけ)。起動はこの worker のサンドボックスの外から行い、実行担当のサンドボックスは初期化できた (#133 とは違う)。

| 版 | 試行 | 判定 | 受け入れ条件 | 既存テスト | 欠けた工程 | Skill | outcome | 費用 | ターン |
|---|---|---|---|---|---|---|---|---|---|
| 0.106.0 (`20004da`、#223 まで) | 1 | 不合格 | AC1〜AC4 ok | 6/6 ok | code-review | test-perspectives | done (`schema_version` 2) | 0.7762 | 18 |
| 0.106.0 | 2 | 不合格 | AC1〜AC4 ok | 5/5 ok | test-perspectives, code-review | なし | done (`schema_version` 2) | 0.6286 | 10 |
| 0.107.0 (`dd6e1b9`、この修正。コミット前に契約テストだけを足して書き直したので、ブランチのコミットとは `tests/issue-outcome-test.sh` だけが違う) | 1 | 合格 | AC1〜AC4 ok | 8/8 ok | なし | test-perspectives, TDD, requesting-code-review | done (3つの `ran`、観点のファイルあり) | 0.9959 | 22 |
| 0.107.0 | 2 | 合格 | AC1〜AC4 ok | 6/6 ok | なし | test-perspectives, TDD, requesting-code-review | done (3つの `ran`、観点のファイルあり) | 0.9444 | 20 |

- 0.106.0 の2試行は、どちらも `aidd:reviewer` を直接 dispatch した。試行2の完了報告は「`/aidd:test-perspectives` などの skill: 予算を考えて呼んでいません」と書いた
- 0.106.0 の outcome の検査は工程を見ないので、2試行とも `done` が通った。0.107.0 の検査なら、試行1は `code_review`、試行2は `test_perspectives`・`code_review`・観点のファイルが無いので `done` は拒否される (どちらも正直に書けば `blocked/required_check_not_run`)
- 0.107.0 の2試行の stream-json に「予算」の語は無かった
- 生の記録: `2026-11-28-issue-implement-skipped-steps/before/` (0.106.0) と `after/` (0.107.0)。各試行の最終回答・meta・工程・差分・outcome・`gh` の呼び出し・refs。stream-json はコミットしていない

## 分けていないこと

- 上限の額 (4 USD と 10 USD) とケース (slugify-fix と wordfreq) のどちらが省きを招いたかは、試していない。上限 10 USD で slugify-fix を動かすには、この作業の予算 (12 USD、上限の合計で数える) が足りなかった。修正は額によらず「表示された予算は省く理由にならない」としたので、どちらが原因でも効く
- 設計レーンのケース (note-share) と、`/security-review` が拒否される経路 (#223) は、実モデルで動かしていない
- 値 (`ran`) が実態どおりかはスクリプトでは確かめられない。観点のファイルの実在だけは確かめる

## コスト

| 実行 | total_cost_usd |
|---|---|
| 予算の表示の確認 (haiku) | 0.0059 |
| 0.106.0 試行1・2 | 1.4048 |
| 0.107.0 試行1・2 | 1.9403 |
| **合計** | **3.3510** |
