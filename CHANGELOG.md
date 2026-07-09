# Changelog

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
