# 実行担当の記録: data-error-standard 試行 1

| 項目 | 値 |
|---|---|
| session_id | 2c81128f-ede4-426b-a9f5-214674e4a1d7 |
| Claude Code (init) | 2.1.332 |
| メインのモデル (init) | claude-opus-5-5 |
| permissionMode | auto |
| cwd | [input] |
| 終了 | success / is_error=False |
| duration_ms | 97909 |
| num_turns | 2 |
| total_cost_usd | 0.9375655 |
| プラグイン (init) | aidd 0.93.0; orca-agent-view 0.2.0; codex 1.0.6; commit-commands 1.0.1; skill-creator None; pr-review-toolkit 1.0.1; superpowers 6.1.1; reqd 0.6.0; uidd 0.9.0; stdd 0.7.0; estimate 0.14.0; pptx-toolkit 0.1.0; cc-plugin-sec-default None; cc-plugin-agents-md None; cc-plugin-telemetry None; cc-plugin-privacy None; cc-plugin-plugin-authoring None |
| 読み込まれた aidd | 0.93.0 aidd@inline [input]/plugin |
| 判定 | 検出なし (stream-json に残った tool_use に限る) |

## モデル別 (modelUsage)

| モデル | provider | costBasis | input | output | cache read | cache creation | costUSD |
|---|---|---|---|---|---|---|---|
| claude-opus-5-5 | firstParty | list | 14 | 10617 | 351933 | 51766 | 0.6969105999999999 |
| claude-sonnet-5-5 | firstParty | list | 20 | 10903 | 101824 | 48561 | 0.24065490000000003 |

## agent 別 (task_notification の usage.total_tokens)

| tool_use_id | subagent_type | status | total_tokens |
|---|---|---|---|
| toolu_01Dresk3FYsf1XM3vDoWX7bj | aidd:reviewer | completed | 21480 |
| toolu_01S9Ff9VALWRL19uAEpt7xaQ | aidd:reviewer | completed | 19777 |
| toolu_0121yejs8T3ppRzR8pcyvmcn | aidd:reviewer | completed | 19834 |
| toolu_01DUDwE3RAoajxuuaPcL8U8k | aidd:refuter | completed | 21023 |

## 作業ディレクトリの外・元リポジトリ・keys・results への参照 (tool_use)

なし
