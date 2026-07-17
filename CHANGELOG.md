# Changelog

## 0.20.0 (2026-07-17)

セキュリティ・可観測性レビューの体系化 (Perspective-Based Reading / チェックリスト読解の実証知見に基づく「具体的観点の付与」)。0.17.1 の委譲ポインタ (忘れ防止) を、再現可能なレビュー手段に引き上げる。

- `templates/design-perspectives.md.template` を追加: OWASP ASVS 5.0 の設計段階に関わる章 (V1/V2/V6/V7/V8/V12/V13/V14/V16) から抜粋したセキュリティ観点 + 可観測性観点 (SLI 定義・Golden Signals・trace ID・障害シナリオのログ追跡可能性)。`.aidd/design-perspectives.md` にコピーして Agent 4 の観点として使う
- `agents/security-reviewer.md` を追加 (sonnet): 信頼境界を跨ぐデータフローに STRIDE 6カテゴリを機械的に適用する脅威レビュー agent。攻撃経路を具体的に構成できる懸念のみ high/mid で報告し、信頼境界のない設計は「該当なし」で終了
- `design-review.md`: 信頼境界を跨ぐ設計で security-reviewer を **Agent 6** として条件起動 (判定はメインループの意味判断、`--security` で強制・`--no-security` で抑止)。指摘は既存の refuter → arbiter パイプに合流。セキュリティ委譲節を役割分担 (Agent 6 = 設計の STRIDE、`/security-review` = 実装後のコード監査) に書き換え
- `agents/refuter.md`: セキュリティ指摘の反証規則を追加 — 攻撃経路が構成不能である現物証拠のみ反証成立。「攻撃されにくい」「フレームワークが守る (現物未確認)」は反証と認めず、反証の過程で回避手順を構成できた指摘は手順付きで存続
- 既知事項: `.aidd/design-perspectives.md` (Agent 4) と Agent 6 の指摘が重複しうるが、dedup は arbiter の既存責務で吸収する

## 0.19.0 (2026-07-17)

- `session-start.sh`: 20セッションごとの retro nudge に、`usage.json` から集計した aidd コマンド使用回数上位5件と繰り返しプロンプト最大2件を10行以内で注入。`jq` 不在・集計失敗時は従来の提案文へフォールバック
- `docs/adr/0001-retro-nudge-summary-injection.md`: 自動レポート化 scope 外決定を nudge 時の縮小サマリに限って変更し、cron・ダッシュボードによるフル自動化は引き続き採らない理由を記録

## 0.18.0 (2026-07-17)

- `review-loop/SKILL.md`: ユーザー承認で棄却した指摘を `.aidd/review-dismissed.md` に対象ドキュメント・要約・理由・日付付きで追記保存し、次セッションの初回 dispatch から再報告禁止として渡す手順を追加
- `design-review.md`: `.aidd/review-dismissed.md` を開始時に読み込み、削除済み・大幅改訂済みの対象のエントリを除外できるようにした

## 0.17.1 (2026-07-17)

- `design-review.md`: 外部入力・認証認可・秘密情報・外部公開エンドポイントを扱う設計では、レビュー結果末尾で `/security-review` の実行を推奨する委譲ポインタを追加（標準6観点・agent 分担は不変）
- `design-review.md`: 運用観点に、障害調査・性能分析を成立させるログ設計・メトリクス設計を明記
- `design-review.md`: セキュリティ観点を常設したいプロジェクト向けに `.aidd/design-perspectives.md` への追加を案内

## 0.17.0 (2026-07-17)

Integrate with the new stdd plugin (scientific test-design method catalog, split out of the aidd domain the same way uidd was): aidd keeps perspective listing and method-applicability flags; derivation procedures and citations live in stdd.

- `test-perspectives.md`: the 境界値 category now flags perspectives with "BVA適用" (ordered values: numeric ranges, lengths, dates) or "ECP適用" (inputs partitionable into valid/invalid classes) — flag judgment only, derivation steps and sources stay in stdd
- `test-perspectives.md`: point case derivation to stdd's `/stdd:test-design`, which takes the saved perspectives file as input (only when stdd is installed)
- README: add a uidd-style one-line pointer to stdd (no duplicated assets; aidd owns perspectives + flags only)

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
