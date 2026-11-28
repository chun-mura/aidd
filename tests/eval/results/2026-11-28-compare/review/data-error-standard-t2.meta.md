# 実行担当の記録: data-error-standard 試行 2

| 項目 | 値 |
|---|---|
| session_id | 49bdaa1e-d4db-45e9-badc-2c3604f76f5b |
| Claude Code (init) | 2.1.332 |
| メインのモデル (init) | claude-opus-5-5 |
| permissionMode | auto |
| cwd | [input] |
| 終了 | success / is_error=False |
| duration_ms | 94613 |
| num_turns | 2 |
| total_cost_usd | 0.9275308999999999 |
| プラグイン (init) | aidd 0.93.0; orca-agent-view 0.2.0; codex 1.0.6; commit-commands 1.0.1; skill-creator None; pr-review-toolkit 1.0.1; superpowers 6.1.1; reqd 0.6.0; uidd 0.9.0; stdd 0.7.0; estimate 0.14.0; pptx-toolkit 0.1.0; cc-plugin-sec-default None; cc-plugin-agents-md None; cc-plugin-telemetry None; cc-plugin-privacy None; cc-plugin-plugin-authoring None |
| 読み込まれた aidd | 0.93.0 aidd@inline [input]/plugin |
| 判定 | 検出なし (stream-json に残った tool_use に限る) |

## モデル別 (modelUsage)

| モデル | provider | costBasis | input | output | cache read | cache creation | costUSD |
|---|---|---|---|---|---|---|---|
| claude-opus-5-5 | firstParty | list | 14 | 10215 | 357111 | 48568 | 0.6643222 |
| claude-sonnet-5-5 | firstParty | list | 20 | 13033 | 101537 | 49074 | 0.26320869999999996 |

## agent 別 (task_notification の usage.total_tokens)

| tool_use_id | subagent_type | status | total_tokens |
|---|---|---|---|
| toolu_01Dd2ZosZioDjEBQ8yG4etZZ | aidd:reviewer | completed | 23010 |
| toolu_01KLEBZB6R94McegKZpfFtU3 | aidd:reviewer | completed | 20172 |
| toolu_016LwgaYxoBuiNEbV2RFjLMx | aidd:reviewer | completed | 19372 |
| toolu_01QLzgY1BNzTWiLpX6i1uHK9 | aidd:refuter | completed | 21481 |

## 作業ディレクトリの外・元リポジトリ・keys・results への参照 (tool_use)

なし
