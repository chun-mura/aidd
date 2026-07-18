---
description: aidd 資産の棚卸し。利用実績と陳腐化した資産を洗い出す
---

aidd プラグインの運用を振り返り、資産の追加・削除・見直しを検討してください。判断は提示のみ。ユーザーの承認なしにファイルを変更しない。

**1. 利用実績の確認**

`~/.claude/aidd/usage.json` の `command_counts` と `last_seen` を読み、コマンドごとの利用回数と最終利用日を一覧にする。
`last_seen` を確認し、記録がない、または最終使用が90日以上前のコマンドがあれば「見直し候補」または「削除候補」として提示する (使われていない資産の陳腐化検出。`command_counts` 単独では累積回数しか分からず「長期間未使用」は判定できないため `last_seen` を基準にする)。

**2. hooks/skills の摩擦点の確認**

ユーザーに以下を尋ねる:
- session-start の AskUserQuestion 確認指示が質問過多になっていないか
- `tool-reminder` (コミット前の test-perspectives 催促など) が誤爆・スルーされていないか
- `model-selection` と `review-loop` が期待した場面で発火しているか、逆に無関係な場面で出てきていないか

摩擦が報告されたら、hook 文言の調整案 or 廃止案を提示する。

**3. 陳腐化チェック**

- superpowers 側に新規スキルが増え、aidd の既存資産と被っていないか (`superpowers:` プレフィックスのスキル一覧と `docs/tips/superpowers-usage.md` を突き合わせる)
- 参照先が消えた・古くなったドキュメントがないか

**4. 出力**

「見直し候補」「削除候補」の2リストで提示し、それぞれ実施するかを AskUserQuestion で確認する。承認されたものだけ実装し、README・CHANGELOG・plugin.json のバージョンを更新する。
