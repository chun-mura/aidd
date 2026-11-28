issue #1 の対応が終わりました。`slugify` が、連続する記号をハイフン1つにまとめ、先頭と末尾のハイフンを取り除くようになっています。テストは6件すべて通りました（`python3 -B -m unittest`）。コミット・push・PR 作成はしていません。

**変更内容**
- `textutil.py:8`: 正規表現を `[^a-z0-9]` から `[^a-z0-9]+` に変え、結果に `.strip("-")` を付けました。
- `test_textutil.py`: テストを5件足し、既存の1件はそのままです。
- テスト観点の一覧を `docs/test-perspectives/2026-11-28-slugify-collapse-hyphens.md` に保存しました。

**進め方の判断**
- 設計書を作らずに実装へ進みました。スキーマ・エントリポイント・認可・画面の変更がなく、方式の候補も1つで、触ったのは2ファイルだけだったためです。
- 人に確認が必要な点はありませんでした。「英数字」は既存コードの `[a-z0-9]` どおり ASCII の英数字と解釈しました。日本語などは issue の「範囲外」に書かれているため、区切りとして消える今の挙動のままです。関連する ADR はありません（`docs/adr` 自体がありません）。

**要件とテストの対応**（出典は issue #1 本文の受け入れ基準）

| 原要件 | 観点 | テスト | 前提を壊して落ちたか | 結果 |
|---|---|---|---|---|
| 1 記号の連続はハイフン1つ | P1 (must) | `test_collapses_a_run_of_non_alphanumerics_into_one_hyphen` | `+` を外すと落ちた（`"a--b"` の検証も単独で落ちることを確認） | pass |
| 2 先頭と末尾にハイフンを残さない | P2 (must) | `test_strips_leading_and_trailing_hyphens` | `.strip` を外すと落ちた | pass |
| 3 英数字が無い入力は空文字 | B1 (must) | `test_returns_empty_string_without_alphanumerics` | `.strip` を外す、または既定値を返すようにすると落ちた | pass |
| 3 の延長（空の入力） | B2 (should) | `test_returns_empty_string_for_empty_input` | 既定値を返すようにすると落ちた | pass |
| 4 小文字化を保ち、既存テストを通す | R1 (must) / P3 (should) | `test_lowercases_and_replaces_a_space` / `test_keeps_digits_and_lowercases_letters` | 小文字化を外すと落ちた。数字を許可しないと P3 が落ちた | pass |

E2E・移行・性能の検証は要件にないため行っていません。

**レビュー**
- 別のエージェントのレビューは low の指摘4件だけでした。空の入力と `"a--b"` の2件はテストに足しました。
- 足さなかった2件は直すべき不具合ではないと判断し、追跡はしていません。
  - 日本語や `İ` など ASCII 以外の文字の扱いは、issue で範囲外と決まっています。
  - 同じ入力に2回かけても結果が変わらないことの確認は、優先度の低い観点でテストは任意です。
- 例外処理がなく外部入力も扱わないため、`/security-review` と例外処理の専用レビューは不要と判断しました。
- `/stdd:mutation-check` は入っていないため実行していません。代わりに手動で実装を壊し、テストが落ちることを確かめました。

**後片付けと残っているもの**
- テスト実行でできた `__pycache__/` は削除しました。
- 作業ツリーには、実行記録用の `.aidd/` と、テスト観点の `docs/` が未追跡のまま残っています。`.aidd/` をコミットするかどうかは決めてください。
- 実行記録（`.aidd/issue-implement/20261128T085426Z-b50a8344`）の終了状態は `done` として書き込み済みです。

PR に進めるときは `superpowers:finishing-a-development-branch` を使えます。push する前に、担当者が変更内容を確認してください。
