#!/bin/bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
output=$(AIDD_DISABLE_CLARIFY_NUDGE=1 bash "$repo_root/hooks/scripts/session-start.sh")

printf '%s\n' "$output" | grep -F 'aidd: 設計案は design-review'
if printf '%s\n' "$output" | grep -Fq '/aidd:retro'; then
  exit 1
fi
