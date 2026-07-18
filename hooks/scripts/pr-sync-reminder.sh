#!/bin/bash
# PostToolUse hook (Bash matcher): after a git push, remind to sync the open
# PR's title/body if the pushed commits changed its scope.
# Non-blocking: only adds context. PR existence is checked by the model, not
# here, to keep the hook fast and network-free.
# Matches only tool_input.command — PostToolUse stdin also contains the tool
# output, and grepping the whole payload fires on any output mentioning "git push".
input=$(cat)

cmd=$(printf '%s' "$input" | python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('tool_input', {}).get('command', ''))
except Exception:
    print('')
" 2>/dev/null)

if printf '%s' "$cmd" | grep -qE 'git[[:space:]]+push'; then
  cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"aidd: push したブランチに open PR がある場合 (gh pr view で確認)、追加コミットが PR の範囲・内容を変えたなら gh pr edit でタイトルと概要を最新化すること (日本語)。変えていなければ何もしない。"}}
EOF
fi
exit 0
