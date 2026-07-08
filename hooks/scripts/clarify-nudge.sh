#!/bin/bash
# UserPromptSubmit hook: standing instruction to ask instead of guessing.
# Conditional wording keeps trivial tasks from turning into question storms.
cat <<'EOF'
aidd: if the request has ambiguities that would change the implementation or design, confirm them via AskUserQuestion before proceeding instead of guessing. For trivial choices, proceed with sensible defaults.
EOF
exit 0
