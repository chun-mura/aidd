#!/bin/bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

state_dir="$tmp_dir/aidd"
hook_copy="$tmp_dir/session-start.sh"
bin_dir="$tmp_dir/bin"
mkdir -p "$state_dir" "$bin_dir"

sed "s|STATE_DIR=\"\\\$HOME/.claude/aidd\"|STATE_DIR=\"$state_dir\"|" \
  "$repo_root/hooks/scripts/session-start.sh" > "$hook_copy"

jq -n '{session_count: 19}' > "$state_dir/state.json"
jq -n '
  {
    command_counts: {
      "design-review": 7,
      "retro": 3,
      "adr": 2,
      "doctor": 1,
      "test-perspectives": 1,
      "issue-split": 1
    },
    prompt_log: [
      {text: "設計レビューを実行してください"},
      {text: "設計レビューを実行してください"},
      {text: "設計レビューを実行してください"},
      {text: "ADRを作成してください"},
      {text: "ADRを作成してください"}
    ]
  }
' > "$state_dir/usage.json"

summary_output=$(bash "$hook_copy")
printf '%s\n' "$summary_output" | grep -F 'aidd usage (top 5):'
printf '%s\n' "$summary_output" | grep -F '/aidd:design-review: 7'
printf '%s\n' "$summary_output" | grep -F '/aidd:retro: 3'
printf '%s\n' "$summary_output" | grep -F 'Repeated prompts:'
printf '%s\n' "$summary_output" | grep -F '3x: 設計レビューを実行してください'
printf '%s\n' "$summary_output" | grep -F '/aidd:retro で棚卸し推奨'

summary_lines=$(printf '%s\n' "$summary_output" | wc -l | tr -d ' ')
[ "$summary_lines" -le 10 ]

jq -n '{session_count: 19}' > "$state_dir/state.json"
ln -s "$(command -v python3)" "$bin_dir/python3"
fallback_output=$(PATH="$bin_dir:/bin" /bin/bash "$hook_copy")
printf '%s\n' "$fallback_output" | grep -F 'aidd: 20 sessions since tracking began. Consider running /aidd:retro'
if printf '%s\n' "$fallback_output" | grep -Fq 'aidd usage (top 5):'; then
  exit 1
fi
