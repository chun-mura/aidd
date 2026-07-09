#!/bin/bash
# PostToolUse hook (Bash matcher): after a git push, remind to sync the open
# PR's title/body if the pushed commits changed its scope.
# Non-blocking: only adds context. PR existence is checked by the model, not
# here, to keep the hook fast and network-free.
input=$(cat)

if printf '%s' "$input" | grep -qE 'git[[:space:]]+push'; then
  cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"aidd: push したブランチに open PR がある場合 (gh pr view で確認)、追加コミットが PR の範囲・内容を変えたなら gh pr edit でタイトルと概要を最新化すること (日本語)。変えていなければ何もしない。"}}
EOF
fi
exit 0
