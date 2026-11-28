issue #1 の修正は終わりました。テストは 8 本すべて通っています（`python3 -m unittest -v` → `Ran 8 tests … OK`）。commit・push・PR 作成はしていません。

## 変更内容
- `textutil.py:8`: 正規表現を `[^a-z0-9]` から `[^a-z0-9]+` に変え、`.strip("-")` を足しました（1 行の変更）。英数字以外が続く箇所はハイフン 1 つにまとまり、先頭と末尾のハイフンは消え、英数字が無い入力は空文字になります。
- `test_textutil.py`: テストを 7 本足しました。
- `docs/test-perspectives/2026-11-28-slugify-collapse-hyphens.md`: テスト観点のファイルを新しく作りました。

## 進め方
- **直行レーンにした理由**: スキーマ・入口・認可・画面のどれも変えず、触るのは 2 ファイル、直し方も実質 1 通りのため、設計書は作っていません。
- **自分で決めた点**: 「英数字」は既存コードの `[a-z0-9]` で判断しました（`textutil.py:8`）。日本語などがハイフン扱いになって消えるのは、issue の「範囲外」の記述に合わせたものです。関連する ADR はありません（`docs/adr` が無い）。人に確認が必要な点は残っていません。
- **レビュー**: `superpowers:requesting-code-review` の Skill を起動して、手順どおりレビューを受けました。重大な指摘は 0 件でした。軽い指摘のうち、追加テスト 2 本（区切り文字の混在、日本語）は入れました。ほかの 3 件は直していません。
  - `"İstanbul"` が `i-stanbul` になる：issue で範囲外とされた挙動です。
  - `__pycache__`：差分には入らないファイルで、テストを動かしたときにできたものは消しました。
  - 古い出力に頼る呼び出し元：`git grep` で確かめたところ、テスト以外にありませんでした。
  
  追跡が必要な残りの指摘はありません。
- **実行しなかったチェック**:
  - silent-failure-hunter：例外処理やフォールバックが無いので対象外です。
  - `/security-review`：外部入力・認証・秘密情報などの境界を跨がないので対象外です。
  - 横展開のレビュー：守りの処理を変えていないので対象外です。
  - `/stdd:mutation-check`：導入されていないので動かしていません。代わりに手で正規表現をいじって、テストが落ちることを確かめました（下の表）。
- **ファイルの置き場所**: 既存の 2 ファイルの中だけで変えていて、どちらの役割からも外れていません。
- **消したテスト**: ありません。

## 要件とテストの対応

テストはすべて `test_textutil.py` にあります。「壊した条件」は、実装を一時的に壊してテストが落ちるかを見たときの壊し方です。

| 要件（issue） | 観点 | テスト | 壊した条件 → 落ちたか | 結果 |
|---|---|---|---|---|
| 1 連続した記号をハイフン 1 つに | N1 must | `test_collapses_a_run_of_non_alphanumerics_into_one_hyphen` | 修正前のコードで落ちるのを確認（TDD の最初の失敗）。`+` を外しても落ちた | pass |
| 1 | レビューで追加 | `test_collapses_mixed_separators_between_words` | `+` を外す → 落ちた | pass |
| 2 先頭・末尾のハイフンを残さない | N2 must | `test_strips_leading_and_trailing_hyphens` | 修正前のコードで落ちるのを確認 | pass |
| 3 英数字が無ければ空文字 | B1 must | `test_returns_empty_string_without_alphanumerics` | 修正前のコードで落ちた。`or "x"` を足しても落ちた | pass |
| 3（空文字の入力） | B2 should | `test_returns_empty_string_for_empty_input` | `or "x"` を足す → 落ちた | pass |
| 4 小文字化と既存テストの維持 | R1（既存テストでカバー） | `test_lowercases_and_replaces_a_space` | 未確認（既存のテスト） | pass |
| （数字を残す） | N3 should | `test_keeps_digits` | 正規表現を `[^a-z]+` にする → 落ちた | pass |
| 範囲外（日本語は区切り扱い） | could | `test_treats_non_ascii_characters_as_separators` | 正規表現を `[\W_]+` にする → 落ちた | pass |

E2E・移行・性能の検証は不要と判断しました。要件に操作の流れや性能の条件が無く、保存するデータの形式も変えていないためです。

終了状態は `.aidd/issue-implement/20261128T085731Z-c9812f67` に `done` として書きました。PR を出す前に、担当の方が差分を確かめてください。次に進めるときの skill は `superpowers:finishing-a-development-branch` です（このコマンドの中では起動していません）。
