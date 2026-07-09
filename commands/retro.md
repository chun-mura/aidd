---
description: aidd 資産の棚卸し。繰り返しプロンプトの昇格候補と、hooks/skills の摩擦を洗い出す
---

aidd プラグインの運用を振り返り、資産の追加・削除・見直しを検討してください。判断は提示のみ。ユーザーの承認なしにファイルを変更しない。

**1. 昇格候補の発見 (README の2回ルール)**

`~/.claude/aidd/usage.json` を読み、`prompt_log` から類似意図のプロンプトが2回以上手で書かれていないか調べる (コマンド化されていない繰り返し依頼が対象。すでに `/aidd:*` として存在するものは `command_counts` で使用頻度を見るだけでよい)。見つかったら:
- 内容を要約し、commands / skills のどちらが適切か (`docs/tips/superpowers-usage.md` の「形態の選び方」節を判断基準に使う)
- 既に superpowers に同等スキルがないか確認 (被りなら見送り)

`command_counts` が長期間0のコマンドがあれば「見直し候補」または「削除候補」として提示する (使われていない資産の陳腐化検出)。

**2. hooks/skills の摩擦点の確認**

ユーザーに以下を尋ねる:
- `clarify-nudge` (毎プロンプトの確認催促) が質問過多になっていないか
- `commit-reminder` (コミット前の test-perspectives 催促) が誤爆・スルーされていないか
- skills (`model-selection`, `parallel-investigation`) が期待した場面で発火しているか、逆に無関係な場面で出てきていないか

摩擦が報告されたら、hook 文言の調整案 or 廃止案を提示する。

**3. 陳腐化チェック**

- superpowers 側に新規スキルが増え、aidd の既存資産と被っていないか (`superpowers:` プレフィックスのスキル一覧と `docs/tips/superpowers-usage.md` を突き合わせる)
- 参照先が消えた・古くなったドキュメントがないか

**4. 出力**

「追加候補」「見直し候補」「削除候補」の3リストで提示し、それぞれ実施するかを AskUserQuestion で確認する。承認されたものだけ実装し、README・CHANGELOG・plugin.json のバージョンを更新する。
