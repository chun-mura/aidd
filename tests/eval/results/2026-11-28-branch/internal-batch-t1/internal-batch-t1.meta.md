# 実行担当の記録: internal-batch 試行 1

| 項目 | 値 |
|---|---|
| session_id | 20e3fe64-cca3-458d-9a04-7bee1c5af1b8 |
| Claude Code (init) | 2.1.332 |
| メインのモデル (init) | claude-opus-5-5 |
| permissionMode | auto |
| cwd | [input] |
| 終了 | success / is_error=False |
| duration_ms | 83347 |
| num_turns | 2 |
| total_cost_usd | 0.9240121 |
| プラグイン (init) | aidd 0.98.0; orca-agent-view 0.2.0; codex 1.0.6; commit-commands 1.0.1; skill-creator None; pr-review-toolkit 1.0.1; superpowers 6.1.1; reqd 0.6.0; uidd 0.9.0; stdd 0.7.0; estimate 0.14.0; pptx-toolkit 0.1.0; cc-plugin-sec-default None; cc-plugin-agents-md None; cc-plugin-telemetry None; cc-plugin-privacy None; cc-plugin-plugin-authoring None |
| 読み込まれた aidd | 0.98.0 aidd@inline [input]/plugin |
| 判定 | 検出なし (stream-json に残った tool_use に限る) |

## モデル別 (modelUsage)

| モデル | provider | costBasis | input | output | cache read | cache creation | costUSD |
|---|---|---|---|---|---|---|---|
| claude-opus-5-5 | firstParty | list | 18 | 11412 | 420709 | 52344 | 0.7312058 |
| claude-sonnet-5-5 | firstParty | list | 16 | 7623 | 49968 | 44619 | 0.1928063 |

## agent 別 (task_notification の usage.total_tokens)

| tool_use_id | subagent_type | status | total_tokens |
|---|---|---|---|
| toolu_01PVuDfRMUrZhWTE3BYJGkny | aidd:reviewer | completed | 14125 |
| toolu_01DDaUjGamp4yfD3GhdK2MNK | aidd:reviewer | completed | 15106 |
| toolu_01PKCDuw5wnCJZXcjmg21RJ7 | aidd:reviewer | completed | 13405 |
| toolu_01QfX15sveQset7cGq3Yyq3C | aidd:refuter | completed | 14704 |

## 作業ディレクトリの外・元リポジトリ・keys・results への参照 (tool_use)

なし
