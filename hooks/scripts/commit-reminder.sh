#!/bin/bash
# PreToolUse hook (Bash matcher): inject a reminder when a git commit is about to run.
# Non-blocking: never denies the tool call, only adds context.
input=$(cat)

if printf '%s' "$input" | grep -qE 'git[[:space:]]+commit'; then
  cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"aidd: if /aidd:test-perspectives has not been run for this change, run it before committing (skip for docs-only or trivial changes)."}}
EOF
fi
exit 0
