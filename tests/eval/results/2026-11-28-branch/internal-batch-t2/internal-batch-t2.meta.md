# 実行担当の記録: internal-batch 試行 2

| 項目 | 値 |
|---|---|
| session_id | 39f7b837-33a2-4683-a81f-fea94fc16795 |
| Claude Code (init) | 2.1.332 |
| メインのモデル (init) | claude-opus-5-5 |
| permissionMode | auto |
| cwd | [input] |
| 終了 | success / is_error=False |
| duration_ms | 79475 |
| num_turns | 2 |
| total_cost_usd | 0.8072466 |
| プラグイン (init) | aidd 0.98.0; orca-agent-view 0.2.0; codex 1.0.6; commit-commands 1.0.1; skill-creator None; pr-review-toolkit 1.0.1; superpowers 6.1.1; reqd 0.6.0; uidd 0.9.0; stdd 0.7.0; estimate 0.14.0; pptx-toolkit 0.1.0; cc-plugin-sec-default None; cc-plugin-agents-md None; cc-plugin-telemetry None; cc-plugin-privacy None; cc-plugin-plugin-authoring None |
| 読み込まれた aidd | 0.98.0 aidd@inline [input]/plugin |
| 判定 | 検出なし (stream-json に残った tool_use に限る) |

## モデル別 (modelUsage)

| モデル | provider | costBasis | input | output | cache read | cache creation | costUSD |
|---|---|---|---|---|---|---|---|
| claude-opus-5-5 | firstParty | list | 18 | 9238 | 421379 | 49562 | 0.6656038 |
| claude-sonnet-5-5 | firstParty | list | 16 | 7317 | 69608 | 24592 | 0.1416428 |

## agent 別 (task_notification の usage.total_tokens)

| tool_use_id | subagent_type | status | total_tokens |
|---|---|---|---|
| toolu_01SjGyDwmxpR2Bfgk9zFnPSN | aidd:reviewer | completed | 13781 |
| toolu_018Joy5L6oiEU6cM1FifnQNn | aidd:reviewer | completed | 14704 |
| toolu_019vK54Mf8wj3wEk8THwPFGJ | aidd:reviewer | completed | 13430 |
| toolu_01BjCFnffRKjcX2rqCdDTN6D | aidd:refuter | completed | 14921 |

## 作業ディレクトリの外・元リポジトリ・keys・results への参照 (tool_use)

なし
