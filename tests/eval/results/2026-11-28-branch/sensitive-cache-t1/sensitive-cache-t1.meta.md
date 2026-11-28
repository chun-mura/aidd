# 実行担当の記録: sensitive-cache 試行 1

| 項目 | 値 |
|---|---|
| session_id | b53a9eca-2213-4b10-b8b3-bcf1e436b41d |
| Claude Code (init) | 2.1.332 |
| メインのモデル (init) | claude-opus-5-5 |
| permissionMode | auto |
| cwd | [input] |
| 終了 | success / is_error=False |
| duration_ms | 115022 |
| num_turns | 2 |
| total_cost_usd | 1.1356530999999999 |
| プラグイン (init) | aidd 0.98.0; orca-agent-view 0.2.0; codex 1.0.6; commit-commands 1.0.1; skill-creator None; pr-review-toolkit 1.0.1; superpowers 6.1.1; reqd 0.6.0; uidd 0.9.0; stdd 0.7.0; estimate 0.14.0; pptx-toolkit 0.1.0; cc-plugin-sec-default None; cc-plugin-agents-md None; cc-plugin-telemetry None; cc-plugin-privacy None; cc-plugin-plugin-authoring None |
| 読み込まれた aidd | 0.98.0 aidd@inline [input]/plugin |
| 判定 | 検出なし (stream-json に残った tool_use に限る) |

## モデル別 (modelUsage)

| モデル | provider | costBasis | input | output | cache read | cache creation | costUSD |
|---|---|---|---|---|---|---|---|
| claude-opus-5-5 | firstParty | list | 20 | 13896 | 485951 | 57885 | 0.8382702 |
| claude-sonnet-5-5 | firstParty | list | 24 | 19707 | 99199 | 36138 | 0.2973829 |

## agent 別 (task_notification の usage.total_tokens)

| tool_use_id | subagent_type | status | total_tokens |
|---|---|---|---|
| toolu_01Y18XsoFBkUhEbZ4G6e1bR6 | aidd:reviewer | completed | 14550 |
| toolu_01Qp46cZsUxwhVJXu3hKdj1K | aidd:reviewer | completed | 18192 |
| toolu_01PgSQKEs1UHcAN33fUUqwvz | aidd:reviewer | completed | 14736 |
| toolu_012jwJR1UTsLaTK5cv2QEch1 | aidd:security-reviewer | completed | 18743 |
| toolu_01KrpL3vYLEET1AfeFcfgTxE | aidd:refuter | completed | 16722 |

## 作業ディレクトリの外・元リポジトリ・keys・results への参照 (tool_use)

なし
