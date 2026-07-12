#!/bin/bash
# UserPromptSubmit hook: standing instruction to ask instead of guessing.
# Conditional wording keeps trivial tasks from turning into question storms.
# Opt-out: set AIDD_DISABLE_CLARIFY_NUDGE=1 (shell env or settings.json "env").
[ "$AIDD_DISABLE_CLARIFY_NUDGE" = "1" ] && exit 0
cat <<'EOF'
aidd: if the request has ambiguities that would change the implementation or design, confirm them via AskUserQuestion before proceeding instead of guessing. For trivial choices, proceed with sensible defaults.
EOF
exit 0
