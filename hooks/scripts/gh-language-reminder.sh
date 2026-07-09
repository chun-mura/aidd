#!/bin/bash
# PreToolUse hook (Bash matcher): inject a language reminder when a GitHub
# issue/PR is about to be created or edited via gh.
# Non-blocking: never denies the tool call, only adds context.
input=$(cat)

if printf '%s' "$input" | grep -qE 'gh[[:space:]]+(pr|issue)[[:space:]]+(create|edit)'; then
  cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"aidd: GitHub issue/PR のタイトルと本文は日本語で書くこと (コード識別子・コマンド・コミットメッセージは英語のまま)。既に日本語なら変更不要。"}}
EOF
fi
exit 0
