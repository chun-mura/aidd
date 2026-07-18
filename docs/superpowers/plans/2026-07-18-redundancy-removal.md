# aidd Redundancy Removal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove duplicated aidd assets and redundant security review inputs without losing the specialist review path.

**Architecture:** Delete the duplicate parallel-investigation skill, reduce review-loop and retro to their unique responsibilities, and make STRIDE the single security-review mechanism. Keep scout, design-sync, usage telemetry, and all security flags intact.

**Tech Stack:** Markdown, Bash, Python 3, shellcheck.

## Global Constraints

- `usage.json` retains only `command_counts` and `last_seen`.
- Existing `.aidd/design-perspectives.md` files are never modified automatically.
- Agent 6 remains the only security reviewer for trust-boundary designs.

---

### Task 1: Remove duplicate skills and simplify review guidance

**Files:**
- Delete: `skills/parallel-investigation/SKILL.md`
- Modify: `skills/review-loop/SKILL.md`
- Modify: `agents/security-reviewer.md`
- Modify: `commands/design-review.md`
- Test: `tests/redundancy-contract-test.sh`

- [ ] Add tests that assert the parallel skill is absent, review-loop keeps severity and dismissed-finding rules, and Agent 4 excludes security when Agent 6 applies.
- [ ] Run `bash tests/redundancy-contract-test.sh` and observe failure.
- [ ] Apply the minimum deletions and concise contracts.
- [ ] Re-run `bash tests/redundancy-contract-test.sh` and confirm success.

### Task 2: Reduce retro and logging to asset telemetry

**Files:**
- Modify: `commands/retro.md`
- Modify: `hooks/scripts/session-start.sh`
- Modify: `hooks/scripts/usage-log.sh`
- Modify: `tests/hook-contract-test.sh`

- [ ] Add assertions that no prompt log is written even with `AIDD_PROMPT_LOG=1`, and that SessionStart emits no retro nudge.
- [ ] Run `bash tests/hook-contract-test.sh` and observe failure.
- [ ] Remove prompt-log handling and nudge logic while preserving command counts and last-seen timestamps.
- [ ] Re-run `bash tests/hook-contract-test.sh` and confirm success.

### Task 3: Update public documentation and verify

**Files:**
- Modify: `README.md`, `templates/design-perspectives.md.template`, `templates/README.md`, `docs/tips/superpowers-usage.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`
- Test: `tests/command-contract-test.sh`, `tests/redundancy-contract-test.sh`, `tests/hook-contract-test.sh`, `tests/session-start-test.sh`

- [ ] Remove references to deleted assets and document STRIDE as the security owner.
- [ ] Increment the patch version and record the behavior change.
- [ ] Run all shell tests, `shellcheck hooks/scripts/*.sh`, and `claude plugin validate . --strict`.
