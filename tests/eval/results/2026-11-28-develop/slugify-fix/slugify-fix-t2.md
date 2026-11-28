issue #1 を実装しました。`slugify` が記号の続く箇所でハイフンを1つにまとめ、先頭と末尾のハイフンを落とすようになり、テストは5件とも通っています。変更はコミットしておらず、push と PR 作成もしていません。

## 変更内容
`textutil.py:8`
```python
return re.sub(r"[^a-z0-9]+", "-", lowered).strip("-")
```
`test_textutil.py` には受け入れ基準1〜3と、数字が残ることのテストを足しました。消したテストはありません。

## レーンと決めたこと
- **直行レーン**にしました。スキーマ・入口・認可・画面の変更がなく、実装方法の選択肢も残っておらず、触ったのは2ファイルです。
- 曖昧さはありませんでした。要件はすべて issue 本文の受け入れ基準どおりで、人に確認した点もありません。
- ADR と設計書はリポジトリにありません（`docs/` が存在しない）。
- **配置**: 既存の `slugify` の中だけを直しており、元の構造から外れていません。

## 要件とテストの対応

| 原要件（issue #1 受け入れ基準） | 観点 | テスト（test_textutil.py） | 実装を壊して落ちたか | 結果 |
|---|---|---|---|---|
| 1. 記号の連続はハイフン1つ | must | `test_collapses_a_run_of_non_alphanumerics_into_one_hyphen` | `+` を外すと落ちた | pass |
| 2. 先頭・末尾にハイフンを残さない | must | `test_strips_leading_and_trailing_hyphens` | `.strip("-")` を外すと落ちた | pass |
| 3. 英数字が無い入力は `""` | must | `test_returns_empty_string_without_alphanumerics` | `.strip("-")` を外すと落ちた | pass |
| 4. 英字は小文字のまま、既存テストも通す | must | `test_lowercases_and_replaces_a_space`（既存） | `lower()` を外すと落ちた | pass |
| なし（観点から追加）数字が残る | should | `test_keeps_digits` | `[^a-z]+` に変えると落ちた | pass |

- 未判断の行はありません。
- E2E・移行・性能・ロールバックの検証は、要件にも変更の性質にも当たらないため行っていません。

## レビュー
- **実行したもの**: サブエージェント（`aidd:reviewer`）によるレビュー。high と mid の指摘はなく、low が2件でした。
  - 非 ASCII の大文字の扱い（例: `"İstanbul"` が `"i-stanbul"` になる）は、issue が範囲外としている話で、修正前からの挙動です。なので直していません。
  - 追加テストの提案（空文字など）は任意の改善なので見送りました。
  - 今回直さずに残した指摘として追跡が必要なものはありません。
- **実行しなかったもの**:
  - silent-failure-hunter、`/security-review`、横展開のレビュー: 差分に例外処理・信頼境界・守りの処理が無いため、対象外です。
  - `/stdd:mutation-check`: stdd のこのコマンドが入っていないので動かしていません。代わりに上の表のとおり、実装を4通り手で壊してテストが落ちることを確かめました。
  - `/aidd:test-perspectives` と superpowers の各 skill（計画・TDD・レビュー依頼・完了前の検証）: 予算の都合で起動せず、同じ手順を手で行いました。テストを先に書いて3件が落ちることを確かめ、そのあと実装して全件通しています。

## 検証
`python3 -m unittest -v` → 5件とも OK。

outcome は `done` で記録しました（`.aidd/issue-implement/20261128T080045Z-8408ecf0`）。

## 気をつけてほしい点
- サンドボックスが起動に失敗したため、このセッションのコマンドはすべてサンドボックスの外で動いています。
- テストの実行で `__pycache__/` ができ、`.gitignore` が無いので未追跡ファイルとして残っています。コミットに含めないでください。
- 次に進めるときに使う skill は `superpowers:finishing-a-development-branch` です。push や PR を出す前に、差分を目で確認してください。
