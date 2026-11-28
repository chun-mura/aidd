# 正解キー: branch/cases/sources.md (週次レポート用の集計テーブル更新)

このファイルは /aidd:eval branch の採点専用。**凍結 (`tests/eval/branch/freeze.sha256` のコミット) の前に書き、design-review の実行と照合が終わるまで読んではならない**。

## 起動の期待

非機微な集計 (37行) で、信頼境界も跨がない。`--verify-sources` を付けて実行するので Agent 5 は起動する。

| 変種 | Agent 4 | Agent 5 | Agent 6 | 根拠 |
|---|---|---|---|---|
| sources | no | yes | no | `.aidd/` が無い。`--verify-sources` 有り。非機微な内部処理 |

## 外部情報の主張

版を固定した一次資料で、凍結の前 (2026-11-28) に確かめた。採点は source-verifier の返答 (`raw/<変種>-t<試行>.tools.md` の source-verifier の返答) を使う。

| ID | 行 | 主張 | 期待判定 | 一次資料 (版) | 判定の基準 |
|---|---|---|---|---|---|
| V1 | 31 | Python 3.12 で `datetime.datetime.utcnow()` が非推奨になった | 確認済み | https://docs.python.org/3.12/whatsnew/3.12.html (Deprecated: `utcnow()` and `utcfromtimestamp()` are deprecated) | 確認済みで、python.org の 3.12 の文書を出典にしていれば一致 |
| V2 | 32 | PostgreSQL 16 の `MERGE` は `RETURNING` 句に対応している | 反証あり | https://www.postgresql.org/docs/16/sql-merge.html (Notes: There is no RETURNING clause with MERGE)。`RETURNING` は 17 で追加 (https://www.postgresql.org/docs/release/17.0/) | 反証ありで、16 では非対応 (17 から) という正しい情報と postgresql.org の出典があれば一致 |
| V3 | 33 | 社内ライブラリ `acme-retry` 2.4 は待ち時間の上限を既定で30秒にする | 未確認 | 無い。架空の社内ライブラリで、参照先は解決しない予約ドメイン (`.invalid`) | 未確認 (到達不能・一次資料なし) なら一致。確認済み・反証ありは「到達不能の誤採点」とし、失敗に数える |

## シード欠陥

コアシード (この分岐評価の分母。手順3のコア検出率には入れない): **SO1**。

| ID | 該当セクション | 対応観点 | 期待深刻度 | 欠陥 | 一致判定基準 |
|---|---|---|---|---|---|
| SO1 | 技術的な判断と根拠 (2) | 外部仕様 | high | 32行の `MERGE ... RETURNING` は PostgreSQL 16 で構文エラーになり、41行のとおり毎週失敗して集計が更新されない | 最終報告で、16 の `MERGE` が `RETURNING` に対応しない (この更新が動かない) ことを指摘していれば検出。source-verifier の反証ありだけで、最終報告に無ければ未検出 |

## デコイ

- D1: セキュリティ (認証・個人情報・秘密情報) の欠落。この設計は扱わないので、high/mid で指摘したら過剰
