Issue #1 の修正が終わりました。テストは6本すべて通っています（`python3 -B -m unittest -v`）。コミット・push・PR 作成はしていません。

## 変更内容
- `textutil.py:8` を1行だけ変えました。英数字以外が続く部分をまとめてハイフン1つにし（`[^a-z0-9]+`）、先頭と末尾のハイフンを `.strip("-")` で取り除きます。
- `test_textutil.py` にテストを5本足しました。
- テスト観点のファイル `docs/test-perspectives/2026-11-28-slugify-collapse-hyphens.md` を新しく作りました。

## レーン
設計書を作らずに実装する進め方（直行レーン）を選びました。スキーマ変更・新しい入口・認可・新しい画面・方式の選択のどれにも当たらず、触ったのは2ファイルです。

## 自分で決めた点
- **「英数字」の範囲**: ASCII の `a-z0-9` としました。既存コード `textutil.py:8` の文字クラスがそうなっており、issue の範囲外に「日本語などを残す・読み替える対応はしない」とあるためです。
- **関連 ADR**: `docs/adr/` が無いので、照らす ADR はありませんでした。
- **人に確認した点**: ありません。

## 要件とテストの対応表
「前提を壊して落ちたか」は、実装を一時コピーで書き換えた版（変異）に対してテストを走らせた結果です。元のファイルには手を入れていません。

| 原要件 (出典: issue #1 受け入れ基準) | 観点 (優先度) | テスト (`test_textutil.py`) | 前提を壊して落ちたか | 実行結果 |
|---|---|---|---|---|
| 1 連続をハイフン1つに | N1 (must) | `test_collapses_consecutive_non_alphanumerics_into_one_hyphen` | 落ちた（TDD の RED、`+` を外した変異） | pass |
| 2 先頭・末尾のハイフンを残さない | N2 (must) | `test_strips_leading_and_trailing_hyphens` | 落ちた（RED、`.strip` を外した変異） | pass |
| 3 英数字が無ければ `""` | B1 (must) | `test_returns_empty_string_without_alphanumerics` | 落ちた（RED、`.strip` を外した変異） | pass |
| 4 小文字化を維持し、既存テストを通す | N3・R1 (既存テストでカバー済み) | `test_lowercases_and_replaces_a_space` | 落ちた（`lower()` を外した変異） | pass |
| なし (観点から追加) | N4 (should) | `test_keeps_digits` | 落ちた（文字クラスを `[^a-z]` にした変異） | pass |
| なし (観点から追加) | B2 (should) | `test_returns_empty_string_for_empty_input` | 落ちた（結果が空なら `"-"` を返す変異） | pass |

「未判断」の行はありません。移行・性能・E2E の検証は、要件にも変更の性質にも求められていないので行っていません。

## レビュー
- **実行したもの**: `superpowers:requesting-code-review`。Critical・Important ともに0件で、判定は「マージ可」でした。
- **Minor 3件の扱い**:
  - `__pycache__/` が追跡外に残っている点は、自分のテスト実行で生じたものなので消しました。
  - 観点 B4（日本語の入力）と S1（2回かけても結果が同じ）は could なので、テストを書いていません。
  - 観点ファイルは issue が求めたものではないという指摘は、この進め方で作る成果物なので残しています。
  - 3件とも Minor なので、追跡先の起票はしていません。
- **当たらないので実行していないもの**:
  - `/security-review`: 外部入力・認証・秘密情報のどれにも触れない純粋な関数で、機微情報も保存しません。
  - `silent-failure-hunter`: 例外処理やフォールバックがありません。
  - 横展開のレビュー: 認可や入力検証などの守りの処理を変えていません。
- **未実行のもの**: `/stdd:mutation-check` は導入されておらず、実行していません。代わりに手で5種類の変異を作り、6本のテストがそれぞれどれかの変異で落ちることを確かめました。それ以外の変異への耐性は確かめていません。

## 配置の照合
`slugify` の責務は `textutil.py` に、テストは `test_textutil.py` に置いたままで、既存の構造から外れていません。消したテストもありません。

## 終了状態の記録
`.aidd/issue-implement/20261128T085734Z-e5645668/` に `done` で書きました（終了コード0）。

`docs/` は追跡外のままなので、コミットに含めるかどうかは決めてください。PR に進める場合は `superpowers:finishing-a-development-branch` を使ってください。その前に、担当者が内容を確認してください。
