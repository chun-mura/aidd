# AIDD Knowledge Base 設計 (案C: プラグイン + docs ハイブリッド)

日付: 2026-07-08
ステータス: レビュー待ち

## 目的

システム開発でAIを駆使するための個人用ナレッジベースを構築する。
実行可能資産 (skills / commands / agents / テンプレート) を主体とし、Claude Code プラグインとして他プロジェクトから1コマンドで導入できる形にする。方法論の知見は人向け docs に蓄積する。

## 前提 (確定事項)

- 利用者: 本人のみ (前提知識の説明は最小限)
- 対象ツール: Claude Code 特化
- コンテンツ: プロンプト/コマンド集、エージェント構成パターン、開発フロー tips、設定テンプレートの4種
- 配布方式: リポジトリ自体を Claude Code プラグイン (+ローカル marketplace) にする

## superpowers との棲み分け

原則: **「どう進めるか (process)」は superpowers、「何をさせるか (task/domain)」は本リポジトリ**。

superpowers が既にカバーする領域 (本リポジトリでは作らない):

- 要件探索 (brainstorming)、計画作成/実行 (writing-plans, executing-plans, subagent-driven-development)
- TDD (test-driven-development)、デバッグ (systematic-debugging)
- コードレビューの依頼/受領 (requesting/receiving-code-review)
- 検証 (verification-before-completion)、worktree 運用、ブランチ完了処理
- スキル作成メタ (writing-skills)
- 並列エージェント派遣の一般論 (dispatching-parallel-agents)

本リポジトリが担う領域:

| 領域 | 例 | 置き場 |
|---|---|---|
| タスク特化コマンド | 設計レビュー、テスト観点出し、ADR生成、リリースノート生成 | `commands/` |
| ドメイン特化スキル | API設計ガイド、DB設計ガイド等 (2回使ったら昇格) | `skills/` |
| エージェント構成の具体レシピ | レビュー担当×実装担当の分担定義、調査フォーメーション | `agents/` + `docs/patterns/` |
| 設定雛形 | CLAUDE.md 雛形、settings.json 雛形、hooks 雛形 | `templates/` |
| 方法論 tips | コンテキスト管理、モデル使い分け (haiku/sonnet/opus)、並列化戦略、superpowers の運用知見 | `docs/tips/` |

境界の判断基準: 「このスキルはどの開発フェーズでも同じ動きをするか?」→ Yes なら process (superpowers 側、作らない)。「特定の成果物・特定のドメインに紐づくか?」→ Yes なら本リポジトリ。

既存グローバル資産 (~/.claude) との重複も避ける: Cloudflare 系・trailofbits 系スキル、humanizer-ja、通知 hooks は既存のまま。本リポジトリには移さない。

## ディレクトリ構成

```
aidd/
├── .claude-plugin/
│   ├── plugin.json          # プラグイン manifest (name: aidd)
│   └── marketplace.json     # ローカル marketplace 定義
├── skills/                  # ドメイン/タスク特化スキル
├── commands/                # slash commands (定番タスクのプロンプト)
├── agents/                  # サブエージェント定義 (構成パターンの実体)
├── templates/               # 生ファイル雛形 (CLAUDE.md, settings.json, hooks)
├── docs/
│   ├── tips/                # 方法論の知見 (1トピック1ファイル)
│   ├── patterns/            # エージェント構成パターン解説 (agents/ の背景・使い分け)
│   └── superpowers/specs/   # 設計ドキュメント (本ファイル含む)
└── README.md                # 全資産インデックス + 導入手順
```

## 運用ルール

1. **1ファイル1関心事**。docs は冒頭に「いつ使うか」を必ず書く
2. **2回ルール**: プロンプトはまず docs/tips か commands の下書きとして記録し、2回以上使ったものだけ skills/commands に昇格
3. **README がインデックス**: 資産追加時に README の一覧を更新
4. **重複禁止**: superpowers・グローバル資産と機能が被るものは作らず、docs/tips に「〇〇は superpowers の△△を使う」とポインタだけ書く
5. モデル使い分け: 軽微な調査・整形は haiku/sonnet に委譲する方針を tips に明文化し、agents/ の定義にも model 指定を含める

## 初期コンテンツ (最小セット)

- `commands/`: 設計レビュー、テスト観点出し の2本
- `agents/`: 調査用軽量エージェント (haiku)、レビューエージェント の2本
- `templates/`: CLAUDE.md 雛形、settings.json 雛形
- `docs/tips/`: モデル使い分け、コンテキスト管理、superpowers 運用の3本
- `docs/patterns/`: 並列調査フォーメーション の1本
- README: インデックス + プラグイン導入手順

以降は実際の利用の中で追記していく (最初から網羅しない)。

## エラーハンドリング / テスト

- プラグインとして読み込めることを `claude` の `/plugin` 経由で実際に検証してから完了とする
- commands/skills は最低1回実プロジェクトで動作確認してから README に掲載

## スコープ外

- チーム共有・公開 (将来必要になったら README に導入手順を足すだけで対応可能な構造にはしておく)
- Claude Code 以外のツール対応
- 既存グローバル資産 (~/.claude) の本リポジトリへの移設
