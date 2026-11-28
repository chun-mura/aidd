# issue-implement 1件の費用 (予備測定、1試行)

#191 の outcome.json を入れた版 (0.94.0、作業ツリー) で、非対話のホストの形で `/aidd:issue-implement` を1回動かし、`result` イベントの `total_cost_usd` を記録した。非エンジニア向け改修依頼システムの API 費用の見積もり (1件 $3〜10 と置いた推定) を、実測で置き換え始めるため。**1試行・小さな直行レーンの issue だけ**なので、代表値ではない。

## 条件

| 項目 | 値 |
|---|---|
| 日時 | 2026-11-28 00:06:56Z〜00:08:56Z |
| CLI | Claude Code 2.1.332 |
| 起動 | `claude -p "/aidd:issue-implement 1" --model opus --plugin-dir <aidd の作業ツリー> --output-format stream-json --verbose --max-budget-usd 10 --permission-mode acceptEdits --allowedTools Bash` (stdin は `/dev/null`) |
| ホストの役 | `AIDD_ISSUE_IMPLEMENT_RUN_ID=20261128T120000Z-c0570001` を渡し、終了後に `issue-outcome.py check <outcome> --issue 1` で検証 |
| 対象 | 使い捨てのローカル repo (Python の関数1つ `top_words` とテスト1件)。GitHub には何も書いていない |
| issue | 受け入れ基準4つ (大文字小文字を区別しない・同数はアルファベット順・`n <= 0` は空・既存テストが通る)。`gh` は PATH 上のスタブで、`gh issue view 1` にだけ本文を返す |
| plugin | init の `plugins` に `--plugin-dir` の aidd、superpowers 6.1.1、pr-review-toolkit、stdd などが載った。`AskUserQuestion` は tools に無い |
| 分離 | HOME は分離していない (利用者の global の CLAUDE.md・plugin・設定が効いている) |

## 結果

| 項目 | 値 |
|---|---|
| 終了 | exit 0、`subtype: success`、`result` は1個 |
| 所要 | 116,475 ms (14 ターン) |
| **total_cost_usd** | **0.8131** |
| claude-opus-5-5 | in 22 / out 9,077 / cache read 618,798 / cache creation 55,551、$0.7498 |
| claude-sonnet-5-5 (`aidd:reviewer`) | in 4 / out 1,602 / cache read 14,903 / cache creation 18,334、$0.0634 |
| outcome.json | `status: needs_input`、質問1件 (`kind: approval`、選択肢3つ。直さない low 指摘3件の追跡先)。`check --issue 1` は通過 (終了コード0) |
| 作業ツリー | `wordfreq.py` と `test_wordfreq.py` を変更、テスト5件が通る。commit はしていない |

- 直行レーンと判定し、レーンの理由・原要件とテストの対応表・前提を壊して落ちたかを完了報告に書いた。
- deferred の追跡先が決まっていないため完了にせず、`needs_input/approval` で止まった。6 の deferred の規則と印のとおりで、質問は issue と outcome だけで読める文だった
- `Skill` ツールの呼び出しは0件だった。4-1 の `/aidd:test-perspectives` と superpowers の skill を起動せず、テスト観点もファイルに保存していない (`artifacts.test_perspectives` は `null`)。このため、この費用は手順どおりの実行より小さい可能性がある (別の issue で扱う)

## 見積もりへの反映

- 小さな直行レーンの issue で、承認待ちで止まるまで約 $0.8。
- 設計レーンでは、さらに design-doc と design-review (standard で1回 $0.9〜2.1、`2026-11-28-compare-prelim.md`) と大きな実装が加わる。
- 回答後の実行し直しでは、もう1回分かかる。
- 1件 $3〜10 と置いた推定は、直行レーンでは高すぎた可能性がある。ただし1試行なので、幅を決めるには直行・設計レーンそれぞれ複数件の測定が要る。

## 残していないもの

- stream-json の生の出力は、利用者の環境のパスを含むので保存していない (使い捨ての scratchpad にだけ置いた)
- 採点はしていない (費用の測定だけが目的)
