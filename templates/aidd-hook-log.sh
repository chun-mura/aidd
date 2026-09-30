#!/bin/bash
# Wraps one of a consumer project's own hooks (declared in its .claude/settings.json) and
# records that it fired, for /aidd:asset-audit. Copy into the consumer project, e.g.
# .claude/hooks/aidd-hook-log.sh, and prefix the existing hook command:
#   aidd-hook-log.sh <hook-id> <command> [args...]
# The wrapped hook sees the same stdin, env and cwd; its stdout/stderr pass through untouched
# and its exit code is returned as-is, so wrapping never changes what the hook does.
# Records go only under ~/.claude/aidd/ and are never sent anywhere.
# Opt-out: set AIDD_DISABLE_HOOK_LOG=1 (shell env or settings.json "env").

if [ "$#" -lt 2 ]; then
  echo "usage: aidd-hook-log.sh <hook-id> <command> [args...]" >&2
  exit 1
fi

hook_id=$1
shift

[ "$AIDD_DISABLE_HOOK_LOG" = "1" ] && exec "$@"

# Keep stdin byte-exact for the wrapped hook: the trailing sentinel stops $(...) from
# stripping trailing newlines.
input=$(cat; printf x)
input=${input%x}

# A hook that exits without reading stdin breaks the pipe; that write error is the wrapper's,
# not the hook's, so it must not reach the hook's stderr.
{ printf '%s' "$input"; } 2>/dev/null | "$@"
rc=${PIPESTATUS[1]}

# Logging must never affect the hook, so every failure below is swallowed.
{
  # The id becomes a file name; anything outside [A-Za-z0-9._-] is replaced.
  safe_id=$(printf '%s' "$hook_id" | tr -c 'A-Za-z0-9._-' '_')
  project_key=$(printf '%s' "${CLAUDE_PROJECT_DIR:-$PWD}" | tr -c 'A-Za-z0-9' '-')
  log_dir="${AIDD_TEST_STATE_DIR:-$HOME/.claude/aidd}/projects/$project_key/hook-log"
  log_file="$log_dir/$safe_id.jsonl"
  mkdir -p "$log_dir"

  # Marks when recording began, so the audit can tell "never fired" from "not recorded yet".
  [ -e "$log_dir/.since" ] || : > "$log_dir/.since"

  event=$(printf '%s' "$input" | grep -o '"hook_event_name"[[:space:]]*:[[:space:]]*"[A-Za-z]*"' | head -n 1 | sed 's/.*"\([A-Za-z]*\)"$/\1/')
  # Exit 2 is the hook deliberately blocking, not a failure.
  case "$rc" in
    0) status=ok ;;
    2) status=block ;;
    *) status=error ;;
  esac
  printf '{"ts":"%s","event":"%s","status":"%s","exit":%d}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$event" "$status" "$rc" >> "$log_file"

  # Bounded per hook: a noisy hook trims only its own file, so a rarely firing hook's
  # last record is never pushed out by another hook.
  if [ "$(wc -c < "$log_file")" -gt 262144 ]; then
    tail -n 1000 "$log_file" > "$log_file.tmp" && mv "$log_file.tmp" "$log_file"
  fi
} 2>/dev/null

exit "$rc"
