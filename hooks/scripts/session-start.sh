#!/bin/bash
# SessionStart hook: surface aidd assets so they are used without relying on memory.

cat <<'EOF'
aidd plugin: run /aidd:design-review before presenting a design or implementation approach; run /aidd:test-perspectives before committing. Agents: aidd:scout (haiku, parallel fact-finding), aidd:reviewer (sonnet, deliverable acceptance check).
EOF

# aidd assumes superpowers for the implementation phase (brainstorming/TDD/debugging/plans);
# it only covers design and review. Warn, don't block — detection is best-effort.
INSTALLED_PLUGINS="$HOME/.claude/plugins/installed_plugins.json"
if [ -f "$INSTALLED_PLUGINS" ]; then
  if ! grep -q '"superpowers@' "$INSTALLED_PLUGINS" 2>/dev/null; then
    echo "aidd: superpowers plugin not detected. aidd covers design/review only and assumes superpowers for the implementation phase (brainstorming, TDD, debugging, plans). Install: /plugin marketplace add obra/superpowers && /plugin install superpowers@..."
  fi
fi

# Retro nudge: every 20th session, suggest an asset stocktake.
# State lives outside the plugin cache so it survives `/plugin update`.
STATE_DIR="$HOME/.claude/aidd"
STATE_FILE="$STATE_DIR/state.json"
NUDGE_EVERY=20

mkdir -p "$STATE_DIR" 2>/dev/null

count=0
if [ -f "$STATE_FILE" ]; then
  count=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('session_count', 0))" 2>/dev/null)
  [ -z "$count" ] && count=0
fi
count=$((count + 1))

python3 -c "import json; json.dump({'session_count': $count}, open('$STATE_FILE', 'w'))" 2>/dev/null

if [ $((count % NUDGE_EVERY)) -eq 0 ]; then
  echo "aidd: ${count} sessions since tracking began. Consider running /aidd:retro to check for repeated prompts worth promoting, or hooks/skills causing friction."
fi

exit 0
