---
description: aidd/superpowers の導入状態・バージョン整合・hooks 実行可否・Codex custom agents の導入を診断する
---

aidd プラグインの動作環境を診断してください。各チェックは独立に実行し、1項目の失敗が他の診断を止めないようにする。

**チェック項目**:

1. **superpowers 導入**: `claude plugin list --json` に `superpowers@` で始まり `enabled: true` のエントリがあるか (plugin.json の dependencies 宣言により通常は自動導入されるはずだが、古い Claude Code や依存解決エラーを検知する)
2. **バージョン整合**: `.claude-plugin/plugin.json` の `version` と、`~/.claude/plugins/installed_plugins.json` に記録された aidd のインストール済みバージョンを比較する。ズレていれば `push + /plugin update aidd` 忘れの可能性を指摘する
3. **hooks 実行権限**: `hooks/scripts/*.sh` それぞれに実行ビット (`x`) が付いているか (`ls -l` で確認)
4. **python3 存在**: `which python3` — hooks が python3 に依存しているため必須
5. **状態ファイルの妥当性**: `~/.claude/aidd/state.json` と `~/.claude/aidd/usage.json` が存在する場合、それぞれ有効な JSON としてパースできるか (存在しない場合はスキップ、エラーではない)
6. **adapter の素通り**: `~/.claude/aidd/adapter-skips.json` がある場合、直近の素通り理由と件数を表示する (`harness` / `event` / `tool_name` / `reason` / `count` / `last_seen`)。無い場合はスキップ
7. **Cursor fixture の版**: `adapter-skips.json` に記録された `harness_version` (`cursor_version`) が、設計書 `docs/superpowers/specs/2026-10-27-multi-harness-hooks-design.md` の実測版 (`2026.10.22-27dcf5f`) と違う場合、fixture を取り直すよう促す。記録が無い場合はスキップ
8. **Codex custom agents**: `scripts/install-codex-agents.sh --check` で、`~/.codex/agents/` の TOML がプラグイン正本と一致するか見る。未導入・版ずれなら同スクリプトの実行を促す。インストーラが見つからない場合はスキップせず WARN にする。Codex のプラグイン導入だけでは TOML は届かない

各項目を実行するには Bash tool で以下相当のコマンドを使う:

```bash
claude plugin list --json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
sp = next((p for p in data if p['id'].startswith('superpowers@') and p.get('enabled')), None)
print('superpowers: OK (%s)' % sp['id'] if sp else 'superpowers: WARN not detected or disabled')
"
python3 -c "import json; d=json.load(open('$HOME/.claude/plugins/installed_plugins.json')); print([v.get('version') for k,v in d.items() if k.startswith('aidd@')])" 2>/dev/null
cat .claude-plugin/plugin.json | python3 -c "import json,sys; print(json.load(sys.stdin)['version'])" 2>/dev/null
for f in hooks/scripts/*.sh; do [ -x "$f" ] && echo "$f: OK" || echo "$f: WARN not executable"; done
which python3 && echo "python3: OK" || echo "python3: WARN not found"
python3 -m json.tool ~/.claude/aidd/state.json > /dev/null 2>&1 && echo "state.json: OK" || echo "state.json: missing or invalid"
python3 -m json.tool ~/.claude/aidd/usage.json > /dev/null 2>&1 && echo "usage.json: OK" || echo "usage.json: missing or invalid"
python3 - <<'PY'
import json, os
path = os.path.expanduser("~/.claude/aidd/adapter-skips.json")
expected = "2026.10.22-27dcf5f"
if not os.path.isfile(path):
    print("adapter-skips: skip (no file)")
    raise SystemExit
try:
    data = json.load(open(path))
except Exception:
    print("adapter-skips: WARN invalid JSON")
    raise SystemExit
entries = data.get("entries") if isinstance(data, dict) else None
if not isinstance(entries, list) or not entries:
    print("adapter-skips: OK (empty)")
    raise SystemExit
entries = sorted(entries, key=lambda e: e.get("last_seen") or "", reverse=True)
print("adapter-skips: OK")
for e in entries[:10]:
    print("  %s %s %s %s count=%s last=%s" % (
        e.get("harness"), e.get("event"), e.get("tool_name"), e.get("reason"),
        e.get("count"), e.get("last_seen")))
versions = {e.get("harness_version") for e in entries if e.get("harness") == "cursor" and e.get("harness_version")}
if not versions:
    print("adapter-skips cursor_version: skip (no cursor records)")
elif versions - {expected}:
    print("adapter-skips: WARN cursor_version %s != fixture %s; re-record tests/fixtures/hooks/cursor/" % (
        ",".join(sorted(versions - {expected})), expected))
else:
    print("adapter-skips cursor_version: OK")
PY
script=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$CLAUDE_PLUGIN_ROOT/scripts/install-codex-agents.sh" ]; then
  script="$CLAUDE_PLUGIN_ROOT/scripts/install-codex-agents.sh"
elif [ -n "${PLUGIN_ROOT:-}" ] && [ -f "$PLUGIN_ROOT/scripts/install-codex-agents.sh" ]; then
  script="$PLUGIN_ROOT/scripts/install-codex-agents.sh"
elif [ -f "./scripts/install-codex-agents.sh" ]; then
  script="./scripts/install-codex-agents.sh"
fi
if [ -z "$script" ]; then
  echo "codex-agents: WARN installer not found; from the aidd plugin directory run: bash scripts/install-codex-agents.sh"
else
  bash "$script" --check || true
fi
```

**出力**: 項目ごとに `OK` / `WARN` / `FAIL` と、`WARN`・`FAIL` には具体的な対処手順を1行で付ける。最後に総合サマリ (問題数) を1行で出す。
