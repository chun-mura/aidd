#!/bin/bash
# Event-aware Bash hook dispatcher. Non-matching commands produce no context.
input=$(cat)

read -r event cmd < <(printf '%s' "$input" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get("hook_event_name", ""), data.get("tool_input", {}).get("command", ""))
except Exception:
    print("", "")
' 2>/dev/null)

case "$event:$cmd" in
  PreToolUse:* )
    if [[ "$cmd" =~ git[[:space:]]+commit ]]; then
      staged=$(git diff --cached --name-only 2>/dev/null)
      if [ -n "$staged" ] && ! printf '%s\n' "$staged" | grep -qvE '(^docs/|\.md$|\.txt$)'; then
        exit 0
      fi
      recent_perspectives=$(find docs/test-perspectives -name '*.md' -mmin -360 2>/dev/null | head -1)
      if [ -z "$recent_perspectives" ]; then
        cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"aidd: if /aidd:test-perspectives has not been run for this change, run it before committing (skip for docs-only or trivial changes)."}}
EOF
      fi
    elif [[ "$cmd" =~ gh[[:space:]]+(pr|issue)[[:space:]]+(create|edit) ]]; then
      cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"aidd: GitHub issue/PR のタイトルと本文は日本語で書くこと (コード識別子・コマンド・コミットメッセージは英語のまま)。既に日本語なら変更不要。"}}
EOF
    fi
    ;;
  PostToolUse:* )
    if [[ "$cmd" =~ git[[:space:]]+push ]]; then
      cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"aidd: push したブランチに open PR がある場合 (gh pr view で確認)、追加コミットが PR の範囲・内容を変えたなら gh pr edit でタイトルと概要を最新化すること (日本語)。変えていなければ何もしない。"}}
EOF
    fi
    ;;
esac

exit 0
