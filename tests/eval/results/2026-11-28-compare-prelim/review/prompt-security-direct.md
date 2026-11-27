# eval compare prompt (case: security, config: direct)
あなたは aidd の design-review を評価する実行担当です。採点は、あなたの実行が終わった後に別の工程で行います。作業ディレクトリの中のファイルだけを使い、親ディレクトリや作業ディレクトリの外の絶対パスを開かないでください。

1. `plugin/skills/design-review/SKILL.md` を読み、対象 `cases/security.md` に次の構成で適用する。`--security` と `--verify-sources` は付けない (security-reviewer の起動は条件判定に任せる)。作業ディレクトリに `.aidd/` は無い。
   構成: `--depth=standard` で適用し、小規模対象ショートカットを使う (agent に dispatch せず、メインが design-review の観点で直接レビューする)。その後の refuter・arbiter は design-review の standard の条件に従う。
2. dispatch する場合は、各 agent に対象ケースのパスと担当観点だけを渡し、「このファイルだけをレビューする」と明示する。
3. ユーザーには質問しない (答えは返らない)。判断が要るところは、判断と理由を出力に書いて進める。
4. 最後に、次の見出しをこの順ですべて含む Markdown を最終回答にする。中身が無い節には「なし」、取れない値には「不明」と書く。
   - `## 経路` (dispatch した agent、refuter・arbiter を起動したかとその理由、小規模対象ショートカットを使ったか)
   - `## reviewer の生指摘` (agent ごと、またはメインが直接レビューした指摘。深刻度・引用箇所・指摘・代案)
   - `## refuter の判定` (指摘ごとに、反証成立/反証失敗と根拠)
   - `## 最終報告` (design-review がユーザーに返す最終の報告の全文と、high/mid/low 別の件数)
   - `## security-reviewer の起動` (yes/no と理由)
# end eval compare prompt
