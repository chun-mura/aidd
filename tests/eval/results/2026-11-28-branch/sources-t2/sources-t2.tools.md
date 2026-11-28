# 起動と Web の記録: sources 試行 2

| 項目 | 値 |
|---|---|
| Agent 4 (プロジェクト固有観点を渡した reviewer) | no (0) |
| Agent 5 (source-verifier) | yes (1) |
| Agent 6 (security-reviewer) | no (0) |
| reviewer の dispatch 数 | 3 |
| source-verifier の Web 到達 | 到達あり (成功 3 / 呼び出し 3) |

## dispatch した agent

| tool_use_id | subagent_type | 呼んだ側 | プロジェクト固有観点 | 返答 |
|---|---|---|---|---|
| toolu_01BTmnXMWagXJJN5tRQ23DDn | aidd:reviewer | メイン | no | あり |
| toolu_01Cqp4CSo1sgRLUhnV8x3u4U | aidd:reviewer | メイン | no | あり |
| toolu_01M1eXzbxdKpcZCPtmhRRfG9 | aidd:reviewer | メイン | no | あり |
| toolu_0129ajUo28FThCvp4ckKi43t | aidd:source-verifier | メイン | no | あり |
| toolu_01EPx6c9Bh8iDqUQEmUq36yH | aidd:refuter | メイン | no | あり |
| toolu_01PUcuXBpC2ZHm49ed3tUsKx | aidd:design-arbiter | メイン | no | あり |

## Web の呼び出し

| tool | 呼んだ側 | 入力 | 結果 |
|---|---|---|---|
| WebFetch | aidd:source-verifier | https://www.postgresql.org/docs/16/sql-merge.html | 成功 |
| WebFetch | aidd:source-verifier | https://www.postgresql.org/docs/17/sql-merge.html | 成功 |
| WebFetch | aidd:source-verifier | https://docs.python.org/3.12/library/datetime.html | 成功 |

## source-verifier の返答

### toolu_0129ajUo28FThCvp4ckKi43t

検証対象: [input]/cases/sources.md
検証した主張は3件で、1件が反証、1件が確認済み、1件が未確認です。プロジェクト内部の判断(差分更新の方針、運用、エラー処理、ロールバック)は対象外としました。

1. 反証あり: 「PostgreSQL 16 の `MERGE` は `RETURNING` 句に対応している」(技術的な判断 2)
- PostgreSQL 16 の公式ドキュメントには、MERGE の Notes に "There is no `RETURNING` clause with `MERGE`." とあります。`MERGE` が返すのはコマンドタグ `MERGE total_count` だけです。
  https://www.postgresql.org/docs/16/sql-merge.html
- `MERGE ... RETURNING` は PostgreSQL 17 のドキュメントに載っています。
  https://www.postgresql.org/docs/17/sql-merge.html
  - 補足: 取得ツールは、17 のページ内容を「18 のものかもしれない」と推測しました。私の記憶では、17 で MERGE の RETURNING と `merge_action()` が追加されています。ただしこの版の点は 17 のリリースノートを直接確認していないため、未確認です。
- 修正案(いずれかを選ぶ)
  - PostgreSQL 17 以上に前提の版を上げる。
  - 16 のままにして `RETURNING` をやめ、`MERGE` のコマンドタグ(件数)をログに出す。ドライバから取れる場合は、そのコマンドタグの件数を使う。
  - どちらでも、「更新・追加した行を受け取る」という要件が件数だけで足りるかは、設計側で見直してください。

2. 確認済み: 「Python 3.12 で `datetime.datetime.utcnow()` が非推奨になった」「`datetime.now(timezone.utc)` を使う」(技術的な判断 1)
- 公式ドキュメントに "Deprecated since version 3.12" とあり、推奨は `datetime.now(timezone.utc)` または `datetime.now(UTC)` です。
  https://docs.python.org/3.12/library/datetime.html

3. 未確認: 「`acme-retry` 2.4 は待ち時間の上限を既定で30秒にする」(技術的な判断 3)
- 社内ライブラリで、公開の一次情報がありません。
- 参照 URL は `wiki.example.invalid` で、ドメインが無効のため到達できません。
- 設計書が根拠として挙げている出典が、実在するか確認できない状態です。担当者が社内の実物で既定値を確認してください。
