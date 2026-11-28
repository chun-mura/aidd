# aidd — AI-Driven Development Knowledge Base

AI駆使のための実行可能資産 + 知見。Claude Code プラグインとして導入可能な、タスク特化の skill・エージェント・hook・テンプレート・方法論の集約。Codex CLI と Cursor agent CLI でも使える。

## 概要

aidd は設計・レビュー・ADR・運用強制 (hook) を担う。実装フェーズ (brainstorming・TDD・デバッグ・計画立案) は持たず superpowers に委ねる ([棲み分け原則](docs/tips/superpowers-usage.md))。`/aidd:issue-implement` も、着手・レーン・レビュー追加・完了の判断の間で superpowers の skill を順に呼ぶ入口である。

- **superpowers (必須)**: `plugin.json` の `dependencies` で宣言しており、`/plugin install aidd@aidd` 時に自動導入・有効化される (Claude Code v2.1.110+)。古いバージョンでは session-start hook が未導入を検知して警告する (ブロックはしない。検知はベストエフォート)
- **pr-review-toolkit (推奨)**: aidd:reviewer は成果物単体の検収用で、PR全体の多観点レビュー (スタイル・テストカバレッジ・サイレント障害・型設計など) は pr-review-toolkit の担当。無くても aidd は動くが、PRレビューの網羅性が下がる

関連ツールとの棲み分け (aidd は重複資産を作らない):

| 領域 | 担当 | aidd との関係 |
|---|---|---|
| UI・デザインシステム (Storybook 中心) | [uidd](https://github.com/chun-mura/uidd) | aidd は汎用タスクのみ |
| テスト設計手法 (BVA/ECP/デシジョンテーブル/PBT/mutation) | [stdd](https://github.com/chun-mura/stdd) | aidd は観点洗い出しと手法適用フラグのみ |
| 要件の形式化・曖昧さ検査 | [reqd](https://github.com/chun-mura/reqd) | `/reqd:new` の出力パスを `/aidd:design-doc` に渡す。発散・対話ヒアリングは superpowers (brainstorming) |
| 工数見積もり (WBS + 3点見積もり + モンテカルロで P50/P80) | [estimate](https://github.com/chun-mura/estimate-workload) | aidd は見積もりしない。要件や設計書のパスを `/estimate:new` に渡す |

## 目次

- [導入 (他プロジェクトから使う)](#導入-他プロジェクトから使う)
- [最初の使い方](#最初の使い方)
- [インデックス](#インデックス) (全資産の正本)
- [詳細ガイド](#詳細ガイド)
- [依存プラグインの互換方針](#依存プラグインの互換方針)
- [運用ルール](#運用ルール)
- [設計ドキュメント](#設計ドキュメント)

## 導入 (他プロジェクトから使う)

### 前提環境

- OS: macOS / Linux (`usage-log.sh` が `fcntl` を使うため Windows 非対応)
- 必須コマンド: `bash`, `python3`, `git`。`gh` は PR/issue 関連の hooks・skills が対象とする操作で使用
- 利用側のディレクトリ規約 (`docs/design/`・`docs/adr/`・`.aidd/` など) は [利用側プロジェクトの設定](docs/guides/project-setup.md#ディレクトリ規約)

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

利用プロジェクトの `.claude/settings.json` に `templates/team-settings.json.template` の内容をマージしてコミットすると、プロジェクトフォルダを trust したメンバーに aidd のインストールが自動で提案される。更新の配信は `plugin.json` の `version` に固定される (version を上げない限り届かない)。リリース時は必ず version を上げて CHANGELOG に記録する (運用ルール3)。メンバー側は `/plugin update aidd` で追従する。

### ローカルで権限を絞って使う (Claude Code)

**`/aidd:issue-implement` などを自動で動かす前に、権限設定を確認する。** エージェントは利用者の権限で Bash と `gh` を実行する。手順・制約・未検証事項は [ローカルで権限を絞って使う](docs/guides/local-permissions.md) にまとめた:

1. sandbox を有効にする (`templates/sandbox-settings.json.template` をマージ)
2. `gh` には対象リポジトリだけの fine-grained PAT を `GH_TOKEN` で渡す (`gh` を `excludedCommands` に入れない)
3. 対象リポジトリの既定ブランチに ruleset をかける (hook と雛形はミスを防ぐ層にとどまる)
4. 完全な隔離が必要なら aidd-autopilot を使う

#### 破壊的な操作をどこで止めるか

GitHub の ruleset・aidd の hook・雛形の `permissions.ask` の分担と、それぞれが止められない書き方は [local-permissions.md の同名の節](docs/guides/local-permissions.md#破壊的な操作をどこで止めるか) に移した。

### Codex CLI (hooks・skills・custom agents)

```bash
codex plugin marketplace add chun-mura/aidd
codex plugin add aidd@aidd
```

導入後に `/hooks` で aidd の hook を信頼する。信頼していない hook は何も表示されずに実行されない。`hooks.json` のエントリが変わるリリースでは、そのエントリを `/hooks` で信頼し直す (スクリプト本体だけの修正では不要)。0.53.0 は Claude Code 用の `^Skill$` エントリに `skill-gate.sh` を足したので、信頼し直しが要る (しないと `usage-log.sh` の記録が止まる。Codex の skill の起動は変わらない)。`/hooks` 画面では aidd 以外の hook の有効・無効を変えないこと (信頼の操作のあとに、無効にしていた別の hook が有効に戻った実測がある)。

利用者が呼ぶ skill は `$aidd:<name>` で起動する ([一覧](#skills-利用者が呼ぶモデルからは自動起動しない))。`commands/` は無い。custom agents はプラグイン導入だけでは届かない (Codex が読むのは `~/.codex/agents/` か今のリポの `.codex/agents/` だけ)。プラグインのディレクトリで次を実行する:

```bash
bash scripts/install-codex-agents.sh            # このマシンの全プロジェクト
bash scripts/install-codex-agents.sh --project  # 今のリポだけ（チーム共有）
```

spawn 名は `aidd-reviewer` / `aidd-refuter` / `aidd-design-arbiter` / `aidd-scout` / `aidd-security-reviewer` / `aidd-source-verifier`。`/aidd:doctor` が未コピーと正本とのずれを見る。

### Cursor agent CLI (hooks と skills)

```bash
cursor-agent --trust --plugin-dir <aidd を clone したパス>
```

利用者が呼ぶ skill は `/<name>` で起動する (名前空間は付かない。[一覧](#skills-利用者が呼ぶモデルからは自動起動しない))。`commands/` は無い。

Claude Code に入れた aidd と、この Cursor 用プラグインは併用しない。併用すると usage.json の二重加算や案内文の重複が起きうる。Cursor は Claude Code に入っているプラグインの skill も読むので、Claude 側だけ入れてある場合は自動 skill は見える。Cursor の編集は `preToolUse` では `tool_name` `Write` として届くので、Write 配線で足りる。専用の Edit matcher は無い。Cursor のモデルは skill を SKILL.md の `Read` で読み込むので、`Read` 配線で `/autonomous-review` のモデル起動を拒否し、手で打つよう案内する (Cursor の `preToolUse` は `ask` を無視するため。手で打った起動は `Read` を通らないので止まらない)。

## 前提環境と利用側プロジェクトの規約

実行環境は [前提環境](#前提環境) に、利用側のディレクトリ規約と知見の台帳 (任意、既定で無効。有効にする前の CI 要件・機密情報の注意を含む) は [利用側プロジェクトの設定](docs/guides/project-setup.md) に移した。

## 最初の使い方

- 設計書をレビューする: `/aidd:design-review docs/design/<設計書>.md` ([design-review](skills/design-review/SKILL.md))
- 変更のテスト観点を洗い出してから実装する: `/aidd:test-perspectives <実装対象のパスか変更の説明>` ([test-perspectives](skills/test-perspectives/SKILL.md))
- issue 1本を着手判断から完了報告まで進める: `/aidd:issue-implement <issue 番号>` ([issue-implement](skills/issue-implement/SKILL.md)。自動で動かす前に [権限設定](docs/guides/local-permissions.md) を確認する)

導入状態がおかしいときは `/aidd:doctor` で診断する。Codex は `$aidd:<name>`、Cursor は `/<name>` で同じように呼ぶ。

## インデックス

### Skills (利用者が呼ぶ。モデルからは自動起動しない)

フラグ・条件分岐・処理の詳細は各 SKILL.md にある。例外として `autonomous-review` は Claude Code ではモデルも起動できるが、起動の前に `skill-gate.sh` が必ずユーザーに許可を求める (Codex は手で起動したときだけ、Cursor はモデルの起動を拒否する)。`test-perspectives`・`design-doc`・`design-review` も、Claude Code と Cursor ではモデルが許可なしで起動できる。`issue-implement` と hook の案内がこの3つを使うよう指示しており、非対話のホストでも動かす必要があるため (#196)。Codex では `allow_implicit_invocation: false` のままなので、依頼の内容からこの3つを選んで起動する対象には入らない。ただし `$aidd:issue-implement` の手順がこの3つを指すと、モデルが SKILL.md を読んで従う (codex-cli 0.163.0 で実測、#205)。

| Skill | 用途 | Claude Code | Codex | Cursor |
|---|---|---|---|---|
| [`design-review/`](skills/design-review/SKILL.md) | 設計や実装方針を多観点レビューする (深さ・差分再レビュー・外部情報源検証・STRIDE のフラグあり) | `/aidd:design-review` | `$aidd:design-review` | `/design-review` |
| [`eval/`](skills/eval/SKILL.md) | design-review パイプラインの精度をゴールデンセットで測り、`impl` で実装レビューの同種・異種を、`compare` で design-review の構成と単体モデルを比べる (aidd リポジトリ自身で実行) | `/aidd:eval` | `$aidd:eval` | `/eval` |
| [`autonomous-review/`](skills/autonomous-review/SKILL.md) | 差分を新しい文脈の独立レビュー・観点別レビュー・品質ゲート・リスク判定で検査し、自動マージ可否だけを判定する (push・PR作成・マージはしない) | `/aidd:autonomous-review` | `$aidd:autonomous-review` | `/autonomous-review` |
| [`issue-split/`](skills/issue-split/SKILL.md) | 設計を独立マージ可能なPR単位に分割し、承認後に GitHub issue 化する | `/aidd:issue-split` | `$aidd:issue-split` | `/issue-split` |
| [`issue-select/`](skills/issue-select/SKILL.md) | open issue から今着手できる分を選び、提案で止める | `/aidd:issue-select` | `$aidd:issue-select` | `/issue-select` |
| [`retro/`](skills/retro/SKILL.md) | aidd 自身の資産を棚卸しし、利用側から還流した issue を集計して選ばれたものを反映する | `/aidd:retro` | `$aidd:retro` | `/retro` |
| [`asset-audit/`](skills/asset-audit/SKILL.md) | 利用側の `.claude/`・`CLAUDE.md`・auto memory を棚卸しし、削除・改訂・修正の候補を出す | `/aidd:asset-audit` | `$aidd:asset-audit` | `/asset-audit` |
| [`incident-retro/`](skills/incident-retro/SKILL.md) | セッションの事故を棚卸しし、再発防止の置き場を決める (知見の台帳・還流は既定で無効) | `/aidd:incident-retro` | `$aidd:incident-retro` | `/incident-retro` |
| [`adr/`](skills/adr/SKILL.md) | アーキテクチャ決定記録を `docs/adr/NNNN-<slug>.md` に作成する (1 ADR = 1 決定) | `/aidd:adr` | `$aidd:adr` | `/adr` |
| [`design-doc/`](skills/design-doc/SKILL.md) | 要件から design-review の6観点に対応した設計書を生成し `docs/design/` に保存する | `/aidd:design-doc` | `$aidd:design-doc` | `/design-doc` |
| [`design-sync/`](skills/design-sync/SKILL.md) | 設計書と実装の乖離を検知し、status を最新化する | `/aidd:design-sync` | `$aidd:design-sync` | `/design-sync` |
| [`doctor/`](skills/doctor/SKILL.md) | aidd/superpowers の導入状態・版の整合・hooks・Codex custom agents・利用側の sandbox 設定を診断する (`--hooks` で hook の動作も確かめる) | `/aidd:doctor` | `$aidd:doctor` | `/doctor` |
| [`infra-audit/`](skills/infra-audit/SKILL.md) | 利用側プロジェクトの静的解析・重複コード検出・多OS CI の導入状況を診断する | `/aidd:infra-audit` | `$aidd:infra-audit` | `/infra-audit` |
| [`issue-implement/`](skills/issue-implement/SKILL.md) | issue 1本を着手ゲートから完了報告まで進める入口 (実装の中身は superpowers と既存資産に委ね、push・PR作成はしない。止まるたびに終了状態を `.aidd/issue-implement/<実行ID>/outcome.json` に残す) | `/aidd:issue-implement` | `$aidd:issue-implement` | `/issue-implement` |
| [`test-perspectives/`](skills/test-perspectives/SKILL.md) | 実装対象・変更差分からテスト観点を洗い出し、BVA/ECP 適用フラグを付ける (手法の導出は stdd) | `/aidd:test-perspectives` | `$aidd:test-perspectives` | `/test-perspectives` |

### Agents (サブエージェント定義)

| ファイル | 説明 |
|---------|------|
| [`design-arbiter.md`](agents/design-arbiter.md) | design-review の統合裁定エージェント (opus 固定) |
| [`refuter.md`](agents/refuter.md) | high/mid 指摘を現物に照らして反証し、耐えた指摘だけを昇格させる (sonnet)。design-review・review-loop から起動 |
| [`reviewer.md`](agents/reviewer.md) | 成果物の検収用エージェント (sonnet)。PR全体のレビューは pr-review-toolkit の担当 |
| [`scout.md`](agents/scout.md) | 軽量読み取り調査エージェント (haiku)、ファイル検索・コードベース偵察用 |
| [`security-reviewer.md`](agents/security-reviewer.md) | 信頼境界を跨ぐ設計 (機微情報をファイル・ログ・キャッシュに保存する設計を含む) への STRIDE ベース脅威レビュー (sonnet)。design-review が条件起動 |
| [`source-verifier.md`](agents/source-verifier.md) | 設計書の外部検証可能な主張を信頼できる情報源と突き合わせる (sonnet, WebSearch/WebFetch)。design-review の `--verify-sources` 専用 |
| [`.codex/agents/aidd-*.toml`](.codex/agents/) | 上の6定義の Codex 用写し。必須キーは `name` / `description` / `developer_instructions` だけ。`scripts/generate-codex-agents.py` が生成し、`scripts/install-codex-agents.sh` が利用側へコピーする |

### Skills (自動トリガする知見)

| ファイル | 発火条件 |
|---------|------|
| [`adr-recall/`](skills/adr-recall/SKILL.md) | アーキ変更・既存構造変更・設計判断の前 |
| [`model-selection/`](skills/model-selection/SKILL.md) | サブエージェント起動時・model 指定に迷ったとき |
| [`four-kinds-check/`](skills/four-kinds-check/SKILL.md) | コミット直前にコメント・テスト名を足したとき・コミット本文を書くとき (コメントの置き場所の規約を採るプロジェクトだけ) |
| [`issue-priority/`](skills/issue-priority/SKILL.md) | 優先度ラベルの付与・見直しを頼まれたとき・優先度ラベルを使うリポジトリで issue を起票するとき |
| [`parallel-coordinator/`](skills/parallel-coordinator/SKILL.md) | 複数の issue・タスクを worker に並行実装させるコーディネーターの立場のとき (superpowers に無い差分のみ) |
| [`review-loop/`](skills/review-loop/SKILL.md) | レビュー→修正のラウンドを反復するとき・指摘が尽きないとき・重要度語彙が混在したとき |

### Hooks (強制力のある運用)

各 hook の判定の詳細・限界は [hooks の運用と調査](docs/guides/hooks-operations.md#各-hook-の動作) にある。

| スクリプト | 動作 |
|---------|------|
| [`session-start.sh`](hooks/scripts/session-start.sh) | SessionStart で資産の使いどころと不明点の確認指示を注入し、棚卸しの期限切れと superpowers 未導入を知らせる |
| [`usage-log.sh`](hooks/scripts/usage-log.sh) | `/aidd:*` の起動回数と最終利用時刻を `~/.claude/aidd/usage.json` に記録する。モデルが Skill ツールで起動した回数は `model_counts` にも分けて記録する (プロンプト本文は記録しない) |
| [`tool-reminder.sh`](hooks/scripts/tool-reminder.sh) | Bash の git / gh を1本で判定し、作業を失う git 操作・指名しないステージ・既定ブランチへの force push と削除・重複検索なしの `gh issue create` などを拒否し、テスト観点・日本語・レビュー証跡・コミット規約などを通知する |
| [`skill-gate.sh`](hooks/scripts/skill-gate.sh) | モデルが `autonomous-review` を起動する前にユーザーの許可を求める (Cursor では SKILL.md の `Read` を拒否する) |
| [`write-guard.sh`](hooks/scripts/write-guard.sh) | 新規ファイルのうち sandbox で読めなくなる名前を拒否し、`.claude/` への新規資産には重なる aidd 資産を案内する (同名は拒否) |
| [`harness-adapter.sh`](hooks/scripts/harness-adapter.sh) | Codex・Cursor の入力を既存スクリプトの形に揃えて呼び、返事を各ハーネスの形に戻す (判定ロジックは持たない) |

#### Hooks の書き込み先と無効化

書き込み先 (`~/.claude/aidd/` 配下のみ、外部送信なし)・状態ファイル・環境変数による無効化は [hooks-operations.md の同名の節](docs/guides/hooks-operations.md#hooks-の書き込み先と無効化) に移した。

### Templates (設定雛形)

| ファイル | 説明 |
|---------|------|
| [`CLAUDE.md.template`](templates/CLAUDE.md.template) | プロジェクト概要・技術スタック・コマンド・AI運用とコメントの置き場所の規約をまとめるテンプレート |
| [`settings.json.template`](templates/settings.json.template) | Claude Code 権限設定の基本構成テンプレート |
| [`sandbox-settings.json.template`](templates/sandbox-settings.json.template) | ローカル実行で権限を絞るときに `.claude/settings.json` にマージする (手順は [ローカルで権限を絞って使う](docs/guides/local-permissions.md)) |
| [`team-settings.json.template`](templates/team-settings.json.template) | チーム導入用。利用プロジェクトの `.claude/settings.json` にマージすると aidd が自動提案される |
| [`design-perspectives.md.template`](templates/design-perspectives.md.template) | `.aidd/design-perspectives.md` の出発点。可観測性・プロジェクト固有観点 (design-review の Agent 4 が読む) |
| [`asset-overlap-prompt-hook.json.template`](templates/asset-overlap-prompt-hook.json.template) | 資産の重複を厳格に止めたい利用側向けの prompt 型 hook (既定では無効)。`scripts/generate-asset-index.py` が生成する |
| [`assurance-claims.md.template`](templates/assurance-claims.md.template) | 明示選択の保証構成で、主張ごとの対象版・前提・証拠・限界・責任者・状態を記録する (規則は [保証条件と責任分担](docs/assurance/contract.md)。コピーしただけでは採用にならない) |
| [`aidd-hook-log.sh`](templates/aidd-hook-log.sh) | 利用側の hook を包み、発火と失敗を `~/.claude/aidd/` 配下に記録するラッパー (`/aidd:asset-audit` が読む) |

雛形ごとの使い方と制約は [templates/README.md](templates/README.md)。

#### `aidd-hook-log.sh` の導入 (利用側プロジェクト)

手順は [hooks-operations.md の同名の節](docs/guides/hooks-operations.md#aidd-hook-logsh-の導入-利用側プロジェクト) に移した。

### Tips (方法論の知見)

| ファイル | 説明 |
|---------|------|
| [`superpowers-usage.md`](docs/tips/superpowers-usage.md) | superpowers スキルとの棲み分け、二重実装の回避 |

## 詳細ガイド

| ガイド | 読む場面 |
|---|---|
| [ローカルで権限を絞って使う](docs/guides/local-permissions.md) | skill を自動で動かす前の sandbox・PAT・ruleset の設定、破壊的な操作の防止と限界 |
| [利用側プロジェクトの設定](docs/guides/project-setup.md) | ディレクトリ規約、知見の台帳 (任意) の有効化・項目・CI・機密情報の扱い |
| [hooks の運用と調査](docs/guides/hooks-operations.md) | 各 hook の判定の詳細、状態ファイル・環境変数・無効化、`aidd-hook-log.sh` の導入 |
| [保証条件と責任分担](docs/assurance/contract.md) | 安全性・成果物の正しさを主張ごとに説明するとき。主張ID (`AC-PROC-*` 手順遵守・`AC-PRIV-*` 権限制限・`AC-SPEC-*` 仕様適合)、状態と期限付き例外、責任分担、明示選択の保証構成の採用条件。通常の利用は対象外 |
| [重要な状態遷移の形式検証](docs/assurance/formal-methods.md) | 状態遷移の不変条件を `AC-SPEC-002` の証拠にするか決めるとき。TLA+ (TLC) の小さな例と反例、実装トレースとの対応の検査、有限範囲の探索の限界、再検証の条件、適用の判断基準 |
| [受け入れ基準と重要性質の検証](docs/assurance/acceptance.md) | `AC-SPEC-001` の証拠を作るとき。原要件から実装と独立に受け入れ基準を作り保護する条件、例・境界・性質・障害の試験の使い分けと限界、承認者を実装者から分ける導入手順。架空アプリの例 (`examples/assurance/acceptance/`) |

## 依存プラグインの互換方針

- **superpowers (必須)**: `plugin.json` の `dependencies` で `superpowers@superpowers-marketplace` を宣言しており、インストール・有効化時に自動解決される (Claude Code v2.1.110+)。古いバージョン向けのフォールバックとして `session-start.sh` が `~/.claude/plugins/installed_plugins.json` の `superpowers@` エントリで導入有無を検知する (ベストエフォート、非ブロック)。`docs/tips/superpowers-usage.md` が superpowers のスキル名を参照するため、superpowers 側の破壊的変更 (スキル改名・削除) で連携が壊れても aidd 自体の commands / agents / hooks は動作する。壊れた疑いがあるときは `/aidd:doctor` で診断する
- **pr-review-toolkit (推奨)**: 連携点は `/aidd:issue-implement` の条件付きレビュー (silent-failure-hunter) だけで、未導入なら `aidd:reviewer` のエラーハンドリング観点で代える。未導入でも aidd の全機能が動作し、PRレビューの網羅性だけが下がる

## 運用ルール

1. **1ファイル1関心事**: 各ファイルは単一トピックに集中。docs は冒頭に「いつ使うか」を明記
2. **2回ルール**: 同じプロンプトを2回以上使ったものだけ commands/skills に昇格
3. **README更新**: 資産追加時は本インデックスを更新し、`.claude-plugin` / `.codex-plugin` / `.cursor-plugin` の `version` を同じ値に上げて CHANGELOG に記録。command・skill・agent・hook の追加・削除・改名、frontmatter の `name`・`description` の変更、`hooks/hooks.json` の配線や hook スクリプトの shebang 直後のコメント行の変更、plugin.json の `commands`・`skills`・`agents`・`hooks` の宣言の変更をしたら `python3 scripts/generate-asset-index.py` で資産一覧を再生成する (CI の `python3 scripts/generate-asset-index.py --check` と `tests/hook-contract-test.sh` が不一致で落ちる)。`agents/*.md` の本文や frontmatter を変えたら `python3 scripts/generate-codex-agents.py` も同じコミットで回す (CI の `--check` が stale で落ちる)
4. **重複禁止**: superpowers・reqd・estimate・uidd・stdd・グローバル資産と被る機能は作らず、ポインタのみ記載
5. **受動ドキュメント禁止**: セッション中に効かせたい知見は docs でなく skills (自動トリガ) か hooks (強制) にする
6. **パイプライン変更時の評価**: `skills/design-review/SKILL.md`・`agents/refuter.md`・`agents/design-arbiter.md`・`agents/security-reviewer.md`・`agents/reviewer.md` のプロンプトを変更するリリースは、リリース前に `/aidd:eval` を実行し結果を `tests/eval/results/` に残す (退行の検知はこの記録の比較でのみ可能)

## 設計ドキュメント

詳細な設計・運用ガイドは以下を参照:

- `docs/superpowers/specs/2026-07-08-aidd-knowledge-base-design.md` — 全体設計、ディレクトリ構成、スコープの棲み分け
