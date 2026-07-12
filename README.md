# aidd — AI-Driven Development Knowledge Base

AI駆使のための実行可能資産 + 知見。Claude Code プラグインとして導入可能な、タスク特化コマンド・エージェント・スキル・テンプレート・方法論の集約。

**superpowers プラグイン必須**: aidd は設計・レビュー・運用強制のみを担当し、実装フェーズ (brainstorming・TDD・デバッグ・計画立案) は superpowers に委ねる設計 ([棲み分け原則](docs/tips/superpowers-usage.md))。superpowers 未導入だと `/aidd:design-doc` 等で作った設計を実装に繋ぐプロセスが空白になる。session-start hook が未導入を検知して警告するが、ブロックはしない (検知はベストエフォート)。

**pr-review-toolkit プラグイン推奨**: aidd:reviewer は成果物単体の検収用で、PR全体のレビュー (スタイル・テストカバレッジ・サイレント障害・型設計など多観点) は pr-review-toolkit の担当。導入しなくても aidd の各機能は動くが、PRレビューの網羅性が下がる。

## 導入 (他プロジェクトから使う)

### 個人で使う

```bash
/plugin marketplace add chun-mura/aidd
/plugin install aidd@aidd

# 必須: 実装フェーズを担う superpowers も導入
/plugin marketplace add obra/superpowers-marketplace
/plugin install superpowers@superpowers-marketplace

# 推奨: PR全体レビューを担う pr-review-toolkit も導入
/plugin marketplace add anthropics/claude-plugins-official
/plugin install pr-review-toolkit@claude-plugins-official
```

### チームで使う (プロジェクト単位で自動導入)

利用プロジェクトの `.claude/settings.json` に `templates/team-settings.json.template` の内容をマージしてコミットすると、プロジェクトフォルダを trust したメンバーに aidd のインストールが自動で提案される。各自が手で `/plugin marketplace add` する必要はない。

更新の配信は `plugin.json` の `version` に固定される (version を上げない限りメンバーに更新が届かない)。リリース時は必ず version を上げて CHANGELOG に記録すること (運用ルール3)。メンバー側は `/plugin update aidd` で追従する。

## 前提環境と利用側プロジェクトの規約

**実行環境** (hooks が依存):

- OS: macOS / Linux (`usage-log.sh` が `fcntl` を使うため Windows 非対応)
- 必須コマンド: `bash`, `python3`, `git`。`gh` は PR/issue 関連の hooks・commands が対象とする操作で使用

**利用側プロジェクトのディレクトリ規約** (commands / hooks は cwd 相対で以下を前提とする):

| パス | 用途 |
|------|------|
| `docs/design/` | `/aidd:design-doc` の出力先、`/aidd:design-sync` の検査対象 |
| `docs/adr/` | `/aidd:adr` の出力先、adr-recall スキルの参照先 |
| `docs/test-perspectives/` | `/aidd:test-perspectives` の出力先。`commit-reminder.sh` が6時間以内の更新有無を見る |
| `.aidd/design-perspectives.md` | `/aidd:design-review` のプロジェクト固有観点 (任意) |

## インデックス

### Commands (タスク特化プロンプト)

| ファイル | 説明 |
|---------|------|
| `retro.md` | aidd 資産の棚卸し。昇格候補・hooks/skills の摩擦・陳腐化を洗い出す (20セッションごとに hook が想起) |
| `design-doc.md` | 要件から設計書を生成し docs/design/ に保存。構成は design-review の6観点と1対1対応 |
| `adr.md` | アーキテクチャ決定記録を docs/adr/NNNN-<slug>.md に作成。1 ADR = 1 決定 |
| `design-review.md` | 設計や実装方針を多観点レビュー。3× reviewer (sonnet) 並列 → design-arbiter (opus) が裁定。`--verify-sources` で外部情報源検証を追加 |
| `design-sync.md` | 設計書と実装の乖離を検知し、status を最新化する |
| `test-perspectives.md` | 実装対象・変更差分からテスト観点 (正常系・異常系・エッジケース) を洗い出す |
| `doctor.md` | aidd/superpowers の導入状態・バージョン整合・hooks 実行可否を診断する |

### Agents (サブエージェント定義)

| ファイル | 説明 |
|---------|------|
| `design-arbiter.md` | design-review の統合裁定エージェント (opus)。メインのモデルに依らず重い判断を opus に固定 |
| `reviewer.md` | 成果物の検収用エージェント (sonnet)。PR全体のレビューは pr-review-toolkit の担当 |
| `scout.md` | 軽量読み取り調査エージェント (haiku)、ファイル検索・コードベース偵察用 |
| `source-verifier.md` | 設計書の外部検証可能な主張を信頼できる情報源と突き合わせる (sonnet, WebSearch/WebFetch)。design-review の `--verify-sources` 専用 |

### Skills (自動トリガする知見)

| ファイル | 発火条件 |
|---------|------|
| `adr-recall/` | アーキ変更・既存構造変更・設計判断の前 |
| `model-selection/` | サブエージェント起動時・model 指定に迷ったとき |
| `parallel-investigation/` | 未知コードベースの調査・独立した複数の問いがあるとき |

### Hooks (強制力のある運用)

| スクリプト | 動作 |
|---------|------|
| `session-start.sh` | SessionStart で aidd 資産の使いどころを1行注入。superpowers 未導入を検知して警告。20セッションごとに `/aidd:retro` を提案 (状態は `~/.claude/aidd/state.json`) |
| `clarify-nudge.sh` | UserPromptSubmit 毎に「実装を左右する不明点は AskUserQuestion で確認」を注入 |
| `usage-log.sh` | UserPromptSubmit 毎に aidd コマンド使用数・プロンプト履歴を `~/.claude/aidd/usage.json` に記録 (`/aidd:retro` が読む) |
| `commit-reminder.sh` | `git commit` 前に、`docs/test-perspectives/` に6時間以内の更新がなければ注意を注入 (非ブロック) |
| `gh-language-reminder.sh` | `gh pr/issue create・edit` 前に「タイトル・本文は日本語で」を注入 (非ブロック) |
| `pr-sync-reminder.sh` | `git push` 後に「open PR があればタイトル・概要を最新化」を注入 (非ブロック) |

#### Hooks の書き込み先と無効化

hooks は上記スクリプトをセッション中に自動実行する。ファイル書き込みは `~/.claude/aidd/` 配下のみで、外部送信は一切しない:

| 書き込み先 | 内容 | 書き込み元 |
|-----------|------|-----------|
| `~/.claude/aidd/state.json` | セッション通算数 | `session-start.sh` |
| `~/.claude/aidd/usage.json` | `/aidd:*` コマンドの使用数・最終使用時刻と、**全プロンプトの先頭120文字** (最新200件、owner のみ読める権限で保存) | `usage-log.sh` |

プロンプトログは `/aidd:retro` がコマンド昇格候補を検出するためだけに使う。記録したくない場合や毎プロンプトの注入がノイズな場合は、環境変数で個別に無効化できる (シェル環境、または settings.json の `env` で設定):

| 変数 | 効果 |
|------|------|
| `AIDD_DISABLE_USAGE_LOG=1` | `usage-log.sh` のプロンプト記録を止める |
| `AIDD_DISABLE_CLARIFY_NUDGE=1` | `clarify-nudge.sh` の毎プロンプト注入を止める |

### Templates (設定雛形)

| ファイル | 説明 |
|---------|------|
| `CLAUDE.md.template` | プロジェクト概要・技術スタック・コマンド・AI運用をまとめるテンプレート |
| `settings.json.template` | Claude Code 権限設定の基本構成テンプレート |
| `team-settings.json.template` | チーム導入用。利用プロジェクトの `.claude/settings.json` にマージすると aidd が自動提案される |

### Tips (方法論の知見)

| ファイル | 説明 |
|---------|------|
| `superpowers-usage.md` | superpowers スキルとの棲み分け、二重実装の回避 |

## 依存プラグインの互換方針

- **superpowers (必須)**: 連携点は2つ — `session-start.sh` が `~/.claude/plugins/installed_plugins.json` の `superpowers@` エントリで導入有無を検知する (ベストエフォート、非ブロック)、`docs/tips/superpowers-usage.md` が superpowers のスキル名を参照する。superpowers 側の破壊的変更 (スキル改名・削除、インストール記録形式の変更) で連携が壊れても aidd 自体の commands / agents / hooks は動作する。壊れた疑いがあるときは `/aidd:doctor` で診断する
- **pr-review-toolkit (推奨)**: 連携点なし。未導入でも aidd の全機能が動作し、PRレビューの網羅性だけが下がる

## 運用ルール

1. **1ファイル1関心事**: 各ファイルは単一トピックに集中。docs は冒頭に「いつ使うか」を明記
2. **2回ルール**: 同じプロンプトを2回以上使ったものだけ commands/skills に昇格
3. **README更新**: 資産追加時は本インデックスを更新し、plugin.json の version を上げて CHANGELOG に記録
4. **重複禁止**: superpowers・グローバル資産と被る機能は作らず、ポインタのみ記載
5. **受動ドキュメント禁止**: セッション中に効かせたい知見は docs でなく skills (自動トリガ) か hooks (強制) にする

## 設計ドキュメント

詳細な設計・運用ガイドは以下を参照:

- `docs/superpowers/specs/2026-07-08-aidd-knowledge-base-design.md` — 全体設計、ディレクトリ構成、スコープの棲み分け
