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
USAGE_FILE="$STATE_DIR/usage.json"
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
  if command -v jq >/dev/null 2>&1 && [ -f "$USAGE_FILE" ]; then
    usage_summary=$(jq -r '
      [
        (.command_counts // {})
        | to_entries
        | sort_by(-.value, .key)
        | .[:5][]
        | "- /aidd:\(.key): \(.value)"
      ] as $commands
      | [
          (.prompt_log // [])
          | map(.text[0:120])
          | group_by(.)
          | map({text: .[0], count: length})
          | map(select(.count > 1))
          | sort_by(-.count, .text)
          | .[:2][]
          | "Repeated prompts: \(.count)x: \(.text)"
        ] as $repeated
      | if ($commands | length) > 0 then $commands[] else "- no /aidd command usage recorded" end,
        if ($repeated | length) > 0 then $repeated[] else "Repeated prompts: none" end
    ' "$USAGE_FILE" 2>/dev/null)

    if [ -n "$usage_summary" ]; then
      echo "aidd: ${count} sessions since tracking began. aidd usage (top 5):"
      printf '%s\n' "$usage_summary"
      echo "/aidd:retro で棚卸し推奨"
      exit 0
    fi
  fi

  echo "aidd: ${count} sessions since tracking began. Consider running /aidd:retro to check for repeated prompts worth promoting, or hooks/skills causing friction."
fi

exit 0
