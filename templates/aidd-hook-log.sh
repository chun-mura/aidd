#!/bin/bash
# Wraps one of a consumer project's own hooks (declared in its .claude/settings.json) and
# records that it fired, for /aidd:asset-audit. Copy into the consumer project, e.g.
# .claude/hooks/aidd-hook-log.sh, and prefix the existing hook command:
#   aidd-hook-log.sh <hook-id> <command> [args...]
# The wrapped hook sees the same stdin, env and cwd; its stdout/stderr pass through untouched
# and its exit code is returned as-is, so wrapping never changes what the hook does. If the
# wrapper is terminated (TERM/HUP/INT, e.g. a hook timeout), the hook is terminated too and
# the wrapper dies of the same signal, as an unwrapped hook would.
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

# Logging must never affect the hook, so every failure in it is swallowed.
{
  # The id becomes a file name; anything outside [A-Za-z0-9._-] is replaced.
  safe_id=$(printf '%s' "$hook_id" | tr -c 'A-Za-z0-9._-' '_')
  # One key per repository, worktrees included: hooks get CLAUDE_PROJECT_DIR (where the
  # session started) while /aidd:asset-audit runs wherever the model's shell is, so both
  # resolve the shared git directory. The paths are only a fallback outside git.
  project_root=${CLAUDE_PROJECT_DIR:-$PWD}
  common_dir=$(git -C "$project_root" rev-parse --path-format=absolute --git-common-dir) &&
    project_root=$(dirname "$common_dir")
  project_key=$(printf '%s' "$project_root" | tr -c 'A-Za-z0-9' '-')
  log_dir="${AIDD_TEST_STATE_DIR:-$HOME/.claude/aidd}/projects/$project_key/hook-log"
  log_file="$log_dir/$safe_id.jsonl"
  mkdir -p "$log_dir"

  # Marks when recording of this hook began, so the audit can tell "never fired" from
  # "not recorded yet" for a hook wrapped later than the others.
  [ -e "$log_dir/$safe_id.since" ] || : > "$log_dir/$safe_id.since"

  event=$(printf '%s' "$input" | grep -o '"hook_event_name"[[:space:]]*:[[:space:]]*"[A-Za-z]*"' | head -n 1 | sed 's/.*"\([A-Za-z]*\)"$/\1/')
} 2>/dev/null

# log_line <status> [<exit>]
log_line() {
  {
    if [ -n "$2" ]; then
      printf '{"ts":"%s","event":"%s","status":"%s","exit":%d}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$event" "$1" "$2"
    else
      printf '{"ts":"%s","event":"%s","status":"%s"}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$event" "$1"
    fi >> "$log_file"
  } 2>/dev/null
}

# The hook runs in the background so a signal reaches this trap at once instead of after the
# hook exits; the trap passes it on, so a timed-out hook is not left running as an orphan.
# bash starts background commands with INT ignored, so INT is passed on as TERM.
child=
# shellcheck disable=SC2317,SC2329 # invoked from the traps below
on_signal() {
  if [ -n "$child" ]; then
    if [ "$1" = INT ]; then kill -TERM "$child"; else kill -s "$1" "$child"; fi
    wait "$child"
  fi 2>/dev/null
  log_line killed "$2"
  trap - "$1"
  kill -s "$1" "$$"
  exit "$2"
}
trap 'on_signal TERM 143' TERM
trap 'on_signal HUP 129' HUP
trap 'on_signal INT 130' INT

# Written before the hook runs: a start line with no end line after it means the hook was
# killed where no trap can run (SIGKILL), so the audit still sees it fired and broke.
log_line start

# A hook that exits without reading stdin breaks the pipe; that write error is the wrapper's,
# not the hook's, so it must not reach the hook's stderr.
{ printf '%s' "$input"; } 2>/dev/null | "$@" &
child=$!
wait "$child"
rc=$?

# Exit 2 is the hook deliberately blocking, not a failure.
case "$rc" in
  0) log_line ok "$rc" ;;
  2) log_line block "$rc" ;;
  *) log_line error "$rc" ;;
esac

# Bounded per hook: a noisy hook trims only its own file, so a rarely firing hook's
# last record is never pushed out by another hook. A unique temp file keeps concurrent
# firings from overwriting each other's trimmed copy.
{
  if [ "$(wc -c < "$log_file")" -gt 262144 ]; then
    tmp_file=$(mktemp "$log_file.XXXXXX") &&
      tail -n 1000 "$log_file" > "$tmp_file" && mv "$tmp_file" "$log_file"
    [ -n "$tmp_file" ] && rm -f "$tmp_file"
  fi
} 2>/dev/null

exit "$rc"
