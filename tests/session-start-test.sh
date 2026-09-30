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

# Asset-audit nudge: only once the project's audit is overdue, measured from the last audit
# (written by /aidd:asset-audit) or, before the first one, from when aidd-hook-log.sh began.
audit_tmp=$(mktemp -d)
trap 'rm -rf "$audit_tmp"' EXIT
project_dir="$audit_tmp/project"
mkdir -p "$project_dir"
project_state="$audit_tmp/aidd/projects/$(printf '%s' "$project_dir" | tr -c 'A-Za-z0-9' '-')"
run_start() {
  CLAUDE_PROJECT_DIR="$project_dir" AIDD_TEST_STATE_DIR="$audit_tmp/aidd" AIDD_DISABLE_CLARIFY_NUDGE=1 \
    bash "$repo_root/hooks/scripts/session-start.sh"
}
old_stamp=$(python3 -c 'import time; print(time.strftime("%Y%m%d%H%M", time.localtime(time.time() - 40 * 86400)))')

# Never audited and nothing recorded: the project has not opted in, so no nudge.
if run_start | grep -Fq '/aidd:asset-audit'; then
  exit 1
fi

# Only a hook wrapped recently: recording has not run for the interval yet, so no nudge.
mkdir -p "$project_state/hook-log"
: > "$project_state/hook-log/lint.since"
if run_start | grep -Fq '/aidd:asset-audit'; then
  exit 1
fi

# Recording of the first hook began 40 days ago and no audit since: nudge.
touch -t "$old_stamp" "$project_state/hook-log/format.since"
run_start | grep -F '/aidd:asset-audit'

# A recent audit takes precedence over the old recording start: no nudge.
date +%F > "$project_state/asset-audit.last"
if run_start | grep -Fq '/aidd:asset-audit'; then
  exit 1
fi

# The audit itself is 40 days old: nudge, stating the default 30-day interval.
touch -t "$old_stamp" "$project_state/asset-audit.last"
audit_nudge=$(run_start | grep -F '/aidd:asset-audit')
printf '%s\n' "$audit_nudge" | grep -F '30日以上'

# The interval is configurable; 60 days is not yet overdue at 40.
if AIDD_AUDIT_INTERVAL_DAYS=60 run_start | grep -Fq '/aidd:asset-audit'; then
  exit 1
fi

# The interval is read in base 10: "08" is 8 days (overdue at 40), not a shell error.
AIDD_AUDIT_INTERVAL_DAYS=08 run_start 2> "$audit_tmp/err" | grep -F '8日以上'
[ ! -s "$audit_tmp/err" ]

# A value too long to be a day count falls back to the default instead of overflowing:
# a fresh audit must still suppress the nudge.
date +%F > "$project_state/asset-audit.last"
if AIDD_AUDIT_INTERVAL_DAYS=9999999999999999999 run_start | grep -Fq '/aidd:asset-audit'; then
  exit 1
fi
touch -t "$old_stamp" "$project_state/asset-audit.last"

# Opt-out removes it.
if AIDD_DISABLE_AUDIT_NUDGE=1 run_start | grep -Fq '/aidd:asset-audit'; then
  exit 1
fi

# One key per repository: a session started in a worktree reads the audit recorded for the
# main checkout (a fresh one suppresses the nudge, an old one shows it).
repo="$audit_tmp/repo"
mkdir -p "$repo"
git_env=(env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1)
"${git_env[@]}" git -C "$repo" init -q
"${git_env[@]}" git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
"${git_env[@]}" git -C "$repo" worktree add -q "$audit_tmp/wt"
repo_key=$(printf '%s' "$(dirname "$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)")" | tr -c 'A-Za-z0-9' '-')
mkdir -p "$audit_tmp/aidd/projects/$repo_key"
touch -t "$old_stamp" "$audit_tmp/aidd/projects/$repo_key/asset-audit.last"
run_in_worktree() {
  CLAUDE_PROJECT_DIR="$audit_tmp/wt" AIDD_TEST_STATE_DIR="$audit_tmp/aidd" AIDD_DISABLE_CLARIFY_NUDGE=1 \
    bash "$repo_root/hooks/scripts/session-start.sh"
}
run_in_worktree | grep -F '/aidd:asset-audit'
date +%F > "$audit_tmp/aidd/projects/$repo_key/asset-audit.last"
if run_in_worktree | grep -Fq '/aidd:asset-audit'; then
  exit 1
fi

# One short sentence: it may enter any session.
audit_len=$(printf '%s' "$audit_nudge" | wc -c | tr -d ' ')
if [ "$audit_len" -gt 240 ]; then
  echo "asset-audit nudge too long: $audit_len bytes" >&2
  exit 1
fi
