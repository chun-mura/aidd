# AIDD Knowledge Base 初期構築 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** AI駆動開発の実行可能資産 (plugin) + 知見 (docs) を持つ個人用ナレッジベースの初期セットを構築する。

**Architecture:** リポジトリ自体を Claude Code プラグイン `aidd` (+ローカル marketplace) とし、`commands/` `agents/` を機械向け資産、`templates/` を雛形素材、`docs/tips|patterns/` を人向け知見とする。spec: `docs/superpowers/specs/2026-07-08-aidd-knowledge-base-design.md`

**Tech Stack:** Claude Code plugin 規約 (plugin.json / marketplace.json)、Markdown。ビルド・テストフレームワークなし。検証は `jq` による JSON validity と `claude plugin` コマンド、目視レビュー。

## Global Constraints

- 言語: ドキュメント本文は日本語、コード・ファイル名・frontmatter は英語
- superpowers と機能が被るものは作らない。被る話題は「superpowers の〇〇を使う」とポインタのみ書く
- docs は必ず冒頭に「いつ使うか」セクションを置く
- 1ファイル1関心事
- プラグイン name は `aidd`
- 各タスク完了時に git commit (メッセージは英語、conventional commits)
- 軽微な執筆タスクは haiku / sonnet モデルのサブエージェントに委譲してよい

---

### Task 1: プラグイン骨格 (manifest + marketplace)

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `.claude-plugin/marketplace.json`
- Create: `.gitignore`

**Interfaces:**
- Produces: プラグイン名 `aidd`。後続タスクは `commands/` `agents/` `skills/` をリポジトリ直下に置けばプラグインに含まれる。

- [ ] **Step 1: plugin.json を作成**

```json
{
  "name": "aidd",
  "version": "0.1.0",
  "description": "Personal AI-driven development knowledge base: task commands, agent recipes, templates, and tips",
  "author": { "name": "Kohki Nakamura" }
}
```

- [ ] **Step 2: marketplace.json を作成**

```json
{
  "name": "aidd-local",
  "owner": { "name": "Kohki Nakamura" },
  "plugins": [
    {
      "name": "aidd",
      "source": ".",
      "description": "Personal AI-driven development knowledge base"
    }
  ]
}
```

- [ ] **Step 3: .gitignore を作成**

```
.claude/settings.local.json
.DS_Store
```

- [ ] **Step 4: JSON validity を検証**

Run: `jq . .claude-plugin/plugin.json && jq . .claude-plugin/marketplace.json`
Expected: 両方ともパース済み JSON が出力される (エラーなし)

- [ ] **Step 5: Commit**

```bash
git add .claude-plugin .gitignore
git commit -m "feat: add plugin manifest and local marketplace"
```

---

### Task 2: commands/ 2本 (設計レビュー・テスト観点出し)

**Files:**
- Create: `commands/design-review.md`
- Create: `commands/test-perspectives.md`

**Interfaces:**
- Consumes: なし (Task 1 の配置規約のみ)
- Produces: slash commands `/aidd:design-review`, `/aidd:test-perspectives`

- [ ] **Step 1: commands/design-review.md を作成**

```markdown
---
description: 設計ドキュメントや実装方針を多観点でレビューする
argument-hint: [設計ファイルのパス or 設計の要約]
---

対象: $ARGUMENTS

以下の観点で設計をレビューし、観点ごとに「問題なし」か「指摘 (深刻度: high/mid/low)」を返してください。

1. **責務分割**: 1コンポーネント1責務になっているか。境界が曖昧な箇所はないか
2. **インターフェース**: 内部を読まずに使い方が分かるか。変更が波及しない構造か
3. **データフロー**: 状態の持ち主が明確か。同じデータの二重管理はないか
4. **エラー処理**: 失敗経路が設計されているか。silent failure の余地はないか
5. **YAGNI**: 今必要ない拡張性・抽象化が入っていないか
6. **運用**: デプロイ・ロールバック・監視の考慮があるか

最後に「最優先で直すべき1点」を明示してください。指摘には必ず具体的な代案を付けること。
```

- [ ] **Step 2: commands/test-perspectives.md を作成**

```markdown
---
description: 実装対象・変更差分からテスト観点を洗い出す
argument-hint: [対象ファイル/機能の説明。省略時は git diff を対象とする]
---

対象: $ARGUMENTS (未指定なら `git diff` と `git diff --staged` の変更内容)

対象コードを読み、テスト観点を以下の分類で洗い出してください。テストコードはまだ書かない。

1. **正常系**: 代表的な入力と期待値
2. **境界値**: 空・0・最大長・境界前後
3. **異常系**: 不正入力、依存先の失敗、タイムアウト
4. **状態遷移**: 順序依存・冪等性・並行実行
5. **回帰**: この変更が壊しうる既存挙動

各観点に「優先度 (must/should/could)」を付け、must だけで最低限の安全網になる構成にしてください。
既存テストでカバー済みの観点は「カバー済み」と明示して除外してください。
```

- [ ] **Step 3: frontmatter 構文を目視確認**

各ファイルの frontmatter が `---` で開閉し、`description` を含むこと。

- [ ] **Step 4: Commit**

```bash
git add commands/
git commit -m "feat: add design-review and test-perspectives commands"
```

---

### Task 3: agents/ 2本 (軽量調査・レビュー)

**Files:**
- Create: `agents/scout.md`
- Create: `agents/reviewer.md`

**Interfaces:**
- Consumes: なし
- Produces: サブエージェント `scout` (haiku)、`reviewer` (sonnet)。`docs/patterns/parallel-investigation.md` (Task 6) が scout を参照する。

- [ ] **Step 1: agents/scout.md を作成**

```markdown
---
name: scout
description: Lightweight read-only investigator. Use for codebase reconnaissance, file inventories, and fact-finding that only needs conclusions, not analysis. Dispatch multiple scouts in parallel for independent questions.
model: haiku
tools: Read, Glob, Grep, Bash
---

You are a fast, read-only scout. Answer exactly the question you were given.

Rules:
- Read-only. Never modify files.
- Return conclusions with `file:line` references, not file dumps.
- If the answer is uncertain, say what you checked and what remains unknown.
- Keep the final report under 30 lines. Bullet points over prose.
```

- [ ] **Step 2: agents/reviewer.md を作成**

```markdown
---
name: reviewer
description: Code and document reviewer for routine quality checks. Use after a task completes to verify the deliverable matches its requirements. For deep architectural review use the design-review command instead.
model: sonnet
tools: Read, Glob, Grep, Bash
---

You review a deliverable against its stated requirements.

Process:
1. Restate the requirements you were given as a checklist.
2. Verify each item against the actual files (read them; do not trust summaries).
3. Report: PASS items in one line each, FAIL items with file:line and a concrete fix.

Rules:
- Read-only. Suggest fixes; never apply them.
- Distinguish "requirement violated" from "improvement idea" — label the latter as optional.
- No praise, no filler. If everything passes, say so in one line.
```

- [ ] **Step 3: frontmatter に name / description / model があることを確認**

- [ ] **Step 4: Commit**

```bash
git add agents/
git commit -m "feat: add scout (haiku) and reviewer (sonnet) subagents"
```

---

### Task 4: templates/ 2本 (CLAUDE.md 雛形・settings.json 雛形)

**Files:**
- Create: `templates/CLAUDE.md.template`
- Create: `templates/settings.json.template`
- Create: `templates/README.md`

**Interfaces:**
- Consumes: なし
- Produces: 新規プロジェクト立ち上げ時にコピーして使う雛形。README (Task 7) がリンクする。

- [ ] **Step 1: templates/CLAUDE.md.template を作成**

```markdown
# CLAUDE.md

## プロジェクト概要
<!-- 何のためのリポジトリか1-2行。ビジネス文脈が非自明なら書く -->

## 技術スタック
<!-- 言語/フレームワーク/主要ライブラリ。バージョン制約があれば明記 -->

## コマンド
<!-- 実際に検証済みのものだけ書く。動かないコマンドは書くだけ有害 -->
- ビルド: `<command>`
- テスト: `<command>`
- lint: `<command>`
- ローカル起動: `<command>`

## アーキテクチャ
<!-- ディレクトリの責務を1行ずつ。コードを読めば分かることは書かない -->

## 規約 (コードから読み取れないものだけ)
<!-- 例: エラーは必ず Result 型で返す / DB migration は手動適用 など -->

## 触ってはいけないもの
<!-- 自動生成ファイル、他チーム管理の領域、既知の地雷 -->
```

- [ ] **Step 2: templates/settings.json.template を作成**

```json
{
  "permissions": {
    "allow": [
      "Bash(git status)",
      "Bash(git diff:*)",
      "Bash(git log:*)",
      "Read(**)"
    ],
    "deny": [
      "Read(./.env)",
      "Read(./.env.*)",
      "Read(./**/credentials*)",
      "Read(./**/*.pem)",
      "Read(./**/*.key)"
    ]
  }
}
```

- [ ] **Step 3: templates/README.md を作成**

```markdown
# templates

新規プロジェクト立ち上げ時にコピーして使う雛形。

いつ使うか: Claude Code を新しいリポジトリで使い始めるとき。

- `CLAUDE.md.template` — プロジェクトの CLAUDE.md の出発点。コメントを埋めて `.template` を外す。「コードから読み取れないことだけ書く」が原則
- `settings.json.template` — `.claude/settings.json` の出発点。read-only git 操作を許可し、機密ファイルを deny する最小構成

使い方: `cp templates/CLAUDE.md.template <project>/CLAUDE.md` して編集。
```

- [ ] **Step 4: settings.json.template の JSON validity を検証**

Run: `jq . templates/settings.json.template`
Expected: パース済み JSON が出力される

- [ ] **Step 5: Commit**

```bash
git add templates/
git commit -m "feat: add CLAUDE.md and settings.json project templates"
```

---

### Task 5: docs/tips/ 3本 (モデル使い分け・コンテキスト管理・superpowers 運用)

**Files:**
- Create: `docs/tips/model-selection.md`
- Create: `docs/tips/context-management.md`
- Create: `docs/tips/superpowers-usage.md`

**Interfaces:**
- Consumes: なし
- Produces: README (Task 7) がリンクする tips 3本。

各ファイルは以下の骨子に沿って日本語で書く。分量は1本 40-80 行。冒頭に「## いつ使うか」必須。

- [ ] **Step 1: docs/tips/model-selection.md を作成**

骨子 (これを全節埋めて執筆する):

```markdown
# モデル使い分け (haiku / sonnet / opus / fable)

## いつ使うか
サブエージェントに model を指定するとき。コスト・速度と品質のトレードオフ判断。

## 原則
- デフォルトはメインループのモデルを継承 (指定しない)
- 出力の正しさを機械的に検証できるタスクほど下位モデルに委譲できる

## 使い分け表
| タスク | モデル | 理由 |
(調査・棚卸し→haiku / 定型執筆・単純実装→sonnet / 設計判断・レビュー→上位、等を具体例つきで)

## アンチパターン
- 設計判断を haiku に委ねる / 全部に opus を使う 等

## このリポジトリでの実例
- agents/scout.md は haiku、agents/reviewer.md は sonnet — 理由を1行ずつ
```

- [ ] **Step 2: docs/tips/context-management.md を作成**

骨子:

```markdown
# コンテキスト管理

## いつ使うか
長いセッションで応答品質が落ちてきたとき。大きなタスクの開始前の設計。

## 原則
- メインコンテキストは「判断」に使い、「収集」はサブエージェントに出す
- ファイル全読みより部分読み。検索はエージェント委譲

## 実践
- 調査を scout に並列で出す / compact 前に重要情報を書き出す /
  1セッション1関心事 / 大きな中間成果物はファイルに落として参照渡し

## 兆候と対処
(同じ質問を繰り返す・指示を忘れる → セッション分割 等)
```

- [ ] **Step 3: docs/tips/superpowers-usage.md を作成**

骨子:

```markdown
# superpowers 運用ガイド (aidd との棲み分け)

## いつ使うか
新しいスキル/コマンドを aidd に追加しようとしたとき (重複チェック)。
superpowers のどのスキルをいつ使うか迷ったとき。

## 棲み分け原則
「どう進めるか (process) = superpowers、何をさせるか (task/domain) = aidd」
判断基準: どの開発フェーズでも同じ動きをするか? → Yes なら作らない

## superpowers 主要スキルの使いどころ
(brainstorming / writing-plans / subagent-driven-development / TDD /
 systematic-debugging / verification-before-completion を各1-2行)

## aidd に追加してよいものの例・悪い例
(良: ADR生成コマンド、DB設計ガイド / 悪: 汎用デバッグ手順、計画の立て方)
```

- [ ] **Step 4: 各ファイルに「## いつ使うか」があることを確認**

Run: `grep -l "## いつ使うか" docs/tips/*.md | wc -l`
Expected: `3`

- [ ] **Step 5: Commit**

```bash
git add docs/tips/
git commit -m "docs: add tips for model selection, context management, superpowers usage"
```

---

### Task 6: docs/patterns/ 1本 (並列調査フォーメーション)

**Files:**
- Create: `docs/patterns/parallel-investigation.md`

**Interfaces:**
- Consumes: `agents/scout.md` (Task 3) — scout の名前と役割を参照する
- Produces: README (Task 7) がリンクするパターン解説1本。

- [ ] **Step 1: docs/patterns/parallel-investigation.md を作成**

骨子 (全節埋めて執筆、40-80行):

```markdown
# 並列調査フォーメーション

## いつ使うか
未知のコードベース把握、影響範囲調査、技術選定の情報収集など
「独立した問いが複数ある」調査。

## 構成
メイン (判断役) + scout ×N (haiku, 収集役)。
問いを独立に分解 → 1問い1scout → 単一メッセージで並列起動 → 結論だけ回収。

## 分解の仕方
(場所で割る / 観点で割る / 仮説で割る — 具体例つき)

## プロンプトの型
scout への依頼文テンプレート (対象パス・問い・出力形式・行数上限)

## 落とし穴
- 問い同士に依存があるのに並列化する
- scout の報告を検証せず設計判断に使う
- 2-3ファイルで済む調査をわざわざ委譲する

## 関連
superpowers:dispatching-parallel-agents (一般論)、agents/scout.md (実体)
```

- [ ] **Step 2: 「## いつ使うか」があることを確認**

Run: `grep -c "## いつ使うか" docs/patterns/parallel-investigation.md`
Expected: `1`

- [ ] **Step 3: Commit**

```bash
git add docs/patterns/
git commit -m "docs: add parallel investigation pattern"
```

---

### Task 7: README (インデックス + 導入手順) と最終検証

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: Task 1-6 の全成果物 (パスと1行説明をインデックス化)

- [ ] **Step 1: README.md を作成**

以下の構成で、Task 1-6 で実際に作られたファイルをすべて列挙する:

```markdown
# aidd — AI-Driven Development Knowledge Base

個人用。AI駆使のための実行可能資産 + 知見。

## 導入 (他プロジェクトから使う)
/plugin marketplace add /Users/nakamurakohki/workspace/private_dev/prototype_aidd
/plugin install aidd@aidd-local

## インデックス
### Commands (実際のファイル一覧 + 1行説明)
### Agents (同上)
### Templates (同上)
### Tips (同上)
### Patterns (同上)

## 運用ルール (specの5項目を要約)
1ファイル1関心事 / 2回ルール / README更新 / superpowers重複禁止 / モデル使い分け

## 設計ドキュメント
docs/superpowers/specs/ へのリンク
```

- [ ] **Step 2: インデックスと実ファイルの一致を検証**

Run: `ls commands/ agents/ templates/ docs/tips/ docs/patterns/`
Expected: README のインデックスに全ファイルが載っている (手動照合)

- [ ] **Step 3: プラグインとして読み込めることを検証**

Run: `claude plugin validate .` (コマンドが存在しない場合は `jq` での manifest 再検証 + ディレクトリ規約の目視で代替)
Expected: エラーなし

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: add README with asset index and install instructions"
```
