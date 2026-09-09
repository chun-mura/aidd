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

# aidd assumes superpowers for the implementation phase (brainstorming/TDD/debugging/plans);
# it only covers design and review. Warn, don't block — detection is best-effort.
INSTALLED_PLUGINS="$HOME/.claude/plugins/installed_plugins.json"
if [ -f "$INSTALLED_PLUGINS" ]; then
  if ! grep -q '"superpowers@' "$INSTALLED_PLUGINS" 2>/dev/null; then
    echo "aidd: superpowers plugin not detected. aidd covers design/review only and assumes superpowers for the implementation phase (brainstorming, TDD, debugging, plans). Install: /plugin marketplace add obra/superpowers && /plugin install superpowers@..."
  fi
fi

exit 0
