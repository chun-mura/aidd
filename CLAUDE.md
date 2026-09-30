# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

`aidd` is a Claude Code **plugin** (not an app): a knowledge base of task-specific slash commands, subagent
definitions, skills, hooks, and templates for AI-driven development (design review, ADR, test perspectives,
etc.). There is no build step and no application runtime — the "product" is the Markdown/JSON/shell assets
themselves, consumed by another Claude Code session that installs this plugin. `README.md` is the canonical
index of every asset; when you add or remove a command/agent/skill/hook, update that index, bump `version` in
`.claude-plugin/plugin.json`, and add a `CHANGELOG.md` entry (operating rule 3, see README "運用ルール").

## Commands (verified against `.github/workflows/validate.yml`)

CI (`validate` job) runs exactly four steps, in order:

```bash
shellcheck hooks/scripts/*.sh templates/*.sh   # lint the hook scripts and the consumer-side wrapper template
python3 scripts/generate-asset-index.py --check # fail if hooks/asset-index.json / the prompt-hook template are stale
npm install -g @anthropic-ai/claude-code       # install the claude CLI
claude plugin validate . --strict              # validates .claude-plugin/marketplace.json + plugin.json
```

Adding, removing or renaming a command/agent/skill, or changing a hook script's line-2 description, changes the
asset index shipped for `write-guard.sh`: run `python3 scripts/generate-asset-index.py` in the same commit or CI
fails.

There is no `package.json`/Makefile/test runner. The contract tests are plain bash scripts run directly:

```bash
bash tests/autonomous-review-contract-test.sh  # grep-asserts required phrases in commands/autonomous-review.md
bash tests/command-contract-test.sh      # grep-asserts exact phrases exist in commands/design-review.md, agents/reviewer.md, agents/refuter.md, commands/eval.md, commands/incident-retro.md, commands/asset-audit.md
bash tests/hook-contract-test.sh         # feeds fake hook-event JSON into hooks/scripts/*.sh via stdin, asserts output
bash tests/hook-log-test.sh              # exercises templates/aidd-hook-log.sh (pass-through, signals, per-hook markers)
bash tests/redundancy-contract-test.sh   # asserts removed assets stay removed and de-duplication boundaries hold
bash tests/session-start-test.sh         # asserts session-start.sh injects the short nudges only when due
```

On macOS inside the Claude Code sandbox, `mktemp -d` may ignore `$TMPDIR` and fail under `/var/folders`; run the
tests outside the sandbox (or with a writable temp dir) rather than treating that as a test failure.

These are **not** a general-purpose test framework — each script greps for literal strings that must appear in
specific prompt files. If you edit `commands/design-review.md`, `agents/reviewer.md`, `agents/refuter.md`,
`commands/eval.md`, `skills/review-loop/SKILL.md`, `templates/design-perspectives.md.template`, or
`hooks/scripts/*.sh`, run the matching test script — a wording change can silently break the contract. There is
no CI job that runs these `tests/*.sh` scripts automatically; run them locally before committing.

`claude plugin validate . --strict` requires the `claude` CLI on PATH (`npm install -g @anthropic-ai/claude-code`
if missing) and validates both `.claude-plugin/marketplace.json` and `.claude-plugin/plugin.json`.

## Architecture: how the asset types relate

- **Commands** (`commands/*.md`) are the entry points a user invokes as `/aidd:<name>`. Most commands don't do
  the work themselves — they orchestrate **agents** (`agents/*.md`) via parallel `Task`/dispatch, one message per
  wave, passing only the target + assigned perspective (never the full agent/command definition text, to keep
  dispatch payloads small).
- **Skills** (`skills/*/SKILL.md`) are auto-triggered knowledge, not commands — they fire based on their
  `description` frontmatter matching the situation (e.g. `adr-recall` fires before an architectural change,
  `model-selection` fires when choosing a subagent model). They hold *reusable* judgment logic that would
  otherwise be duplicated across commands.
- **Hooks** (`hooks/hooks.json` + `hooks/scripts/*.sh`) are the only assets with actual enforcement power —
  everything else is advisory text a model can ignore. `hooks.json` wires 6 lifecycle entries to 4 scripts:
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
  Git checks use the hook input's `cwd`, not `CLAUDE_PROJECT_DIR` (which stays on the main checkout inside a worktree).
  All hook writes are confined to `~/.claude/aidd/` — no network calls, no writes elsewhere.
- **Templates** (`templates/*.template`) are copied into a *consumer* project (e.g.
  `.aidd/design-perspectives.md.template` → consumer's `.aidd/design-perspectives.md`), not used in this repo
  directly, except that `tests/redundancy-contract-test.sh` asserts invariants about their content (e.g. no
  `## セキュリティ` section, since security perspectives were centralized into Agent 6 / `security-reviewer`).

### The design-review pipeline (`commands/design-review.md`)

This is the most structurally complex asset — read the file itself before modifying it, but the shape is:

1. **Flag parsing**: `--depth=standard|deep` (default `standard`), `--verify-sources`, `--security`/`--no-security`
   are stripped from `$ARGUMENTS` before anything is dispatched to agents.
2. **Dismissed-findings intake**: reads consumer's `.aidd/review-dismissed.md` if present, passes it to every
   reviewer so previously user-approved dismissals aren't re-reported.
3. **Parallel dispatch, single message**: up to 6 `aidd:reviewer`/specialist agents fire together —
   Agent 1 (structure), Agent 2 (data/error handling), Agent 3 (pragmatism/YAGNI/ops), Agent 4 (project-specific,
   only if consumer has `.aidd/design-perspectives.md` — never carries security perspectives), Agent 5
   (`aidd:source-verifier`, only with `--verify-sources`), Agent 6 (`aidd:security-reviewer`, STRIDE, only if the
   design crosses a trust boundary — decided semantically by the main loop, not by keyword match; forced/suppressed
   by `--security`/`--no-security`).
   Below 5 files / 3000 lines total the whole thing can shortcut to a direct in-context review — except when
   `--verify-sources` is set, which always forces the full parallel path (to guarantee Agent 5 runs).
4. **Refutation stage**: `aidd:refuter` (sonnet) runs only if any high/mid findings exist, and only receives the
   findings + citations + minimal related paths (not the whole target again). `low` findings and Agent 5 output
   skip refutation entirely.
5. **Arbitration**: `aidd:design-arbiter` (opus, fixed regardless of main-loop model) runs only when
   `--depth=deep`, or when there's cross-agent contradiction, or when Agent 5 ran. In `standard` mode with no
   contradiction and nothing surviving refutation, results are reported directly without invoking the arbiter —
   this shortcut is the main token-saving mechanism of `standard` vs `deep`.
6. Findings needing a code-level security audit after implementation are pointed at `/security-review` (a
   *different*, code-diff-focused tool) — Agent 6 only covers the design document, not implementation.

### Evaluation harness (`commands/eval.md`, `tests/eval/`)

`/aidd:eval` measures the design-review pipeline's own precision by running it (always at `--depth=deep`, no
shortcuts) against seeded-defect design docs in `tests/eval/cases/*.md` and grading against
`tests/eval/keys/*.md`. Contamination guard: **keys must not be read until every case's review has completed** —
reading them early would let the scoring pass (the main loop) leak into how it dispatches/reviews. Metrics
(core detection rate, extended detection rate, false-refutation rate, severity match, decoy false-positive rate,
security auto-trigger) are written to `tests/eval/results/YYYY-MM-DD.md`, compared against the most recent prior
result. **Operating rule 6**: any release that changes `design-review.md`, `refuter.md`, `design-arbiter.md`,
`security-reviewer.md`, or `reviewer.md` must run `/aidd:eval` before release and keep the result file — this is
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
