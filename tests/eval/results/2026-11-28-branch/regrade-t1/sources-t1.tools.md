# 起動と Web の記録: sources 試行 1

| 項目 | 値 |
|---|---|
| Agent 4 (プロジェクト固有観点を渡した reviewer) | no (0) |
| Agent 5 (source-verifier) | yes (1) |
| Agent 6 (security-reviewer) | no (0) |
| reviewer の dispatch 数 | 3 |
| source-verifier の Web 到達 | 到達あり (成功 2 / 呼び出し 3) |

## dispatch した agent

| tool_use_id | subagent_type | 呼んだ側 | プロジェクト固有観点 | 返答 |
|---|---|---|---|---|
| toolu_01A3AVeRNxNbDGML4ckh9PgH | aidd:reviewer | メイン | no | あり |
| toolu_01ThP1Pos2g2TV8jaHAwgDkd | aidd:reviewer | メイン | no | あり |
| toolu_016DzjNs86DdG7z72L9eM2Au | aidd:reviewer | メイン | no | あり |
| toolu_01QUFo4Ca1z4iz31nUdK3c3C | aidd:source-verifier | メイン | no | あり |
| toolu_01QxYp8ogKKCpdL3n4G7aXgc | aidd:refuter | メイン | no | あり |
| toolu_01D379s6dyYexYzivsktiimg | aidd:design-arbiter | メイン | no | あり |

## Web の呼び出し

| tool | 呼んだ側 | 入力 | 結果 |
|---|---|---|---|
| WebFetch | aidd:source-verifier | https://www.postgresql.org/docs/16/sql-merge.html | 成功 |
| WebFetch | aidd:source-verifier | https://docs.python.org/3.12/whatsnew/3.12.html | エラー: aborted |
| WebFetch | aidd:source-verifier | https://docs.python.org/3.12/library/datetime.html | 成功 |

## source-verifier の返答

### toolu_01QUFo4Ca1z4iz31nUdK3c3C

対象: [input]/cases/sources.md

検証した主張は3件です。うち1件は反証あり、1件は確認済み、1件は未確認です。

**主張2(技術的な判断2)は反証ありです。**
- 主張: 「PostgreSQL 16 の `MERGE` は `RETURNING` 句に対応している」。
- 結果: 反証あり。PostgreSQL 16 の公式ドキュメントに「There is no `RETURNING` clause with `MERGE`」と明記されています。`MERGE` の成功時に返るのはコマンドタグ `MERGE total_count` だけで、更新・追加した行は受け取れません。
- 出典: https://www.postgresql.org/docs/16/sql-merge.html
- 補足: 私の知識では `MERGE ... RETURNING` は PostgreSQL 17 で追加されたものです。この点は今回の取得では確認していません。
- 修正案(いずれも提案のみ。適用はしていません):
  - 実行ログに出すのは行数だけなので、コマンドタグの件数 (psycopg なら `cursor.rowcount`) を使う。ただし更新と追加は区別できません。
  - 更新と追加を分けて数える必要がある場合は、`INSERT ... ON CONFLICT ... RETURNING` を検討する。ただし `MERGE` と完全に同じ動作ではありません。
  - 前提の版を PostgreSQL 17 以上に変更する。

**主張1(技術的な判断1)は確認済みです。**
- 主張: Python 3.12 で `datetime.datetime.utcnow()` が非推奨になった。代替は `datetime.now(timezone.utc)`。
- 結果: ドキュメントに「Deprecated since version 3.12」とあり、推奨は `datetime.now(timezone.utc)` と記載されています。
- 出典: https://docs.python.org/3.12/library/datetime.html

**主張3(技術的な判断3)は未確認です。**
- 主張: `acme-retry` 2.4 は待ち時間の上限を既定で30秒にする。
- 理由: 社内ライブラリです。参照先 URL は `wiki.example.invalid` で、解決できない無効ドメインです。外部の信頼できる情報源がなく、検証できません。
- 補足: 社内ライブラリの既定値は、ライブラリのソースかリリースノートで確認してください。到達可能な参照先に直すことも提案します。

**範囲外として除外したもの**
- 週次の集計方式、エラー処理、運用、ロールバックなどのプロジェクト内部の設計判断。
- 「Python 3.12、PostgreSQL 16」という前提の版の選択。ただし上記のとおり、主張2は PostgreSQL 16 では成立しません。
