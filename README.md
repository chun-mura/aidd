# aidd — AI-Driven Development Knowledge Base

個人用。AI駆使のための実行可能資産 + 知見。Claude Code プラグインとして導入可能な、タスク特化コマンド・エージェント・スキル・テンプレート・方法論の集約。

## 導入 (他プロジェクトから使う)

```bash
/plugin marketplace add chun-mura/aidd
/plugin install aidd@aidd-local
```

## インデックス

### Commands (タスク特化プロンプト)

| ファイル | 説明 |
|---------|------|
| `retro.md` | aidd 資産の棚卸し。昇格候補・hooks/skills の摩擦・陳腐化を洗い出す (20セッションごとに hook が想起) |
| `design-doc.md` | 要件から設計書を生成し docs/design/ に保存。構成は design-review の6観点と1対1対応 |
| `adr.md` | アーキテクチャ決定記録を docs/adr/NNNN-<slug>.md に作成。1 ADR = 1 決定 |
| `design-review.md` | 設計や実装方針を多観点レビュー。3× reviewer (sonnet) 並列 → design-arbiter (opus) が裁定 |
| `test-perspectives.md` | 実装対象・変更差分からテスト観点 (正常系・異常系・エッジケース) を洗い出す |

### Agents (サブエージェント定義)

| ファイル | 説明 |
|---------|------|
| `design-arbiter.md` | design-review の統合裁定エージェント (opus)。メインのモデルに依らず重い判断を opus に固定 |
| `reviewer.md` | 成果物の検収用エージェント (sonnet)。PR全体のレビューは pr-review-toolkit の担当 |
| `scout.md` | 軽量読み取り調査エージェント (haiku)、ファイル検索・コードベース偵察用 |

### Skills (自動トリガする知見)

| ファイル | 発火条件 |
|---------|------|
| `model-selection/` | サブエージェント起動時・model 指定に迷ったとき |
| `parallel-investigation/` | 未知コードベースの調査・独立した複数の問いがあるとき |

### Hooks (強制力のある運用)

| スクリプト | 動作 |
|---------|------|
| `session-start.sh` | SessionStart で aidd 資産の使いどころを1行注入。20セッションごとに `/aidd:retro` を提案 (状態は `~/.claude/aidd/state.json`) |
| `clarify-nudge.sh` | UserPromptSubmit 毎に「実装を左右する不明点は AskUserQuestion で確認」を注入 |
| `commit-reminder.sh` | `git commit` 前に test-perspectives 未実施の注意を注入 (非ブロック) |

### Templates (設定雛形)

| ファイル | 説明 |
|---------|------|
| `CLAUDE.md.template` | プロジェクト概要・技術スタック・コマンド・AI運用をまとめるテンプレート |
| `settings.json.template` | Claude Code 権限設定の基本構成テンプレート |

### Tips (方法論の知見)

| ファイル | 説明 |
|---------|------|
| `superpowers-usage.md` | superpowers スキルとの棲み分け、二重実装の回避 |

## 運用ルール

1. **1ファイル1関心事**: 各ファイルは単一トピックに集中。docs は冒頭に「いつ使うか」を明記
2. **2回ルール**: 同じプロンプトを2回以上使ったものだけ commands/skills に昇格
3. **README更新**: 資産追加時は本インデックスを更新し、plugin.json の version を上げて CHANGELOG に記録
4. **重複禁止**: superpowers・グローバル資産と被る機能は作らず、ポインタのみ記載
5. **受動ドキュメント禁止**: セッション中に効かせたい知見は docs でなく skills (自動トリガ) か hooks (強制) にする

## 設計ドキュメント

詳細な設計・運用ガイドは以下を参照:

- `docs/superpowers/specs/2026-07-08-aidd-knowledge-base-design.md` — 全体設計、ディレクトリ構成、スコープの棲み分け
