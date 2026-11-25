# 実行担当の記録: settings-fallback-claude 試行 2

| 項目 | 値 |
|---|---|
| session_id | c83665c6-0075-496d-8132-6ede807d2159 |
| Claude Code (init) | 2.1.332 |
| メインのモデル (init) | claude-opus-5-5 |
| permissionMode | auto |
| cwd | [input] |
| 終了 | success / is_error=False |
| duration_ms | 13446 |
| num_turns | 2 |
| total_cost_usd | 0.08976719999999999 |
| プラグイン (init) | orca-agent-view 0.2.0; codex 1.0.6; commit-commands 1.0.1; skill-creator None; pr-review-toolkit 1.0.1; superpowers 6.1.1; reqd 0.6.0; uidd 0.9.0; stdd 0.7.0; aidd 0.87.0; estimate 0.14.0; pptx-toolkit 0.1.0; cc-plugin-sec-default None; cc-plugin-agents-md None; cc-plugin-telemetry None; cc-plugin-privacy None; cc-plugin-plugin-authoring None |
| 読み込まれた aidd | 0.87.0 aidd@aidd ~/.claude/plugins/cache/aidd/aidd/0.87.0 |
| 判定 | 検出なし (stream-json に残った tool_use に限る) |

## モデル別 (modelUsage)

| モデル | provider | costBasis | input | output | cache read | cache creation | costUSD |
|---|---|---|---|---|---|---|---|
| claude-opus-5-5 | firstParty | list | 4 | 1412 | 66396 | 6029 | 0.08976719999999999 |

## agent 別 (task_notification の usage.total_tokens)

| tool_use_id | subagent_type | status | total_tokens |
|---|---|---|---|
| なし | | | |

## 作業ディレクトリの外・元リポジトリ・keys・results への参照 (tool_use)

なし
