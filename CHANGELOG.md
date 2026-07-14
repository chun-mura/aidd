# Changelog

## 0.16.0 (2026-07-14)

Move review-unit splitting upstream: 0.15.0 added a reactive "consider splitting" note to review-loop; this release makes the split decision at design completion, before any PR exists.

- Add `commands/issue-split.md`: split a design into independently mergeable PR-sized units (vertical slices only, ~5 changed files each, boundaries taken from the design's component/responsibility section), present the plan, and create GitHub issues via `gh` only after AskUserQuestion approval (Japanese title/body with design-doc path, scope, done criteria, and dependencies); falls back to plan-only when `gh`/GitHub is unavailable; session-level task breakdown stays with superpowers:writing-plans
- `design-doc.md`: after saving, estimate implementation size from the design (heuristic: >5 changed files or 2+ independently mergeable units) and suggest `/aidd:issue-split` when over the threshold

## 0.15.0 (2026-07-14)

Review-accuracy improvements for review-loop / design-review, backed by external evidence (Anthropic Code Review's verify stage, adversarial refutation research, an industrial false-positive study, LLM-as-a-judge bias research, Google's Small CLs guide).

- Add `agents/refuter.md` (sonnet): adversarial verifier whose job is to disprove high/mid findings against the actual target, not confirm them; refutation requires evidence from the target ("unlikely" does not count), and only findings that survive are promoted
- `design-review.md`: insert a refutation stage between reviewers and arbiter — high/mid findings pass through aidd:refuter, refuted ones are discarded and reported separately with reasons (low findings and source-verified Agent 5 results skip the stage); accept a rejected-findings list in `$ARGUMENTS` and instruct reviewers not to re-report identical findings
- `skills/review-loop/`: carry rejected findings (refuted or mismatching the actual file, with reasons) across rounds as a "do not re-report" list included in each dispatch; re-reported rejected findings do not count toward the termination criterion; verified high/mid findings get a refutation attempt (via aidd:refuter or manually) before being fixed
- `skills/review-loop/`: add a concrete severity rubric for the canonical high/mid/low vocabulary (high = ships real damage: data loss/corruption, security, production outage; mid = correctness/maintainability impact with a workaround or limited blast radius; low = style/preference/improvement ideas) — severity variance directly destabilized the termination criterion, which counts high/mid findings
- `skills/review-loop/`: run the project's static checks (lint/typecheck/tests, whichever exist) before each round's dispatch and include the results; machine-detectable issues are delegated to static checks, not reported as review findings
- `skills/review-loop/`: when high/mid findings keep piling up every round, consider splitting the review unit before running more rounds (per Google's Small CLs guidance)
- `design-review.md`: embed the same severity rubric in the reviewer dispatch instructions (canonical copy lives in review-loop; keep in sync); instruct the arbiter to re-rank each finding against the rubric independently, not by description length or presentation order

## 0.14.0 (2026-07-13)

Lessons from a review-fix loop session in a consuming project (review findings applied blindly broke a framework's internal load path; mock-heavy tests missed it; review rounds had no stop condition).

- Add `skills/review-loop/`: decide the termination criterion before starting review-fix rounds (default: zero high/mid findings for 2 consecutive rounds); treat reviews as sampling that never converges to zero findings; read the framework implementation before applying suggestions that touch framework base classes; delegates per-finding handling to `superpowers:receiving-code-review`
  - Canonical severity vocabulary: high/mid/low (same scale as design-review/design-arbiter), with a translation table for external vocabularies (Critical/Important/Suggestion/Nit, Google's blocking/`Nit:`); sorting and termination judgment always use the canonical terms
  - Read-completion protocol for code-diff rounds run outside design-review: dispatched review agents must read all diff hunks plus surrounding context, attach file:line to findings, and report read-completion status; high/mid findings must be verified against the actual file with Read before applying (agent line numbers/function names can hallucinate)
- `test-perspectives.md`: add 6th category **フレームワーク結合** — framework/ORM base-class overrides and implicitly-invoked paths require at least one mock-less real-path test as must

## 0.13.0 (2026-07-12)

Team-readiness release: no functional changes to commands/agents/skills.

- **Breaking**: rename marketplace `aidd-local` → `aidd`. Existing installs must re-add: `/plugin marketplace add chun-mura/aidd` then `/plugin install aidd@aidd`
- Add MIT `LICENSE`; `plugin.json` gains `homepage`/`repository`/`license`/`keywords`; marketplace entry gains `category`/`tags`
- Hooks opt-outs: `AIDD_DISABLE_USAGE_LOG=1` disables prompt logging (`usage-log.sh`), `AIDD_DISABLE_CLARIFY_NUDGE=1` disables the per-prompt nudge (`clarify-nudge.sh`)
- Add `templates/team-settings.json.template`: project-scoped auto-install via `extraKnownMarketplaces` + `enabledPlugins`
- Add CI (`.github/workflows/validate.yml`): shellcheck on hook scripts + `claude plugin validate --strict`
- README: document runtime prerequisites (macOS/Linux, bash/python3/gh), consuming-project directory conventions, hook write targets and opt-outs, and the dependency compatibility policy for superpowers / pr-review-toolkit

## 0.12.0 (2026-07-10)

- `design-review.md`: prevent partial-read false findings on large doc sets
  - Reviewer agents must read assigned files in full, check later sections (decision log / revision history) before reporting "unresolved" issues, and report read-completion status
  - Split dispatch across multiple agents per perspective when the target exceeds ~5 files or ~3000 lines total; cross-file consistency perspectives still see the full file list
  - Arbiter discards findings tied to files an agent could not fully read, and quarantines "unresolved"-type findings lacking evidence of decision-log verification

## 0.11.0 (2026-07-09)

- Add `hooks/scripts/pr-sync-reminder.sh` (PostToolUse): after `git push`, remind to refresh the open PR's title/body via `gh pr edit` when the pushed commits changed its scope

## 0.10.0 (2026-07-09)

- Add `hooks/scripts/gh-language-reminder.sh` (PreToolUse): inject "write GitHub issue/PR titles and bodies in Japanese" before `gh pr/issue create|edit` runs

## 0.9.0 (2026-07-09)

- Add `agents/source-verifier.md` (sonnet, WebSearch/WebFetch/Read): verify externally checkable claims in design docs (technology-choice rationale, API/spec assertions, version compatibility, security recommendations) against trusted sources
- `design-review.md`: opt-in `--verify-sources` flag dispatches source-verifier as Agent 5; arbiter treats only 反証あり as ranked findings, 未確認 as informational

## 0.8.0 (2026-07-09)

- Add `skills/adr-recall/`: surface conflicting ADRs before architectural changes
- Add `hooks/scripts/usage-log.sh`: log aidd command usage and prompt history to `~/.claude/aidd/usage.json` for data-driven `/aidd:retro`
- Add `commands/design-sync.md`: detect drift between `docs/design/` and implementation; `design-doc.md` now writes a `status` frontmatter field
- `test-perspectives.md` now persists output to `docs/test-perspectives/`; `commit-reminder.sh` skips the reminder when a fresh file exists
- `design-review.md` supports project-specific perspectives via `.aidd/design-perspectives.md` (Agent 4, additive only)
- Add `commands/doctor.md`: diagnose aidd/superpowers install state, version drift, and hook prerequisites

## 0.7.0 (2026-07-08)

- session-start hook: warn (non-blocking) when superpowers plugin is not detected in installed_plugins.json
- README: document superpowers as a required companion plugin, add install step

## 0.6.0 (2026-07-08)

- Add `commands/retro.md`: periodic stocktake for promotion candidates, hook/skill friction, and staleness
- session-start hook: track session count in `~/.claude/aidd/state.json`, nudge toward `/aidd:retro` every 20th session

## 0.5.0 (2026-07-08)

- Add UserPromptSubmit hook (clarify-nudge): standing "ask via AskUserQuestion instead of guessing" instruction, replacing the manually typed one
- design-doc / adr: confirm design-affecting ambiguities via AskUserQuestion before writing

## 0.4.0 (2026-07-08)

- Add `commands/design-doc.md`: generate design docs into docs/design/, sections aligned 1:1 with design-review perspectives, volume auto-scaled to change size
- Add `commands/adr.md`: architecture decision records into docs/adr/, one decision per ADR
- superpowers-usage.md: add asset-form guide (skills/hooks/commands/docs) and adjacency rules for superpowers overlap

## 0.3.0 (2026-07-08)

- Add `agents/design-arbiter.md` (opus): design-review integration/arbitration now always runs on opus, independent of the main-loop model (fixes shallow arbitration when running sonnet as the main model)

## 0.2.0 (2026-07-08)

- Convert passive docs into auto-triggering skills: `skills/model-selection/`, `skills/parallel-investigation/` (former `docs/tips/model-selection.md`, `docs/patterns/parallel-investigation.md`)
- Remove `docs/tips/context-management.md` (generic process knowledge — superpowers territory)
- Add hooks: SessionStart asset nudge, PreToolUse `git commit` reminder for test-perspectives
- `design-review` now dispatches 3 reviewer agents in parallel instead of running inline
- `test-perspectives` output now feeds superpowers:test-driven-development
- Templates: add AI-operations section to CLAUDE.md.template, note `/fewer-permission-prompts` in templates README

## 0.1.0 (2026-07-08)

- Initial release: commands (design-review, test-perspectives), agents (scout, reviewer), templates, tips
