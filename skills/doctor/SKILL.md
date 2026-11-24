---
name: doctor
description: aidd/superpowers の導入状態・バージョン整合・hooks 実行可否・Codex custom agents の導入・利用側の sandbox 設定を診断する
disable-model-invocation: true
argument-hint: "[--hooks]"
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
9. **利用側の sandbox 設定**: 利用側プロジェクトで aidd の skill を権限を絞って動かせる状態かを見る。読む設定ファイルは優先順位の高い順に managed (macOS `/Library/Application Support/ClaudeCode/`、Linux・WSL `/etc/claude-code/`、Windows `C:\Program Files\ClaudeCode\` の `managed-settings.d/*.json` と `managed-settings.json`)、`.claude/settings.local.json` (git のリポジトリではルートのもの、worktree では main checkout のもの。Windows、ルートがホームディレクトリ、ルート・`.git`・`.claude` が自分の所有でない場合は `.claude/settings.json` と同じ場所のもの。旧版が開始ディレクトリに残したものもルートのものの下で読む)、`.claude/settings.json`、`~/.claude/settings.json` (`CLAUDE_CONFIG_DIR` があればその下)。無いファイルは飛ばし、JSON として読めないファイルは WARN を出して飛ばす。どちらも残りの判定を止めない。結果は WARN にとどめ、FAIL にしない (sandbox を使わない運用もありうる)
   - `sandbox.enabled` を、それを設定している最も優先順位の高いファイルの値で判定する。true でなければ「sandbox 未設定」とし、README の「ローカルで権限を絞って使う (Claude Code)」と `templates/sandbox-settings.json.template` を案内する。サーバー配信・MDM・レジストリの managed settings はファイルから読めないので、WARN のときは `/status` の `Setting sources` で確かめるよう添える。起動時の `--settings` (managed の次に優先) もここからは読めないので、`--settings` で sandbox を切り替えていれば結果は実際と違う。見るのは `sandbox.enabled` だけで、sandbox の外へ抜ける `allowUnsandboxedCommands`・`failIfUnavailable` は見ない (OK の行にもそう書く)
   - `excludedCommands` (全ファイルの和) に `gh` を除外するもの (`gh`・`gh *`・`gh:*`・`gh*`・`/opt/homebrew/bin/gh` のようなパス) があれば、「`gh` は sandbox の外で利用者の全権限で動く (任意のファイルへの書き込み・任意のホストへの送信。`GH_TOKEN` が無ければ `gh auth login` の保存済みの認証)」と知らせ、`excludedCommands` から外して README の手順2 (gh を sandbox の中で動かす) に従うよう案内する
   - `gh` が sandbox の中で動く (`sandbox.enabled` が true で、`excludedCommands` に無い) なら、この Bash の環境変数を見る。`GH_TOKEN` と `GITHUB_TOKEN` がどちらも空 (空白だけを含む) なら、`gh` は認証できないと知らせ、README の手順2 (対象リポジトリだけの fine-grained PAT を `GH_TOKEN` で渡す) を案内する。macOS で `SSL_CERT_FILE` が空なら `gh` は TLS で失敗する (`x509: OSStatus -26276`) と、`GH_CONFIG_DIR` が空なら読み取りを拒否した `~/.config/gh` を読めずに失敗しうると知らせ、雛形の `env` を案内する (プロジェクトの `env` はフォルダを trust するまで効かないことも添える)。変数は名前だけを出し、値は出さない。**token の値は表示しない**。有無だけを見て、値を echo・print しない。token の権限の範囲は見ないので、OK でも絞れているとは限らない (OK の行に `gh auth status` での確認を添える)。token が環境にあるので、python3 は利用側のファイルを import しないよう `-I` で動かす。`sandbox.credentials.envVars` で token を隠していると、ここからは無いように見える
10. **hook の動作確認 (fixture の再生)**: `$ARGUMENTS` に `--hooks` があるときだけ実行する。無ければ「skip (`--hooks` で実行)」と書く。プラグインの `tests/fixtures/hooks/{claude,codex,cursor}/` の無害な入力を、プラグイン自身の hook スクリプトに渡し、期待する拒否 (deny)・通過 (pass)・確認 (ask)・記録 (record) が返るかを見る。HOME・状態ディレクトリ (`AIDD_TEST_STATE_DIR`)・`CLAUDE_CONFIG_DIR`・TMPDIR は使い捨てのディレクトリに向け、hook に渡す環境変数は PATH、それら、git の全体設定を読ませない `GIT_CONFIG_GLOBAL=/dev/null`・`GIT_CONFIG_NOSYSTEM=1` だけにする (利用者の `~/.claude/aidd/`・token・`AIDD_*` の設定は hook に届かない)。削除するのは自分で作ったディレクトリだけ。項目10と11では、利用者の実際の設定ファイルや認証情報は読まない。fixture が見つからなければ WARN にして、OK にしない。期待と違えば FAIL にする
   - 見るのはスクリプトの判定だけで、ハーネスが実際にその hook を呼ぶかは見ない。**fixture の再生が OK でも、実配線を OK にしない** (実配線は項目11)
   - `AIDD_*` の設定で判定を変えている利用者では、実際の挙動は再生結果と違いうる
11. **実配線とハーネスごとの保護範囲**: `--hooks` のときだけ実行する
   - 各ハーネスの CLI の版: 下の `# Item 11:` で `claude`・`codex`・`cursor-agent` の `--version` だけを実行する (ログイン・通信をする操作はしない)。CLI が無ければ skip。Claude Code は 2.1.110 未満、Codex と Cursor は設計書の実測版 (Codex CLI `0.163.0`、Cursor agent CLI `2026.10.22-27dcf5f`) と違えば WARN にし、実配線の確認と fixture の取り直しを促す
   - 実配線の確認は、いま doctor を実行しているハーネスでだけ行う。先に下の `# Item 11 settings:` を実行し、確認の結果を変える設定の**名前だけ**を出す (値は出さない。見えるのはこの Bash の環境変数だけで、ハーネスが hook に渡す環境とは違いうる)。`AIDD_DISABLE_GIT_SAFETY` があれば1の結果を、`AIDD_DISABLE_UNREADABLE_NAME_GUARD` か `AIDD_UNREADABLE_NAME_PATTERNS` があれば2の結果を、止まらなくても FAIL にせず「未確認（設定で無効）」と書く
   - 一時ディレクトリは `mktemp -d "${TMPDIR:-/tmp}/aidd-doctor-probe.XXXXXX"` で作る。Bash の状態 (変数・cd) は呼び出しをまたいで残らないので、表示されたパスを覚えておき、以降のコマンドとツールにはそのパスを**リテラルで**渡す (`<dir>` と書いた箇所)。`git -C <dir> rev-parse --git-dir` が失敗する (どのリポジトリの中でもない) ことを確かめてから、次の2つを試す。リポジトリの中だった場合は試さず「未確認」にする
     1. シェルのツール (Claude Code・Codex の Bash、Cursor の Shell) で `git -C <dir> add -A`。hook が効いていなければ git が `not a git repository` で失敗するだけで、何も変わらない
     2. ファイル作成のツール (Claude Code の Write、Codex の apply_patch、Cursor の Write) で `<dir>/.env.local` に `AIDD_DOCTOR_PROBE=1` を書く。hook が効いていなければ、作ったディレクトリの中にファイルができるだけ
   - それぞれ、aidd の文言 (`aidd:` で始まる) で止められたときだけ OK。実行された・作られたら FAIL (hook が無効・未信頼・配線ずれ。Codex は `/hooks` での信頼、Claude Code は plugin の有効化と `disableAllHooks` を確かめるよう添える)。aidd 以外の理由 (権限の確認・ハーネスの拒否) で止まったら「未確認」。確認が終わったら、下の `# Probe cleanup:` の `<dir>` をそのパスに置き換えて実行し、作ったディレクトリだけを削除する。パスに `aidd-doctor-probe.` が含まれることを確かめてから、再帰削除は使わず `rm -f -- <dir>/.env.local` と `rmdir -- <dir>` で消す (ほかのファイルがあれば `rmdir` が失敗して残るので、その旨を報告する)。この確認で増える hook の記録は、adapter が素通りしたときの `adapter-skips.json` だけ (リポジトリの外なので `main-tree.json` にも残らない)
   - skill gate (autonomous-review の起動) の実配線は確かめない (確かめると利用者への確認や SKILL.md の読み込みが起きる)。結果は「未確認」と書く
   - 実配線を確かめていないハーネスは「未確認」と書く。doctor を実行していないハーネスは、CLI があっても未確認である。依存 skill/agent の利用可否は、Claude Code は項目1、Codex は項目8の結果を書く。Cursor はここからは見ないので「未確認」と書く
   - 最後に次の表を出す。保護される操作と残る限界は下の一覧から写し、版・再生・実配線の列はこの実行の結果を書く

     | ハーネス | CLI の版 | fixture の再生 | 実配線 | 保護される操作 | 残る限界 |
     |---|---|---|---|---|---|

   - **Claude Code**: 保護される操作は、Bash の作業を失う git 操作・名前を指定しないステージ・既定ブランチへの force push の拒否と `gh issue create` 前の検索 (`tool-reminder.sh`)、まだ無いファイルの Write・Edit・NotebookEdit のうち sandbox が読めない名前と重複資産の拒否 (`write-guard.sh`)、モデルによる autonomous-review の起動の確認 (`skill-gate.sh`)、使用回数の記録 (`usage-log.sh`)。残る限界は、hook はツールの呼び出しにしか効かない (Bash の中で動くスクリプトが行う操作や、利用者が手で打つコマンドは見ない)、plugin の無効化・`disableAllHooks`・python3 が無いと止まらない、`AIDD_*` で判定を切れる、Write の判定は新規ファイルだけ
   - **Codex**: 保護される操作は、Bash の `tool-reminder.sh` (Claude Code と同じ判定) と、apply_patch の新規ファイルの `write-guard.sh` (adapter 経由)。残る限界は、`/hooks` で信頼していない hook は何も表示されずに実行されない、`hooks.json` のエントリが変わるリリースでは信頼し直すまでそのエントリが止まる、信頼はスクリプト本体の改変を検出しない、skill gate は無い (`openai.yaml` の `allow_implicit_invocation: false` が代わり)、adapter は変換できない入力を素通りさせて `adapter-skips.json` に数えるだけ、python3 が無いと止まらない
   - **Cursor**: 保護される操作は、Shell の `tool-reminder.sh`、Write (編集も Write として届く) の `write-guard.sh`、モデルが autonomous-review の SKILL.md を Read することの拒否 (`skill-gate.sh`)。すべて adapter 経由。残る限界は、adapter はどの失敗でも素通りさせる (理由は `adapter-skips.json` に数える)、`ask` は無視されるので確認でなく拒否になる、利用者が手で打った `/autonomous-review` は止まらない、Claude Code に入れた aidd との併用で記録や案内が二重になる、python3 が無いと止まらない、Read の判定は Cursor のパスの解決 (2026.10.22 のバンドルで確認) を前提にしていて Windows では未計測、相対パスの基点に入力の `cwd` を使う点は未実測 (#173)

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
# -I keeps a json.py or glob.py in the consumer project from loading while the token is in the env.
AIDD_PROJ="$proj" AIDD_MAIN_ROOT="$main_root" python3 -I - <<'PY'
import glob, json, os, re, sys
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
def owned(path):
    try:
        return os.stat(path).st_uid == os.getuid()
    except FileNotFoundError:
        return True
    except OSError:
        return False
# The local file sits at the repository (main checkout) root, except on Windows, when that root
# is the home directory, or when the root, its .git or its .claude is not owned by the user.
# A file an older Claude Code left in the starting directory is still read, below the root one.
root_local = (sys.platform != "win32" and main_root != proj
              and os.path.realpath(main_root) != os.path.realpath(os.path.expanduser("~"))
              and all(owned(os.path.join(main_root, p)) for p in ("", ".git", ".claude")))
files += [("managed", os.path.join(managed_dir, "managed-settings.json"))]
if root_local:
    files += [("local", os.path.join(main_root, ".claude", "settings.local.json"))]
files += [("local", os.path.join(proj, ".claude", "settings.local.json")),
          ("project", os.path.join(proj, ".claude", "settings.json")),
          ("user", os.path.join(user_dir, "settings.json"))]
enabled, source, excluded = None, None, []
for scope, path in files:
    if not os.path.isfile(path):
        continue
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, UnicodeDecodeError, RecursionError) as e:
        print("sandbox: WARN %s could not be read (%s); skipped" % (path, type(e).__name__))
        continue
    except ValueError:
        data = None
    if not isinstance(data, dict):
        print("sandbox: WARN %s is not a valid JSON object; skipped" % path)
        continue
    sb = data.get("sandbox")
    if not isinstance(sb, dict):
        continue
    if source is None and "enabled" in sb:
        enabled, source = sb["enabled"], "%s (%s)" % (scope, path)
    if isinstance(sb.get("excludedCommands"), list):
        excluded += [c for c in sb["excludedCommands"] if isinstance(c, str)]
if enabled is True:
    print("sandbox: OK enabled in %s (allowUnsandboxedCommands and failIfUnavailable are not checked)" % source)
else:
    # Echo only a boolean/null; any other value could carry arbitrary file content.
    shown = json.dumps(enabled) if enabled is None or isinstance(enabled, bool) else "a non-boolean value"
    reason = "enabled=%s in %s" % (shown, source) if source else "sandbox.enabled is not set"
    print("sandbox: WARN not enabled (%s); see README \"ローカルで権限を絞って使う (Claude Code)\" and "
          "templates/sandbox-settings.json.template. Server/MDM managed settings are not read here: "
          "check Setting sources in /status" % reason)
def env_set(name):
    return bool((os.environ.get(name) or "").strip())
has_token = env_set("GH_TOKEN") or env_set("GITHUB_TOKEN")
# Catch "gh", "gh *", "gh:*", "gh*" and a path such as /opt/homebrew/bin/gh.
if any(re.match(r"(?:\S*/)?gh(?:$|[\s:*])", c.strip()) for c in excluded):
    print("sandbox gh: WARN gh is in excludedCommands, so it runs outside the sandbox with full access "
          "(writes any file, sends to any host%s); remove it and follow README step 2"
          % ("" if has_token else ", and uses the saved gh auth login credentials"))
elif enabled is not True:
    print("sandbox gh: skip (sandbox is not enabled)")
else:
    # Names only: a value could be a token or a path the user does not want echoed.
    missing = [] if has_token else ["GH_TOKEN"]
    if sys.platform == "darwin":
        missing += [v for v in ("SSL_CERT_FILE", "GH_CONFIG_DIR") if not env_set(v)]
    if missing:
        print("sandbox gh: WARN %s not set; gh in the sandbox has no scoped token (GH_TOKEN), "
              "fails TLS with x509: OSStatus -26276 on macOS (SSL_CERT_FILE), or cannot read the "
              "denied ~/.config/gh (GH_CONFIG_DIR). See the env of templates/sandbox-settings.json.template "
              "and README step 2; project env applies only after the folder is trusted" % ", ".join(missing))
    else:
        print("sandbox gh: OK gh runs in the sandbox with a token from the environment "
              "(its scope is not checked; gh auth status shows which token gh uses)")
PY
```

`--hooks` のときだけ、項目10–11を次のコマンドで実行する:

```bash
# Item 10: replay hook fixtures through this plugin's scripts in a throwaway HOME and state.
# Only PATH and the throwaway directories reach the hooks; python removes only the directory it made.
AIDD_PLUGIN_ROOT=""
for r in "${CLAUDE_PLUGIN_ROOT:-}" "${PLUGIN_ROOT:-}" .; do
  if [ -n "$r" ] && [ -f "$r/hooks/scripts/harness-adapter.sh" ]; then AIDD_PLUGIN_ROOT=$(cd "$r" && pwd -P); break; fi
done
AIDD_PLUGIN_ROOT="$AIDD_PLUGIN_ROOT" python3 -I - <<'PY'
import json, os, shutil, subprocess, tempfile
root = os.environ["AIDD_PLUGIN_ROOT"]
fixtures = os.path.join(root, "tests", "fixtures", "hooks")
if not root:
    print("hooks replay: WARN plugin root not found; run from the aidd plugin directory (not OK)")
    raise SystemExit
if not all(os.path.isdir(os.path.join(fixtures, h)) for h in ("claude", "codex", "cursor")):
    print("hooks replay: WARN fixtures not found in %s; replay skipped (not OK)" % fixtures)
    raise SystemExit
print("hooks replay: fixtures through the hook scripts only, not the real wiring (see item 11)")
tmp = tempfile.mkdtemp(prefix="aidd-doctor-hooks.")
try:
    work, state = os.path.join(tmp, "work"), os.path.join(tmp, "state")
    for d in ("home", "config", "tmp", "work"):
        os.makedirs(os.path.join(tmp, d))
    open(os.path.join(work, "notes.txt"), "w").close()
    env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": os.path.join(tmp, "home"),
           "TMPDIR": os.path.join(tmp, "tmp") + "/", "CLAUDE_CONFIG_DIR": os.path.join(tmp, "config"),
           "AIDD_TEST_STATE_DIR": state, "GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1"}
    skill = os.path.join(root, "skills", "autonomous-review", "SKILL.md")

    def event(name, path=None, patch=None):
        with open(os.path.join(fixtures, name), encoding="utf-8") as f:
            e = json.load(f)
        e["cwd"] = work
        if path:
            e["tool_input"]["file_path"] = path
        if patch:
            e["tool_input"]["command"] = "*** Begin Patch\n*** Add File: %s\n+x\n*** End Patch" % patch
        return e

    def decision(out):
        for line in out.splitlines():
            try:
                o = json.loads(line)
            except ValueError:
                continue
            if not isinstance(o, dict):
                continue
            if o.get("permission") in ("deny", "ask"):
                return o["permission"]
            spec = o.get("hookSpecificOutput")
            if isinstance(spec, dict) and spec.get("permissionDecision") in ("deny", "ask"):
                return spec["permissionDecision"]
        return "pass"

    def recorded(name, check):
        try:
            with open(os.path.join(state, name), encoding="utf-8") as f:
                return bool(check(json.load(f)))
        except (OSError, ValueError, LookupError, AttributeError, TypeError):
            return False

    def skips():
        try:
            with open(os.path.join(state, "adapter-skips.json"), encoding="utf-8") as f:
                return sum(e.get("count", 0) for e in json.load(f)["entries"])
        except (OSError, ValueError, LookupError, AttributeError, TypeError):
            return 0

    env_local = os.path.join(work, ".env.local")
    adapter = ["harness-adapter.sh"]
    try:
        cases = [
            ("claude PreToolUse Bash git add -A", ["tool-reminder.sh"], event("claude/PreToolUse.bash-git-add-all.json"), "deny"),
            ("claude PreToolUse Bash git status", ["tool-reminder.sh"], event("claude/PreToolUse.bash-git-status.json"), "pass"),
            ("claude PreToolUse Write .env.local", ["write-guard.sh"], event("claude/PreToolUse.write-new-file.json", path=env_local), "deny"),
            ("claude PreToolUse Skill aidd:autonomous-review", ["skill-gate.sh"], event("claude/PreToolUse.skill-autonomous-review.json"), "ask"),
            ("claude UserPromptSubmit /aidd:doctor", ["usage-log.sh"], event("claude/UserPromptSubmit.aidd-doctor.json"),
             ("usage.json", lambda d: d["command_counts"]["doctor"] >= 1)),
            ("codex PreToolUse Bash git add -A", ["tool-reminder.sh"], event("codex/PreToolUse.bash-git-add-all.json"), "deny"),
            ("codex PreToolUse apply_patch Add .env.local", adapter + ["write-guard.sh"], event("codex/PreToolUse.apply_patch-add.json", patch=env_local), "deny"),
            ("codex PreToolUse apply_patch Add new-notes.txt", adapter + ["write-guard.sh"], event("codex/PreToolUse.apply_patch-add.json", patch=os.path.join(work, "new-notes.txt")), "pass"),
            ("cursor preToolUse Shell git add -A", adapter + ["tool-reminder.sh"], event("cursor/preToolUse.shell-git-add-all.json"), "deny"),
            ("cursor preToolUse Write .env.local", adapter + ["write-guard.sh"], event("cursor/preToolUse.write.json", path=env_local), "deny"),
            ("cursor preToolUse Read autonomous-review SKILL.md", adapter + ["skill-gate.sh"], event("cursor/preToolUse.read-before-edit.json", path=skill), "deny"),
            ("cursor preToolUse Read notes.txt", adapter + ["skill-gate.sh"], event("cursor/preToolUse.read-before-edit.json", path=os.path.join(work, "notes.txt")), "pass"),
            ("cursor preToolUse Read missing unrelated path", adapter + ["skill-gate.sh"], event("cursor/preToolUse.read-before-edit.json", path=os.path.join(work, "no-such-dir", "unrelated.md")), "pass"),
            ("adapter missing child script", adapter + ["aidd-doctor-missing.sh"], event("cursor/preToolUse.shell-git-add-all.json"),
             ("adapter-skips.json", lambda d: any(e["reason"] == "missing_script" for e in d["entries"]))),
        ]
    except (OSError, ValueError, LookupError, AttributeError, TypeError) as e:
        print("hooks replay: WARN fixtures incomplete in %s (%s); replay skipped (not OK)" % (fixtures, type(e).__name__))
        raise SystemExit
    ok = 0
    for label, argv, payload, want in cases:
        before = skips()
        cmd = ["bash", os.path.join(root, "hooks", "scripts", argv[0])] + argv[1:]
        try:
            proc = subprocess.run(cmd, input=json.dumps(payload), capture_output=True, text=True, env=env, cwd=work, timeout=60)
        except subprocess.TimeoutExpired:
            print("hooks replay %s: FAIL timed out" % label)
            continue
        got = decision(proc.stdout)
        # A pass through the adapter counts only if the adapter did not skip (fail open).
        skipped = argv[0] == "harness-adapter.sh" and want == "pass" and skips() != before
        if proc.returncode != 0:
            print("hooks replay %s: FAIL exit %d" % (label, proc.returncode))
        elif isinstance(want, tuple):
            if recorded(*want):
                ok += 1
                print("hooks replay %s: OK record %s" % (label, want[0]))
            else:
                print("hooks replay %s: FAIL nothing recorded in %s" % (label, want[0]))
        elif skipped:
            print("hooks replay %s: FAIL the adapter skipped (adapter-skips.json grew), so pass is not a decision" % label)
        elif got == want:
            ok += 1
            print("hooks replay %s: OK %s" % (label, want))
        else:
            print("hooks replay %s: FAIL expected %s, got %s" % (label, want, got))
    if ok == len(cases):
        print("hooks replay: %d/%d OK (scripts only; the real wiring is item 11)" % (ok, len(cases)))
    else:
        print("hooks replay: FAIL %d/%d OK; a script no longer gives the expected decision" % (ok, len(cases)))
finally:
    shutil.rmtree(tmp, ignore_errors=True)
PY
# Item 11: harness CLI versions. Only --version runs; a missing CLI is a skip, never OK.
for cli in claude codex cursor-agent; do
  if ! command -v "$cli" >/dev/null 2>&1; then
    echo "$cli: skip (CLI not found; its real wiring stays unverified)"
    continue
  fi
  v=$("$cli" --version 2>/dev/null | head -n 1)
  case "$cli" in
    claude)
      if python3 -I -c 'import re, sys
m = re.search(r"(\d+)\.(\d+)\.(\d+)", sys.argv[1])
sys.exit(0 if m and tuple(map(int, m.groups())) >= (2, 1, 110) else 1)' "$v"; then
        echo "claude: OK $v"
      else
        echo "claude: WARN $v is older than 2.1.110 (or unreadable); plugin dependencies need 2.1.110+"
      fi ;;
    *)
      [ "$cli" = codex ] && measured=0.163.0 || measured=2026.10.22-27dcf5f
      # Exact match on the last word (codex prints "codex-cli 0.163.0"), not a substring.
      if [ "${v##* }" = "$measured" ]; then
        echo "$cli: OK $v (measured version)"
      else
        echo "$cli: WARN $v differs from the measured $measured; probe the real wiring there and re-record tests/fixtures/hooks/"
      fi ;;
  esac
done
# Item 11 settings: names only (never values) of the settings that change the wiring probes.
names=$(compgen -e | grep -E '^(AIDD_DISABLE_[A-Z0-9_]+|AIDD_UNREADABLE_NAME_PATTERNS)$' | sort | tr '\n' ' ')
echo "probe settings: ${names:-none}"
case " $names " in
  *" AIDD_DISABLE_GIT_SAFETY "*) echo "probe git add -A: 未確認（設定で無効: AIDD_DISABLE_GIT_SAFETY）" ;;
  *) echo "probe git add -A: run" ;;
esac
case " $names " in
  *" AIDD_DISABLE_UNREADABLE_NAME_GUARD "* | *" AIDD_UNREADABLE_NAME_PATTERNS "*)
    echo "probe .env.local write: 未確認（設定で無効: AIDD_DISABLE_UNREADABLE_NAME_GUARD / AIDD_UNREADABLE_NAME_PATTERNS）" ;;
  *) echo "probe .env.local write: run" ;;
esac
```

実配線の確認の後片付け (`<dir>` は `mktemp` が表示したパスをリテラルで書く):

```bash
# Probe cleanup: remove only the probe directory, never recursively.
d='<dir>'
case "$d" in
  *aidd-doctor-probe.*)
    rm -f -- "$d/.env.local"
    rmdir -- "$d" && echo "probe dir: removed" || echo "probe dir: WARN not removed (not empty?): $d" ;;
  *) echo "probe dir: WARN not removed ($d is not an aidd-doctor-probe directory)" ;;
esac
```

**出力**: 項目ごとに `OK` / `WARN` / `FAIL` と、`WARN`・`FAIL` には具体的な対処手順を1行で付ける。項目1–2と9を Claude Code 以外でスキップしたときは `Claude Code のみ` と書く。最後に総合サマリ (問題数) を1行で出す。
