#!/bin/bash
# SessionStart hook: surface aidd assets so they are used without relying on memory.
# The agent roster is omitted on purpose — it already appears in the system prompt's agent list.

echo 'aidd: 設計案は design-review、不明点は確認、コミット前は test-perspectives を検討。'

# Standing instruction, injected once per session (was a per-prompt UserPromptSubmit hook;
# once in context it stays effective, so re-injecting every prompt only burned tokens).
# The wording names no single channel on purpose: naming AskUserQuestion sent supervised
# workers and non-interactive runs (print mode, scheduled sessions) toward a tool with nobody
# to answer it, instead of the channel back to whoever dispatched them. Keep it one short
# sentence per the token-optimization spec — this text enters every session.
# Opt-out: set AIDD_DISABLE_CLARIFY_NUDGE=1 (shell env or settings.json "env").
if [ "$AIDD_DISABLE_CLARIFY_NUDGE" != "1" ]; then
  cat <<'EOF'
aidd: if a request has ambiguities that would change the implementation or design, confirm them instead of guessing — AskUserQuestion if interactive, otherwise back to whoever dispatched this session; if neither exists, state the assumption in your final report. For trivial choices, use sensible defaults.
EOF
fi

# Periodic nudge for /aidd:asset-audit, only once the project's audit is overdue: counted from
# the last audit (written by that command), or, before the first one, from when
# aidd-hook-log.sh began recording its first hook here. Neither present means the project
# never opted in. File mtimes via find -mmin keep this portable between BSD and GNU without
# date parsing. The key is derived as in aidd-hook-log.sh (one per repository, worktrees
# included). Opt-out: set AIDD_DISABLE_AUDIT_NUDGE=1. Interval: AIDD_AUDIT_INTERVAL_DAYS
# (default 30; forced to base 10 and capped at 5 digits so "08" or a huge value can't break it).
if [ "$AIDD_DISABLE_AUDIT_NUDGE" != "1" ]; then
  interval_days=${AIDD_AUDIT_INTERVAL_DAYS:-30}
  case "$interval_days" in '' | *[!0-9]* | ??????*) interval_days=30 ;; esac
  interval_days=$((10#$interval_days))
  project_root=${CLAUDE_PROJECT_DIR:-$PWD}
  common_dir=$(git -C "$project_root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) &&
    project_root=$(dirname "$common_dir")
  project_key=$(printf '%s' "$project_root" | tr -c 'A-Za-z0-9' '-')
  project_state="${AIDD_TEST_STATE_DIR:-$HOME/.claude/aidd}/projects/$project_key"
  if [ -e "$project_state/asset-audit.last" ]; then
    overdue=$(find "$project_state/asset-audit.last" -mmin +$((interval_days * 1440)) 2>/dev/null)
  else
    overdue=$(find "$project_state/hook-log" -maxdepth 1 -name '*.since' -mmin +$((interval_days * 1440)) 2>/dev/null | head -n 1)
  fi
  if [ -n "$overdue" ]; then
    echo "aidd: このプロジェクトの .claude/ と CLAUDE.md の棚卸しが${interval_days}日以上行われていないため、/aidd:asset-audit の実行を検討してください。"
  fi
fi

# aidd assumes superpowers for the implementation phase (brainstorming/TDD/debugging/plans);
# it only covers design and review. Warn, don't block — detection is best-effort.
INSTALLED_PLUGINS="$HOME/.claude/plugins/installed_plugins.json"
if [ -f "$INSTALLED_PLUGINS" ]; then
  if ! grep -q '"superpowers@' "$INSTALLED_PLUGINS" 2>/dev/null; then
    echo "aidd: superpowers plugin not detected. aidd covers design/review only and assumes superpowers for the implementation phase (brainstorming, TDD, debugging, plans). Install: /plugin marketplace add obra/superpowers && /plugin install superpowers@..."
  fi
fi

exit 0
