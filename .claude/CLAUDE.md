# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

`aidd` is a Claude Code **plugin** (not an app): a knowledge base of task-specific slash commands, subagent
definitions, skills, hooks, and templates for AI-driven development (design review, ADR, test perspectives,
etc.). There is no build step and no application runtime — the "product" is the Markdown/JSON/shell assets
themselves, consumed by another Claude Code session that installs this plugin. `README.md` is the canonical
index of every asset; when you add or remove a command/agent/skill/hook, update that index, bump `version` in
`.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, and `.cursor-plugin/plugin.json` to the same value,
and add a `CHANGELOG.md` entry (operating rule 3, see README "運用ルール").

## Commands (verified against `.github/workflows/validate.yml`)

CI (`validate` job) runs exactly five steps, in order:

```bash
shellcheck hooks/scripts/*.sh templates/*.sh scripts/install-codex-agents.sh
python3 scripts/generate-asset-index.py --check # fail if hooks/asset-index.json / the prompt-hook template are stale
python3 scripts/generate-codex-agents.py --check
npm install -g @anthropic-ai/claude-code       # install the claude CLI
claude plugin validate . --strict              # validates .claude-plugin/marketplace.json + plugin.json
```

`scripts/generate-asset-index.py` builds `hooks/asset-index.json` (read by `write-guard.sh`) and
`templates/asset-overlap-prompt-hook.json.template` from: command/skill/agent files and their frontmatter `name`/
`description`, the event names each hook script is wired to in `hooks.json`, each hook script's first comment line
after the shebang, and the `commands`/`skills`/`agents`/`hooks` declarations in `plugin.json`. Changing any of these
— including just editing an existing command's `description` — requires `python3 scripts/generate-asset-index.py`
in the same commit, or CI fails.

There is no `package.json`/Makefile/test runner. The contract tests are plain bash scripts run directly:

```bash
bash tests/autonomous-review-contract-test.sh  # grep-asserts required phrases in skills/autonomous-review/SKILL.md
bash tests/command-contract-test.sh      # grep-asserts exact phrases exist in skills/design-review/SKILL.md, agents/reviewer.md, agents/refuter.md, skills/eval/SKILL.md, skills/review-loop/SKILL.md, commands/adr.md, skills/incident-retro/SKILL.md, skills/asset-audit/SKILL.md
bash tests/hook-contract-test.sh         # feeds fake hook-event JSON into hooks/scripts/*.sh via stdin, asserts output; also runs generate-asset-index.py --check
bash tests/hook-log-test.sh              # exercises templates/aidd-hook-log.sh (pass-through, signals, per-hook markers)
bash tests/redundancy-contract-test.sh   # asserts removed assets stay removed and de-duplication boundaries hold
bash tests/session-start-test.sh         # asserts session-start.sh injects the short nudges only when due
bash tests/codex-agents-contract-test.sh # Codex TOML stays generated from agents/*.md; installer copies and --check detects stale/missing
```

On macOS inside the Claude Code sandbox, `mktemp -d` may ignore `$TMPDIR` and fail under `/var/folders`; run the
tests outside the sandbox (or with a writable temp dir) rather than treating that as a test failure.

These are **not** a general-purpose test framework — some grep for literal strings that must appear in specific
prompt files; `hook-contract`, `hook-log` and `session-start` execute the scripts. If you edit
`skills/design-review/SKILL.md`, `agents/reviewer.md`, `agents/refuter.md`, `skills/eval/SKILL.md`, `commands/adr.md`,
`skills/incident-retro/SKILL.md`, `skills/autonomous-review/SKILL.md`, `skills/asset-audit/SKILL.md` (also executed by
`hook-log-test.sh`), `skills/review-loop/SKILL.md`, `templates/design-perspectives.md.template`,
`templates/CLAUDE.md.template`, `templates/aidd-hook-log.sh`, `hooks/hooks.json`, `hooks/scripts/*.sh`,
`scripts/generate-asset-index.py`, `scripts/generate-codex-agents.py`, `scripts/install-codex-agents.sh`,
`.codex/agents/*.toml`, or any command/skill/agent frontmatter, run the matching test script — a wording
change can silently break the contract. There is no CI job that runs these `tests/*.sh` scripts automatically; run
them locally before committing. After editing `agents/*.md`, run `python3 scripts/generate-codex-agents.py`.

`claude plugin validate . --strict` requires the `claude` CLI on PATH (`npm install -g @anthropic-ai/claude-code`
if missing) and validates both `.claude-plugin/marketplace.json` and `.claude-plugin/plugin.json`.

## Multi-harness: moving commands to skills

`design-review`, `eval`, `autonomous-review`, `issue-split`, `issue-select`, `retro`,
`asset-audit`, and `incident-retro` already live in `skills/<name>/SKILL.md`.
Remaining task commands still live in `commands/*.md`. Claude Code invokes both as `/aidd:<name>`.
Codex does not ship plugin commands; Cursor recommends skills. Follow reqd / stdd / uidd
(`origin/main`): move each remaining command to `skills/<name>/SKILL.md`, delete the
`commands/` file (no stub), and keep `/aidd:<name>` via the skill's `name:` frontmatter.

When moving a command:

- Frontmatter: keep `description` (and `argument-hint` / `disable-model-invocation` if present),
  add `name: <name>`, set `disable-model-invocation: true`.
- Add `skills/<name>/agents/openai.yaml` with `policy.allow_implicit_invocation: false`
  (Codex would otherwise auto-start a user-invoked task).
- Do not add a `skills` key to `.claude-plugin/plugin.json`. `.codex-plugin` and
  `.cursor-plugin` already declare `"skills": "./skills/"`.
- Prepend this block (uidd wording) after the frontmatter, before the existing body:

```
**パスと引数と質問の扱い**: この文書の相対パスは、この SKILL.md があるディレクトリを起点にする。`$ARGUMENTS` が文字のまま残っている場合（Codex・Cursor など）は、この skill を呼び出したメッセージのうち skill 名以外の部分を `$ARGUMENTS` とみなす。`AskUserQuestion` と書かれた箇所は、ユーザーに質問するツールがあればそれを使い、無ければ質問を書いて作業を止め、回答を待つ。回答が無いまま推測で進めない。
```

- Leave the word `AskUserQuestion` in the body. Do not rewrite each occurrence.
- Do not change hook scripts, hook write destinations (`~/.claude/aidd/`), or Cursor Edit
  write-guard. Existing auto-trigger skills (`adr-recall` and the others) keep auto-start;
  do not add `disable-model-invocation` or `openai.yaml` to them.
- Update contract tests that grep `commands/<name>.md` to the new `SKILL.md` path, and run
  `python3 scripts/generate-asset-index.py` in the same commit.

## Architecture: how the asset types relate

- **Commands** (`commands/*.md`) are user-invoked entry points still waiting to move. Claude Code
  invokes them as `/aidd:<name>`. Most don't do the work themselves — they orchestrate **agents**
  (`agents/*.md`) via parallel `Task`/dispatch, one message per wave, passing only the target +
  assigned perspective (never the full agent/command definition text, to keep dispatch payloads small).
- **User-invoked skills** (`skills/design-review/`, `skills/eval/`, `skills/autonomous-review/`, `skills/issue-split/`, `skills/issue-select/`, `skills/retro/`, `skills/asset-audit/`, `skills/incident-retro/`) are the same kind of entry point,
  already moved so Codex (`$aidd:<name>`) and Cursor (`/<name>`) can run them. They carry
  `disable-model-invocation: true` and Codex `allow_implicit_invocation: false`.
- **Auto-trigger skills** (`skills/adr-recall/` and the others) fire based on their `description`
  frontmatter matching the situation. They hold *reusable* judgment logic that would otherwise be
  duplicated across commands.
- **Hooks** (`hooks/hooks.json` + `hooks/scripts/*.sh`) are the only assets with actual enforcement power —
  everything else is advisory text a model can ignore. `hooks.json` wires 8 entries across 5 events to 5 scripts
  (the 8th is Codex `apply_patch` → `harness-adapter.sh` → `write-guard.sh`; Cursor uses `hooks/hooks-cursor.json`):
  - `session-start.sh` (SessionStart): injects a one-time short nudge, an `/aidd:asset-audit` nudge only when the
    consumer's audit is overdue, and detects missing `superpowers` plugin
  - `usage-log.sh` (UserPromptSubmit + PreToolUse `^Skill$`): counts `/aidd:*` usage into `~/.claude/aidd/usage.json`
    (read by `/aidd:retro`); never logs prompt text
  - `tool-reminder.sh` (PreToolUse + PostToolUse + PostToolUseFailure, matcher `Bash`): the single Bash dispatcher.
    It splits the command (quotes, `&&`/`;`, comments, control keywords, `cd`, `git -C`, wrappers), collects every
    matching check, and emits one JSON: the original nudges (test-perspectives, Japanese PR/issue text, post-push
    PR sync), review-evidence warning before `gh pr create`, denial of work-losing git operations and unnamed
    staging, main-tree sharing warning, search-before-`gh issue create` gate, optional required-label gate, and the
    post-commit subject/Why check (only in repos that adopt the convention). Commands without a `git`/`gh` word exit
    before python starts. Don't split it back out without checking `docs/superpowers/specs/2026-07-18-token-optimization-design.md`
  - `write-guard.sh` (PreToolUse, matcher `Write|Edit|NotebookEdit`): acts only on files that don't exist yet —
    denies names the sandbox usually can't read back, and points new consumer `.claude/{hooks,skills,commands,rules,agents}`
    assets at the aidd assets they duplicate (denying same-name commands/skills/agents)
  - `harness-adapter.sh` (PreToolUse `apply_patch` in `hooks.json`; Cursor Shell / Write / SessionStart in
    `hooks-cursor.json`): rewrite Codex/Cursor input to the Claude Code shape, call one existing script,
    convert the reply, and on any failure exit 0 after counting the reason in `adapter-skips.json`
  `tool-reminder.sh` and `write-guard.sh` resolve paths from the hook input's `cwd`, not `CLAUDE_PROJECT_DIR` (which
  stays on the main checkout inside a worktree); `session-start.sh` uses `${CLAUDE_PROJECT_DIR:-$PWD}`.
  All hook writes are confined to `~/.claude/aidd/` — no network calls, no writes elsewhere.
- **Templates** (`templates/*.template`) are copied into a *consumer* project (e.g.
  `.aidd/design-perspectives.md.template` → consumer's `.aidd/design-perspectives.md`), not used in this repo
  directly, except that `tests/redundancy-contract-test.sh` asserts invariants about their content (e.g. no
  `## セキュリティ` section, since security perspectives were centralized into Agent 6 / `security-reviewer`),
  `asset-overlap-prompt-hook.json.template` is generated here (checked by CI `--check` and `hook-contract-test.sh`),
  and `templates/aidd-hook-log.sh` is shellchecked in CI and tested by `hook-log-test.sh`.

### The design-review pipeline (`skills/design-review/SKILL.md`)

This is the most structurally complex asset — read the file itself before modifying it, but the shape is:

1. **Flag parsing**: `--depth=standard|deep` (default `standard`), `--review-delta=<range>` (re-review limited to
   the diff since the last review), `--verify-sources`, `--security`/`--no-security` are stripped from `$ARGUMENTS`
   before anything is dispatched to agents.
2. **Dismissed-findings intake**: reads consumer's `.aidd/review-dismissed.md` if present, passes it to every
   reviewer so previously user-approved dismissals aren't re-reported.
3. **Parallel dispatch, single message**: up to 6 `aidd:reviewer`/specialist agents fire together —
   Agent 1 (structure), Agent 2 (data/error handling), Agent 3 (pragmatism/YAGNI/ops), Agent 4 (project-specific,
   only if consumer has `.aidd/design-perspectives.md` — never carries security perspectives), Agent 5
   (`aidd:source-verifier`, only with `--verify-sources`), Agent 6 (`aidd:security-reviewer`, STRIDE, only if the
   design crosses a trust boundary — decided semantically by the main loop, not by keyword match; forced/suppressed
   by `--security`/`--no-security`).
   Only a small target (1 file, or a summary under 100 lines) may shortcut to a direct in-context review — except
   when `--verify-sources` is set, which always forces the full parallel path (to guarantee Agent 5 runs). A large
   target (over 5 files or 3000 lines total) is instead split across multiple agents per perspective group.
4. **Refutation stage**: `aidd:refuter` (sonnet) runs only if any high/mid findings exist, and only receives the
   findings + citations + minimal related paths (not the whole target again). `low` findings and Agent 5 output
   skip refutation entirely.
5. **Arbitration**: `aidd:design-arbiter` (opus, fixed regardless of main-loop model). In `standard`, high/mid
   surviving refutation are reported directly; the arbiter runs only on cross-agent contradiction or when Agent 5
   ran. In `deep`, it also runs whenever high/mid survive refutation. Skipping the arbiter for surviving high/mid is
   the main token-saving mechanism of `standard` vs `deep`.
6. Findings needing a code-level security audit after implementation are pointed at `/security-review` (a
   *different*, code-diff-focused tool) — Agent 6 only covers the design document, not implementation.

### Evaluation harness (`skills/eval/SKILL.md`, `tests/eval/`)

`/aidd:eval` measures the design-review pipeline's own precision by running it (always at `--depth=deep`, no
shortcuts) against seeded-defect design docs in `tests/eval/cases/*.md` and grading against
`tests/eval/keys/*.md`. Contamination guard: **keys must not be read until every case's review has completed** —
reading them early would let the scoring pass (the main loop) leak into how it dispatches/reviews. Metrics
(core detection rate, extended detection rate, false-refutation rate, severity match, decoy false-positive rate,
security auto-trigger) are written to `tests/eval/results/YYYY-MM-DD.md`, compared against the most recent prior
result. **Operating rule 6**: any release that changes `skills/design-review/SKILL.md`, `agents/refuter.md`,
`agents/design-arbiter.md`, `agents/security-reviewer.md`, or `agents/reviewer.md` must run `/aidd:eval` before
release and keep the result file — this is
the only regression signal for pipeline prompt changes, since there's no automated scoring in CI.

## Dependency on `superpowers`

`.claude-plugin/plugin.json` declares `superpowers@superpowers-marketplace` as a hard dependency (auto-installed
on `/plugin install aidd@aidd`, requires Claude Code v2.1.110+). The split of responsibility (see
`docs/tips/superpowers-usage.md` and README's scope-boundary bullets) is: **aidd owns design/review/ADR/process
enforcement; superpowers owns implementation-phase skills** (brainstorming, TDD, debugging, plan-writing). Do not
duplicate superpowers skills here — if a superpowers skill is renamed/removed upstream, `session-start.sh`'s
best-effort detection (checking `~/.claude/plugins/installed_plugins.json` for a `superpowers@` entry, non-blocking)
is the only fallback; `/aidd:doctor` diagnoses breakage.

## Design docs

`docs/superpowers/specs/*.md` hold the design rationale for major changes (dated filenames). Check the most
recent one before restructuring the design-review pipeline, hooks consolidation, or the redundancy-removal work —
they explain *why* something was consolidated/removed, which the code/prompts alone don't show.
