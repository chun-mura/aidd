# hooks の運用と調査

[README に戻る](../../README.md) / 関連: [ローカルで権限を絞って使う](local-permissions.md) / [利用側プロジェクトの設定](project-setup.md)

## いつ使うか

aidd の hook が何を拒否・通知・記録するかを詳しく確かめるとき、hook の状態ファイルの置き場所を調べるとき、環境変数で hook を個別に無効にしたり判定を変えたりするとき、利用側プロジェクト自身の hook の発火を `aidd-hook-log.sh` で記録するとき。hook の一覧と1文の説明は README の [Hooks](../../README.md#hooks-強制力のある運用) にある。配線は [`hooks/hooks.json`](../../hooks/hooks.json) (Cursor は [`hooks/hooks-cursor.json`](../../hooks/hooks-cursor.json))、本体は [`hooks/scripts/`](../../hooks/scripts/)。

## 各 hook の動作

### `session-start.sh`

SessionStart で aidd 資産の使いどころと「実装を左右する不明点は、このセッションが実際に持つ手段で確認する (対話なら AskUserQuestion、監督下なら親への返答)」を注入。`/aidd:asset-audit` の最終実施日 (未実施なら `aidd-hook-log.sh` が最初の hook の記録を始めた日) から一定期間 (既定30日) が過ぎたプロジェクトでだけ、棚卸しを促す1文を足す。superpowers 未導入を検知して警告

### `usage-log.sh`

起動を2経路で記録し、aidd コマンド使用数・最終利用時刻を `~/.claude/aidd/usage.json` に残す (`/aidd:retro` が読む): 行頭が `/aidd:<name>` のプロンプト (UserPromptSubmit) と、Skill ツール経由の起動 (PreToolUse、サブエージェント内の起動もここに入る)。文中で名前に触れただけのプロンプトは計上しない。実在するコマンド・skill 名だけを計上し、旧版が残した `prompt_log` は起動時に削除する

### `tool-reminder.sh`

`git commit` 時、直近6時間に保存した観点が無ければ、この変更の観点を出していなければ残りの実装の前に test-perspectives を出すよう促す確認 (この変更のために出し済みなら再実行を、実装が済んでいれば後追いの作成を求めない)、`gh pr/issue create・edit` 前の日本語確認、`gh pr create` 前のレビュー証跡の確認、`git push` 後の PR 同期確認、`git commit` 後の HEAD の件名 (Conventional Commits 形式) と本文の有無の検査を1本で処理 (ここまでは非ブロック。コミットの検査はコマンド文字列でなく確定後の HEAD を SHA ごとに1回だけ読み、規約を採るリポジトリだけで行う。後続のコマンドが失敗した場合 (PostToolUseFailure) もコミットは検査する)。加えて、未コミットの作業を失う git 操作 (`stash`・`reset --hard`・パスを指定した `checkout` (`checkout -- <path>` / `checkout .` / `checkout <path>` / `checkout HEAD <path>`)・`checkout -f`・`switch -f` / `--discard-changes`・`--staged` だけでない `restore`・`-n` の無い `clean`) と指名しないステージ (`add -A` / `-u`、`.` / `./` / `..` / `:/` のように作業ディレクトリやルートを指すパス、`commit -a`) を拒否する。既定ブランチ (push 先のリモートの `HEAD` が指す実在のブランチと、常に `main` / `master`) への force push (`--force`・`-f`・`--force-with-lease`・`+<refspec>`・`--mirror`・`--force --all`・`+:`・`heads/<既定>` のような短い書き方・`--force-w` のような省略形。refspec を省いた場合は `remote.<name>.push` と `push.default` で決まる送り先が既定ブランチなら) と既定ブランチのリモート削除 (`push --delete`・`push <remote> :<branch>`) も拒否し (送り先に `$`・バッククォートを含む force / delete / prune の push も、判定できないので拒否する)、作業ブランチへの force push と `-n` / `--dry-run` は止めない (どの操作をどこで止めるかは [local-permissions.md の「破壊的な操作をどこで止めるか」](local-permissions.md#破壊的な操作をどこで止めるか))。主ツリーを別のセッションが直近に使っているときは相手ごとに1回だけ worktree への移動を促し (拒否はしない。`session_id` は resume / compact の前後で同じと保証されていない)、`git commit` は、ステージ済みか同じコマンドの `git add` / `git commit` が名指しした知見の台帳 (`.aidd/learnings/`) のファイルが検査 (`scripts/learnings.py`) に通らなければ拒否する (よくある形での不注意を防ぐ層で、効かない経路は [project-setup.md の「知見の台帳に機密を入れない4層」](project-setup.md#知見の台帳に機密を入れない4層) にある。台帳の有効化に関係なく動き、台帳のファイルを含まないコミットでは何もしない。検査スクリプトを読み込めない・検査が途中で失敗したときは台帳を含むコミットを拒否し、git が台帳のファイルを列挙できなかったときもコミットを拒否する)。`gh issue create` は同じセッションで直近に同じリポジトリ (`-R` / `--repo`、無ければ cwd の `origin`) に対して `gh issue list --search` を実行していなければ拒否する。`AIDD_REQUIRED_LABEL_PREFIX` を設定すると、その接頭辞のラベルが無い `gh issue create` も拒否する。コマンドは引用符・`&&` / `;` の連結・`#` のコメント・`if` / `then` / `do` などの制御構文・`cd`・`git -C`・前置のラッパー (`rtk` など) を見分けて判定し、1回の起動で当たった判定は JSON 1つにまとめて返す。コマンドに `git` / `gh` の語が無ければ python を起動せずに終わる。レビュー証跡の確認は、`--head` のブランチ (未指定なら cwd のブランチ) が基点ブランチに対してコードを変更しているのに、どの worktree の `.aidd/autonomous-review/` にも現在の差分のレビューを完了した `state.json` が無いときだけ、変更ファイルの一覧つきで警告する (docs だけの変更では鳴らさない)。完了とみなすのは、`schema_version` 5 以上で、最終判定が `auto_merge_eligible` か `human_required_reason: human_judgment` の `human_required`、`base_sha` が `origin/<base>` の先端 (ローカルの `<base>` は origin に含まれるときだけ。`origin/<base>` が無ければローカル) と一致し、レビューした最終コミットが PR の head と一致するか、その後のコミットが `.aidd/autonomous-review/` と `.aidd/learnings/` だけを変えるもの (それ以外の `.aidd/` 配下・rename の元の場所・mode・submodule のポインタの変更はコードの変更として数える)。古い・未完了・失敗・型が不正・旧スキーマの証跡は数えない。証跡の判定に失敗したときは確認できなかったと書いて警告し、同じコマンドのほかの拒否・通知は残す。hook はネットワークに出ないので、fetch していない古い `origin/<base>` は検出できない

### `skill-gate.sh`

モデルが Skill ツールで `autonomous-review` を起動する前に、PreToolUse で `ask` を返してユーザーの許可を取る (名前は接頭辞・先頭の `/`・大文字小文字の違いをならして照合する)。対話の default / auto / bypassPermissions、allow ルール、サブエージェントのどれでも確認がユーザーに届き、headless (`-p`) では拒否として働く。ユーザーが手で打った起動は Skill ツールを通らないので確認は出ない。判定を出してから件数を記録し、入力を解釈できなくても `autonomous-review` を含めば `ask` を返す。Cursor では adapter 経由で、この plugin の `skills/autonomous-review/SKILL.md` の `Read` を拒否する。Bash の PreToolUse (Codex と Claude Code) では、コマンドの語がこの plugin の `skills/autonomous-review/SKILL.md` と同じファイルを指せば拒否する (Codex は Skill ツールを持たず、モデルが SKILL.md をシェルで読んで従う。Codex は `ask` を扱わないので `deny`。#225)。同じディレクトリのほかのファイルやディレクトリ自体を指す語は通す。`skill`・`autonomous`・glob の文字 (`*`・`?`・`[`)・`\u` を含まない Bash は python を起動せずに抜ける。`cd` の後の相対パス、実行時に組み立てるパスなどは止めない (一覧は 2026-11-14 の設計書の既知の限界)。hook が起動できないときや hook が無効な環境 (`disableAllHooks` など) では確認なしで起動しうる (hook の起動失敗は Claude Code が素通りさせる)

### `write-guard.sh`

Write・Edit・NotebookEdit の PreToolUse を1本で処理する。対象はまだ存在しないファイルだけで、既存ファイルと対象外のパスでは何も出さずに終わる。サンドボックスの読み取り拒否によく入る名前 (`.env*`・`*.pem`・`*secret*`・`*credential*` など) のファイルを新しく作ろうとしたら拒否する (作った後に git・テスト・シェルから読めなくなるため)。Claude Code には読み取り拒否の既定リストが無いので、パターンは `AIDD_UNREADABLE_NAME_PATTERNS` で利用側の設定に合わせて差し替える。この検査は読めなくなる手戻りを防ぐためだけのもので、ファイルの中身は見ないので機密の内容検査や漏えい防止ではなく、sandbox 本体の読み取り拒否 (`sandbox.filesystem.denyRead`・`permissions.deny`) の代わりにもならない。既定は名前の部分一致や前方一致 (`*secret*`・`.env.*` など) なので `secretary.ts`・`.env.example` のような通常のファイルも拒否する。自分の sandbox が部分一致で拒否していないなら、`AIDD_UNREADABLE_NAME_PATTERNS` を実際の deny 設定と同じ値 (書き方は下の [環境変数の表](#hooks-の書き込み先と無効化)) に差し替えて許可する (書いたパターンには引き続き拒否される)。あわせて、`.claude/{hooks,skills,commands,rules,agents}/` (プロジェクト側・`~/.claude/` 側の両方) に新しい資産を作ろうとしたら、同梱の `hooks/asset-index.json` から aidd の資産一覧 (名前と description) を additionalContext で渡し、役割が重なるならそれを使うか aidd への要望として起票するよう促す。重なりの判断はモデルに任せ、aidd の command・skill・agent と同名のときだけ拒否する (command・agent は種類のディレクトリ直下のファイルだけ比べる。`commands/adr/new.md` は `/adr:new` になり、agent の名前は frontmatter で決まるため)。既存の資産と既存 skill 内のファイルは対象外。`AIDD_ASSET_OVERLAP_PLUGINS` で指定した他のプラグインの資産も、そのディレクトリの `.claude-plugin/plugin.json` から実行時に読んで一覧に加える (同梱の一覧には入れない。`<plugin>:<name>` の名前空間で利用側の同名の資産と共存するため、案内だけで拒否しない)

### `harness-adapter.sh`

Codex の `apply_patch` と Cursor の Shell / Write / Read / SessionStart を、既存スクリプトが読める形に揃えて呼び、返事を各ハーネスの形に戻す。判定ロジックは持たない。adapter 自体は常に exit 0。子の起動失敗 (`script_failed`)、非0終了 (`script_nonzero_exit`)、シグナル終了 (`script_signaled`) を `adapter-skips.json` に計数する。異常終了時は有効な拒否 JSON のみ保持し、通知 JSON・テキストは破棄する。複数ファイルの一部で失敗しても、他ファイルの拒否を保持する。Cursor の Read は、`file_path` が無いとき、または存在する絶対パスで `..` を含まず bash の `-ef` で対象と別ファイルだと分かったときだけ python を起動せずに抜け、それ以外 (名前・バックスラッシュを含む、相対パス・`~`、存在しないパス、`file_path` が複数など) は python を起動して `skill-gate.sh` に渡す。gate は `file://` の URI と `~` (`~user` は展開しない) を Cursor と同じ規則で解決し、相対パスは Cursor の基点に依存しないよう `/` と入力の `cwd` のすべての祖先から照合し (孤立サロゲートは U+FFFD として扱う。workspace の root が無い Read でも cwd を `/` にして動かす)、そのパスと正規化したパスのどれかが、この plugin の `skills/autonomous-review/SKILL.md` と同じ実ファイル (別名リンク・大小文字の違いを含む) のときだけ拒否する

## Hooks の書き込み先と無効化

hooks は上記スクリプトをセッション中に自動実行する。ファイル書き込みは `~/.claude/aidd/` 配下のみで、外部送信は一切しない:

| 書き込み先 | 内容 | 書き込み元 |
|-----------|------|-----------|
| `~/.claude/aidd/usage.json` | `/aidd:*` コマンドの使用数・最終使用時刻 | `usage-log.sh` |
| `~/.claude/aidd/main-tree.json` | 主ツリーごとの、git を実行したセッション ID と最終時刻 (失効時間を過ぎたものは削除)、警告済みの組 (相手の占有が失効したら削除) | `tool-reminder.sh` |
| `~/.claude/aidd/issue-search.json` | セッション ID とリポジトリの組ごとの、最後に `gh issue list --search` を実行した時刻 (1日を過ぎたものは削除) | `tool-reminder.sh` |
| `~/.claude/aidd/commit-why.json` | コミットの検査で判定済みの SHA と判定時刻 (新しい 200 件まで) | `tool-reminder.sh` |
| `~/.claude/aidd/skill-gate.json` | `skill-gate.sh` が返した判定の種類 (`ask` / `ask_failclosed` / `deny_cursor_read` / `deny_shell_read`) ごとの件数と最終日時 (skill 名・パス・入力は残さない。承認・拒否の結果は hook から見えないので数えない) | `skill-gate.sh` |
| `~/.claude/aidd/adapter-skips.json` | adapter の変換失敗・子の異常終了などの `{harness, harness_version, event, tool_name, reason}` ごとの件数と最終日時。`/aidd:doctor` で確認できる (入力本文・stdout・stderr・終了番号は残さない) | `harness-adapter.sh` |
| `~/.claude/aidd/*.json.lock`、`*.json.tmp` | 上の状態ファイルを更新するときの排他ロック (空ファイル、残る) と書き込み途中の一時ファイル (置き換えで消える) | `usage-log.sh`、`tool-reminder.sh`、`harness-adapter.sh`、`skill-gate.sh` |
| `~/.claude/aidd/projects/<プロジェクトキー>/hook-log/<hook-id>.jsonl` | 利用側の hook の発火1回ごとに、実行前の `start` 行と、終了後の時刻・イベント名・`ok` / `block` / `error` / `killed`・終了コードの行 (hook の入出力の中身は記録しない。1 hook あたり 256KB を超えたら直近1000行に切り詰める)。同じディレクトリの `<hook-id>.since` はその hook の記録開始の目印 (ラッパーの初回実行か、`/aidd:asset-audit` が置く) | 利用側に導入した `aidd-hook-log.sh` |
| `~/.claude/aidd/projects/<プロジェクトキー>/asset-audit.last` | 棚卸しの最終実施日 (session-start の nudge が読む。書けなかったときはコマンドが報告し、実行するコマンドを示す) | `/aidd:asset-audit` |

`tool-reminder.sh` の状態記録はbest-effortで、JSONの外形・主ツリー状態の下位型や時刻が不正でも、計算済みの拒否を失わない。記録処理の例外も最終出力から隔離する。状態ロックの取得待ちは1回100msまでとし、取得できない場合は状態を変更しない（Git照会やOSのファイルI/O、hook全体の時間上限を保証する値ではない）。更新はロック内で一時ファイルを書いて原子的に置換する。状態を読めない・書けない場合に共有通知が省略されることはあるが、確認できた危険操作は拒否する。issue検索の確認に失敗した場合は従来どおり検索を要求する。

プロンプト本文は記録しない (0.25.0 で廃止。旧版が書いた `prompt_log` は次回の hook 実行時に削除される)。記録したくない場合や注入がノイズな場合は、環境変数で個別に無効化できる (シェル環境、または settings.json の `env` で設定):

| 変数 | 効果 |
|------|------|
| `AIDD_DISABLE_USAGE_LOG=1` | `usage-log.sh` の利用統計の記録をすべて止める (`prompt_log` の削除も行われなくなる)。`skill-gate.sh` の件数の記録も止める (許可の確認は止まらない) |
| `AIDD_DISABLE_HOOK_LOG=1` | `aidd-hook-log.sh` の記録を止める (包んだ hook はそのまま実行される) |
| `AIDD_DISABLE_AUDIT_NUDGE=1` | `session-start.sh` の棚卸しの nudge を止める |
| `AIDD_AUDIT_INTERVAL_DAYS=<日数>` | 棚卸しの nudge を出すまでの期間と、`/aidd:asset-audit` が「一定期間発火しない」とみなす期間 (既定30。10進で読み、1〜5桁の数字以外は既定値) |
| `AIDD_DISABLE_CLARIFY_NUDGE=1` | `session-start.sh` の不明点確認指示の注入を止める。注入文は確認手段を1つに固定しないため非対話セッションでも矛盾しないが、確認自体を求めたくない自動実行では設定する |
| `AIDD_DISABLE_REVIEW_BEFORE_PR=1` | `tool-reminder.sh` の `gh pr create` 前のレビュー証跡の警告を止める |
| `AIDD_REVIEW_BASE=<branch>` | レビュー証跡の警告で使う基点ブランチ。コマンドの `--base` を優先し、どちらも無ければ `origin/HEAD`、それも無ければ `main`、次に `master`。どれも解決できなければ、確認しなかったことを1行で伝える |
| `AIDD_REVIEW_SKIP_PATHS=<正規表現>` | レビュー証跡の警告で「コードの変更」に数えないパス (既定 `(^docs/`、`\.md$`、`\.txt$` の OR)。変更がすべてこれに当たれば警告しない |
| `AIDD_REVIEW_LIST_LIMIT=<件数>` | レビュー証跡の警告に並べる変更ファイルの上限 (既定 20)。超えた分は件数だけ出す |
| `AIDD_COMMAND_WRAPPERS=<a,b c>` | `tool-reminder.sh` がコマンドの前置として読み飛ばすラッパーを追加する (カンマ区切り、1つが複数語でもよい。例 `chronic,sudo -E`)。既定は `rtk proxy`・`rtk`・`command`・`env`・`time`・`nohup`・`exec` と、行頭の `VAR=value`。一覧に無い前置の後ろのコマンドは判定されない |
| `AIDD_DISABLE_GIT_SAFETY=1` | 未コミットの作業を失う git 操作と指名しないステージの拒否を止める |
| `AIDD_DISABLE_MAIN_TREE_WARNING=1` | 主ツリーの共用の警告を止める |
| `AIDD_MAIN_TREE_TTL_MINUTES=<分>` | 主ツリーの占有を有効とみなす時間 (既定 30)。これより前に git を実行したセッションは占有していないものとする |
| `AIDD_WORKTREE_DIR=<path>` | 主ツリーの共用の警告で案内する worktree の作成先 (既定 `.claude/worktrees`。相対パスは主ツリーから) |
| `AIDD_DISABLE_ISSUE_SEARCH_GATE=1` | `gh issue create` 前の重複検索の要求を止める |
| `AIDD_ISSUE_SEARCH_TTL_MINUTES=<分>` | `gh issue list --search` の結果を有効とみなす時間 (既定 30) |
| `AIDD_REQUIRED_LABEL_PREFIX=<接頭辞>` | 設定すると、`gh issue create` にこの接頭辞 (例 `priority:`) で始まる `--label` が無ければ拒否する。未設定なら判定しない (そのラベルを持たないリポジトリで起票できなくなるため既定は無効)。ラベルの選び方は `issue-priority` skill |
| `AIDD_DISABLE_COMMIT_WHY_CHECK=1` | `git commit` 後の HEAD の検査を止める |
| `AIDD_COMMIT_TYPES=<a,b>` | 設定すると、コミットの件名が Conventional Commits 形式でこの type か (英数字と `-`) を検査する。未設定でもリポジトリのルートに commitlint の設定 (`commitlint.config.*`・`.commitlintrc*`・`package.json` の `commitlint`) があれば既定の `feat,fix,docs,style,refactor,perf,test,build,ci,chore,revert` で検査し、どちらも無ければ件名は検査しない (件名の規約が違うリポジトリで書き換えを促さないため)。`Revert "..."` は検査しない |
| `AIDD_COMMIT_BODY_EXEMPT_TYPES=<a,b>` | 本文が無くてもよい type (既定 `docs,style,chore`) |
| `AIDD_COMMIT_IGNORED_TRAILERS=<a,b>` | 本文の有無を数えるときに除くトレーラー (既定 `Co-Authored-By,Signed-off-by,Refs,Closes,Fixes,Resolves,Reviewed-by,Change-Id`)。除くのは最後の段落だけで、その段落が `Key: value` の行と、`:` の無い issue 参照 (`Closes #19` のように `Closes` / `Fixes` / `Resolves` / `Refs` の後ろに `#番号`・`owner/repo#番号`・URL) の行だけでできているときに限る (`Fixes the crash ...` のような本文は除かない) |
| `AIDD_COMMIT_WHY_CANON=<文書と節>` | コミットの検査と `four-kinds-check` skill が参照する正典。設定するか、リポジトリの `CLAUDE.md` (または `.claude/CLAUDE.md`) に「コメントの置き場所」の節があるときだけ、コミット本文の有無を検査する |
| `AIDD_DISABLE_UNREADABLE_NAME_GUARD=1` | `write-guard.sh` の読み取り拒否名の検査を止める |
| `AIDD_UNREADABLE_NAME_PATTERNS=<p1>:<p2>` | `write-guard.sh` が拒否するパターンを既定から差し替える (コロン区切りの glob)。利用側の `sandbox.filesystem.denyRead`・`sandbox.credentials.files` の値はそのまま書ける: `~/` はホーム、`/` と `//` は絶対パス、`./` と接頭辞なしで `/` を含むものは hook 入力の cwd (通常はプロジェクトルート) からの相対で、パスはそのディレクトリの下すべてにも当たる (末尾の `/`・`/**` は有っても無くても同じ。ユーザー設定の `./`・接頭辞なしの値は `~/.claude` 基準なので `~/.claude/...` と書く)。`/` を含まない名前はどの深さのファイル名とも照合し、`secrets/`・`secrets/**` のようにディレクトリと示した名前は cwd 以下のどの深さの同名ディレクトリの中にも当たる。`Read(...)` の deny ルールは `/` の意味が違うので書き換える: `Read(//abs/**)` → `/abs/**`、プロジェクト設定の `Read(/path)` → `./path`、ユーザー設定の `Read(/path)` → `~/.claude/path` (`Read(~/x)`・`Read(.env)`・`Read(secrets/**)` はそのまま) |
| `AIDD_DISABLE_ASSET_OVERLAP=1` | `write-guard.sh` の資産重複の案内と同名拒否を止める |
| `AIDD_ASSET_OVERLAP_DIRS=<k1>:<k2>` | 資産重複の検査対象にする `.claude/` 直下のディレクトリ (既定 `hooks:skills:commands:rules:agents`) |
| `AIDD_ASSET_OVERLAP_DENY_SAME_NAME=0` | 同名の資産も拒否せず、一覧の案内だけにする |
| `AIDD_ASSET_OVERLAP_PLUGINS=<dir1>:<dir2>` | 資産重複の一覧に加える他のプラグインのディレクトリ (コロン区切り。`~/` はホーム、相対パスは hook 入力の cwd から。既定は aidd の一覧だけ)。**信頼できるディレクトリ (導入済みのプラグインの置き場) だけを指定する**: 指定したディレクトリの manifest と frontmatter の名前・description は、改行と制御文字を空白にし長さを切ったうえで、ほぼそのまま additionalContext (system reminder) に入る (一覧は各プラグインのファイルから読んだデータで指示ではない、と1文添えるが、それで防げるとは限らない)。相対パスは作業中のリポジトリの中を指すので、リポジトリに書き込める人が文面を差し込める (issue やコメントの作者を信頼しきれない自動実行の環境では特に)。絶対パスか `~/` で書く。導入済みのプラグインだけを指すなら、Claude Code がもともと読んでいる description を並べ直すだけなので、新しい危険はほぼ増えない。置き場は各ディレクトリの `.claude-plugin/plugin.json` から `scripts/generate-asset-index.py` と同じ規則 (`commands`・`agents` は既定の走査を置き換え、`skills` は既定に追加、`hooks` はマージ。manifest が無ければ既定の配置を読み、名前はディレクトリ名) で決め、資産ディレクトリへの新規作成のときだけ読む。名前は plugins-reference の既定の配置に従う: `skills/` も `skills` キーも無ければルートの `SKILL.md` を1つの skill として読み、既定の `agents/`・`commands/` のサブフォルダは名前に `<サブフォルダ>:` を足す (manifest の `commands` に書いたディレクトリはサブフォルダを読まない。公式のドキュメントが平らな `.md` のディレクトリとしか書いていないため)。frontmatter の YAML ブロックスカラー (`|`・`>`) も読む。manifest の `name` が命名規則 (空白・`@`・`:`・パス区切り・制御文字・双方向制御文字を含まない) に反するプラグインは Claude Code が読み込まないので、読めなかったものとして扱う。プラグインごとに `[<plugin>]` の見出しを付け、名前は 64 字、description は 120 字で切り、additionalContext の上限 (10,000 字。UTF-16 の単位で数える) に収まらない分は件数だけ出す (aidd の一覧は常に全件)。存在しない・manifest が壊れている・manifest も資産も無いディレクトリは飛ばし、その旨を1行添える。導入済みのプラグインの置き場 (`~/.claude/plugins/cache/...`) は更新でバージョンのディレクトリが変わるため、変わったら読めなかった旨の行で気づける。`asset-overlap-prompt-hook.json.template` は同梱の一覧から生成するので、他のプラグインの資産は含まない |

<プロジェクトキー> は git の共通ディレクトリ (`git rev-parse --git-common-dir`) の親のパスの英数字以外を `-` に置き換えたもの。worktree を含めて1リポジトリ1キーになる (hook が見る `CLAUDE_PROJECT_DIR` はセッション開始時のルートのまま、モデルのシェルの cwd は worktree や `cd` 先に移るため)。git の外では `CLAUDE_PROJECT_DIR` (無ければ cwd) から作る。

非対話・監督下のセッション (print モード、スケジュール実行、親エージェントが指示を出すサブエージェント) では、注入文の指示どおり「このセッションが持つ確認手段」を使う。人間に届く手段が無い場合は前提を最終報告に明記させる形になるため、確認そのものを止めたい場合は `AIDD_DISABLE_CLARIFY_NUDGE=1` を設定する。

## `aidd-hook-log.sh` の導入 (利用側プロジェクト)

aidd の hook ではなく、**利用側プロジェクト自身の hook** の発火を記録する。記録したい hook ごとに、既存のコマンドの前にラッパーと hook-id (記録ファイル名。英数字・`.`・`_`・`-`) を足す:

```bash
mkdir -p .claude/hooks
cp <aidd>/templates/aidd-hook-log.sh .claude/hooks/   # 実行ビットごとコピーしてコミットする
```

```jsonc
// .claude/settings.json (変更前)
"command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/format.sh"
// 変更後: <wrapper> <hook-id> <元のコマンド...>
"command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/aidd-hook-log.sh format \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/format.sh"
// パイプや && を含む元のコマンドは bash -c で1つの引数にまとめる
"command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/aidd-hook-log.sh lint bash -c 'npm run lint --silent && echo ok'"
```

ラッパーは包んだ hook の終了コード (2 の阻止も含む) と stdout / stderr をそのまま返すので、hook の振る舞いは変わらない。終了コードが 0 と 2 以外なら `error` 行になる。timeout などでラッパーが TERM / HUP / INT を受けたときは、包んだ hook も止め (INT は TERM として渡す。bash がバックグラウンドの子に INT を無視させるため)、`killed` 行を書いてから同じシグナルで終わる。trap の効かない SIGKILL では、実行前に書いた `start` 行だけが残る。ラッパーで包んでいない hook は発火を判定できないため、`/aidd:asset-audit` は削除候補にせず「判定不能」とする。
