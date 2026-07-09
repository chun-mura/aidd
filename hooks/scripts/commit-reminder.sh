#!/bin/bash
# PreToolUse hook (Bash matcher): inject a reminder when a git commit is about to run,
# unless test-perspectives output was saved recently (within the last 6 hours).
# Non-blocking: never denies the tool call, only adds context.
input=$(cat)

if printf '%s' "$input" | grep -qE 'git[[:space:]]+commit'; then
  recent_perspectives=$(find docs/test-perspectives -name '*.md' -mmin -360 2>/dev/null | head -1)
  if [ -z "$recent_perspectives" ]; then
    cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"aidd: if /aidd:test-perspectives has not been run for this change, run it before committing (skip for docs-only or trivial changes)."}}
EOF
  fi
fi
exit 0
