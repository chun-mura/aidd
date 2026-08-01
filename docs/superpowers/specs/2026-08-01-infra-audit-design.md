# infra-audit コマンド設計書

## 背景・目的

[stopped-reviewing-my-code](https://zenn.dev/singularity/articles/stopped-reviewing-my-code) が提示する「壊れない仕組み」のうち、aidd-ecosystem 全体で未カバーだった以下3項目を、利用側プロジェクトに対して診断する新規コマンドを追加する。

1. 静的解析による複雑度制御（ESLint: 関数長・循環的複雑度・ネスト深さ・`any`禁止等）
2. 重複・未使用コード検出（jscpd / knip）
3. 多OSでのCI実行

CLAUDE.md運用（`aidd/templates/CLAUDE.md.template`）、テスト設計・mutation testing（`stdd`）、クロスモデルレビュー（`aidd:design-review`）は既存資産でカバー済みのため対象外とする。

## 対象範囲

- 対象エコシステム: TypeScript/JavaScript（`package.json` が存在するプロジェクトのみ診断対象。存在しなければ「対象外」として全項目スキップ）
- 対象ディレクトリ: プロジェクトルート直下のみ（`.eslintrc*` / `eslint.config.*` / `package.json` / `.github/workflows/*.yml`）。モノレポの `packages/*` 探索は v1 スコープ外（YAGNI）
- 検査は読み取り専用。設定ファイルの生成・編集は一切行わない

## `doctor.md` との違い

`aidd:doctor` は **aidd 自身の導入状態**（superpowers連携・バージョン整合・hooks実行権限）を診断する。`aidd:infra-audit` は **利用側プロジェクトのコード品質ガード導入状況** を診断する。診断対象がaiddではなく利用側プロジェクトである点を明記し、混同を避ける。

## チェック項目

### 1. 静的解析（ESLint複雑度制御）

- `package.json` の有無 → なければ「対象外」
- `.eslintrc*` / `eslint.config.*` の有無
- 存在する場合、以下ルールの設定有無を grep:
  - `complexity`
  - `max-lines-per-function`
  - `max-depth`
  - `max-params`
  - `@typescript-eslint/no-explicit-any`
  - `sonarjs/cognitive-complexity`
- 不足項目があれば、記事基準値（関数長60行 / 循環的複雑度20 / ネスト4 / パラメータ6）を参考値として提示し、該当ルールの導入例（設定スニペット）を出す

### 2. 重複・未使用コード検出

- `package.json` の `devDependencies` に `jscpd` または `knip` が含まれるか
- `.github/workflows/*.yml` 内でそれらの実行コマンドが呼ばれているか
- 未導入なら `npm i -D jscpd knip` とCI設定スニペット例を提示

### 3. 多OS CI

- `.github/workflows/*.yml` を走査し、`runs-on:` の値を収集
- `ubuntu-latest` のみの場合、記事の折衷案（PR時: ubuntu + macOS、Windows: daily/main push限定）を提案として提示

## 出力形式

`doctor.md` と同様、項目ごとに `OK` / `未導入` + 対処コマンド例（1〜2行）、最後に総合サマリ（未導入項目数）を1行で出す。

**既知の限界の明記**: ヒューリスティック（ファイル存在・grep）による判定であり、flat config の共有設定 `extends`/`import` 経由で実際にはルールが有効なケースを検出できないことがある旨を出力の冒頭に一言添える。

## エラーハンドリング

- `package.json` なし → 全項目「対象外」として1行で終了（エラーではない）
- `.github/workflows/` なし → 項目2・3は「CI未設定」として扱う

## 変更ファイル

- 新規: `commands/infra-audit.md`
- 更新: `README.md`（インデックス表に追加）, `CHANGELOG.md`（0.25.3として記録）, `.claude-plugin/plugin.json`（`version` を `0.25.3` に bump）

## テスト

既存の `tests/command-contract-test.sh` / `tests/redundancy-contract-test.sh` は本コマンドに依存しないため変更不要。新規の契約テストは追加しない（1コマンド追加のみで、既存テストが強制する契約が今回の変更に該当しないため）。
