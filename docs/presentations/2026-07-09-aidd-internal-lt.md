---
marp: true
theme: default
paginate: true
title: aidd — AI駆動開発の共通ツールキット
description: 社内LT用ドラフト（5〜10分想定）· v0.11.0
---

# aidd を社内で使う
## AI駆動開発の「仕事の型」をプラグインにしたもの

**LT ドラフト** · 想定時間 7分 · v0.11.0 · 2026-07-09

---

## 今日伝えたいこと

1. **aidd とは何か** — 毎回プロンプトを書き直さなくていい仕組み
2. **何が便利か** — 設計・レビュー・ADR・運用リマインドまで標準化
3. **どう始めるか** — 2コマンドで導入、使いながらデータで育てる

> デモ環境: Claude Code + aidd (v0.11.0) + superpowers

---

## あるある

```
「設計レビュー、前と同じ観点でお願い」
「ADR と矛盾してない？ 毎回自分で探してる」
「テスト観点、コミット前に書いたっけ…」
「PR タイトル英語のまま push しちゃった」
```

AI は賢い。**でも毎回同じ指示を繰り返すのは人間のコスト。**

知見が個人の頭の中やチャット履歴に閉じている。

---

## aidd とは（一言）

> **Claude Code 用プラグイン。AI駆動開発の「実行可能な資産」をまとめたナレッジベース**

| 資産の種類 | 中身の例 |
|-----------|---------|
| コマンド (7) | `/aidd:design-review` `/aidd:design-sync` `/aidd:doctor` |
| エージェント (4) | 調査・レビュー・裁定・外部情報源検証 |
| スキル (3) | ADR 想起・モデル選び・並列調査 |
| フック (6) | セッション開始・コミット前・PR 作成・push 後 |

**ドキュメントを読むだけではなく、セッション中に実際に効く。**

---

## 用語で整理（30秒版）

| 用語 | aidd での意味 |
|------|--------------|
| **プロンプト** | `commands/` — 定型タスク用の指示文（スラッシュコマンド） |
| **コンテキスト** | `CLAUDE.md` / `.aidd/` — プロジェクト固有の前提知識 |
| **エージェント** | `agents/` — 調査・レビュー・裁定・検証の役割分担 |
| **ハーネス** | プラグイン機構 + `hooks/` — 実行環境側の注入・リマインド |
| **ループ** | 実装サイクルは **superpowers** が担当。aidd はその前後 |

---

## 全体像

```
┌─────────────────────────────────────────────┐
│  あなたのプロジェクト                          │
│  CLAUDE.md · .aidd/design-perspectives.md    │
│  docs/adr · docs/design · docs/test-perspectives │
└──────────────────┬──────────────────────────┘
                   │ プラグインとして読み込み
┌──────────────────▼──────────────────────────┐
│  aidd プラグイン (v0.11.0)                    │
│  commands · agents · skills · hooks          │
└──────────────────┬──────────────────────────┘
                   │ 実装フェーズは委譲
┌──────────────────▼──────────────────────────┐
│  superpowers プラグイン                       │
│  ブレスト → 計画 → TDD → デバッグ → 検証       │
└─────────────────────────────────────────────┘
```

---

## 主要コマンド（7本）

| コマンド | いつ使う |
|---------|---------|
| `/aidd:design-doc` | 要件から設計書を `docs/design/` に生成 |
| `/aidd:design-review` | 多観点レビュー（並列エージェント + 任意で外部検証） |
| `/aidd:adr` | アーキテクチャ決定を `docs/adr/` に記録 |
| `/aidd:test-perspectives` | テスト観点を洗い出し `docs/test-perspectives/` に保存 |
| `/aidd:design-sync` | 設計書と実装の乖離を検知・status 更新 |
| `/aidd:doctor` | aidd / superpowers の導入状態を診断 |
| `/aidd:retro` | 使用実績から昇格候補・陳腐化資産を棚卸し |

---

## 設計レビューの中身（デモの核）

`/aidd:design-review` を実行すると:

1. **Agent 1–3**（reviewer / sonnet）— 構造・データとエラー・実用性を並列レビュー
2. **Agent 4**（任意）— `.aidd/design-perspectives.md` のプロジェクト固有観点
3. **Agent 5**（任意）— `--verify-sources` で技術選定・API仕様等を外部情報源と突合
4. **design-arbiter**（opus）— 統合・裁定 → 最優先の修正1点を提示

メインが sonnet でも、**重い判断は opus に固定**。外部検証は opt-in（コスト考慮）。

---

## 自動で効く仕組み — Skills

ユーザーが明示的に呼ばなくても、状況に応じて読み込まれる:

| スキル | 発火タイミング |
|--------|--------------|
| `adr-recall` | アーキ変更・設計判断の前 → 既存 ADR との矛盾を検知 |
| `model-selection` | サブエージェント起動時 → haiku/sonnet/opus の使い分け |
| `parallel-investigation` | 未知コードベースの調査 → scout 並列偵察の編成 |

**受動ドキュメントではなく、セッション中に能動的に参照される。**

---

## 自動で効く仕組み — Hooks

モデルに頼らず、ハーネスが運用を補助する（すべて非ブロック）:

| タイミング | 内容 |
|-----------|------|
| セッション開始 | 資産の使いどころ注入・superpowers 未導入警告・20回ごとに retro 提案 |
| プロンプト送信時 | 不明点は推測せず確認 / 使用実績を `usage.json` に記録 |
| `git commit` 前 | `docs/test-perspectives/` が6時間以内に更新されていなければ注意 |
| `gh pr/issue` 前 | タイトル・本文は日本語で、と注入 |
| `git push` 後 | open PR のタイトル・概要を最新化するようリマインド |

---

## 設計 ↔ 実装の一気通貫

```
要件 → /aidd:design-doc → docs/design/
         ↓
      /aidd:design-review（+ プロジェクト固有観点 + 外部検証）
         ↓
      superpowers で実装（TDD・デバッグ）
         ↓
      /aidd:test-perspectives → docs/test-perspectives/
         ↓ commit-reminder が鮮度チェック
      /aidd:design-sync → 設計と実装の乖離検知
```

ADR は `adr-recall` が変更前に自動で矛盾チェック。

---

## superpowers との棲み分け

| 担当 | 領域 | 例 |
|------|------|-----|
| **superpowers** | どう進めるか（プロセス） | ブレスト、計画、TDD、デバッグ |
| **aidd** | 何をさせるか（タスク） | 設計書、ADR、設計レビュー、テスト観点、運用リマインド |

**セットで使う前提。** `/aidd:doctor` で両方の導入状態を確認できる。

---

## プロジェクトごとに最適化できる

| レイヤー | 置き場 | 用途 |
|---------|--------|------|
| コンテキスト | `CLAUDE.md` | 技術スタック・規約・コマンド |
| 固有観点 | `.aidd/design-perspectives.md` | 設計レビューの追加観点 |
| 成果物 | `docs/adr/` `docs/design/` `docs/test-perspectives/` | プロジェクトの記録 |
| ローカル資産 | `.claude/skills/` 等 | ドメイン特化の知見 |
| 昇格 | aidd 本体 | 2回以上使ったプロンプトを共通化 |

`/aidd:retro` が `usage.json` の実データから昇格候補を提案。

---

## 導入（2ステップ）

```bash
# 1. aidd
/plugin marketplace add chun-mura/aidd
/plugin install aidd@aidd-local

# 2. superpowers（必須）
/plugin marketplace add obra/superpowers
/plugin install superpowers@superpowers-marketplace
```

`CLAUDE.md` を置く → `/aidd:doctor` で状態確認 → 開発開始。

---

## 運用のコツ（3つだけ）

1. **2回ルール** — 同じプロンプトを2回使ったら `commands/` / `skills/` に昇格
2. **受動ドキュメント禁止** — 効かせたい知見は docs ではなく skills / hooks に
3. **重複禁止** — superpowers と被るものは作らず、ポインタだけ

20セッションごとに `/aidd:retro` で棚卸し。使われていない資産は削除候補に。

---

## 社内で始めるなら

**Phase 1（今週）**
- 1プロジェクトで aidd + superpowers を導入
- `CLAUDE.md` と `.aidd/design-perspectives.md` を整備
- 設計レビュー・テスト観点を実際の PR で試す

**Phase 2（1ヶ月後）**
- `/aidd:retro` で使用実績ベースの昇格候補を洗い出し
- チーム共通の観点を `.aidd/` や aidd 本体に昇格
- hooks の摩擦（リマインド過多など）を調整

---

## まとめ

- **aidd** = 設計・レビュー・ADR・運用リマインドをプラグイン化
- **7コマンド + 4エージェント + 3スキル + 6フック** で前後をカバー
- **superpowers** とセットで、設計〜実装のループが閉じる
- **使いながら育てる** — usage ログ + retro でデータ駆動の改善

---

## Q & A

**よくある質問（先回り）**

- *Cursor でも使える？* → 現状 Claude Code 特化。Cursor 向けは別途検討
- *チーム全員必須？* → 個人導入から OK。共通資産は retro で徐々に昇格
- *hooks がうるさい？* → すべて非ブロック。摩擦は retro で調整・廃止可能
- *外部検証は必須？* → `--verify-sources` は opt-in。通常レビューだけでも十分
- *社内 marketplace は？* → リポジトリを fork して社内 GitHub に置けば同じ仕組みで配布可能

---

<!--
## 発表者メモ（スライド外）

### タイム配分（7分）
- 導入・課題: 1分
- aiddとは・用語・全体像: 1.5分
- コマンド・設計レビュー: 1.5分
- skills/hooks・一気通貫フロー: 1.5分
- 棲み分け・導入・まとめ: 1分
- Q&A: バッファ

### デモがある場合（+3分）
1. `/aidd:doctor` — aidd + superpowers の導入確認
2. `/aidd:design-review docs/design/xxx.md` — 並列レビュー + arbiter 裁定
3. （任意）`--verify-sources` で Agent 5 の外部検証を見せる
4. `.aidd/design-perspectives.md` がある場合の Agent 4 追加を見せる

### v0.11.0 で追加された主な機能（このドラフトへの反映点）
- `agents/source-verifier.md` + design-review `--verify-sources` (0.9.0)
- `skills/adr-recall/` — ADR 矛盾の能動的検知 (0.8.0)
- `hooks/usage-log.sh` — usage.json によるデータ駆動 retro (0.8.0)
- `commands/design-sync.md` — 設計と実装の乖離検知 (0.8.0)
- test-perspectives 永続化 + commit-reminder 鮮度チェック (0.8.0)
- `.aidd/design-perspectives.md` によるプロジェクト固有観点 (0.8.0)
- `commands/doctor.md` — 導入診断 (0.8.0)
- `hooks/gh-language-reminder.sh` — PR/issue 日本語リマインド (0.10.0)
- `hooks/pr-sync-reminder.sh` — push 後の PR 更新リマインド (0.11.0)

### 社内向けにカスタムする箇所
- [ ] marketplace の URL（社内 GitHub org/repo）
- [ ] 導入の責任者・問い合わせ先
- [ ] Phase 1 の対象プロジェクト名
- [ ] 社内固有の `.aidd/design-perspectives.md` 例（セキュリティ・コンプライアンス観点など）
-->
