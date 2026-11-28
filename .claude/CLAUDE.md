# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

`aidd` is a Claude Code **plugin** (not an app): a knowledge base of task-specific slash commands, subagent
definitions, skills, hooks, and templates for AI-driven development (design review, ADR, test perspectives,
etc.). There is no build step and no application runtime — the "product" is the Markdown/JSON/shell assets
themselves, consumed by another Claude Code session that installs this plugin. `README.md` is the canonical
index of every asset; when you add or remove an agent/skill/hook, update that index, bump `version` in
`.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, and `.cursor-plugin/plugin.json` to the same value,
and add a `CHANGELOG.md` entry (operating rule 3, see README "運用ルール").

## Commands (verified against `.github/workflows/validate.yml`)

CI keeps the following five checks in the Ubuntu-only `validate` job, in order (after checkout):

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

The separate `contract-tests` job runs all thirteen scripts below on both `ubuntu-latest` and `macos-latest`
with Python 3.12. Its OS × script matrix reports 26 independent results, has a 10-minute limit per job,
and uses `fail-fast: false` so a failed test does not cancel the other combinations. A script's nonzero
exit fails its job. Each job uses a fresh temporary root for HOME, TMPDIR, CLAUDE_CONFIG_DIR and
AIDD_TEST_STATE_DIR, unsets CLAUDE_PROJECT_DIR, ignores global/system Git configuration, and removes
only its own root on exit. Tests need Bash, Python, Git and standard Unix tools; they use fake hook
events, throwaway repositories/settings/memories and their own child processes, without invoking a
model CLI or writing to GitHub. The Codex installer test copies only into temporary destinations.

There is no `package.json`/Makefile/test runner. The contract tests are plain bash scripts run directly
in CI and locally:

```bash
bash tests/autonomous-review-contract-test.sh  # grep-asserts required phrases in skills/autonomous-review/SKILL.md
bash tests/command-contract-test.sh      # grep-asserts exact phrases exist in skills/design-review/SKILL.md, agents/reviewer.md, agents/refuter.md, skills/eval/SKILL.md, skills/review-loop/SKILL.md, skills/adr/SKILL.md, skills/incident-retro/SKILL.md, skills/asset-audit/SKILL.md, skills/issue-implement/SKILL.md, skills/design-doc/SKILL.md, skills/test-perspectives/SKILL.md, skills/doctor/SKILL.md
bash tests/hook-contract-test.sh         # feeds fake hook-event JSON into hooks/scripts/*.sh via stdin, asserts output; also runs generate-asset-index.py --check
bash tests/hook-log-test.sh              # exercises templates/aidd-hook-log.sh (pass-through, signals, per-hook markers)
bash tests/redundancy-contract-test.sh   # asserts removed assets stay removed and de-duplication boundaries hold
bash tests/session-start-test.sh         # asserts session-start.sh injects the short nudges only when due
bash tests/codex-agents-contract-test.sh # Codex TOML stays generated from agents/*.md; installer copies and --check detects stale/missing
bash tests/incident-retro-memory-test.sh # runs incident-retro's auto memory listing snippet on a fake memory dir and checks that candidates counts the imported observations only once merged
bash tests/learnings-test.sh             # scripts/learnings.py: ledger check rejects/passes, add is off by default, candidates counting
bash tests/issue-outcome-test.sh         # scripts/issue-outcome.py: outcome.json rejections one by one; issue-implement stop-point markers match the script enums
bash tests/assurance/acceptance-test.sh  # examples/assurance/acceptance: approved digest, criteria-test traceability, correct impl passes, each wrong impl fails exactly its criteria
bash tests/assurance/release-gate-test.sh  # examples/assurance/github: gate.py verdicts on check-run fixtures, static checks of the gate workflow/ruleset/policy (stdlib YAML subset in tests/assurance/workflow_lint.py)
bash tests/assurance/evidence-test.sh   # examples/assurance/evidence: verify_evidence.py verdicts on fake gh attestation verify output; provenance.yml signs only in a job that runs no project code
```

For local runs, isolate HOME, CLAUDE_CONFIG_DIR and AIDD_TEST_STATE_DIR as CI does; unset
CLAUDE_PROJECT_DIR and ignore global/system Git configuration. Never point tests at another session's
state. On macOS, bare `mktemp -d` may ignore TMPDIR and use `/var/folders`; if the sandbox disallows that
directory, use an allowed execution environment rather than treating the sandbox restriction as a test failure.

These are **not** a general-purpose test framework — some grep for literal strings that must appear in specific
prompt files; `hook-contract`, `hook-log` and `session-start` execute the scripts. If you edit
`skills/design-review/SKILL.md`, `agents/reviewer.md`, `agents/refuter.md`, `skills/eval/SKILL.md`, `skills/adr/SKILL.md`,
`skills/incident-retro/SKILL.md`, `skills/autonomous-review/SKILL.md`, `skills/issue-implement/SKILL.md`, `skills/design-doc/SKILL.md`, `skills/test-perspectives/SKILL.md`, `skills/doctor/SKILL.md`, `skills/asset-audit/SKILL.md` (also executed by
`hook-log-test.sh`), `skills/review-loop/SKILL.md`, `templates/design-perspectives.md.template`,
`templates/CLAUDE.md.template`, `templates/aidd-hook-log.sh`, `hooks/hooks.json`, `hooks/scripts/*.sh`,
`scripts/generate-asset-index.py`, `scripts/generate-codex-agents.py`, `scripts/install-codex-agents.sh`, `scripts/learnings.py`, `scripts/issue-outcome.py`,
`.codex/agents/*.toml`, `examples/assurance/acceptance/*`, `examples/assurance/github/*`, `examples/assurance/evidence/*`, `tests/assurance/workflow_lint.py`, or any command/skill/agent frontmatter, run the matching test script — a wording
change can silently break the contract. CI runs these thirteen scripts automatically; still run the matching
tests locally before committing. When adding a test script, update the workflow matrix and this list together.
After editing `agents/*.md`, run `python3 scripts/generate-codex-agents.py`.

`claude plugin validate . --strict` requires the `claude` CLI on PATH (`npm install -g @anthropic-ai/claude-code`
if missing) and validates both `.claude-plugin/marketplace.json` and `.claude-plugin/plugin.json`.

## Adding a user-invoked skill

There is no `commands/` directory. Codex does not ship plugin commands and Cursor recommends
skills, so a user-invoked task goes in `skills/<name>/SKILL.md` (same as reqd / stdd / uidd).
Do not add a `commands/` file, not even a stub. Claude Code invokes it as `/aidd:<name>` through
the skill's `name:` frontmatter.

- Frontmatter: `name: <name>`, `description`, `disable-model-invocation: true`, and
  `argument-hint` if it takes arguments.
- Add `skills/<name>/agents/openai.yaml` with `policy.allow_implicit_invocation: false`
  (Codex would otherwise auto-start a user-invoked task).
- Do not add a `skills` key to `.claude-plugin/plugin.json`. `.codex-plugin` and
  `.cursor-plugin` already declare `"skills": "./skills/"`.
- Put this block (uidd wording) right after the frontmatter:

```
**パスと引数と質問の扱い**: この文書の相対パスは、この SKILL.md があるディレクトリを起点にする。`$ARGUMENTS` が文字のまま残っている場合（Codex・Cursor など）は、この skill を呼び出したメッセージのうち skill 名以外の部分を `$ARGUMENTS` とみなす。`AskUserQuestion` と書かれた箇所は、ユーザーに質問するツールがあればそれを使い、無ければ質問を書いて作業を止め、回答を待つ。回答が無いまま推測で進めない。
```

- Write `AskUserQuestion` in the body as is; the block above covers other harnesses.
- Auto-trigger skills (`adr-recall` and the others) keep auto-start; do not give them
  `disable-model-invocation` or `openai.yaml`.
- Run `python3 scripts/generate-asset-index.py` in the same commit.
- One exception: `autonomous-review` has no `disable-model-invocation`, so the model can start it
  in Claude Code, and `hooks/scripts/skill-gate.sh` asks the user before every model-started run
  (Cursor: refuses the model's SKILL.md read). It keeps `openai.yaml`. Do not copy this to another
  skill without measuring the gate for it; the measurements are in
  `docs/superpowers/specs/2026-11-14-autonomous-review-auto-invocation-design.md`.
- Second exception: `test-perspectives`, `design-doc` and `design-review` have no
  `disable-model-invocation` and no gate. `issue-implement`, `autonomous-review`, and the
  `session-start.sh` / `tool-reminder.sh` nudges tell the model to run them, and a gate's `ask`
  acts as a deny under `claude -p`, so a gate would keep non-interactive hosts stuck (#196). They only
  create new files (design-review writes nothing), so the reason other skills stay user-only — not
  letting the model start edits to existing canonical text on its own — does not apply. Their
  `description` says when not to use them. They keep `openai.yaml` with
  `allow_implicit_invocation: false`: Codex (codex-cli 0.163.0) still follows them from
  `$aidd:issue-implement` by reading their SKILL.md (#205,
  `tests/eval/results/2026-11-28-codex-design-skills.md`).
  `tests/command-contract-test.sh` holds the allowlist; any other skill with `openai.yaml` must keep
  `disable-model-invocation: true`. Design: `docs/superpowers/specs/2026-11-28-model-invocable-design-skills-design.md`.

## Architecture: how the asset types relate

- **Commands** (`commands/*.md`) are gone. User-invoked entry points are the skills listed
  below. Claude Code invokes them as `/aidd:<name>`. Most don't do the work themselves — they
  orchestrate **agents** (`agents/*.md`) via parallel `Task`/dispatch, one message per wave,
  passing only the target + assigned perspective (never the full agent/command definition
  text, to keep dispatch payloads small).
- **User-invoked skills** (`skills/design-review/`, `skills/eval/`, `skills/autonomous-review/`, `skills/issue-split/`, `skills/issue-select/`, `skills/retro/`, `skills/asset-audit/`, `skills/incident-retro/`, `skills/adr/`, `skills/design-doc/`, `skills/design-sync/`, `skills/doctor/`, `skills/infra-audit/`, `skills/issue-implement/`, `skills/test-perspectives/`) are the same kind of entry point,
  already moved so Codex (`$aidd:<name>`) and Cursor (`/<name>`) can run them. They carry
  `disable-model-invocation: true` and Codex `allow_implicit_invocation: false`, except
  `autonomous-review` (model-invocable behind `skill-gate.sh`) and `test-perspectives` /
  `design-doc` / `design-review` (model-invocable without a gate), see above.
- **Auto-trigger skills** (`skills/adr-recall/` and the others) fire based on their `description`
  frontmatter matching the situation. They hold *reusable* judgment logic that would otherwise be
  duplicated across commands.
- **Hooks** (`hooks/hooks.json` + `hooks/scripts/*.sh`) are the only assets with actual enforcement power —
  everything else is advisory text a model can ignore. `hooks.json` wires 8 entries across 5 events to 6 scripts
  (the 8th is Codex `apply_patch` → `harness-adapter.sh` → `write-guard.sh`; Cursor uses `hooks/hooks-cursor.json`):
  - `session-start.sh` (SessionStart): injects a one-time short nudge, an `/aidd:asset-audit` nudge only when the
    consumer's audit is overdue, and detects missing `superpowers` plugin
  - `usage-log.sh` (UserPromptSubmit + PreToolUse `^Skill$`): counts `/aidd:*` usage into `~/.claude/aidd/usage.json`
    (read by `/aidd:retro`); never logs prompt text
  - `skill-gate.sh` (PreToolUse `^Skill$`, beside `usage-log.sh`; Cursor `Read` through the adapter): returns
    `ask` before the model starts `autonomous-review`, and on Cursor denies the read of this plugin's
    `skills/autonomous-review/SKILL.md`. Prints the decision before its best-effort count in `skill-gate.json`,
    always exits 0 (a hook that fails to start lets the Skill through), and asks when it cannot parse input
    that names the skill
  - `tool-reminder.sh` (PreToolUse + PostToolUse + PostToolUseFailure, matcher `Bash`): the single Bash dispatcher.
    It splits the command (quotes, `&&`/`;`, comments, control keywords, `cd`, `git -C`, wrappers), collects every
    matching check, and emits one JSON: the original nudges (test-perspectives, Japanese PR/issue text, post-push
    PR sync; the Japanese nudge stays quiet only when every given `--title`/`--body`/`--body-file`/heredoc body
    holds kana or kanji, and it reads a body file — a regular file, the first 64 KiB, at most 3, 1 s in all —
    only when the run has no denial, so a hanging read cannot drop a denial), review-evidence warning before `gh pr create`, denial of work-losing git operations and unnamed
    staging, denial of a force push to / remote delete of the default branch (the remote's `HEAD` if it
    exists, plus `main`/`master` always; a destination with `$`/backquote is denied; work-branch force pushes pass), main-tree sharing warning, search-before-`gh issue create` gate, optional required-label gate, and the
    post-commit subject/Why check (only in repos that adopt the convention). A denial of a command that joins more
    than one operation ends with a note that none of them ran (reflux #219). Commands without a `git`/`gh` word exit
    before python starts. Don't split it back out without checking `docs/superpowers/specs/2026-07-18-token-optimization-design.md`
  - `write-guard.sh` (PreToolUse, matcher `Write|Edit|NotebookEdit`): acts only on files that don't exist yet —
    denies names the sandbox usually can't read back, and points new consumer `.claude/{hooks,skills,commands,rules,agents}`
    assets at the aidd assets they duplicate (denying same-name commands/skills/agents)
  - `harness-adapter.sh` (PreToolUse `apply_patch` in `hooks.json`; Cursor Shell / Write / Read / SessionStart in
    `hooks-cursor.json`): rewrite Codex/Cursor input to the Claude Code shape, call one existing script,
    convert the reply, and on any failure exit 0 after counting the reason in `adapter-skips.json`. For
    `skill-gate.sh` it exits before python only when the input has no `file_path`, or the path is absolute,
    exists, has no `..`, and bash `-ef` shows it is not this plugin's `skills/autonomous-review/SKILL.md`; every
    other input (a missing, `..`, relative or `~` path, the skill name, a backslash, more than one `file_path`)
    goes to python (every Cursor Read lands here)
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
   design crosses a trust boundary or stores sensitive data in files, logs, or caches — decided semantically by the main loop, not by keyword match; forced/suppressed
   by `--security`/`--no-security`).
   Only a small target (1 file, or a summary under 100 lines) may shortcut to a direct in-context review — except
   when `--verify-sources` is set, which always forces the full parallel path (to guarantee Agent 5 runs). The shortcut
   skips only the reviewer dispatch: a target that meets the Agent 6 condition still gets Agent 6 (#200). A large
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
`tests/eval/keys/*.md`. Contamination guard: each case and trial runs in a new executor session (`claude -p`)
whose working directory is a staged temp `input/` holding only the case and a plugin copy — no keys, results, git
history or planted file (planted rows are appended to the fixed prompt under neutral M IDs). The main loop freezes
the raw output and the stream-json, records the printed hash of SHA256SUMS, and reads `tests/eval/keys/` only after
verifying it. This separates input and context, not read permissions: absolute-path reads outside the working
directory and arbitrary Bash commands are not blocked, and the files can be changed before the freeze. The metrics
are defined in the table in `skills/eval/SKILL.md` (step 3); results are written to
`tests/eval/results/YYYY-MM-DD.md`, with the raw output under `tests/eval/results/<run-id>/`, and compared against the most recent prior result. `/aidd:eval impl` compares the autonomous-review main review by a fresh `claude -p` (Read/Grep/Glob only) and
`codex exec --sandbox read-only` on the frozen cases in `tests/eval/impl/` (seeded defects and defect-free controls,
keys, `rubric.md`). The user approves and commits `tests/eval/impl/freeze.sha256` (cases, keys, rubric, fixed prompt
and staging block) before any run; staging stops if it does not match. It reuses the #129 extract/freeze/verify, and
its result is a proposal only — it never relaxes autonomous-review eligibility. **Operating rule 6**: any release that changes `skills/design-review/SKILL.md`, `agents/refuter.md`,
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
