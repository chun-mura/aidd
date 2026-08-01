# infra-audit Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new `/aidd:infra-audit` command that diagnoses a consuming TypeScript/JavaScript project for three mechanical quality gates (ESLint complexity rules, duplicate/unused code detection, multi-OS CI) that the design spec identified as gaps against the "stopped-reviewing-my-code" article's practices.

**Architecture:** A single new prompt file, `commands/infra-audit.md`, following the exact structure of the existing `commands/doctor.md` (frontmatter `description`, numbered checklist, one embedded bash block covering all checks, `OK`/`未導入`/`対象外` output convention). No new agents, skills, or hooks. Read-only — the command never writes to the target project.

**Tech Stack:** Markdown prompt file + POSIX shell (bash) snippets executed via the Bash tool at invocation time. No new runtime dependency in this repo itself.

## Global Constraints

- Diagnostic target: TypeScript/JavaScript projects only (`package.json` present at project root). Absence of `package.json` → all checks skipped, one-line "対象外" output.
- Root-level only — no monorepo `packages/*` traversal (v1 scope, per design spec).
- Read-only: the command must never generate or edit config files, only print advisory text and example snippets.
- Output convention matches `doctor.md`: per-item `OK` / `未導入` / `対象外`, remediation command example (1–2 lines) for anything not `OK`, one-line total summary at the end.
- Output must open with a one-line caveat that detection is heuristic (file existence / grep) and can miss rules enabled via shared/extended ESLint configs.
- Any change to `commands/` requires updating `README.md` index, `CHANGELOG.md`, and bumping `version` in `.claude-plugin/plugin.json` in the same commit (repo operating rule 3).

---

### Task 1: Create `commands/infra-audit.md`

**Files:**
- Create: `commands/infra-audit.md`

**Interfaces:**
- N/A — this is a documentation/prompt asset, not executable code. No functions or types are produced or consumed.

- [ ] **Step 1: Write the command file**

Create `commands/infra-audit.md` with this exact content:

```markdown
---
description: 利用側プロジェクトの静的解析(複雑度制御)・重複コード検出・多OS CI導入状況を診断する
---

利用側プロジェクトの「壊れない仕組み」導入状況を診断してください。各チェックは独立に実行し、1項目の失敗が他の診断を止めないようにする。対象は TypeScript/JavaScript プロジェクトのルート直下のみ (モノレポの `packages/*` は対象外)。

**`aidd:doctor` との違い**: `doctor` は aidd 自身の導入状態を診断する。このコマンドは **利用側プロジェクト** の静的解析・重複検出・CI の導入状況を診断する。

**判定方法の限界**: ファイル存在と grep によるヒューリスティック判定であり、ESLint flat config の `extends` や共有設定経由で実際にはルールが有効なケースを検出できないことがある。判定結果は参考情報として扱うこと。

**チェック項目**:

1. **`package.json` の存在**: 存在しなければ「対象外 (Node.js プロジェクトではない)」として全項目スキップし終了する
2. **静的解析 (ESLint 複雑度制御)**: `.eslintrc*` / `eslint.config.*` の有無、および以下ルールの設定有無
   - `complexity`
   - `max-lines-per-function`
   - `max-depth`
   - `max-params`
   - `@typescript-eslint/no-explicit-any`
   - `sonarjs/cognitive-complexity`
   不足していれば参考値 (関数長60行 / 循環的複雑度20 / ネスト4 / パラメータ6) と導入例を提示する
3. **重複・未使用コード検出**: `package.json` の `devDependencies` に `jscpd` または `knip` があるか、`.github/workflows/*.yml` 内で実行されているか。未導入なら `npm i -D jscpd knip` と CI 設定例を提示する
4. **多OS CI**: `.github/workflows/*.yml` の `runs-on:` の値を収集し、`ubuntu-latest` のみなら折衷案 (PR時: ubuntu + macOS、Windows: daily/main push限定) を提示する

各項目を実行するには Bash tool で以下相当のコマンドを使う:

```bash
# 1. package.json 存在確認
if [ ! -f package.json ]; then
  echo "package.json: 対象外 (Node.js プロジェクトではない、以降スキップ)"
  exit 0
fi
echo "package.json: OK"

# 2. ESLint 複雑度制御ルール
if ls .eslintrc* eslint.config.* > /dev/null 2>&1; then
  echo "eslint config: OK"
  for rule in complexity max-lines-per-function max-depth max-params "@typescript-eslint/no-explicit-any" "sonarjs/cognitive-complexity"; do
    grep -q -- "$rule" .eslintrc* eslint.config.* 2>/dev/null && echo "  $rule: OK" || echo "  $rule: 未導入 (参考値: 関数長60行/循環的複雑度20/ネスト4/パラメータ6)"
  done
else
  echo "eslint config: 未導入 (.eslintrc.json や eslint.config.js の追加を検討)"
fi

# 3. 重複・未使用コード検出
if grep -q '"jscpd"\|"knip"' package.json 2>/dev/null; then
  echo "duplicate/unused detection: OK (devDependencies に jscpd/knip あり)"
else
  echo "duplicate/unused detection: 未導入 (npm i -D jscpd knip を検討)"
fi
if [ -d .github/workflows ] && grep -rl 'jscpd\|knip' .github/workflows/*.yml > /dev/null 2>&1; then
  echo "  CI統合: OK"
else
  echo "  CI統合: 未導入 (jscpd/knip を CI workflow に組み込むことを検討)"
fi

# 4. 多OS CI
if [ -d .github/workflows ]; then
  oses=$(grep -h 'runs-on:' .github/workflows/*.yml 2>/dev/null | sort -u)
  echo "runs-on 一覧:"
  echo "$oses"
  if echo "$oses" | grep -q 'windows-latest\|macos-latest'; then
    echo "多OS CI: OK"
  else
    echo "多OS CI: ubuntu-latest のみ (折衷案: PR時は ubuntu-latest + macOS-latest、Windows は daily/main push限定での実行を検討)"
  fi
else
  echo "多OS CI: 対象外 (.github/workflows なし)"
fi
```

**出力**: 項目ごとに `OK` / `未導入` / `対象外` と、`未導入` には具体的な対処コマンド例を1〜2行付ける。最後に総合サマリ (未導入項目数) を1行で出す。
```

- [ ] **Step 2: Smoke-test the embedded bash snippet against a fake project**

The command has no dedicated contract test (per design spec — it doesn't touch any file the existing `tests/*.sh` scripts assert on). Verify the embedded shell logic is syntactically correct and behaves as intended by running it against three fake fixtures in the scratchpad.

Run:

```bash
SCRATCH=/private/tmp/claude-501/-Users-nakamurakohki-workspace-private-dev-aidd-ecosystem/dd5409a0-1812-4714-b27a-ecb2281eb5e1/scratchpad/infra-audit-fixtures

# Fixture A: no package.json at all
mkdir -p "$SCRATCH/no-node" && cd "$SCRATCH/no-node"

# Fixture B: package.json, no eslint config, no CI
mkdir -p "$SCRATCH/bare-node" && cd "$SCRATCH/bare-node" && echo '{"name":"bare"}' > package.json

# Fixture C: package.json + eslint config with some rules + multi-OS CI
mkdir -p "$SCRATCH/full-node/.github/workflows" && cd "$SCRATCH/full-node"
echo '{"name":"full","devDependencies":{"knip":"^5.0.0"}}' > package.json
echo 'module.exports = { rules: { complexity: ["error", 20], "max-depth": ["error", 4] } };' > eslint.config.js
printf 'jobs:\n  test:\n    runs-on: ubuntu-latest\n' > .github/workflows/ci.yml
printf 'jobs:\n  mac:\n    runs-on: macos-latest\n' > .github/workflows/mac.yml
```

Then extract the bash block from `commands/infra-audit.md` into a temp script and run it in each fixture directory:

```bash
awk '/^```bash$/{flag=1;next}/^```$/{flag=0}flag' commands/infra-audit.md > "$SCRATCH/check.sh"
chmod +x "$SCRATCH/check.sh"

cd "$SCRATCH/no-node" && bash "$SCRATCH/check.sh"
cd "$SCRATCH/bare-node" && bash "$SCRATCH/check.sh"
cd "$SCRATCH/full-node" && bash "$SCRATCH/check.sh"
```

Expected:
- `no-node`: prints only `package.json: 対象外 (Node.js プロジェクトではない、以降スキップ)` and exits 0
- `bare-node`: `package.json: OK`, `eslint config: 未導入 ...`, `duplicate/unused detection: 未導入 ...`, `CI統合: 未導入 ...`, `多OS CI: 対象外 (.github/workflows なし)`
- `full-node`: `package.json: OK`, `eslint config: OK` with `complexity: OK` and `max-depth: OK` but the other 4 rules `未導入`, `duplicate/unused detection: OK`, `CI統合: 未導入` (jscpd/knip not referenced inside the workflow files themselves), `多OS CI: OK` (because `macos-latest` appears in `mac.yml`)

If any fixture's output doesn't match, fix the bash block in `commands/infra-audit.md` and re-run.

- [ ] **Step 3: Clean up fixtures**

```bash
rm -rf "$SCRATCH"
```

- [ ] **Step 4: Commit**

```bash
git add commands/infra-audit.md
git commit -m "feat: add infra-audit command for consumer-project quality-gate diagnostics"
```

---

### Task 2: Wire up README index, CHANGELOG, and version bump

**Files:**
- Modify: `README.md` (Commands index table)
- Modify: `CHANGELOG.md`
- Modify: `.claude-plugin/plugin.json`

**Interfaces:**
- N/A — documentation/metadata only.

- [ ] **Step 1: Add the README index row**

In `README.md`, in the `### Commands (タスク特化プロンプト)` table, add a new row immediately after the `doctor.md` row (both are operational/diagnostic tools, keeping them adjacent):

```markdown
| `doctor.md` | aidd/superpowers の導入状態・バージョン整合・hooks 実行可否を診断する |
| `infra-audit.md` | 利用側プロジェクトの静的解析(複雑度制御)・重複コード検出(jscpd/knip)・多OS CI の導入状況を診断する。doctor が aidd 自身を診断するのに対し、こちらは利用側プロジェクトの品質ガードを対象とする |
| `eval.md` | design-review パイプラインの精度測定。... |
```

(Keep the existing `eval.md` row's description text unchanged — only insert the new `infra-audit.md` row between `doctor.md` and `eval.md`.)

- [ ] **Step 2: Add the CHANGELOG entry**

In `CHANGELOG.md`, insert a new top entry above the existing `## 0.25.2 (2026-08-01)` entry:

```markdown
## 0.25.3 (2026-08-01)

- `infra-audit.md` を追加: 利用側プロジェクトの静的解析(複雑度制御)・重複/未使用コード検出(jscpd/knip)・多OS CI の導入状況を診断する新規コマンド。`doctor` が aidd 自身を診断するのに対し、こちらは利用側プロジェクトの品質ガード導入状況を対象とする (読み取り専用、設定ファイルの生成・編集は行わない)

```

- [ ] **Step 3: Bump the plugin version**

In `.claude-plugin/plugin.json`, change:

```json
  "version": "0.25.2",
```

to:

```json
  "version": "0.25.3",
```

- [ ] **Step 4: Validate the plugin manifest**

Run:

```bash
claude plugin validate . --strict
```

Expected: validation passes (no errors reported for `.claude-plugin/plugin.json` / `.claude-plugin/marketplace.json`).

- [ ] **Step 5: Run the existing contract tests to confirm no regression**

```bash
bash tests/command-contract-test.sh
bash tests/redundancy-contract-test.sh
```

Expected: both exit 0 (they assert against files unrelated to this change, per the design spec, so this confirms nothing was accidentally broken).

- [ ] **Step 6: Commit**

```bash
git add README.md CHANGELOG.md .claude-plugin/plugin.json
git commit -m "chore: register infra-audit command in README/CHANGELOG, bump version to 0.25.3"
```
