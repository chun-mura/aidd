# aidd Token Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve aidd review quality while reducing routine prompt, agent, and hook overhead.

**Architecture:** Add an explicit design-review depth contract and move detailed reviewer requirements into agent definitions. Replace three Bash-event hook scripts with one event-aware dispatcher, and make free-form prompt logging opt-in while preserving command telemetry.

**Tech Stack:** Markdown command and agent definitions, Bash, Python 3, shellcheck.

## Global Constraints

- `--depth=standard` is the default; `--depth=deep` preserves the full review path.
- Security and source-verification flags keep their existing meaning.
- Prompt history is written only when `AIDD_PROMPT_LOG=1`.
- All hook scripts remain non-blocking and exit 0.

---

### Task 1: Add review-depth and compact-output contracts

**Files:**
- Modify: `commands/design-review.md`
- Modify: `agents/reviewer.md`
- Modify: `agents/refuter.md`
- Test: `tests/command-contract-test.sh`

- [ ] **Step 1: Write failing contract tests**

Assert `design-review.md` documents both depth modes, compact clean output, conditional refuter/arbiter dispatch, and that reviewer/refuter own their detailed contracts.

- [ ] **Step 2: Run the test and verify it fails**

Run: `bash tests/command-contract-test.sh`
Expected: FAIL because depth and compact-output contracts are absent.

- [ ] **Step 3: Implement the minimum prompt changes**

Add `--depth=standard|deep`; set standard dispatch conditions; move detailed severity and read-completion instructions to `agents/reviewer.md`; require refuter input to contain only findings and relevant paths.

- [ ] **Step 4: Run the contract test**

Run: `bash tests/command-contract-test.sh`
Expected: PASS.

### Task 2: Consolidate event hooks and make prompt history opt-in

**Files:**
- Modify: `hooks/hooks.json`
- Create: `hooks/scripts/tool-reminder.sh`
- Delete: `hooks/scripts/commit-reminder.sh`
- Delete: `hooks/scripts/gh-language-reminder.sh`
- Delete: `hooks/scripts/pr-sync-reminder.sh`
- Modify: `hooks/scripts/usage-log.sh`
- Modify: `hooks/scripts/session-start.sh`
- Modify: `commands/retro.md`
- Modify: `README.md`
- Test: `tests/hook-contract-test.sh`, `tests/session-start-test.sh`

- [ ] **Step 1: Write failing hook tests**

Exercise tool-reminder for unrelated commands, `git commit`, GitHub create/edit, and `git push`; assert command telemetry is retained while free-form prompt logging is disabled by default and enabled with `AIDD_PROMPT_LOG=1`.

- [ ] **Step 2: Run the tests and verify failure**

Run: `bash tests/hook-contract-test.sh && bash tests/session-start-test.sh`
Expected: FAIL because the unified dispatcher and opt-in prompt-log behavior do not exist.

- [ ] **Step 3: Implement minimal hook changes**

Create one event-aware dispatcher, map it to the existing hook events, preserve reminders, gate `prompt_log` behind `AIDD_PROMPT_LOG=1`, shorten SessionStart output, and make retro tolerate absent prompt history.

- [ ] **Step 4: Run the hook tests**

Run: `bash tests/hook-contract-test.sh && bash tests/session-start-test.sh`
Expected: PASS.

### Task 3: Validate plugin and document the change

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `.claude-plugin/plugin.json`
- Test: `tests/command-contract-test.sh`, `tests/hook-contract-test.sh`, `tests/session-start-test.sh`

- [ ] **Step 1: Update user-facing behavior and version**

Document review depth, prompt-log opt-in, and consolidated hooks; increment the plugin patch version and add a changelog entry.

- [ ] **Step 2: Run validation**

Run: `bash tests/command-contract-test.sh && bash tests/hook-contract-test.sh && bash tests/session-start-test.sh && shellcheck hooks/scripts/*.sh && claude plugin validate . --strict`
Expected: all checks PASS.

- [ ] **Step 3: Run the full eval suite**

Run: `/aidd:eval structure data-error security`
Expected: compare evaluation metrics with the recorded baseline and report any non-deterministic variation.

