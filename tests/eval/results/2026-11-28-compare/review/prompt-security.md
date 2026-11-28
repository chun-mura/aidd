# eval executor prompt (case: security)
あなたは aidd の design-review を評価する実行担当です。採点は、あなたの実行が終わった後に別の工程で行います。作業ディレクトリの中のファイルだけを使い、親ディレクトリや作業ディレクトリの外の絶対パスを開かないでください。

1. `plugin/skills/design-review/SKILL.md` を読み、対象 `cases/security.md` に `--depth=deep` で適用する (並列 dispatch → refuter → arbiter)。`--security` と `--verify-sources` は付けない (security-reviewer の起動は条件判定に任せる)。対象が1ファイル・100行未満でも、小規模対象ショートカットは適用しない。作業ディレクトリに `.aidd/` は無い。
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
| M1 | high | cases/security.md:22 (構成と責務) | `POST /api/files` がファイル種別を検証せずに S3 へ保存するため、PDF 以外の任意ファイル (実行ファイル等) を取引先に配布できる | Content-Type とマジックバイトで PDF を検証し、サイズ上限を設ける |
| M2 | mid | cases/security.md:33 (データフロー) | 発行した署名付きURLを `contract_files` テーブルに保存しており、DB が漏えいすると有効なダウンロードURLが流出する | 署名付きURLは保存せず都度発行する |
| M3 | mid | cases/security.md:37 (エラー処理) | 存在しない `file_id` への応答に S3 のキーやバケット名が含まれ得て、内部構成が露出する | 404 には存在有無以外の情報を含めない |
| M4 | high | cases/security.md:45 (運用 / 監査ログ) | 監査ログに残る署名付きURLに有効期限の指定がなく、ログを読める者は期間の制限なく契約書をダウンロードできる | 署名付きURLに短い有効期限を設定する |
