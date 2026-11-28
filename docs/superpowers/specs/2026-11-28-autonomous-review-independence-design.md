# autonomous-review の適格条件を独立レビューの成立条件にする (#134)

- 日付: 2026-11-28
- 対象: `skills/autonomous-review/SKILL.md`、`tests/autonomous-review-contract-test.sh`、README
- 計画上の名前: `docs/superpowers/specs/2026-11-22-harness-improvements-design.md` の T06。先行する評価は T10 (#131)

## 問題

`--reviewer codex` の主レビューを、実行名だけで「異種AIレビュー」と呼び、`auto_merge_eligible` の条件を「異種AIレビュー完了」としていた。次の2つが分かれていなかった。

- 独立性: レビュー担当が判定者と別の文脈で、固定した対象だけを、過去の結論を見ずに、読み取り専用で読んだか
- モデルの系列: レビュー担当と判定者のモデル・provider が違うか

Codex のセッションから使えば `codex exec` は同じ provider でありうる。また Claude Code から使っても、どのモデルが応答したかは記録していなかった (#131 の評価でも異種側のモデルは「不明」だった)。

## ユーザー決定 (2026-11-22、#134 の本文)

- 同種モデルでも、新しい文脈で独立レビューを行い、必須品質ゲート成功・低リスクの条件を満たせば適格にできる。モデルの異種性を必須にしない
- 独立性の条件: 対象 SHA の固定、過去の最終判定を渡さない、読み取り専用のスナップショット
- `--reviewer claude` は同一セッションの自己レビューなので `human_required` のまま
- 独立性不明・未実行の監査や品質ゲート・高リスク変更は `human_required`
- 新しい CLI バックエンドは足さない

## 評価記録 (T10 = #131)

`tests/eval/results/2026-11-25-impl.md` (PR #179)。autonomous-review の主レビューだけを、5ケース (欠陥あり3・対照2) × 2方式 × 3試行で測った。

| 方式 | 起動 | 実測モデル | 結果 |
|---|---|---|---|
| 同種 | `claude -p --tools Read,Grep,Glob` (新しい文脈) | claude-opus-5-5 (firstParty)、Claude Code 2.1.332 | 15試行: シード検出 9/9、深刻度一致、対照 6/6 通過、誤検出 0 |
| 異種 | `codex exec --sandbox read-only` (スナップショット) | 不明 (`--json` の event に無い)、codex-cli 0.163.0 | 15試行: 同上 |

`rubric.md` の規則による提案は「同種で許容できる範囲の候補: 境界・例外の扱い」「人の判断に残す: 認可 (危険な変更)・改名 (欠陥ありケースが無い)・それ以外の種類」。記録自身が「1標本で適格条件を変える根拠にはしない」「ほかのモデル・言語・規模に広げない」と書いている。

この記録は、新しい文脈の同種モデルが、測った範囲で異種と同じ結果を出したことを示す。同種の独立レビューを否定する結果は無いので、ユーザー決定どおり異種性を条件から外す。ただし記録が支える範囲は狭いので、適格条件の文面に範囲と残存リスクを書き、run ごとに `residual_risks` に残す。

なお `tests/eval/results/2026-11-28-compare*.md` は design-review の構成比較 (#130、T09) で、実装レビューの同種・異種とは関係しない。

## 設計

### 独立レビューの成立条件

`state.json` に `review_independence` を足し (`schema_version` 5 → 6)、すべてのラウンドで次の4つを確かめる。値は `true` / `false` / `null` (確かめられない)。

| キー | `--reviewer codex` で `true` になる条件 |
|---|---|
| `fresh_context` | ラウンドごとに新しい `codex exec` のプロセス (`resume`・`fork` を使わない) |
| `target_pinned` | `rounds[].snapshot.commit` が対象コミットの完全な SHA で、作成済み (作業ツリー差分なら差分も当てた) |
| `prior_verdicts_withheld` | プロンプトは対象差分・変更目的・不変条件・懸念点だけ。スナップショットに `.aidd/` と `.git` が無い |
| `read_only_snapshot` | `--sandbox read-only --skip-git-repo-check -C <snapshot-dir>` で起動した |

`established` は4つがすべて `true` のときだけ `true`。`--reviewer codex` で `true` でなければ `human_required` (`review_incomplete`)。`--reviewer claude` は4つとも `false` で、今までどおり `human_required` (`human_judgment`)。

### モデルと provider の記録

- レビュー担当: `codex exec` の stderr の先頭の見出し (`--------` に挟まれた部分) の `model:` と `provider:` の行。2026-11-28 に codex-cli 0.163.0 で1回、空のディレクトリに対して `codex exec --sandbox read-only` を実行し、見出しに `model: <値>` と `provider: openai` が出ることを確かめた。#131 は `--json` の event だけを記録し、この見出しを残していなかった (それで「不明」だった。`--json` のときに見出しが出るかは確かめていない)。既存の呼び出しは変えず、stderr を毎回ファイルに保存して見出しだけを読む
- 判定者: ホストが示すモデル ID (Claude Code のシステムプロンプトの model ID など) があればそれ。無ければ `null`
- `model_relation` は provider が両方取れたときだけ `same` / `different`、それ以外は `unknown`。判定には使わない
- 実行名 (`codex`)・CLI の名前・既定の設定から埋めない

見出しの値は CLI が「使う」と表示した値で、サーバー側の応答モデルの確認ではない。これは残存リスクとして記録する。

### 変えないもの

- push・PR 作成・マージをしない境界
- `codex exec` の起動と失敗判定 (`-o` の最終メッセージが JSON 契約どおりかで決める)。#193 (コンテナ内の Codex sandbox) と同じ行を触らないよう、stderr の保存と見出しの読み取りは別の項目として足した
- 高リスク領域・観点別レビュー・品質ゲート・`/security-review` の扱い
- `tool-reminder.sh` の PR 前の確認 (`schema_version` 5 以上を数えるので、6 もそのまま数える)
- `skills/autonomous-review/agents/openai.yaml` (暗黙の起動を許さない設定のまま。Codex から使う場合の差は上の記録で表せる)

## 残存リスク

- 評価は主レビューだけ、各ケース1つの小さな Python 差分、`brief.md` が不変条件を明示、3試行の1標本。変更の種類は「境界」「例外の扱い」だけが候補になった
- Codex のホストから `codex exec` を使う組み合わせ (同じ provider) は測っていない。評価時の異種側のモデルは不明で、今の run のモデルと同じかは分からない
- read-only サンドボックスは cwd の外の絶対パスの読み取りを防がない (既存の `residual_risks` のとおり)
- 判定者のモデル ID はホストの表示に頼る

## 検証

- `bash tests/autonomous-review-contract-test.sh`: 新しい節・キー・「実行名から推測しない」・適格の文に `review_independence.established` があって「異種」が無いこと・自己レビューが常に `human_required` であること・評価記録と設計書が存在することを確かめる
- 実モデル: 上の見出しの確認1回だけ (codex の利用。USD は CLI が出さないので不明)
