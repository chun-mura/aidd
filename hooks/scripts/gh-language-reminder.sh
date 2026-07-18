#!/bin/bash
# PreToolUse hook (Bash matcher): inject a language reminder when a GitHub
# issue/PR is about to be created or edited via gh.
# Non-blocking: never denies the tool call, only adds context.
# Matches only tool_input.command, not the whole stdin payload, to avoid false fires.
input=$(cat)

cmd=$(printf '%s' "$input" | python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('tool_input', {}).get('command', ''))
except Exception:
    print('')
" 2>/dev/null)

if printf '%s' "$cmd" | grep -qE 'gh[[:space:]]+(pr|issue)[[:space:]]+(create|edit)'; then
  cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"aidd: GitHub issue/PR のタイトルと本文は日本語で書くこと (コード識別子・コマンド・コミットメッセージは英語のまま)。既に日本語なら変更不要。"}}
EOF
fi
exit 0
