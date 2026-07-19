# aidd — AI-Driven Development Knowledge Base

AI駆使のための実行可能資産 + 知見。Claude Code プラグインとして導入可能な、タスク特化コマンド・エージェント・スキル・テンプレート・方法論の集約。

**superpowers プラグイン必須**: aidd は設計・レビュー・運用強制のみを担当し、実装フェーズ (brainstorming・TDD・デバッグ・計画立案) は superpowers に委ねる設計 ([棲み分け原則](docs/tips/superpowers-usage.md))。`plugin.json` の `dependencies` で `superpowers@superpowers-marketplace` を宣言しているため、`/plugin install aidd@aidd` 時に自動導入・有効化される (Claude Code v2.1.110+ が必要)。古いバージョンでは session-start hook が未導入を検知して警告するが、ブロックはしない (検知はベストエフォート)。

**pr-review-toolkit プラグイン推奨**: aidd:reviewer は成果物単体の検収用で、PR全体のレビュー (スタイル・テストカバレッジ・サイレント障害・型設計など多観点) は pr-review-toolkit の担当。導入しなくても aidd の各機能は動くが、PRレビューの網羅性が下がる。

**UI・デザイン特化の資産は [uidd](https://github.com/chun-mura/uidd)**: Storybook 中心の UI 提案・デザインシステム構築ワークフローは uidd が担当する (aidd は汎用タスクのみ。重複資産は作らない)。

**テスト設計手法特化の資産は [stdd](https://github.com/chun-mura/stdd)**: BVA/ECP/デシジョンテーブル/PBT/mutation 等の手法カタログ・選択ガイド・ケース導出は stdd が担当する (aidd は観点洗い出しと手法適用フラグのみ。重複資産は作らない)。

**要件の形式化・曖昧さ検査は [reqd](https://github.com/chun-mura/reqd)**: メモ・Issue・対話結果を構造化された要件定義書に変換し曖昧さを lint する (aidd は設計=HOW。`/reqd:new` の出力パスを `/aidd:design-doc` の引数に渡す)。発散・対話ヒアリングは superpowers (brainstorming) の担当。

**工数見積もりは [estimate](https://github.com/chun-mura/estimate-workload)**: 仕様・Issue・短い作業説明から WBS + 3点見積もり + モンテカルロで P50/P80 を出す (aidd は見積もりしない。`/reqd:new` や設計書のパスを `/estimate:new` に渡す)。

**Issue 起点の自動実行は [aidd-autopilot](https://github.com/chun-mura/aidd-autopilot)**: Issue にラベルを付けると隔離コンテナ内のヘッドレス Claude Code が triage→設計→実装→検証→PR 作成まで進める (マージ判断は人間。aidd / superpowers の資産を実行環境として使う)。

## 導入 (他プロジェクトから使う)

### 個人で使う

```bash
/plugin marketplace add chun-mura/aidd
/plugin install aidd@aidd
# 実装フェーズを担う superpowers は dependencies 宣言により自動導入される

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
| `docs/test-perspectives/` | `/aidd:test-perspectives` の出力先。hook が6時間以内の更新有無を見る |
| `.aidd/design-perspectives.md` | `/aidd:design-review` のプロジェクト固有観点 (任意)。`cp templates/design-perspectives.md.template .aidd/design-perspectives.md` で可観測性・ドメイン固有の観点から始められる |

## インデックス

### Commands (タスク特化プロンプト)

| ファイル | 説明 |
|---------|------|
| `retro.md` | aidd 資産の棚卸し。利用実績・hooks/skills の摩擦・陳腐化を洗い出す |
| `design-doc.md` | 要件から設計書を生成し docs/design/ に保存。構成は design-review の6観点と1対1対応 |
| `adr.md` | アーキテクチャ決定記録を docs/adr/NNNN-<slug>.md に作成。1 ADR = 1 決定 |
| `design-review.md` | 設計や実装方針を多観点レビュー。既定の `--depth=standard` は必要時だけ refuter / arbiter を起動し、反証済み指摘を直接報告する。`--depth=deep` は品質重視の完全経路。`--verify-sources` で外部情報源検証を追加。信頼境界を跨ぐ設計では security-reviewer (STRIDE) を条件起動 (`--security` / `--no-security` で強制・抑止) |
| `issue-split.md` | 設計を独立マージ可能なPR単位 (縦切り・5ファイル以内目安) に分割し、承認後に GitHub issue 化。design-doc が規模超過を検知すると提案 |
| `design-sync.md` | 設計書と実装の乖離を検知し、status を最新化する |
| `test-perspectives.md` | 実装対象・変更差分からテスト観点 (6分類 + 信頼境界に触れる変更のみセキュリティ分類) を洗い出し、BVA/ECP 適用フラグを付ける (手法の導出は stdd の担当) |
| `doctor.md` | aidd/superpowers の導入状態・バージョン整合・hooks 実行可否を診断する |
| `eval.md` | design-review パイプラインの精度測定。`tests/eval/` のゴールデンセット (シード欠陥入り設計書 + 正解キー) にレビューを実行し、検出率・反証誤棄却・デコイ誤検出等を採点して `tests/eval/results/` に記録する (aidd リポジトリ自身で実行) |

### Agents (サブエージェント定義)

| ファイル | 説明 |
|---------|------|
| `design-arbiter.md` | design-review の統合裁定エージェント (opus)。メインのモデルに依らず重い判断を opus に固定 |
| `refuter.md` | レビュー指摘の反証専任エージェント (sonnet)。high/mid 指摘を現物に照らして積極的に反証し、耐えた指摘だけを昇格させる。design-review・review-loop から起動 |
| `reviewer.md` | 成果物の検収用エージェント (sonnet)。PR全体のレビューは pr-review-toolkit の担当 |
| `scout.md` | 軽量読み取り調査エージェント (haiku)、ファイル検索・コードベース偵察用 |
| `security-reviewer.md` | 信頼境界を跨ぐ設計への STRIDE ベース脅威レビュー (sonnet)。design-review が条件起動。攻撃経路を構成できる懸念のみ high/mid で報告 |
| `source-verifier.md` | 設計書の外部検証可能な主張を信頼できる情報源と突き合わせる (sonnet, WebSearch/WebFetch)。design-review の `--verify-sources` 専用 |

### Skills (自動トリガする知見)

| ファイル | 発火条件 |
|---------|------|
| `adr-recall/` | アーキ変更・既存構造変更・設計判断の前 |
| `model-selection/` | サブエージェント起動時・model 指定に迷ったとき |
| `review-loop/` | レビュー→修正のラウンドを反復するとき・指摘が尽きないとき・重要度語彙が混在したとき (終了条件・severity・棄却指摘の持ち越しを規定) |

### Hooks (強制力のある運用)

| スクリプト | 動作 |
|---------|------|
| `session-start.sh` | SessionStart で aidd 資産の使いどころと「実装を左右する不明点は AskUserQuestion で確認」を注入。superpowers 未導入を検知して警告 |
| `usage-log.sh` | UserPromptSubmit 毎に aidd コマンド使用数・最終利用時刻を `~/.claude/aidd/usage.json` に記録 (`/aidd:retro` が読む) |
| `tool-reminder.sh` | `git commit` 前の test-perspectives 確認、`gh pr/issue create・edit` 前の日本語確認、`git push` 後の PR 同期確認を1本で処理 (非ブロック) |

#### Hooks の書き込み先と無効化

hooks は上記スクリプトをセッション中に自動実行する。ファイル書き込みは `~/.claude/aidd/` 配下のみで、外部送信は一切しない:

| 書き込み先 | 内容 | 書き込み元 |
|-----------|------|-----------|
| `~/.claude/aidd/usage.json` | `/aidd:*` コマンドの使用数・最終使用時刻 | `usage-log.sh` |

プロンプトログは `/aidd:retro` がコマンド昇格候補を検出するためだけに使う。記録したくない場合や注入がノイズな場合は、環境変数で個別に無効化できる (シェル環境、または settings.json の `env` で設定):

| 変数 | 効果 |
|------|------|
| `AIDD_DISABLE_USAGE_LOG=1` | `usage-log.sh` の利用統計・プロンプト記録をすべて止める |
| `AIDD_DISABLE_CLARIFY_NUDGE=1` | `session-start.sh` の AskUserQuestion 確認指示の注入を止める |

### Templates (設定雛形)

| ファイル | 説明 |
|---------|------|
| `CLAUDE.md.template` | プロジェクト概要・技術スタック・コマンド・AI運用をまとめるテンプレート |
| `settings.json.template` | Claude Code 権限設定の基本構成テンプレート |
| `team-settings.json.template` | チーム導入用。利用プロジェクトの `.claude/settings.json` にマージすると aidd が自動提案される |
| `design-perspectives.md.template` | `.aidd/design-perspectives.md` の出発点。可観測性・プロジェクト固有観点 (design-review の Agent 4 が読む) |

### Tips (方法論の知見)

| ファイル | 説明 |
|---------|------|
| `superpowers-usage.md` | superpowers スキルとの棲み分け、二重実装の回避 |

## 依存プラグインの互換方針

- **superpowers (必須)**: `plugin.json` の `dependencies` で `superpowers@superpowers-marketplace` を宣言しており、インストール・有効化時に自動解決される (Claude Code v2.1.110+)。古いバージョン向けのフォールバックとして `session-start.sh` が `~/.claude/plugins/installed_plugins.json` の `superpowers@` エントリで導入有無を検知する (ベストエフォート、非ブロック)。`docs/tips/superpowers-usage.md` が superpowers のスキル名を参照するため、superpowers 側の破壊的変更 (スキル改名・削除) で連携が壊れても aidd 自体の commands / agents / hooks は動作する。壊れた疑いがあるときは `/aidd:doctor` で診断する
- **pr-review-toolkit (推奨)**: 連携点なし。未導入でも aidd の全機能が動作し、PRレビューの網羅性だけが下がる

## 運用ルール

1. **1ファイル1関心事**: 各ファイルは単一トピックに集中。docs は冒頭に「いつ使うか」を明記
2. **2回ルール**: 同じプロンプトを2回以上使ったものだけ commands/skills に昇格
3. **README更新**: 資産追加時は本インデックスを更新し、plugin.json の version を上げて CHANGELOG に記録
4. **重複禁止**: superpowers・reqd・estimate・uidd・stdd・aidd-autopilot・グローバル資産と被る機能は作らず、ポインタのみ記載
5. **受動ドキュメント禁止**: セッション中に効かせたい知見は docs でなく skills (自動トリガ) か hooks (強制) にする
6. **パイプライン変更時の評価**: `design-review.md`・`refuter.md`・`design-arbiter.md`・`security-reviewer.md`・`reviewer.md` のプロンプトを変更するリリースは、リリース前に `/aidd:eval` を実行し結果を `tests/eval/results/` に残す (退行の検知はこの記録の比較でのみ可能)

## 設計ドキュメント

詳細な設計・運用ガイドは以下を参照:

- `docs/superpowers/specs/2026-07-08-aidd-knowledge-base-design.md` — 全体設計、ディレクトリ構成、スコープの棲み分け
