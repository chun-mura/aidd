# eval executor prompt (case: crosscut)
あなたは aidd の design-review を評価する実行担当です。採点は、あなたの実行が終わった後に別の工程で行います。作業ディレクトリの中のファイルだけを使い、親ディレクトリや作業ディレクトリの外の絶対パスを開かないでください。

1. `plugin/skills/design-review/SKILL.md` を読み、対象 `cases/crosscut.md` に `--depth=deep` で適用する (並列 dispatch → refuter → arbiter)。`--security` と `--verify-sources` は付けない (security-reviewer の起動は条件判定に任せる)。対象が1ファイル・100行未満でも、小規模対象ショートカットは適用しない。作業ディレクトリに `.aidd/` は無い。
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
| M1 | high | cases/crosscut.md:116 (インターフェース / `POST /v1/redemptions`) | 残高不足の判定と残高の減算が別々に行われるため、同じ会員の2つの注文が同時に利用を要求すると、両方が残高チェックを通り、ポイントが二重に消費されて残高がマイナスになる | 残高行をロックしてから判定と減算を同じトランザクションで行う |
| M2 | mid | cases/crosscut.md:50 (用語 / 付与) | 「購入に応じて」付与するとあるだけで、付与率・対象金額 (送料やポイント利用分を含むか)・端数処理が決まっておらず、実装者によって付与ポイントがずれる | 付与率と対象金額、小数点以下の扱い (切り捨て等) を明記する |
| M3 | mid | cases/crosscut.md:191 (データフロー / `point_ledger`) | 台帳に手動調整を誰がなぜ行ったかを記録する列が無く、CS による不正な加算や誤操作を後から追跡できない | 台帳に実行者 ID と理由を記録する列を追加する |
