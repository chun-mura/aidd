---
description: aidd/superpowers の導入状態・バージョン整合・hooks 実行可否を診断する
---

aidd プラグインの動作環境を診断してください。各チェックは独立に実行し、1項目の失敗が他の診断を止めないようにする。

**チェック項目**:

1. **superpowers 導入**: `claude plugin list --json` に `superpowers@` で始まり `enabled: true` のエントリがあるか (plugin.json の dependencies 宣言により通常は自動導入されるはずだが、古い Claude Code や依存解決エラーを検知する)
2. **バージョン整合**: `.claude-plugin/plugin.json` の `version` と、`~/.claude/plugins/installed_plugins.json` に記録された aidd のインストール済みバージョンを比較する。ズレていれば `push + /plugin update aidd` 忘れの可能性を指摘する
3. **hooks 実行権限**: `hooks/scripts/*.sh` それぞれに実行ビット (`x`) が付いているか (`ls -l` で確認)
4. **python3 存在**: `which python3` — hooks が python3 に依存しているため必須
5. **状態ファイルの妥当性**: `~/.claude/aidd/state.json` と `~/.claude/aidd/usage.json` が存在する場合、それぞれ有効な JSON としてパースできるか (存在しない場合はスキップ、エラーではない)

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
```

**出力**: 項目ごとに `OK` / `WARN` / `FAIL` と、`WARN`・`FAIL` には具体的な対処手順を1行で付ける。最後に総合サマリ (問題数) を1行で出す。
