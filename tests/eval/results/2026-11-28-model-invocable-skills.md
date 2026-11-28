# test-perspectives・design-doc・design-review をモデルから起動できるようにした前後の測定 (#196)

`disable-model-invocation` を外す前 (aidd 0.94.0) と後 (0.95.0 の作業ツリー) で、`/aidd:issue-implement` を非対話のホストの形で動かした。起動されるか、手順が通るか、費用を比べた。あわせて、skill を使うべきでない依頼で起動されないかを見た。**各条件1〜3試行**なので、率や費用の幅は参考値である。

## 条件

| 項目 | 値 |
|---|---|
| 日時 | 2026-11-28 |
| CLI | Claude Code 2.1.332、`claude -p --model opus --output-format stream-json --verbose --permission-mode acceptEdits --allowedTools Bash` (stdin は `/dev/null`) |
| 変更前 | インストール済みの aidd 0.94.0 |
| 変更後 | `--plugin-dir` で作業ツリーの aidd (コミット `e0d9115`) |
| 対象 | 使い捨てのローカル repo (Python の関数1つとテスト1件)。`gh` は PATH 上のスタブで、`gh issue view 1` にだけ本文を返す。GitHub には何も書いていない |
| issue | 小: `top_words` の大文字小文字と並び順を直す (直行レーン)。設計: `python3 -m wordfreq` の CLI を足す (エントリポイントの追加なので設計レーン) |
| 分離 | HOME は分離していない (利用者の global の設定と plugin が効いている) |

## 結果

| 版 | 実行 | 費用 | 所要 | `Skill` の呼び出し | 成果物 | outcome |
|---|---|---|---|---|---|---|
| 0.94.0 | 小 (#191 の測定) | $0.81 | 116秒 | なし | なし | `needs_input/approval` |
| 0.94.0 | 小1 | $0.75 | 84秒 | なし | なし | `needs_input/approval` |
| 0.94.0 | 小2 | $0.76 | 81秒 | `superpowers:test-driven-development` | なし | `done` |
| 0.94.0 | 設計1 | $0.51 | 32秒 | `aidd:design-doc` → 拒否 (`disable-model-invocation`) | なし | `blocked/incomplete` |
| 0.95.0 | 小1 | $1.22 | 135秒 | `aidd:test-perspectives`、TDD、`requesting-code-review` | テスト観点 | `done` |
| 0.95.0 | 小2 | $1.42 | 157秒 | `aidd:test-perspectives`、`requesting-code-review` | テスト観点 | `done` |
| 0.95.0 | 設計1 | $1.79 | 212秒 (result 3個の合計) | `aidd:design-doc`、`aidd:design-review`、`aidd:test-perspectives`、TDD、`requesting-code-review` | 設計書・テスト観点、テストは通過 | `needs_input/approval` (受け入れ基準の外の指摘の追跡先) |

- 変更後は、test-perspectives が3回とも起動され、観点のファイルが残った (変更前は4回とも飛ばされた)
- 設計レーンは、設計書 → 設計レビュー → テスト観点 → 実装 → テスト通過まで進んだ。最後は受け入れ基準の外の指摘の追跡先を尋ねる承認待ち (`needs_input`) で、`done` までは確かめていない。変更前は design-doc の起動が拒否されて止まっていた
- design-review は、対象が1ファイル・100行未満なので、手順どおり、エージェントを起動せずに直接レビューする経路を通った。大きい設計書では reviewer を起動するので、費用は増える
- 費用は、小さな直行レーンで $0.75〜0.81 から $1.22〜1.42 に増えた。手順を飛ばさなくなった分である

## 起動しすぎないか (変更後、skill を使うべきでない依頼)

| 依頼 | 費用 | `Skill` の呼び出し |
|---|---|---|
| (a) 既存の設計書の内容について質問する | $0.29 | なし |
| (b) docstring に1行足す小さな修正 | $0.35 | なし |
| (c) 既存の設計書を3行で要約する | $0.29 | なし |

3件とも、3つの skill は起動されなかった。対話セッションでの起動 (brainstorming の後、サブエージェントの中など) は測っていない。

## 残していないもの

- stream-json の生の出力は、利用者の環境のパスを含むので保存していない
- Codex での挙動は測っていない (`openai.yaml` は変えていない)
