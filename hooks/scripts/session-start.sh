#!/bin/bash
# SessionStart hook: surface aidd assets so they are used without relying on memory.
cat <<'EOF'
aidd plugin: run /aidd:design-review before presenting a design or implementation approach; run /aidd:test-perspectives before committing. Agents: aidd:scout (haiku, parallel fact-finding), aidd:reviewer (sonnet, deliverable acceptance check).
EOF
exit 0
