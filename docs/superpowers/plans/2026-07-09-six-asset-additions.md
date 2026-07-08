# Six Asset Additions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add six aidd assets (adr-recall skill, retro usage logging, design-sync command, test-perspectives persistence, design-review custom perspectives, doctor command) that turn passive docs into actively-checked resources.

**Architecture:** All additions are plain files (markdown skill/command prompts, bash hook scripts) inside the existing `aidd` plugin tree — no new runtime, no external dependencies. Each task is independently shippable; there is no shared code module between tasks except the plugin metadata files (README/CHANGELOG/plugin.json), updated once at the end.

**Tech Stack:** Bash (hook scripts), Markdown with YAML frontmatter (skills/commands/agents), Python3 (already used by `session-start.sh` for JSON read/write — reuse the same pattern for consistency).

## Global Constraints

- 1ファイル1関心事 (one file, one concern) — from README 運用ルール1.
- Hooks must be non-blocking: never deny a tool call, only inject context or print to stdout, always `exit 0`.
- Any judgment/decision made by a command (design-sync, retro) is presented only — file changes happen only after user approval via AskUserQuestion. Copied verbatim from spec エラー処理 section.
- `usage.json` and `state.json` must remain separate files (spec データフロー: 責務分離のため) — never merge them.
- New commands must have YAML frontmatter with a `description:` (no `## いつ使うか` heading in the body — per README 運用ルール1, commands are prompt bodies, description substitutes for the heading).
- Agents referenced must keep existing model pins: `scout` = haiku, `reviewer` = sonnet, `design-arbiter` = opus. Do not change these.
- State files (`usage.json`, `state.json`) live under `~/.claude/aidd/`, outside the plugin cache, so they survive `/plugin update` (established pattern from `session-start.sh`).

---

### Task 1: adr-recall skill

**Files:**
- Create: `skills/adr-recall/SKILL.md`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: nothing consumed by other tasks (independent skill).

- [ ] **Step 1: Write the skill file**

```markdown
---
name: adr-recall
description: Use when making an architectural decision, changing existing structure, or proposing a design that could contradict a past decision. Checks docs/adr/ for related ADRs before proceeding.
---

# ADR 想起

アーキテクチャ変更・既存構造の変更・設計判断を行う前に、`docs/adr/` にある既存の決定と矛盾しないか確認する。

## 手順

1. `docs/adr/` が存在しなければ何もしない (ADR運用のないプロジェクト)。
2. 存在すれば、今行おうとしている変更のキーワード (コンポーネント名・技術選定・パターン名) で ADR ファイルをgrepし、関連する ADR を洗い出す。
3. 関連 ADR が見つかった場合:
   - 今回の変更が ADR の「決定」と一致するなら、そのまま進める (言及不要)。
   - 矛盾する場合は、進める前にユーザーに提示する: 「`<ADR番号>` は `<決定内容>` としているが、今回の変更はそれと矛盾する。意図的な変更か確認したい」
   - 意図的な覆しと確認できたら、`/aidd:adr` で新しい決定を記録し、旧 ADR を superseded に更新することを提案する。
4. 関連 ADR がなければ、そのまま進める (言及不要)。

## 注意

- ADR の内容を読み違えて誤検知するより、判断に迷う場合はユーザーに確認する側に倒す。
- 矛盾の指摘は提示のみ。ファイル変更はユーザー承認後、`/aidd:adr` に委ねる (このスキル自身は ADR を書かない)。
```

- [ ] **Step 2: Verify frontmatter is valid YAML**

Run: `python3 -c "import yaml, re; content = open('skills/adr-recall/SKILL.md').read(); fm = content.split('---')[1]; yaml.safe_load(fm); print('OK')"`
Expected: `OK` (if `pyyaml` unavailable, instead run `head -5 skills/adr-recall/SKILL.md` and manually confirm the three lines between `---` markers are `name:` and `description:` with no tabs or stray colons)

- [ ] **Step 3: Commit**

```bash
git add skills/adr-recall/SKILL.md
git commit -m "feat: add adr-recall skill to surface conflicting ADRs before design changes"
```

---

### Task 2: retro usage logging

**Files:**
- Create: `hooks/scripts/usage-log.sh`
- Modify: `hooks/hooks.json` (add `usage-log.sh` to the `UserPromptSubmit` hooks array, alongside the existing `clarify-nudge.sh`)
- Modify: `commands/retro.md` (rewrite step 1 to read from `usage.json`)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: `~/.claude/aidd/usage.json` with shape `{"command_counts": {"<command-name>": <int>, ...}, "prompt_log": [{"ts": "<ISO8601>", "text": "<first 120 chars>"}, ...]}` (max 200 entries in `prompt_log`, oldest dropped first). Task 6 (`doctor`) reads this file to validate it's well-formed JSON — must match this exact shape.

- [ ] **Step 1: Write the hook script**

```bash
#!/bin/bash
# UserPromptSubmit hook: log aidd command usage and prompt history for /aidd:retro.
# Non-blocking: always exit 0, never fail the prompt submission.
input=$(cat)

STATE_DIR="$HOME/.claude/aidd"
USAGE_FILE="$STATE_DIR/usage.json"
MAX_LOG=200

mkdir -p "$STATE_DIR" 2>/dev/null

prompt=$(printf '%s' "$input" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get('prompt', ''))
except Exception:
    print('')
" 2>/dev/null)

[ -z "$prompt" ] && exit 0

python3 - "$USAGE_FILE" "$prompt" "$MAX_LOG" <<'PYEOF' 2>/dev/null
import json, re, sys
from datetime import datetime, timezone

usage_file, prompt, max_log = sys.argv[1], sys.argv[2], int(sys.argv[3])

try:
    with open(usage_file) as f:
        data = json.load(f)
except Exception:
    data = {}

data.setdefault("command_counts", {})
data.setdefault("prompt_log", [])

match = re.search(r"/aidd:([a-zA-Z0-9_-]+)", prompt)
if match:
    cmd = match.group(1)
    data["command_counts"][cmd] = data["command_counts"].get(cmd, 0) + 1

data["prompt_log"].append({
    "ts": datetime.now(timezone.utc).isoformat(),
    "text": prompt[:120],
})
data["prompt_log"] = data["prompt_log"][-max_log:]

with open(usage_file, "w") as f:
    json.dump(data, f)
PYEOF

exit 0
```

- [ ] **Step 2: Make it executable and verify it runs**

Run:
```bash
chmod +x hooks/scripts/usage-log.sh
echo '{"prompt": "/aidd:retro please check things"}' | hooks/scripts/usage-log.sh
cat ~/.claude/aidd/usage.json
```
Expected: valid JSON printed, containing `"command_counts": {"retro": 1}` and one entry in `prompt_log` with `"text": "/aidd:retro please check things"`.

- [ ] **Step 3: Verify a second run increments correctly and rotates**

Run:
```bash
echo '{"prompt": "/aidd:retro again"}' | hooks/scripts/usage-log.sh
python3 -c "import json; d = json.load(open('$HOME/.claude/aidd/usage.json')); print(d['command_counts']); print(len(d['prompt_log']))"
```
Expected: `{'retro': 2}` and `2`.

- [ ] **Step 4: Wire into hooks.json**

Read current `hooks/hooks.json`, then modify the `UserPromptSubmit` array to include both hooks:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/scripts/session-start.sh\""
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/scripts/clarify-nudge.sh\""
          },
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/scripts/usage-log.sh\""
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/scripts/commit-reminder.sh\""
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 5: Validate hooks.json is valid JSON**

Run: `python3 -m json.tool hooks/hooks.json > /dev/null && echo OK`
Expected: `OK`

- [ ] **Step 6: Rewrite retro.md step 1 to use usage.json**

Modify `commands/retro.md`, replacing the section under `**1. 昇格候補の発見 (README の2回ルール)**` (lines 7-12 in current file) with:

```markdown
**1. 昇格候補の発見 (README の2回ルール)**

`~/.claude/aidd/usage.json` を読み、`prompt_log` から類似意図のプロンプトが2回以上手で書かれていないか調べる (コマンド化されていない繰り返し依頼が対象。すでに `/aidd:*` として存在するものは `command_counts` で使用頻度を見るだけでよい)。見つかったら:
- 内容を要約し、commands / skills のどちらが適切か (`docs/tips/superpowers-usage.md` の「形態の選び方」節を判断基準に使う)
- 既に superpowers に同等スキルがないか確認 (被りなら見送り)

`command_counts` が長期間0のコマンドがあれば「見直し候補」または「削除候補」として提示する (使われていない資産の陳腐化検出)。
```

- [ ] **Step 7: Commit**

```bash
git add hooks/scripts/usage-log.sh hooks/hooks.json commands/retro.md
git commit -m "feat: log aidd command usage and prompt history for data-driven retro"
```

---

### Task 3: design-sync command

**Files:**
- Create: `commands/design-sync.md`
- Modify: `commands/design-doc.md` (add `status` frontmatter to generated docs)

**Interfaces:**
- Consumes: `docs/design/*.md` files with a `status` frontmatter field (values: `draft` / `implemented` / `superseded`) — this task defines that contract; design-doc.md (modified in this same task) is the producer.
- Produces: nothing consumed by other tasks.

- [ ] **Step 1: Add status frontmatter instruction to design-doc.md**

Modify `commands/design-doc.md`. In the `**保存後**` section (last line of the file), change:

```markdown
**保存後**: パスを報告し、`/aidd:design-review <パス>` の実行を提案する。
```

to:

```markdown
**保存後**: パスを報告し、`/aidd:design-review <パス>` の実行を提案する。

**frontmatter**: 保存する設計書ファイルの先頭に以下を付与する:

```yaml
---
status: draft
---
```

`status` は `draft` (未実装) / `implemented` (実装済み) / `superseded` (後継設計に置き換え) のいずれか。新規作成時は常に `draft`。既存設計書を更新する場合は既存の `status` 値を保持する (design-sync が更新対象)。
```

- [ ] **Step 2: Write design-sync.md**

```markdown
---
description: 設計書と実装の乖離を検知し、status を最新化する
argument-hint: [対象パス。省略時は docs/design/ 全体]
---

対象: $ARGUMENTS (未指定なら `docs/design/` 配下の全 `.md`)

`status: superseded` の設計書は対象から除外する (後継に置き換わった設計は照合不要)。

各設計書について、以下を **単一メッセージで aidd:scout agent に並列 dispatch** してください。各 agent には設計書のパスと「構成と責務」節の内容のみ渡し、以下を調べさせる:

1. 設計書が指すコンポーネント (ファイル・ディレクトリ) が実際に存在するか
2. 存在する場合、設計書に書かれた責務・インターフェースと実装が一致するか (大きな乖離のみ報告。命名の細部は無視)

scout の調査が失敗した設計書 (対象コードが特定できない等) は「調査失敗」として明示し、レポート全体は止めない。

**判定基準**:
- 実装が存在し設計と一致 → `一致` (status を `implemented` に更新する候補)
- 実装が存在するが設計と乖離 → `乖離` (乖離の内容を具体的に記載)
- 実装が存在しない → `未着手` (status は `draft` のまま)

**出力**: 設計書ごとに「一致 / 乖離 / 未着手 / 調査失敗」のレポートを提示する。判断は提示のみ — status の書き換え・設計書本文の修正は、AskUserQuestion でユーザーに1件ずつ確認してから行う。承認された更新のみ frontmatter の `status` フィールドを書き換える (本文には手を入れない)。
```

- [ ] **Step 3: Verify frontmatter of design-sync.md is valid**

Run: `head -4 commands/design-sync.md`
Expected: three lines between `---` markers, first `description:`, second `argument-hint:`, no tabs.

- [ ] **Step 4: Commit**

```bash
git add commands/design-sync.md commands/design-doc.md
git commit -m "feat: add design-sync command and status frontmatter to design docs"
```

---

### Task 4: test-perspectives persistence

**Files:**
- Modify: `commands/test-perspectives.md` (add save-to-file step)
- Modify: `hooks/scripts/commit-reminder.sh` (check freshness before injecting reminder)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: `docs/test-perspectives/YYYY-MM-DD-<slug>.md` files — `commit-reminder.sh` (this same task) is the consumer of their mtime.

- [ ] **Step 1: Add persistence instruction to test-perspectives.md**

Modify `commands/test-perspectives.md`. Append after the last line (`これから実装する場合は、must 観点を superpowers:test-driven-development の最初のテストケース候補としてそのまま使ってください。`):

```markdown

**保存**: 出力を `docs/test-perspectives/YYYY-MM-DD-<slug>.md` に保存する (日付は `date +%F`、slug は対象の英語ケバブケース要約)。ディレクトリがなければ作成する。保存後、パスを報告する。
```

- [ ] **Step 2: Rewrite commit-reminder.sh to check freshness**

Read current `hooks/scripts/commit-reminder.sh`, then replace its entire content with:

```bash
#!/bin/bash
# PreToolUse hook (Bash matcher): inject a reminder when a git commit is about to run,
# unless test-perspectives output was saved recently (within the last 6 hours).
# Non-blocking: never denies the tool call, only adds context.
input=$(cat)

if printf '%s' "$input" | grep -qE 'git[[:space:]]+commit'; then
  recent_perspectives=$(find docs/test-perspectives -name '*.md' -mmin -360 2>/dev/null | head -1)
  if [ -z "$recent_perspectives" ]; then
    cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"aidd: if /aidd:test-perspectives has not been run for this change, run it before committing (skip for docs-only or trivial changes)."}}
EOF
  fi
fi
exit 0
```

- [ ] **Step 3: Verify the reminder still fires when no test-perspectives file exists**

Run:
```bash
cd /tmp && mkdir -p reminder-test && cd reminder-test
echo '{"tool_input": {"command": "git commit -m test"}}' | bash /Users/nakamurakohki/workspace/private_dev/aidd/hooks/scripts/commit-reminder.sh
```
Expected: JSON output with `additionalContext` containing "test-perspectives" (no `docs/test-perspectives` dir exists in `/tmp/reminder-test`).

- [ ] **Step 4: Verify the reminder is suppressed when a fresh file exists**

Run:
```bash
mkdir -p docs/test-perspectives && touch docs/test-perspectives/2026-07-09-example.md
echo '{"tool_input": {"command": "git commit -m test"}}' | bash /Users/nakamurakohki/workspace/private_dev/aidd/hooks/scripts/commit-reminder.sh
cd / && rm -rf /tmp/reminder-test
```
Expected: no output (empty stdout) before `exit 0`.

- [ ] **Step 5: Commit**

```bash
cd /Users/nakamurakohki/workspace/private_dev/aidd
git add commands/test-perspectives.md hooks/scripts/commit-reminder.sh
git commit -m "feat: persist test-perspectives output and skip reminder when fresh"
```

---

### Task 5: design-review custom perspectives

**Files:**
- Modify: `commands/design-review.md`

**Interfaces:**
- Consumes: optional `.aidd/design-perspectives.md` in the target project (plain markdown list of perspectives, no schema enforced beyond "a list of things to check").
- Produces: nothing consumed by other tasks.

- [ ] **Step 1: Add custom perspectives dispatch to design-review.md**

Modify `commands/design-review.md`. Replace the line:

```markdown
以下の3グループを **単一メッセージで aidd:reviewer agent に並列 dispatch** し、メインコンテキストで統合してください。各 agent には対象 (ファイルパス or 要約) と担当観点のみ渡すこと。対象が小さい (1ファイル・100行未満の要約) 場合のみ、dispatch せずメインで直接レビューしてよい。
```

with:

```markdown
以下の3グループを **単一メッセージで aidd:reviewer agent に並列 dispatch** し、メインコンテキストで統合してください。各 agent には対象 (ファイルパス or 要約) と担当観点のみ渡すこと。対象が小さい (1ファイル・100行未満の要約) 場合のみ、dispatch せずメインで直接レビューしてよい。

対象プロジェクトに `.aidd/design-perspectives.md` が存在する場合、その内容を担当観点として渡す **Agent 4 — プロジェクト固有観点** を同じメッセージで並列 dispatch に追加する (標準6観点は常に維持し、置き換えない)。ファイルがなければ Agent 4 は起動しない。
```

And after the `**Agent 3 — 実用性:**` block, before the `各 agent への指示:` line, add:

```markdown
**Agent 4 — プロジェクト固有 (存在する場合のみ):**
`.aidd/design-perspectives.md` の内容をそのまま観点として使う。
```

- [ ] **Step 2: Verify the file still has valid frontmatter and renders as expected**

Run: `head -4 commands/design-review.md`
Expected: unchanged frontmatter (`description:`, `argument-hint:`), no corruption from the edit.

- [ ] **Step 3: Commit**

```bash
git add commands/design-review.md
git commit -m "feat: support project-specific design-review perspectives via .aidd/design-perspectives.md"
```

---

### Task 6: doctor command

**Files:**
- Create: `commands/doctor.md`

**Interfaces:**
- Consumes: `~/.claude/aidd/usage.json` shape defined in Task 2 (validates it parses, does not require it to exist).
- Produces: nothing consumed by other tasks.

- [ ] **Step 1: Write doctor.md**

```markdown
---
description: aidd/superpowers の導入状態・バージョン整合・hooks 実行可否を診断する
---

aidd プラグインの動作環境を診断してください。各チェックは独立に実行し、1項目の失敗が他の診断を止めないようにする。

**チェック項目**:

1. **superpowers 導入**: `~/.claude/plugins/installed_plugins.json` に `superpowers@` を含むエントリがあるか
2. **バージョン整合**: `.claude-plugin/plugin.json` の `version` と、`~/.claude/plugins/installed_plugins.json` に記録された aidd のインストール済みバージョンを比較する。ズレていれば `push + /plugin update aidd` 忘れの可能性を指摘する
3. **hooks 実行権限**: `hooks/scripts/*.sh` それぞれに実行ビット (`x`) が付いているか (`ls -l` で確認)
4. **python3 存在**: `which python3` — hooks が python3 に依存しているため必須
5. **状態ファイルの妥当性**: `~/.claude/aidd/state.json` と `~/.claude/aidd/usage.json` が存在する場合、それぞれ有効な JSON としてパースできるか (存在しない場合はスキップ、エラーではない)

各項目を実行するには Bash tool で以下相当のコマンドを使う:

```bash
grep -q '"superpowers@' ~/.claude/plugins/installed_plugins.json 2>/dev/null && echo "superpowers: OK" || echo "superpowers: WARN not detected"
python3 -c "import json; d=json.load(open('$HOME/.claude/plugins/installed_plugins.json')); print([v.get('version') for k,v in d.items() if k.startswith('aidd@')])" 2>/dev/null
cat .claude-plugin/plugin.json | python3 -c "import json,sys; print(json.load(sys.stdin)['version'])"
ls -l hooks/scripts/*.sh
which python3 && echo "python3: OK" || echo "python3: WARN not found"
python3 -m json.tool ~/.claude/aidd/state.json > /dev/null 2>&1 && echo "state.json: OK" || echo "state.json: missing or invalid"
python3 -m json.tool ~/.claude/aidd/usage.json > /dev/null 2>&1 && echo "usage.json: OK" || echo "usage.json: missing or invalid"
```

**出力**: 項目ごとに `OK` / `WARN` / `FAIL` と、`WARN`・`FAIL` には具体的な対処手順を1行で付ける。最後に総合サマリ (問題数) を1行で出す。
```

- [ ] **Step 2: Verify frontmatter is valid**

Run: `head -3 commands/doctor.md`
Expected: `---`, `description: ...`, `---`.

- [ ] **Step 3: Manually dry-run the diagnostic commands**

Run:
```bash
grep -q '"superpowers@' ~/.claude/plugins/installed_plugins.json 2>/dev/null && echo "superpowers: OK" || echo "superpowers: WARN not detected"
which python3 && echo "python3: OK" || echo "python3: WARN not found"
```
Expected: both lines print without error (values depend on local environment — confirm no shell syntax errors, not specific OK/WARN outcomes).

- [ ] **Step 4: Commit**

```bash
git add commands/doctor.md
git commit -m "feat: add doctor command to diagnose aidd install and version drift"
```

---

### Task 7: Update README, CHANGELOG, plugin.json

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `.claude-plugin/plugin.json`

**Interfaces:**
- Consumes: nothing (documentation-only task, run last after Tasks 1-6 are committed).
- Produces: nothing.

- [ ] **Step 1: Bump plugin.json version**

Modify `.claude-plugin/plugin.json`, change:

```json
  "version": "0.7.0",
```

to:

```json
  "version": "0.8.0",
```

- [ ] **Step 2: Add CHANGELOG entry**

Modify `CHANGELOG.md`, insert after the `# Changelog` line and before `## 0.7.0 (2026-07-08)`:

```markdown
## 0.8.0 (2026-07-09)

- Add `skills/adr-recall/`: surface conflicting ADRs before architectural changes
- Add `hooks/scripts/usage-log.sh`: log aidd command usage and prompt history to `~/.claude/aidd/usage.json` for data-driven `/aidd:retro`
- Add `commands/design-sync.md`: detect drift between `docs/design/` and implementation; `design-doc.md` now writes a `status` frontmatter field
- `test-perspectives.md` now persists output to `docs/test-perspectives/`; `commit-reminder.sh` skips the reminder when a fresh file exists
- `design-review.md` supports project-specific perspectives via `.aidd/design-perspectives.md` (Agent 4, additive only)
- Add `commands/doctor.md`: diagnose aidd/superpowers install state, version drift, and hook prerequisites

```

- [ ] **Step 3: Update README index tables**

Modify `README.md`. In the Commands table (after the `test-perspectives.md` row), add:

```markdown
| `design-sync.md` | 設計書と実装の乖離を検知し、status を最新化 |
| `doctor.md` | aidd/superpowers の導入状態・バージョン整合・hooks 実行可否を診断 |
```

In the Skills table (after the `parallel-investigation/` row), add:

```markdown
| `adr-recall/` | アーキ変更・既存構造変更・設計判断の前 |
```

In the Hooks table, replace the `session-start.sh` row description to mention usage.json, and add a note for usage-log.sh. Change:

```markdown
| `session-start.sh` | SessionStart で aidd 資産の使いどころを1行注入。superpowers 未導入を検知して警告。20セッションごとに `/aidd:retro` を提案 (状態は `~/.claude/aidd/state.json`) |
| `clarify-nudge.sh` | UserPromptSubmit 毎に「実装を左右する不明点は AskUserQuestion で確認」を注入 |
| `commit-reminder.sh` | `git commit` 前に test-perspectives 未実施の注意を注入 (非ブロック) |
```

to:

```markdown
| `session-start.sh` | SessionStart で aidd 資産の使いどころを1行注入。superpowers 未導入を検知して警告。20セッションごとに `/aidd:retro` を提案 (状態は `~/.claude/aidd/state.json`) |
| `clarify-nudge.sh` | UserPromptSubmit 毎に「実装を左右する不明点は AskUserQuestion で確認」を注入 |
| `usage-log.sh` | UserPromptSubmit 毎に aidd コマンド使用数・プロンプト履歴を `~/.claude/aidd/usage.json` に記録 (`/aidd:retro` が読む) |
| `commit-reminder.sh` | `git commit` 前に、`docs/test-perspectives/` に6時間以内の更新がなければ注意を注入 (非ブロック) |
```

- [ ] **Step 4: Verify all three files are syntactically valid**

Run:
```bash
python3 -m json.tool .claude-plugin/plugin.json > /dev/null && echo "plugin.json: OK"
head -5 CHANGELOG.md
grep -c '| `' README.md
```
Expected: `plugin.json: OK`; CHANGELOG shows the new `## 0.8.0` entry at top; README table row count increased by 3 versus before this task.

- [ ] **Step 5: Commit**

```bash
git add README.md CHANGELOG.md .claude-plugin/plugin.json
git commit -m "docs: update README/CHANGELOG/plugin.json for v0.8.0 asset additions"
```
