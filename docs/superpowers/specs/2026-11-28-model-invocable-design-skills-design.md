---
status: draft
---

# test-perspectives・design-doc・design-review をモデルから起動できるようにする (#196)

規模: skill 3本の frontmatter、契約テスト、文書の更新のため要約形式。

## 1. 背景と目的

aidd 自身は、次の3か所でモデルにこの3つの skill を使うよう案内している。

- `session-start.sh`: 毎回「設計レーンは design-doc → design-review、test-perspectives に渡す」と注入する
- `tool-reminder.sh`: 「`/aidd:test-perspectives` を実行すること」と通知する
- `issue-implement`・`autonomous-review`: 手順の中でこれらを呼ぶ

ところが3つとも `disable-model-invocation: true` で、モデルは Skill ツールから起動できない。[公式ドキュメント](https://code.claude.com/docs/en/skills.md) にも、skill の中から別の skill を起動する方法は書かれていない。

#196 で測ると (`claude -p`、4回)、次のとおりだった。

- test-perspectives は毎回飛ばされた
- 設計レーンでは design-doc の起動が拒否され、32秒で `blocked/incomplete` になった

非エンジニア向けの改修依頼システムでは、設計レーンの依頼が自動で進まない。対話でも、案内に従えずに止まる。モデルが起動できるようにして、案内と実際を一致させる。

`asset-audit`・`incident-retro` などは、既存の文書 (正典) の記述を削る・足す判断を、モデルが自分の判断の続きとして始めないために、利用者起動に限っている (CHANGELOG 0.37.0)。この3つは新しいファイルを作るだけで (design-review は何も書かない)、正典を書き換えないので、この理由は当たらない。

## 2. スコープ / やらないこと

やる:
- 3つの SKILL.md から `disable-model-invocation: true` を外す
- `description` を自動起動向けに書き直す (いつ使い、いつ使わないか)
- 契約テストで、3つに制限が無く、ほかの利用者起動の skill に制限があることを固定する
- `.claude/CLAUDE.md` の「Adding a user-invoked skill」とアーキテクチャの節、README・CHANGELOG・version を更新する

やらない:
- gate (`skill-gate.sh` の `ask`) を付けない。headless (`-p`) では `ask` が拒否として働く (`2026-11-14-autonomous-review-auto-invocation-design.md` の R2・R13)。付けると無人のホストで起動できず、目的を果たさない
- 条件付きの gate (対話のときだけ `ask`) も採らない。hook の入力の `permission_mode` は `-p` でも対話の auto mode でも `auto` で (先行設計の R2・R6)、両者を見分けられない
- `issue-split` は今の制限のまま。GitHub に起票し、issue-implement は提案して止まるだけで、起動を求めていない
- Codex は変えない (`agents/openai.yaml` の `allow_implicit_invocation: false` のまま)。Codex で `$aidd:issue-implement` の設計レーンが同じように止まるかは測っていない。既知の制限として残し、#196 に記録する (→ #205 で測定: codex-cli 0.163.0 では、モデルが issue-implement の手順に従って3つの SKILL.md を読み、止まらなかった。`tests/eval/results/2026-11-28-codex-design-skills.md`)
- 本文 (手順) は変えない。issue-implement の手順も変えない

## 3. 構成と責務

| 対象 | 配置 | 変更 |
|---|---|---|
| 3つの skill | `skills/{test-perspectives,design-doc,design-review}/SKILL.md` の frontmatter | `disable-model-invocation` を削除し、`description` を書き直す |
| 資産一覧 | `hooks/asset-index.json`・`templates/asset-overlap-prompt-hook.json.template` | `generate-asset-index.py` で再生成 (description が変わるため) |
| 契約テスト | `tests/command-contract-test.sh` | `agents/openai.yaml` を持つ skill (利用者起動の skill) のうち、許可リスト (autonomous-review とこの3つ) 以外がすべて `disable-model-invocation: true` を持ち、許可リストの3つは持たないことを、規則で列挙して確かめる |
| 規約 | `.claude/CLAUDE.md` | 例外を autonomous-review (gate あり) とこの3つ (gate なし、理由つき) にする |

## 4. インターフェース

利用者が `/aidd:<name>` と打つ使い方は変わらない。変わるのは、モデルが Skill ツールで起動できるようになることだけである。

description の案 (英語。auto-trigger の skill に合わせる):

- test-perspectives: `Use before implementing a non-trivial change, once a design doc or an issue fixes what to build, to list test perspectives with priorities. Not when perspectives were already produced for this change, for docs-only or trivial changes, or after implementation is complete; not for deriving concrete cases (stdd) or judging an existing suite.`
- design-doc: `Use when issue-implement's lane check puts a change in the design lane and no design document exists yet. Not when superpowers:brainstorming already produced the spec, and not for direct-lane changes.`
- design-review: `Use to review a design document written by design-doc before implementing it (the issue-implement design lane), or when the user asks for a multi-agent design review. Starts several reviewer agents: not for code diffs (autonomous-review, requesting-code-review), specs from superpowers:brainstorming unless asked, questions about a document, or inside a subagent dispatched to review.`

## 5. データフロー

状態を持たない。起動の経路が1つ増えるだけで、skill の中身は利用者が起動した場合と同じ。`usage-log.sh` は PreToolUse `^Skill$` も数えるので、モデルが起動した回数も `usage.json` に入り、利用者が打った回数と混ざる (利用者の起動は PreToolUse を通らない。先行設計の R4)。`/aidd:retro` はこの3つの回数を「利用者に使われているか」の材料にしない。

## 6. エラー処理・リスク

| リスク | 対処 |
|---|---|
| 普段の会話でモデルが自分の判断で起動する (design-review は reviewer 3〜6体と arbiter を起動するので高い) | description で「いつ使わないか」を書く。既定の `--depth=standard` のまま。実際に過剰に起動されたら description を絞る |
| 無人のホストで、Issue 本文に誘導されて design-review が起動される (先行設計の「誘導されて起動することはない」は、この3つには成り立たない) | 費用は、ホストの1件あたりの上限 (aidd-autopilot の `max_usd_per_task`、`claude -p --max-budget-usd`) で抑える |
| Cursor もこのフラグを解釈するので、Cursor でもモデルが起動できるようになる | 受け入れる。理由は Claude Code と同じ |
| description が文脈に入る | 3つで数百字。ドキュメント上、文脈の上限の1%の予算の中で扱われる |
| 誤って別の利用者起動の skill の制限を外す | 契約テストで、残りの利用者起動の skill に制限があることを固定する |

## 7. 運用

- design-review の SKILL.md を変えるので、運用ルール6により、リリースの前に `/aidd:eval` を実行して結果を残す。本文 (エージェントに渡すプロンプト) は変えないので、精度が変わらないことを確かめる位置づけ。eval 自体はモデルから起動できないので、利用者が打つ
- 変えたあとに #196 と同じ測定 (小×2・設計×1) を行い、起動されるか・費用を記録する
- 起動しすぎないかも測る: skill を使うべきでない依頼を `-p` で3つ流し、Skill の呼び出しを数える。(a) 設計書についての質問、(b) 小さなコード修正、(c) 既存の設計書の要約。起動されたら description を絞る
- ロールバックは revert で済む
