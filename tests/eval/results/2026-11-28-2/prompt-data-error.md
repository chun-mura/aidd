# eval executor prompt (case: data-error)
あなたは aidd の design-review を評価する実行担当です。採点は、あなたの実行が終わった後に別の工程で行います。作業ディレクトリの中のファイルだけを使い、親ディレクトリや作業ディレクトリの外の絶対パスを開かないでください。

1. `plugin/skills/design-review/SKILL.md` を読み、対象 `cases/data-error.md` に `--depth=deep` で適用する (並列 dispatch → refuter → arbiter)。`--security` と `--verify-sources` は付けない (security-reviewer の起動は条件判定に任せる)。対象が1ファイル・100行未満でも、小規模対象ショートカットは適用しない。作業ディレクトリに `.aidd/` は無い。
2. 各 agent への dispatch では、対象ケースのパスと担当観点だけを渡し、「このファイルだけをレビューする」と明示する。
3. 指摘の混入: reviewer の high/mid 指摘と、このプロンプトの末尾にある「混ぜる指摘」の表の行を順不同に混ぜ、すべてを中立な ID (F1, F2, …) に振り直して同じ形式で refuter に渡す。どの指摘を混ぜたかは refuter に知らせない。reviewer の high/mid が無くても、混ぜる指摘だけで refuter を起動する。refuter の後、arbiter に渡す前に混ぜた指摘を取り除く。reviewer・arbiter には混ぜる指摘を渡さない。
4. ユーザーには質問しない (答えは返らない)。判断が要るところは、判断と理由を出力に書いて進める。
5. 最後に、次の見出しをこの順ですべて含む Markdown を最終回答にする。中身が無い節には「なし」、取れない値には「不明」と書く。
   - `## reviewer の生指摘` (agent ごとに、深刻度・引用箇所・指摘・代案)
   - `## refuter への入力と対応表` (中立 ID ごとに元の ID。reviewer の指摘は agent と番号、混ぜた指摘は M の ID)
   - `## refuter の判定` (中立 ID ごとに、反証成立/反証失敗と根拠)
   - `## arbiter の最終報告` (全文と、high/mid/low 別の件数)
   - `## security-reviewer の起動` (yes/no と理由)
# end eval executor prompt

## 混ぜる指摘

| ID | 深刻度 | 引用箇所 | 指摘 | 代案 |
|---|---|---|---|---|
| M1 | high | cases/data-error.md:39 (エラー処理) | WMS API が認証エラーや 5xx を返し続けても、各商品の失敗としてスキップして処理を続け、バッチは正常終了する。WMS 側の全面障害が exit code の監視に現れない | 認証エラー・5xx 連続を検知したら例外を上げてバッチを失敗させる |
| M2 | mid | cases/data-error.md:34 (データフロー) | `StockApi` が Redis にキーが無い場合の挙動が定義されておらず、キャッシュミス時に在庫数を返せない | キャッシュミス時は DB を読む |
| M3 | mid | cases/data-error.md:30 (インターフェース) | `GET /internal/stock/{product_id}` が外部に公開される前提なのに、認証・アクセス制御の設計が無い | 内部ネットワークからのみ到達可能にする |
| M4 | mid | cases/data-error.md:34 (データフロー) | WMS の Webhook によるリアルタイム更新と5分間隔の `SyncBatch` が同じ在庫行に書き込むため、後から書いた方が勝ち、古い在庫数で新しい値を上書きし得る | 書き込みにバージョン番号や更新時刻を持たせ、古い値での上書きを拒否する |
