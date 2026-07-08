# aidd — AI-Driven Development Knowledge Base

個人用。AI駆使のための実行可能資産 + 知見。Claude Code プラグインとして導入可能な、タスク特化コマンド・エージェント・テンプレート・方法論の集約。

## 導入 (他プロジェクトから使う)

```bash
/plugin marketplace add /Users/nakamurakohki/workspace/private_dev/prototype_aidd
/plugin install aidd@aidd-local
```

## インデックス

### Commands (タスク特化プロンプト)

| ファイル | 説明 |
|---------|------|
| `design-review.md` | 設計ドキュメントや実装方針を多観点 (責務分割・エラーハンドリング等) でレビュー |
| `test-perspectives.md` | 実装対象・変更差分からテスト観点 (正常系・異常系・エッジケース) を洗い出す |

### Agents (サブエージェント定義)

| ファイル | 説明 |
|---------|------|
| `reviewer.md` | コード・ドキュメントの品質チェック用エージェント (デフォルト: sonnet) |
| `scout.md` | 軽量読み取り調査エージェント、ファイル検索・コードベース偵察用 (デフォルト: haiku) |

### Templates (設定雛形)

| ファイル | 説明 |
|---------|------|
| `CLAUDE.md.template` | プロジェクト概要・技術スタック・コマンド・作業フローをまとめるテンプレート |
| `settings.json.template` | Claude Code 権限設定・環境変数・hooks の基本構成テンプレート |

### Tips (方法論の知見)

| ファイル | 説明 |
|---------|------|
| `context-management.md` | 長いセッションでコンテキストを効率的に管理するアプローチ |
| `model-selection.md` | haiku / sonnet / opus / fable の使い分け基準 (コスト・速度・判断能力) |
| `superpowers-usage.md` | superpowers スキルとの棲み分け、二重実装の回避 |

### Patterns (エージェント構成パターン)

| ファイル | 説明 |
|---------|------|
| `parallel-investigation.md` | 複数の独立した調査を scout 群で並列化するフォーメーション |

## 運用ルール

1. **1ファイル1関心事**: 各ファイルは単一トピックに集中。docs は冒頭に「いつ使うか」を明記
2. **2回ルール**: 同じプロンプトを2回以上使ったものだけ commands/skills に昇格
3. **README更新**: 資産追加時は本インデックスを更新
4. **重複禁止**: superpowers・グローバル資産と被る機能は作らず、ポインタのみ記載
5. **モデル使い分け**: 軽微な調査は haiku/sonnet に委譲、判断が必要な場合は上位モデルを選定

## 設計ドキュメント

詳細な設計・運用ガイドは以下を参照:

- `docs/superpowers/specs/2026-07-08-aidd-knowledge-base-design.md` — 全体設計、ディレクトリ構成、スコープの棲み分け
