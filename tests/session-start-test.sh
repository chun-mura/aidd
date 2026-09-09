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
printf '%s\n' "$nudge" | grep -F 'AskUserQuestion if interactive'
printf '%s\n' "$nudge" | grep -F 'otherwise back to whoever dispatched this session'
if printf '%s\n' "$nudge" | grep -Fq 'confirm them via AskUserQuestion'; then
  exit 1
fi

# The opt-out still removes the nudge entirely.
if printf '%s\n' "$output" | grep -Fq 'AskUserQuestion'; then
  exit 1
fi

# The nudge enters every session, so its length is part of the contract
# (docs/superpowers/specs/2026-07-18-token-optimization-design.md, 方針 6: 常時注入を短文化する).
nudge_len=$(printf '%s' "$nudge" | grep '^aidd: if' | wc -c | tr -d ' ')
if [ "$nudge_len" -gt 320 ]; then
  echo "clarify nudge too long: $nudge_len chars" >&2
  exit 1
fi
