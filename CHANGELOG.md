# Changelog

## 0.38.0 (2026-09-30)

- `skills/parallel-coordinator/`: 複数の issue・タスクを worker に並行実装させるコーディネーターの規律を追加。並列化の一般的な進め方は `superpowers:dispatching-parallel-agents` / `subagent-driven-development` / `using-git-worktrees` を指すだけにし、それらに無い差分だけを置く: 組み込みサブエージェント (`isolation: "worktree"`、バックグラウンド実行、完了通知、`SendMessage`) を既定とする実行環境、worktree が既定ブランチから切られること、`subagent-driven-development` の並列禁止が worktree で分けた worker には当たらないこと、`model` 省略時の決まり方と fork (`aidd:model-selection` 参照)、検証環境の割り当て、worktree 内の hook・スクリプトは `CLAUDE_PROJECT_DIR` ではなく入力の `cwd` を使うこと、外部実行環境の手順を写さないこと、spec に書く事実の確かめ方、共有ファイルの衝突、マージ順と rebase、worker への指示、報告の検証。複数 issue の並行実装で、古い issue 本文から書いた spec、新しく作るテストファイルの衝突、新しいテストが1度も CI で走らないまま後発がマージされること、数え直されない worker の報告が繰り返し起きたため (#25)

## 0.37.0 (2026-09-30)

- `asset-audit.md` (新規): 利用側プロジェクトの `.claude/` と `CLAUDE.md` を棚卸しし、削除・改訂・修正・統合・見直しの候補を根拠つきで出す。基準は、一定期間発火しない hook、期間内 (直したならその後) に `error` 行・`killed` 行・終わりの行が続かない `start` 行を持つ hook (削除ではなく修正候補。直す前の古い失敗で修正候補に残り続けないため期間で区切る)、参照先が消えた・状態を述べる記述が食い違う、前提が変わった、上流に吸収された、2箇所に同じ基準がある、観測1件からの一般化。候補が0件なら「問題なし」で終えず、基準と根拠の不足を疑う。実施日の記録 (サンドボックスでは `~/.claude/aidd/` に書けないことがある) に失敗したら黙って続けず、ユーザーが実行するコマンドを示す (nudge が止まらなくなるため)。規約と hook は事故のたびに足されて単調に増えるのに、削る入口が無かったため。`/aidd:retro` と同じ型だが、retro は aidd 自身の資産、こちらは利用側の資産と境界を分けた
- `incident-retro.md` (新規): セッションの事故を棚卸しし、再発防止の置き場をコード (今直さないなら issue) → hook → ADR (決定とその理由) → `CLAUDE.md` / memory (リポジトリを移っても効くか) → コマンドの順で決める。ADR を規則より前に置くのは、設計判断も「判断を伴う規則」に当てはまり、後ろに置くと ADR に届かないため。一般則にする前にその規則で壊れるものを1件挙げさせ、足す前に既存の記述との重複を確かめる。置き場を決めずに書くと同じことが2箇所に書かれるため。ADR・issue は `/aidd:adr`・`/aidd:issue-split` に委ね、中身を複製しない
- 両コマンドは `disable-model-invocation: true` にした。正典から記述を削る・足す判断を、モデルが自分の判断の続きとして始めないため (プラグインの commands も skills と同じ frontmatter を受けることを Claude Code のドキュメントで確認)
- `templates/aidd-hook-log.sh` (新規): 利用側の `.claude/settings.json` に書いた hook を包み、発火ごとに時刻・イベント名・`ok` / `block` / `error`・終了コードを `~/.claude/aidd/projects/<キー>/hook-log/` に記録するラッパー。包んだ hook の stdin・stdout・stderr・終了コードはそのまま通し、振る舞いを変えない。timeout などでラッパーが TERM / HUP / INT を受けたら包んだ hook も止め、`killed` 行を書いて同じシグナルで終わる (包んだ hook が孤児として走り続けず、常に止まる hook が「発火しない」に見えないため)。SIGKILL に備え、実行前にも `start` 行を書く。記録開始の目印は hook ごとの `<hook-id>.since` にした (後から包んだ hook が「発火しない」に見えないため)。記録のキーは git の共通ディレクトリの親から作り、worktree を含めて1リポジトリ1キーにした (hook の `CLAUDE_PROJECT_DIR` はセッション開始時のルートのまま、`/aidd:asset-audit` を実行するシェルの cwd は worktree や `cd` 先に移り、キーが食い違うため)。hook の入出力の中身は記録せず、外部送信もしない。「発火しない hook」を判定する記録がどこにも無かったため。無効化は `AIDD_DISABLE_HOOK_LOG=1`。CI の shellcheck の対象に `templates/*.sh` を加えた
- `session-start.sh`: `/aidd:asset-audit` の最終実施日 (未実施ならラッパーが最初の hook の記録を始めた日) から `AIDD_AUDIT_INTERVAL_DAYS` (既定30日。10進で読み、1〜5桁の数字以外は既定値) が過ぎたプロジェクトでだけ、棚卸しを促す1文を出す。どちらの記録も無いプロジェクトでは出さない (常時注入を増やさないため)。無効化は `AIDD_DISABLE_AUDIT_NUDGE=1`。`retro.md` にも対象の境界を1行追記した (#26)

## 0.36.0 (2026-09-30)

- `write-guard.sh`: 利用側で `.claude/{hooks,skills,commands,rules,agents}/` (プロジェクト側と `~/.claude/` 側) に新しい資産を作ろうとしたら、aidd の資産一覧 (名前と description) を additionalContext で渡し、役割が重なるならそれを使うか aidd への要望として起票するよう促す。運用ルール4 (重複禁止) は aidd を作る側の規則で利用側には効いておらず、利用側で似た資産を作ると同じ規則が2か所で別々に直され片方だけ古くなるため。定期的な棚卸しで見つけるより、作る瞬間に知らせる方が消す手間が残らない。重なりの判断はモデルに任せ、aidd の command・skill・agent と同名のときだけ拒否する (command と skill は同じスラッシュ名前空間なので互いに比べる。command・agent は種類のディレクトリ直下のファイルだけ比べ、サブディレクトリ内は一覧の案内だけにする。`commands/adr/new.md` は `/adr:new` で `aidd:adr` と衝突せず、agent の名前はファイル名でなく frontmatter の `name` で決まるため)。既存の資産と既存 skill 内のファイルは対象外。`AIDD_DISABLE_ASSET_OVERLAP=1`・`AIDD_ASSET_OVERLAP_DIRS`・`AIDD_ASSET_OVERLAP_DENY_SAME_NAME=0` で調整できる。hooks.json の `if` では絞らない (1ハンドラ1ルールで、作業ディレクトリ配下にしか当たらず `~/.claude/` を拾えないため、スクリプト内で判定する) (#28)
- `hooks/asset-index.json` と `scripts/generate-asset-index.py` を追加。実行時に資産一覧を返す公式の手段が無いため、リリース時に一覧を生成して同梱し、hook は `${CLAUDE_PLUGIN_ROOT}` から読む。skill・command・agent の置き場は manifest で差し替えられるので、生成スクリプトは `plugin.json` の `commands`・`agents` (既定の走査を置き換える)・`skills` (既定に追加する)・`hooks` を読んで置き場を決め、ディレクトリを決め打ちで走査しない。一覧と実物のずれは CI (`validate.yml`) に足した `python3 scripts/generate-asset-index.py --check` と `tests/hook-contract-test.sh` で検出する (CI は `tests/*.sh` を実行しないため、資産を足す PR が一覧の再生成を忘れても通ってしまうのを防ぐ) (#28)
- `asset-overlap-prompt-hook.json.template` を追加。厳格に止めたい利用側向けに、Write のたびにモデルが aidd の資産一覧と意味の近さを判定して拒否する prompt 型 hook の雛形 (既定では無効)。Edit はファイルを作れないので Write だけを対象にし、資産ディレクトリごとに `if: Edit(**/.claude/<dir>/**)` で絞る (Edit 形式のルールは Write にも当たる)。prompt 型 hook はファイルの有無を見られないため、既存資産の上書きも判定される点を templates/README.md に書いた (#28)

## 0.35.0 (2026-09-30)

- `write-guard.sh` を追加。Write・Edit・NotebookEdit の PreToolUse を1本の dispatcher で受け、まだ存在しないファイルがサンドボックスの読み取り拒否によく入る名前 (`.env*`・`*.pem`・`*.key`・`*secret*`・`*credential*`・`*token*.json`・`*/.ssh/*` など) に当たるときだけ拒否する。そうした名前で作ったファイルは sandbox 内の git・テスト・シェルから読めなくなり、作った後で気づいて名前を変える手戻りが複数セッションで起きていたため。Claude Code には読み取り拒否の既定リストが無い (`sandbox.filesystem.denyRead` の既定は未設定) ので、既定パターンは aidd が持ち、`AIDD_UNREADABLE_NAME_PATTERNS` で利用側の設定に合わせて差し替え (書き方は `sandbox.filesystem.denyRead` と同じで、`~/`・`/`・`//`・cwd 相対を解決し、ディレクトリはその下すべてに当たる。`Read(...)` の deny ルールは `/` の意味が違うため README の書き換え例に従う)、`AIDD_DISABLE_UNREADABLE_NAME_GUARD=1` で止められる。hooks.json では `if` で絞らない (名前はどの場所にも現れ、1つの permission ルールでは表せない)。既存ファイルと対象外のパスでは何も出さずに終わる (#21)

## 0.34.0 (2026-09-30)

- `four-kinds-check` skill を追加。`CLAUDE.md.template` の4分類 (コードには How、テストコードには What、コミットログには Why、コードコメントには Why not) を、staged diff の追加行のコメント・テスト名と、これから書くコミット本文に当てて確かめる。テンプレートは規約を持つが、守られているかを見る手段が無かったため。0.29.0 では「ほぼ全タスクで発火する」として skill 化を見送った。発火の条件にした「追加行にコメントかテスト名がある、またはコミット本文を書くとき」はほぼ毎回のコミットに当たるため、実際に絞っているのは、規約を採るプロジェクト (`CLAUDE.md` に「コメントの置き場所」の節がある、または `AIDD_COMMIT_WHY_CANON` を設定した) に限ったことである
- `tool-reminder.sh`: `git commit` の後に HEAD を検査し、足りなければ注入する。本文 (最後の段落にある除外するトレーラーを除く) の有無は、`AIDD_COMMIT_WHY_CANON` を設定したか、リポジトリの `CLAUDE.md` に「コメントの置き場所」の節があるときだけ見る。件名の Conventional Commits 形式は、`AIDD_COMMIT_TYPES` を設定したか、commitlint の設定があるときだけ見る (`Revert "..."` は除く)。規約の違うリポジトリ (日本語の件名など) で `git commit --amend` を促さないため。PreToolUse でコマンド文字列からメッセージを切り出すと `-m "$(cat <<'EOF' ...)"` で偽陽性になるため、確定後の HEAD を読む。判定済みの SHA は `~/.claude/aidd/commit-why.json` に置き、同じコミットでは1回だけ鳴らす (`--amend` は新しい SHA なので改めて見る)。`git commit ... && git push` の push が拒否されたときのように、コミットの後のコマンドが失敗すると PostToolUse ではなく PostToolUseFailure が届くため、PostToolUseFailure にも登録し、そこではコミットの検査だけを行う。コミット自体が失敗した場合は HEAD が古いまま (他人のものかもしれない) なので、10分より前のコミットは見ない。マージコミットと `fixup!` / `squash!` / `amend!` も見ない。受理する type・本文を免除する type・除外するトレーラー・正典は `AIDD_COMMIT_TYPES` / `AIDD_COMMIT_BODY_EXEMPT_TYPES` / `AIDD_COMMIT_IGNORED_TRAILERS` / `AIDD_COMMIT_WHY_CANON` で設定する (#20)

## 0.33.0 (2026-09-30)

- `issue-priority` skill を追加。issue を読んで優先度ラベルを判定・付与する。深刻さと広さの2軸で出発点を決め、放置コストで1段上げる (「重要だから上げる」ではなく「待たせられないから上げる」)。最上位は自分だけで付けず根拠を示して確認し、既存のラベルは黙って張り替えず、系列が独自のラベル運用を宣言していれば上書きしない。既定のラベルは `priority:P0`〜`P3` の4段で、ラベル名・段数・追加の軸は利用側の `.aidd/issue-priority.md` で定義できる。issue の選定コマンド (#24) はラベルを消費するだけで基準を持たないため、基準を別の skill に置いた。各軸の上位は4段のうち先頭の2段とし、段の順序は `P0` を最上位とする (ラベルで並べる側が順序を決められるように)。優先度の付与や見直しを頼まれていない起票では、`AIDD_REQUIRED_LABEL_PREFIX`・`.aidd/issue-priority.md`・`gh label list` の優先度ラベルがどれも無ければ何もしない。ラベルの作成は明示的に頼まれたときだけ提案する (優先度ラベルを使わないリポジトリで、起票のたびに判定と確認を挟まないため)
- `tool-reminder.sh`: `AIDD_REQUIRED_LABEL_PREFIX` を設定すると、その接頭辞のラベルが無い `gh issue create` を拒否する。文書で「必ず付ける」と書いた規則は、書いた本人の起票でも守られなかったため hook で揃える。そのラベルを持たないリポジトリで起票できなくならないよう、未設定なら判定しない。`gh -R <repo> issue create` のようにグループの前に `-R` / `--repo` を置いた形も判定する (#27)

## 0.32.0 (2026-09-30)

- `tool-reminder.sh`: 複数のセッションが同じリポジトリを扱うと起きる事故を止める3つの判定を足した。手順書では止まらなかったため。(1) 未コミットの作業を失う git 操作 (`stash` の `list` / `show` 以外、`reset --hard`、パスを指定した `checkout` (`checkout -- <path>`、`checkout .`、`checkout <tree-ish> <path>`、コミットでなく作業ツリーに実在する名前だけの `checkout <path>`)、`checkout -f` / `--force`、`switch -f` / `--force` / `--discard-changes`、`--staged` だけでない `restore`、`-n` / `--dry-run` の無い `clean`) と、指名しないステージ (`add -A` / `--all` / `-u`、作業ディレクトリ・リポジトリのルート・その上を指すパス (`.`、`./`、`..`、`:`、`:/`、`:(top)` など)、`commit -a`) を拒否する。`checkout -b` と `checkout <branch>` は通す。`-am` のような結合したフラグは1文字ずつ読み、値を取るフラグ (`-m` など) の後ろは値として扱うので `commit -ma` や `-m "... -a ..."` は拒否しない。値を続けて書く形しか無いフラグ (`commit` の `-S[<keyid>]` / `-u[<mode>]`) は次の語を値として読まない (`commit -S -a` は拒否する)。(2) 主ツリーを別のセッションが直近 (`AIDD_MAIN_TREE_TTL_MINUTES`、既定 30 分) に使っているとき、相手ごとに1回だけ worktree への移動を促す。警告済みの記録は相手の占有が失効したときだけ消すので、相手が使い続けている間は再び警告しない。`session_id` は resume や compact の前後で同じと保証されていないため、拒否にはしない。(3) `gh issue create` を、同じセッションで直近 (`AIDD_ISSUE_SEARCH_TTL_MINUTES`、既定 30 分) に同じリポジトリに対して実行した `gh issue list --search` の後ろに置く (無ければ拒否)。リポジトリは `-R` / `--repo` (グループの前に置いた形も含む)、無ければ cwd の `origin` で決める (別のリポジトリの検索で起票が通らないようにするため)。検索の記録は PostToolUse で行う。`gh -R <repo> issue create` のようにグループの前に置いた `-R` / `--repo` も読み飛ばして判定する。settings.json 側の `if: Bash(gh *)` のようなフィルタはシェル展開を含むコマンドを取りこぼす実測があるため付けず、スクリプトの中で判定する。前置のラッパーは `AIDD_COMMAND_WRAPPERS` で足せる。状態は `~/.claude/aidd/main-tree.json` と `issue-search.json` に置く (#21)
- `/aidd:issue-split`: `gh issue create` の前に `gh issue list --search` で重複を確かめる手順を足した。上の (3) の判定で、最初の起票が必ず拒否されて1往復増えていたため (#21)

## 0.31.0 (2026-09-30)

- `tool-reminder.sh`: `gh pr create` の直前に、PR のブランチが基点ブランチに対してコードを変更しているのに `.aidd/autonomous-review/` にそのブランチの証跡 (`state.json` の `head` か `head_sha` / `head_sha_after_fixes` が一致するもの) が無ければ警告する。拒否はしない。証跡は `git worktree list` の全 worktree (主ツリーを含む) から探す (`/aidd:autonomous-review` は実行した worktree に証跡を書くため、PR を出す場所と一致するとは限らない)。`/aidd:autonomous-review` は PR の前に回す前提だが、手順書だけでは順序を守らせられなかったため。docs だけの変更では鳴らさない (毎回鳴る警告は読まれなくなる)。警告には変更ファイルの一覧を出し、docs だけのつもりのブランチに別ブランチのコミットが混入していることに気づけるようにした。対象は cwd の HEAD ではなく `--head` のブランチにする (worktree から PR を出すと cwd は別のブランチを指していることがある)。基点ブランチ・警告しないパス・一覧の上限・無効化は `AIDD_REVIEW_BASE` / `AIDD_REVIEW_SKIP_PATHS` / `AIDD_REVIEW_LIST_LIMIT` / `AIDD_DISABLE_REVIEW_BEFORE_PR` で設定する。基点ブランチは `--base`、`AIDD_REVIEW_BASE`、`origin/HEAD` の順に決め、どれも無ければ `main`、次に `master` を試す。どれも解決できなければ、確認しなかったことを1行で伝える (黙って通すと、証跡の確認が働いていないことに気づけないため)
- `tool-reminder.sh`: 判定を集めて最後に1回だけ出力する形にし、1回の起動で複数の判定が当たっても JSON 1つにまとめる (後続の拒否系の判定と注入文を1つの応答で両立させるため)。コマンドは shlex で分割し、`&&` / `;` / 改行で連結した各コマンド、`cd` と `git -C` による作業ディレクトリ、前置のラッパー (`rtk` など)、ヒアドキュメントの本文、`#` のコメント、`if` / `then` / `do` / `{` / `!` などの後ろに置いたコマンドを見分ける。コメントはシェルと同じく引用符の外で語の先頭にある `#` から行末までとし (`cd /x#y` の `#` はコメントではない)、コメントの次の行は別のコマンドとして判定する。引用符の中で触れただけのコマンドには反応しない。git の判定は hook 入力の `cwd` を基準にする (worktree の中では `CLAUDE_PROJECT_DIR` がメインのチェックアウトを指すため)。トークン最適化設計の方針4どおり1本の dispatcher のままで、コマンド (`tool_input.command`) に語としての `git` / `gh` が無い入力は python を起動せずに終わる。入力全体ではなくコマンドだけを見る (`cwd` や `transcript_path` に `git` / `gh` を含むプロジェクトで、毎回 python を起動していたため) (#19)

## 0.30.0 (2026-09-30)

- `model-selection` skill: 報告に使ったモデルを書く前に、実際に渡した `model` 引数を見る手順を追加。あわせて「デフォルトは継承」を実際の決まる順序 (`model` 引数 → agent 定義 → `CLAUDE_CODE_SUBAGENT_MODEL` → メインループ、fork は親のモデル) に直した。aidd の agent は定義で model を固定しており省略しても継承されず、弱いモデルのレビューは「指摘なし」で返り、意図したモデルで走らなかったことが出力に現れないため (#23)
- `review-loop` skill: サブエージェントの「全件確認した」を、入力のトークン概算と完了通知の `subagent_tokens` の比較 (固定分があるため入力が大きいときだけ) と、反証が書かれていそうな数件の現物確認で確かめる手順を追加。キーワード判定を全件確認として報告することがあるため (#23)

## 0.29.1 (2026-09-30)

- `autonomous-review.md`: 異種レビューを失ったまま進む経路を塞いだ。(1) codex はサンドボックス内で起動に失敗しても exit 0 で空の応答を返すため、終了コードや stderr の有無ではなく、`-o` (`--output-last-message`) で書かせた最終メッセージが JSON 契約どおりにパースできたかで成否を決め、できなければ `human_required` にする。成功時にも stderr に出る `WARNING: proceeding, ...` は失敗扱いしない。(2) 引数でプロンプトを渡しても stdin が開いていると入力待ちで止まるため、codex の呼び出しはすべて `< /dev/null` で起動し、Bash ツールの `timeout` パラメータで上限を付ける (macOS に `timeout` コマンドは無い)。起動前に `codex --version` で版を、`codex login status` でログイン状態を確かめる。(3) cwd から過去の run の `.aidd/` を読めると前回の結論をなぞるため、codex はラウンドごとに `git archive <対象のコミット> -- . ':(exclude).aidd'` でリポジトリ外に展開した `.git` の無いスナップショットで `--skip-git-repo-check -C` 付きで起動する (worktree は `.aidd/` を消しても共有オブジェクトから読めるため使わない)。ローカル差分は `git apply` でスナップショットに当て、ファイル・行の存在確認は変更後の内容で行う。スナップショットはそのラウンドの現物検証後に削除する。`state.json` は `schema_version` を `2` にし、スナップショットの記録を `rounds[].snapshot` に置いた (`worktree` は品質ゲート用だけ)。証跡の拡張子は `.txt` にした (`*.log` は一般的な `.gitignore` に当たり `git add <dir>` から無言で落ちる)。どの経路でも、同一モデルの自己レビューへ落ちたまま `approved` が出うるため (#22)

## 0.29.0 (2026-09-09)

- `CLAUDE.md.template`: コメントの置き場所の規約を同梱。「コードには How、テストコードには What、コミットログには Why、コードコメントには Why not」を原則とし、コメントは Why not だけを書く (排他) ことと、実況型・変更履歴・タスクID参照の違反例を各1行で添える。参考記事の実測では抽象原則だけの版は効果が半分で、具体的な違反例の列挙が効いたため両方を入れる。skill / hook 化はしない (実装フェーズのほぼ全タスクで発火し、常時注入と hook 起動を増やすため) (#6)

## 0.28.0 (2026-09-09)

- `session-start.sh`: 不明点の確認指示を経路非依存の文言にした。従来は `AskUserQuestion` を名指ししていたため、非対話 (print モード、スケジュール実行) や監督下のサブエージェントでは、答える人間がいないツールへ誘導していた。対話セッションなら AskUserQuestion、そうでなければ親・オーケストレーション層への返答、どちらも無ければ前提を最終報告に明記する、という形に変更。README にも非対話・監督下のセッションでの扱いと `AIDD_DISABLE_CLARIFY_NUDGE=1` の使いどころを追記。常時注入なので1文に収め (トークン最適化設計の方針6)、`tests/session-start-test.sh` に長さの上限検証を追加した (#8)

## 0.27.1 (2026-09-09)

- `adr.md`: 採番手順を追加。チェックアウト中の `docs/adr/` だけでなく、ローカル全ブランチ・`origin/HEAD` (未設定なら `git symbolic-ref` で検出して手順を委譲)・(並行作業がある場合は) 未マージのリモートブランチから既存番号を集め、その最大 +1 を使う。worktree / ブランチを並行させると同じ番号が二重に生まれ、番号は本文中と他 ADR から参照されるため後からの振り直しが高コストだったため。番号を捨てて slug だけにする代替案とその不採用理由もコマンド内に残した (#12)

## 0.27.0 (2026-09-09)

- `autonomous-review.md`: `state.json` のキーを型・必須・意味の表として固定し、`schema_version` を導入。同じ概念への別名 (`head_sha_at_start` / `findings_summary` / `worktree_isolation` など) を禁止し、`reviewer_version` / `reviewer_command` / `final_decision_reason` / `worktree` を正規キーに昇格。必須キー欠落・値域外の書き込みは `failed` とする。run を横断した証跡集計ができなかったため (#11)
- `autonomous-review.md` / `review-loop` skill: `deferred` の追跡先 (確定した issue 番号、または `.aidd/review-dismissed.md` への理由つき追記) をループの終了条件に加えた。どちらも満たさない `deferred` は `tracking: unresolved` として `human_required` とし、`auto_merge_eligible` にしない。判定した時点で指摘が証跡の中に消えていたため (#10)

## 0.26.0 (2026-09-09)

- `autonomous-review.md`: レビュー担当の verdict に関わらず、差分の性質に応じた観点別レビューを条件付きで追加する。例外捕捉・既定値フォールバック・空値返却を含む差分では `aidd:reviewer` にエラーハンドリング観点を、信頼境界を跨ぐ差分では `aidd:security-reviewer` を実行し、該当分が未実行なら `auto_merge_eligible` にしない。単一レビュー担当の `approved` を網羅性の根拠にできないため (#9)
- `usage-log.sh`: 起動の記録経路を、行頭が `/aidd:<name>` のプロンプト (UserPromptSubmit) と Skill ツール経由 (PreToolUse、matcher `^Skill$`) の2つに定めた。プラグインの hook はサブエージェント内でも発火するため (CLI 2.1.266 で実測、2.1.76 では発火しないとの報告あり)、Skill 経路でサブエージェント起動も拾える。自由記述から `aidd:<name>` を拾う方式は、1回の起動が4回計上される (親プロンプト・Agent 起動・サブエージェントの Skill 呼び出し・task notification) ため採らない。hook 入力は argv ではなく stdin から読み、ARG_MAX 超のプロンプトで記録が無言で落ちないようにした。計上対象を `commands/` と `skills/` の実在名に限定し、旧版が残した `prompt_log` (プロンプト先頭120文字) を hook 実行時に削除する (#7)

## 0.25.6 (2026-08-22)

- `autonomous-review.md`: `--base` / `--head` / `--reviewer` が未指定でも即終了せず、AskUserQuestion で未指定項目だけを決めてからレビューを始める。作業ツリー差分が空のときもブランチ比較へ切り替えを尋ねる

## 0.25.5 (2026-08-03)

- `autonomous-review.md`: `--reviewer claude` を追加し、同一モデル自己レビューを既定の Codex 異種AIレビューの代替として選べるようにした。未指定時は従来どおり `codex`。`--reviewer claude` 時の最終判定は常に `human_required`（`auto_merge_eligible` 不可）

## 0.25.4 (2026-08-03)

- `autonomous-review.md` / `design-review.md`: `argument-hint` の複数 `[...]` をクォートし、フロントマター YAML のパースエラーを修正

## 0.25.3 (2026-08-01)

- `infra-audit.md` を追加: 利用側プロジェクトの静的解析(複雑度制御)・重複/未使用コード検出(jscpd/knip)・多OS CI の導入状況を診断する新規コマンド。`doctor` が aidd 自身を診断するのに対し、こちらは利用側プロジェクトの品質ガード導入状況を対象とする (読み取り専用、設定ファイルの生成・編集は行わない)

## 0.25.2 (2026-08-01)

- `autonomous-review.md`: `--base <branch> --head <branch>` を追加。任意の2ブランチ間の三点差分を、現在の作業ツリーを変更しない一時worktreeでレビュー・品質ゲートの対象にできるようにした

## 0.25.1 (2026-08-01)

- `autonomous-review.md` を追加: Codex の read-only 異種AIレビュー、`aidd:refuter` による現物検証、最大3ラウンドの最小修正、検出済み品質ゲート、リスク別の自動マージ可否判定をローカルで統合。実行証跡は消費側 `.aidd/autonomous-review/<実行ID>/` に保存し、push・PR作成・マージは行わない
- `tests/autonomous-review-contract-test.sh` を追加し、レビュー担当の失敗時の `human_required`、構造化出力、品質ゲート、リスク判定、ローカル証跡の契約を検証

## 0.25.0 (2026-07-18)

重複した運用機能を整理し、常時コンテキストと不要な reviewer 起動を削減。

- `parallel-investigation` skill を削除し、並列調査は `superpowers:dispatching-parallel-agents` と `scout` agent に一本化
- `review-loop` を終了条件・severity・棄却済み指摘の持ち越しに縮小。静的検査・反証・修正手順は既存の specialist skills / agents を参照
- `retro`、`usage-log.sh`、`session-start.sh` から prompt history と20セッション nudge を削除。利用統計と陳腐化確認だけを維持
- `design-perspectives` から OWASP セキュリティ観点を削除。信頼境界を跨ぐ設計のセキュリティレビューは Agent 6 (STRIDE) に一本化

## 0.24.0 (2026-07-18)

通常利用時のトークン・hook 実行負荷を削減し、深いレビューが必要な場合の経路を明示化。

- `design-review.md`: `--depth=standard|deep` を追加。standard を既定とし、high/mid がない場合の refuter、裁定対象がない場合の arbiter を起動しない。詳細な severity・読了規約は agent 定義へ集約
- `agents/reviewer.md`: 指摘なしの出力を読了状況を含む1行に固定
- `agents/refuter.md`: 指摘、引用箇所、必要最小限の関連パスだけを入力とする契約を追加
- `tool-reminder.sh`: 3本の Bash hook を event-aware dispatcher へ統合。対象外コマンドは出力なしで終了
- `usage-log.sh`: `/aidd:*` の利用統計は維持し、全プロンプト履歴の保存を `AIDD_PROMPT_LOG=1` の opt-in に変更
- `session-start.sh`: 常時注入を短文化。`retro` は prompt history がない場合も集計・陳腐化確認を継続

## 0.23.0 (2026-07-18)

トークン効率の改善 (hooks の誤発火・冗長注入の削減と、design-review パイプラインの不要 dispatch の削減)。

- `pr-sync-reminder.sh` / `commit-reminder.sh` / `gh-language-reminder.sh`: stdin 全体ではなく `tool_input.command` のみをマッチ対象に変更。PostToolUse の stdin にはツール出力も含まれるため、"git push" を含む任意の出力 (ファイル閲覧・git log 等) で誤発火していた
- `clarify-nudge.sh` を廃止し、AskUserQuestion 確認指示を `session-start.sh` のセッション1回注入に統合 (恒常指示の毎プロンプト再注入は約45トークン×全プロンプトの無駄)。opt-out 変数 `AIDD_DISABLE_CLARIFY_NUDGE` は継続
- `session-start.sh`: 注入メッセージから agent 紹介を削除 (system prompt の agent 一覧と重複)
- `commit-reminder.sh`: staged 変更が docs/*.md/*.txt のみの場合は注入自体をスキップ (「docs-only なら省略可」の判断をモデル側に委ねない)
- `design-review.md`: 反証を生き延びた high/mid が0件の場合は arbiter (opus) を起動せず low 一覧を直接報告するショートカットを追加 (Agent 5 起動時・agent 間矛盾時は適用しない)
- `review-loop/SKILL.md`: 手順2の静的検査結果は要約のみ dispatch に含める (全量ログ渡しを禁止)。description を圧縮
- `agents/source-verifier.md` / `agents/security-reviewer.md`: description を圧縮 (毎セッション system prompt に常駐するため)。source-verifier のコスト注意書きは本文へ移動
- 深刻度ルーブリックの二重管理 (review-loop ⇔ design-review) は確認の結果、既に正典参照+最小埋め込みの形のため変更なし

## 0.22.0 (2026-07-18)

design-review パイプラインの精度を測定する評価ハーネスを追加 (これまで refuter・opus arbiter 等の各段の寄与が未検証だったギャップへの対応)。

- `commands/eval.md` を追加: `/aidd:eval` が `tests/eval/cases/` のゴールデンセットに design-review を通常経路 (並列 dispatch → refuter → arbiter、ショートカット禁止) で実行し、正解キーと意味照合して採点。指標は 検出率 / 反証誤棄却 / 深刻度一致 / デコイ誤検出 / セキュリティ条件起動。結果は `tests/eval/results/YYYY-MM-DD.md` に version 付きで保存し、直近結果と比較する
- `tests/eval/cases/` にシード欠陥入り設計書3件 (structure / data-error / security) を追加。structure には読了プロトコル検証用のデコイ (後半の決定事項で解決済みの論点)、security は Agent 6 の条件起動自体を測定対象に含む
- `tests/eval/keys/` に正解キー3件を追加 (欠陥ID・該当セクション・期待深刻度・一致判定基準)。汚染防止のためケースと別ディレクトリに分離し、レビュー完了まで読まない運用をコマンドに明記
- バージョン間比較の分母を「コアシード」(ケース作成時の意図的シード) に凍結。評価で昇格したキーは「昇格シード」として拡張検出率のみに数える (キー成長で比較が壊れるのを防ぐ)
- README 運用ルール6を追加: レビューパイプラインのプロンプト (design-review / refuter / design-arbiter / security-reviewer / reviewer) を変更するリリースは、リリース前に `/aidd:eval` を実行し結果を残す

## 0.21.0 (2026-07-17)

0.20.0 で design-review が出せるようになったセキュリティ指摘を、テスト観点まで流す受け皿を追加 (設計指摘 → 検証テストの導線の断絶を解消)。

- `test-perspectives.md`: 7番目の分類「セキュリティ (条件付き)」を追加。変更が信頼境界 (外部入力・認証認可・秘密情報・外部公開エンドポイント、design-review Agent 6 と同一条件) に触れる場合のみ出力し、design-review のセキュリティ指摘・`.aidd/design-perspectives.md` を入力として対策の検証観点 (認可・入力検証・エラー情報量・ログマスク) を must 付きで挙げる。触れない変更では分類自体を出力しない
- `test-perspectives.md`: 負荷・性能テストはコミット単位の観点に馴染まないためスコープ外と明記 (必要時は別途計画の1行を出力)

## 0.20.0 (2026-07-17)

セキュリティ・可観測性レビューの体系化 (Perspective-Based Reading / チェックリスト読解の実証知見に基づく「具体的観点の付与」)。0.17.1 の委譲ポインタ (忘れ防止) を、再現可能なレビュー手段に引き上げる。

- `templates/design-perspectives.md.template` を追加: OWASP ASVS 5.0 の設計段階に関わる章 (V1/V2/V6/V7/V8/V12/V13/V14/V16) から抜粋したセキュリティ観点 + 可観測性観点 (SLI 定義・Golden Signals・trace ID・障害シナリオのログ追跡可能性)。`.aidd/design-perspectives.md` にコピーして Agent 4 の観点として使う
- `agents/security-reviewer.md` を追加 (sonnet): 信頼境界を跨ぐデータフローに STRIDE 6カテゴリを機械的に適用する脅威レビュー agent。攻撃経路を具体的に構成できる懸念のみ high/mid で報告し、信頼境界のない設計は「該当なし」で終了
- `design-review.md`: 信頼境界を跨ぐ設計で security-reviewer を **Agent 6** として条件起動 (判定はメインループの意味判断、`--security` で強制・`--no-security` で抑止)。指摘は既存の refuter → arbiter パイプに合流。セキュリティ委譲節を役割分担 (Agent 6 = 設計の STRIDE、`/security-review` = 実装後のコード監査) に書き換え
- `agents/refuter.md`: セキュリティ指摘の反証規則を追加 — 攻撃経路が構成不能である現物証拠のみ反証成立。「攻撃されにくい」「フレームワークが守る (現物未確認)」は反証と認めず、反証の過程で回避手順を構成できた指摘は手順付きで存続
- 既知事項: `.aidd/design-perspectives.md` (Agent 4) と Agent 6 の指摘が重複しうるが、dedup は arbiter の既存責務で吸収する

## 0.19.0 (2026-07-17)

- `session-start.sh`: 20セッションごとの retro nudge に、`usage.json` から集計した aidd コマンド使用回数上位5件と繰り返しプロンプト最大2件を10行以内で注入。`jq` 不在・集計失敗時は従来の提案文へフォールバック
- `docs/adr/0001-retro-nudge-summary-injection.md`: 自動レポート化 scope 外決定を nudge 時の縮小サマリに限って変更し、cron・ダッシュボードによるフル自動化は引き続き採らない理由を記録

## 0.18.0 (2026-07-17)

- `review-loop/SKILL.md`: ユーザー承認で棄却した指摘を `.aidd/review-dismissed.md` に対象ドキュメント・要約・理由・日付付きで追記保存し、次セッションの初回 dispatch から再報告禁止として渡す手順を追加
- `design-review.md`: `.aidd/review-dismissed.md` を開始時に読み込み、削除済み・大幅改訂済みの対象のエントリを除外できるようにした

## 0.17.1 (2026-07-17)

- `design-review.md`: 外部入力・認証認可・秘密情報・外部公開エンドポイントを扱う設計では、レビュー結果末尾で `/security-review` の実行を推奨する委譲ポインタを追加（標準6観点・agent 分担は不変）
- `design-review.md`: 運用観点に、障害調査・性能分析を成立させるログ設計・メトリクス設計を明記
- `design-review.md`: セキュリティ観点を常設したいプロジェクト向けに `.aidd/design-perspectives.md` への追加を案内

## 0.17.0 (2026-07-17)

Integrate with the new stdd plugin (scientific test-design method catalog, split out of the aidd domain the same way uidd was): aidd keeps perspective listing and method-applicability flags; derivation procedures and citations live in stdd.

- `test-perspectives.md`: the 境界値 category now flags perspectives with "BVA適用" (ordered values: numeric ranges, lengths, dates) or "ECP適用" (inputs partitionable into valid/invalid classes) — flag judgment only, derivation steps and sources stay in stdd
- `test-perspectives.md`: point case derivation to stdd's `/stdd:test-design`, which takes the saved perspectives file as input (only when stdd is installed)
- README: add a uidd-style one-line pointer to stdd (no duplicated assets; aidd owns perspectives + flags only)

## 0.16.0 (2026-07-14)

Move review-unit splitting upstream: 0.15.0 added a reactive "consider splitting" note to review-loop; this release makes the split decision at design completion, before any PR exists.

- Add `commands/issue-split.md`: split a design into independently mergeable PR-sized units (vertical slices only, ~5 changed files each, boundaries taken from the design's component/responsibility section), present the plan, and create GitHub issues via `gh` only after AskUserQuestion approval (Japanese title/body with design-doc path, scope, done criteria, and dependencies); falls back to plan-only when `gh`/GitHub is unavailable; session-level task breakdown stays with superpowers:writing-plans
- `design-doc.md`: after saving, estimate implementation size from the design (heuristic: >5 changed files or 2+ independently mergeable units) and suggest `/aidd:issue-split` when over the threshold

## 0.15.0 (2026-07-14)

Review-accuracy improvements for review-loop / design-review, backed by external evidence (Anthropic Code Review's verify stage, adversarial refutation research, an industrial false-positive study, LLM-as-a-judge bias research, Google's Small CLs guide).

- Add `agents/refuter.md` (sonnet): adversarial verifier whose job is to disprove high/mid findings against the actual target, not confirm them; refutation requires evidence from the target ("unlikely" does not count), and only findings that survive are promoted
- `design-review.md`: insert a refutation stage between reviewers and arbiter — high/mid findings pass through aidd:refuter, refuted ones are discarded and reported separately with reasons (low findings and source-verified Agent 5 results skip the stage); accept a rejected-findings list in `$ARGUMENTS` and instruct reviewers not to re-report identical findings
- `skills/review-loop/`: carry rejected findings (refuted or mismatching the actual file, with reasons) across rounds as a "do not re-report" list included in each dispatch; re-reported rejected findings do not count toward the termination criterion; verified high/mid findings get a refutation attempt (via aidd:refuter or manually) before being fixed
- `skills/review-loop/`: add a concrete severity rubric for the canonical high/mid/low vocabulary (high = ships real damage: data loss/corruption, security, production outage; mid = correctness/maintainability impact with a workaround or limited blast radius; low = style/preference/improvement ideas) — severity variance directly destabilized the termination criterion, which counts high/mid findings
- `skills/review-loop/`: run the project's static checks (lint/typecheck/tests, whichever exist) before each round's dispatch and include the results; machine-detectable issues are delegated to static checks, not reported as review findings
- `skills/review-loop/`: when high/mid findings keep piling up every round, consider splitting the review unit before running more rounds (per Google's Small CLs guidance)
- `design-review.md`: embed the same severity rubric in the reviewer dispatch instructions (canonical copy lives in review-loop; keep in sync); instruct the arbiter to re-rank each finding against the rubric independently, not by description length or presentation order

## 0.14.0 (2026-07-13)

Lessons from a review-fix loop session in a consuming project (review findings applied blindly broke a framework's internal load path; mock-heavy tests missed it; review rounds had no stop condition).

- Add `skills/review-loop/`: decide the termination criterion before starting review-fix rounds (default: zero high/mid findings for 2 consecutive rounds); treat reviews as sampling that never converges to zero findings; read the framework implementation before applying suggestions that touch framework base classes; delegates per-finding handling to `superpowers:receiving-code-review`
  - Canonical severity vocabulary: high/mid/low (same scale as design-review/design-arbiter), with a translation table for external vocabularies (Critical/Important/Suggestion/Nit, Google's blocking/`Nit:`); sorting and termination judgment always use the canonical terms
  - Read-completion protocol for code-diff rounds run outside design-review: dispatched review agents must read all diff hunks plus surrounding context, attach file:line to findings, and report read-completion status; high/mid findings must be verified against the actual file with Read before applying (agent line numbers/function names can hallucinate)
- `test-perspectives.md`: add 6th category **フレームワーク結合** — framework/ORM base-class overrides and implicitly-invoked paths require at least one mock-less real-path test as must

## 0.13.0 (2026-07-12)

Team-readiness release: no functional changes to commands/agents/skills.

- **Breaking**: rename marketplace `aidd-local` → `aidd`. Existing installs must re-add: `/plugin marketplace add chun-mura/aidd` then `/plugin install aidd@aidd`
- Add MIT `LICENSE`; `plugin.json` gains `homepage`/`repository`/`license`/`keywords`; marketplace entry gains `category`/`tags`
- Hooks opt-outs: `AIDD_DISABLE_USAGE_LOG=1` disables prompt logging (`usage-log.sh`), `AIDD_DISABLE_CLARIFY_NUDGE=1` disables the per-prompt nudge (`clarify-nudge.sh`)
- Add `templates/team-settings.json.template`: project-scoped auto-install via `extraKnownMarketplaces` + `enabledPlugins`
- Add CI (`.github/workflows/validate.yml`): shellcheck on hook scripts + `claude plugin validate --strict`
- README: document runtime prerequisites (macOS/Linux, bash/python3/gh), consuming-project directory conventions, hook write targets and opt-outs, and the dependency compatibility policy for superpowers / pr-review-toolkit

## 0.12.0 (2026-07-10)

- `design-review.md`: prevent partial-read false findings on large doc sets
  - Reviewer agents must read assigned files in full, check later sections (decision log / revision history) before reporting "unresolved" issues, and report read-completion status
  - Split dispatch across multiple agents per perspective when the target exceeds ~5 files or ~3000 lines total; cross-file consistency perspectives still see the full file list
  - Arbiter discards findings tied to files an agent could not fully read, and quarantines "unresolved"-type findings lacking evidence of decision-log verification

## 0.11.0 (2026-07-09)

- Add `hooks/scripts/pr-sync-reminder.sh` (PostToolUse): after `git push`, remind to refresh the open PR's title/body via `gh pr edit` when the pushed commits changed its scope

## 0.10.0 (2026-07-09)

- Add `hooks/scripts/gh-language-reminder.sh` (PreToolUse): inject "write GitHub issue/PR titles and bodies in Japanese" before `gh pr/issue create|edit` runs

## 0.9.0 (2026-07-09)

- Add `agents/source-verifier.md` (sonnet, WebSearch/WebFetch/Read): verify externally checkable claims in design docs (technology-choice rationale, API/spec assertions, version compatibility, security recommendations) against trusted sources
- `design-review.md`: opt-in `--verify-sources` flag dispatches source-verifier as Agent 5; arbiter treats only 反証あり as ranked findings, 未確認 as informational

## 0.8.0 (2026-07-09)

- Add `skills/adr-recall/`: surface conflicting ADRs before architectural changes
- Add `hooks/scripts/usage-log.sh`: log aidd command usage and prompt history to `~/.claude/aidd/usage.json` for data-driven `/aidd:retro`
- Add `commands/design-sync.md`: detect drift between `docs/design/` and implementation; `design-doc.md` now writes a `status` frontmatter field
- `test-perspectives.md` now persists output to `docs/test-perspectives/`; `commit-reminder.sh` skips the reminder when a fresh file exists
- `design-review.md` supports project-specific perspectives via `.aidd/design-perspectives.md` (Agent 4, additive only)
- Add `commands/doctor.md`: diagnose aidd/superpowers install state, version drift, and hook prerequisites

## 0.7.0 (2026-07-08)

- session-start hook: warn (non-blocking) when superpowers plugin is not detected in installed_plugins.json
- README: document superpowers as a required companion plugin, add install step

## 0.6.0 (2026-07-08)

- Add `commands/retro.md`: periodic stocktake for promotion candidates, hook/skill friction, and staleness
- session-start hook: track session count in `~/.claude/aidd/state.json`, nudge toward `/aidd:retro` every 20th session

## 0.5.0 (2026-07-08)

- Add UserPromptSubmit hook (clarify-nudge): standing "ask via AskUserQuestion instead of guessing" instruction, replacing the manually typed one
- design-doc / adr: confirm design-affecting ambiguities via AskUserQuestion before writing

## 0.4.0 (2026-07-08)

- Add `commands/design-doc.md`: generate design docs into docs/design/, sections aligned 1:1 with design-review perspectives, volume auto-scaled to change size
- Add `commands/adr.md`: architecture decision records into docs/adr/, one decision per ADR
- superpowers-usage.md: add asset-form guide (skills/hooks/commands/docs) and adjacency rules for superpowers overlap

## 0.3.0 (2026-07-08)

- Add `agents/design-arbiter.md` (opus): design-review integration/arbitration now always runs on opus, independent of the main-loop model (fixes shallow arbitration when running sonnet as the main model)

## 0.2.0 (2026-07-08)

- Convert passive docs into auto-triggering skills: `skills/model-selection/`, `skills/parallel-investigation/` (former `docs/tips/model-selection.md`, `docs/patterns/parallel-investigation.md`)
- Remove `docs/tips/context-management.md` (generic process knowledge — superpowers territory)
- Add hooks: SessionStart asset nudge, PreToolUse `git commit` reminder for test-perspectives
- `design-review` now dispatches 3 reviewer agents in parallel instead of running inline
- `test-perspectives` output now feeds superpowers:test-driven-development
- Templates: add AI-operations section to CLAUDE.md.template, note `/fewer-permission-prompts` in templates README

## 0.1.0 (2026-07-08)

- Initial release: commands (design-review, test-perspectives), agents (scout, reviewer), templates, tips
