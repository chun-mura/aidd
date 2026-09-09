#!/bin/bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
output=$(AIDD_DISABLE_CLARIFY_NUDGE=1 bash "$repo_root/hooks/scripts/session-start.sh")

printf '%s\n' "$output" | grep -F 'aidd: 設計案は design-review'
if printf '%s\n' "$output" | grep -Fq '/aidd:retro'; then
  exit 1
fi

# The nudge must not pin confirmation to a single channel: naming only AskUserQuestion made
# supervised workers and non-interactive runs call a tool nobody answers.
nudge=$(bash "$repo_root/hooks/scripts/session-start.sh")
printf '%s\n' "$nudge" | grep -F 'AskUserQuestion in an interactive session'
printf '%s\n' "$nudge" | grep -F 'the channel back to whoever dispatched this session'
if printf '%s\n' "$nudge" | grep -Fq 'confirm them via AskUserQuestion'; then
  exit 1
fi

# The opt-out still removes the nudge entirely.
if printf '%s\n' "$output" | grep -Fq 'AskUserQuestion'; then
  exit 1
fi
