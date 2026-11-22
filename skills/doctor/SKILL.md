---
name: doctor
description: aidd/superpowers の導入状態・バージョン整合・hooks 実行可否・Codex custom agents の導入・利用側の sandbox 設定を診断する
disable-model-invocation: true
---

**パスと引数と質問の扱い**: この文書の相対パスは、この SKILL.md があるディレクトリを起点にする。`$ARGUMENTS` が文字のまま残っている場合（Codex・Cursor など）は、この skill を呼び出したメッセージのうち skill 名以外の部分を `$ARGUMENTS` とみなす。`AskUserQuestion` と書かれた箇所は、ユーザーに質問するツールがあればそれを使い、無ければ質問を書いて作業を止め、回答を待つ。回答が無いまま推測で進めない。

aidd プラグインの動作環境を診断してください。各チェックは独立に実行し、1項目の失敗が他の診断を止めないようにする。

**チェック項目**:

項目1–2と9は Claude Code 以外では実行せず、結果を「Claude Code のみ」と書く。未確認の Codex / Cursor 導入パスは書かない。

1. **superpowers 導入**: `claude plugin list --json` に `superpowers@` で始まり `enabled: true` のエントリがあるか (plugin.json の dependencies 宣言により通常は自動導入されるはずだが、古い Claude Code や依存解決エラーを検知する)
2. **バージョン整合**: `.claude-plugin/plugin.json` の `version` と、`~/.claude/plugins/installed_plugins.json` に記録された aidd のインストール済みバージョンを比較する。ズレていれば `push + /plugin update aidd` 忘れの可能性を指摘する
3. **hooks 実行権限**: `hooks/scripts/*.sh` それぞれに実行ビット (`x`) が付いているか (`ls -l` で確認)
4. **python3 存在**: `which python3` — hooks が python3 に依存しているため必須
5. **状態ファイルの妥当性**: `~/.claude/aidd/state.json` と `~/.claude/aidd/usage.json` が存在する場合、それぞれ有効な JSON としてパースできるか (存在しない場合はスキップ、エラーではない)
6. **adapter の素通り**: `~/.claude/aidd/adapter-skips.json` がある場合、直近の素通り理由と件数を表示する (`harness` / `event` / `tool_name` / `reason` / `count` / `last_seen`)。無い場合はスキップ
7. **Cursor fixture の版**: `adapter-skips.json` に記録された `harness_version` (`cursor_version`) が、設計書 `docs/superpowers/specs/2026-10-27-multi-harness-hooks-design.md` の実測版 (`2026.10.22-27dcf5f`) と違う場合、fixture を取り直すよう促す。記録が無い場合はスキップ
8. **Codex custom agents**: `scripts/install-codex-agents.sh --check` で、`~/.codex/agents/` の TOML がプラグイン正本と一致するか見る。未導入・版ずれなら同スクリプトの実行を促す。インストーラが見つからない場合はスキップせず WARN にする。Codex のプラグイン導入だけでは TOML は届かない
9. **利用側の sandbox 設定**: 利用側プロジェクトで aidd の skill を権限を絞って動かせる状態かを見る。読む設定ファイルは優先順位の高い順に managed (macOS `/Library/Application Support/ClaudeCode/`、Linux・WSL `/etc/claude-code/`、Windows `C:\Program Files\ClaudeCode\` の `managed-settings.d/*.json` と `managed-settings.json`)、`.claude/settings.local.json` (worktree では main checkout のもの)、`.claude/settings.json`、`~/.claude/settings.json` (`CLAUDE_CONFIG_DIR` があればその下)。無いファイルは飛ばし、JSON として読めないファイルは WARN を出して飛ばす。どちらも残りの判定を止めない。結果は WARN にとどめ、FAIL にしない (sandbox を使わない運用もありうる)
   - `sandbox.enabled` を、それを設定している最も優先順位の高いファイルの値で判定する。true でなければ「sandbox 未設定」とし、README の「ローカルで権限を絞って使う (Claude Code)」と `templates/sandbox-settings.json.template` を案内する。サーバー配信・MDM・レジストリの managed settings はファイルから読めないので、WARN のときは `/status` の `Setting sources` で確かめるよう添える
   - `excludedCommands` (全ファイルの和) に `gh` か `gh ` で始まるもの (`gh *` など) があるのに、環境変数 `GH_TOKEN` と `GITHUB_TOKEN` がどちらも空なら、「`gh` は sandbox の外で `gh auth login` の保存済みの認証 (利用者の全権限になりうる) で動く」と知らせ、README の手順2 (対象リポジトリだけの fine-grained PAT を `GH_TOKEN` で渡す) を案内する。**token の値は表示しない**。有無だけを見て、値を echo・print しない。`sandbox.credentials.envVars` で token を隠していると、ここからは無いように見える

各項目を実行するには Bash tool で以下相当のコマンドを使う:

```bash
# 項目1–2と9は Claude Code のみ。Claude Code 以外では実行せず、各項目を「Claude Code のみ」と書く。
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
# Item 9: report only whether a token is set; never print its value.
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
common_dir=$(git -C "$proj" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
main_root="$proj"
[ "$(basename "$common_dir")" = ".git" ] && main_root=$(dirname "$common_dir")
AIDD_PROJ="$proj" AIDD_MAIN_ROOT="$main_root" python3 - <<'PY'
import glob, json, os, sys
proj, main_root = os.environ["AIDD_PROJ"], os.environ["AIDD_MAIN_ROOT"]
user_dir = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
if sys.platform == "darwin":
    managed_dir = "/Library/Application Support/ClaudeCode"
elif sys.platform == "win32":
    managed_dir = r"C:\Program Files\ClaudeCode"
else:
    managed_dir = "/etc/claude-code"
# Highest precedence first; a later managed drop-in overrides an earlier one.
files = [("managed", p) for p in sorted(glob.glob(os.path.join(managed_dir, "managed-settings.d", "*.json")), reverse=True)]
files += [("managed", os.path.join(managed_dir, "managed-settings.json")),
          ("local", os.path.join(main_root, ".claude", "settings.local.json")),
          ("project", os.path.join(proj, ".claude", "settings.json")),
          ("user", os.path.join(user_dir, "settings.json"))]
enabled, source, excluded = None, None, []
for scope, path in files:
    if not os.path.isfile(path):
        continue
    try:
        data = json.load(open(path, encoding="utf-8"))
    except Exception:
        data = None
    if not isinstance(data, dict):
        print("sandbox: WARN %s is not valid JSON; skipped" % path)
        continue
    sb = data.get("sandbox")
    if not isinstance(sb, dict):
        continue
    if source is None and "enabled" in sb:
        enabled, source = sb["enabled"], "%s (%s)" % (scope, path)
    if isinstance(sb.get("excludedCommands"), list):
        excluded += [c for c in sb["excludedCommands"] if isinstance(c, str)]
if enabled is True:
    print("sandbox: OK enabled in %s" % source)
else:
    reason = "enabled=%s in %s" % (json.dumps(enabled), source) if source else "sandbox.enabled is not set"
    print("sandbox: WARN not enabled (%s); see README \"ローカルで権限を絞って使う (Claude Code)\" and "
          "templates/sandbox-settings.json.template. Server/MDM managed settings are not read here: "
          "check Setting sources in /status" % reason)
if not any(c.strip() == "gh" or c.strip().startswith("gh ") for c in excluded):
    print("sandbox gh: skip (gh is not in excludedCommands)")
elif os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN"):
    print("sandbox gh: OK gh runs outside the sandbox with a token from the environment")
else:
    print("sandbox gh: WARN gh runs outside the sandbox with the saved gh auth login credentials "
          "(may be full access); pass a fine-grained PAT in GH_TOKEN (README step 2)")
PY
```

**出力**: 項目ごとに `OK` / `WARN` / `FAIL` と、`WARN`・`FAIL` には具体的な対処手順を1行で付ける。項目1–2と9を Claude Code 以外でスキップしたときは `Claude Code のみ` と書く。最後に総合サマリ (問題数) を1行で出す。
