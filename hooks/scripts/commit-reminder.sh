#!/bin/bash
# PreToolUse hook (Bash matcher): inject a reminder when a git commit is about to run,
# unless test-perspectives output was saved recently (within the last 6 hours)
# or the staged changes are docs-only (the reminder itself says to skip those).
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

if printf '%s' "$cmd" | grep -qE 'git[[:space:]]+commit'; then
  staged=$(git diff --cached --name-only 2>/dev/null)
  if [ -n "$staged" ] && ! printf '%s\n' "$staged" | grep -qvE '(^docs/|\.md$|\.txt$)'; then
    exit 0
  fi
  recent_perspectives=$(find docs/test-perspectives -name '*.md' -mmin -360 2>/dev/null | head -1)
  if [ -z "$recent_perspectives" ]; then
    cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"aidd: if /aidd:test-perspectives has not been run for this change, run it before committing (skip for docs-only or trivial changes)."}}
EOF
  fi
fi
exit 0
