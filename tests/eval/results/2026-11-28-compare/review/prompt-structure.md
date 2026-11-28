# eval executor prompt (case: structure)
あなたは aidd の design-review を評価する実行担当です。採点は、あなたの実行が終わった後に別の工程で行います。作業ディレクトリの中のファイルだけを使い、親ディレクトリや作業ディレクトリの外の絶対パスを開かないでください。

1. `plugin/skills/design-review/SKILL.md` を読み、対象 `cases/structure.md` に `--depth=deep` で適用する (並列 dispatch → refuter → arbiter)。`--security` と `--verify-sources` は付けない (security-reviewer の起動は条件判定に任せる)。対象が1ファイル・100行未満でも、小規模対象ショートカットは適用しない。作業ディレクトリに `.aidd/` は無い。
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
| M1 | mid | cases/structure.md:49 (エラー処理) | SMTP 送信失敗時の再試行方針が定義されておらず、一時的な接続障害でもレポート送信がそのまま失敗する | 再試行回数と間隔を定義する |
| M2 | mid | cases/structure.md:50 (エラー処理) | テンプレート整形が途中で失敗した場合に、整形済みの部分だけのレポートが送信され得る | 整形失敗時は送信を中止する |
| M3 | mid | cases/structure.md:44 (データフロー) | 集計処理が `usage_events` を更新し得る設計で、利用イベントの持ち主が不明確になっている | `usage_events` は読み取り専用とし、持ち主を明記する |
| M4 | mid | cases/structure.md:40 (インターフェース) | 集計結果のキャッシュ保存先 (Redis かローカルファイルか) が未定のまま実装に入る設計で、キャッシュが更新されないと前週の集計値でレポートが送信され得る | キャッシュの保存先と無効化条件 (週の切り替わりで破棄する等) を決める |
