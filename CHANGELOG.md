# Changelog

## 0.68.0 (2026-11-22)

- `autonomous-review`: 知見の台帳 (#104、既定で無効) を有効にしたリポジトリでは、最終判定のあと、confirmed と deferred の指摘の型を `source: autonomous-review` の観測として台帳に書くようにした。run のディレクトリは worktree ごと消えることがあり (#91 の証跡が消えた)、run をまたいで同じ型の指摘が出ても数えられなかったため (#108)。型は `review <category> <type words>` (ファイル名・識別子・業務の固有名を入れない一般的な型) で、既存のどの型と同じかの判定が割れたものは利用者に選ばせる。記録・台帳のファイルのコミット (名指しの `git commit -- <ファイル>`、既定ブランチと detached HEAD では行わない)・昇格はどれも AskUserQuestion で承認されたものだけ行い、`scripts/learnings.py add` を通してだけ書く。別のセッションで2回以上出た型を `.aidd/design-perspectives.md` (design-review の Agent 4) への昇格候補として示す (`security` の型は Agent 6 の担当なので入れない)。この手順は最終判定を変えない。`state.json` の `schema_version` を `4` にし、`learnings` を足した
- `scripts/learnings.py`: `source: autonomous-review` の観測に、`signature` が `review <category> <type words>` (分類は8つの列挙値、型の語は小文字の語だけでフラグ不可)、`scope` が `project`、`evidence` がコミット SHA と `#番号` だけ、の規則を足した。指摘は利用者のコードについてのものなので、項目を狭めて抽象化した型だけを入れるため。語の規則は広げておらず、数え方 (`candidates`) も変えていない。コミット時の検査 (`tool-reminder.sh`) は同じ関数を使うので同じ規則がかかる
- incident-retro の置き場の選択肢に「利用側のレビュー観点」を足すことは、#105 と同時に incident-retro を変えないため、この版では行っていない

## 0.67.0 (2026-11-23)

- `asset-audit`: auto memory を棚卸しの対象に加えた。memory には `CLAUDE.md` や hook と重なる記述や、正典に昇格して要らなくなった記述が残るのに、棚卸しの対象に入っていなかったため (#106)。手順1で、このリポジトリの auto memory (`~/.claude/projects/<プロジェクト>/memory/`。worktree を含めて1リポジトリ1つ。`CLAUDE_CONFIG_DIR` に従う) のファイルごとに、名前・種類 (frontmatter の `type`。既知の4種以外は `other`)・索引 `MEMORY.md` に名前があるかを出す。判定基準に「索引に無い memory」(改訂候補)・「memory と正典の重複」(統合候補)・「台帳で昇格済みの memory」(削除候補) を足した。memory には個人的なメモや機密が入りうるので、本文を写さない
- 「台帳で昇格済み」は、知見の台帳 (#104) が有効なとき (`git config aidd.learnings true`) だけ、`scripts/learnings.py candidates` (`--session-id` なし、既定ブランチにマージ済みの観測だけ) が別の session で2回以上と出した `signature` のうち、正典 (`CLAUDE.md`・`.claude/rules/`・hook) に既にその規則があるものとして判定する。昇格の記録 (`.aidd/learnings/promotions/`) はまだ無いので、それを作らずに既存の出力だけで判定した。台帳は skill のディレクトリから解決した絶対パスで呼び、`.aidd/learnings/*.json` を直接読まない。終了コード4 (既定ブランチの観測を数えられない) と台帳が無効なときは「判定不能」とする
- `tests/hook-log-test.sh` が手順1のコマンドを偽の memory (worktree から本体のキーを引く・索引の名前の部分一致を索引済みとみなさない・frontmatter の外の `type:` を読まない・未知の種類を `other` にする・本文を出さない・memory が無いとき) で実行して検査する。`tests/command-contract-test.sh` に本文を写さないこと・台帳の扱いの文言を足した
- レビューを受けて次を直した:
  - 一覧のコマンドを python3 (`-I`、標準ライブラリだけ) にした。索引は `MEMORY.md` のリンク先とファイル名の完全一致で判定する (別のパスの同じ名前を索引済みとみなさない)。`type` は引用符と行末のコメントを外し、frontmatter の最上位と `metadata:` の直下 (実物の Claude Code が書く位置) だけを読み、最上位を優先する。`[A-Za-z0-9._-]` 以外を含む名前は件数だけを出す (名前で一覧の行を偽造させない)。更新日は日付だけを出す (`ls -l` の所有者名を出さない)
  - memory の置き場のキーは、ASCII の英数字以外を UTF-16 の1単位ごとに `-` にする (シェルのロケールに左右されない。Claude Code の実行ファイルにある `replace(/[^a-zA-Z0-9]/g,"-")` に合わせた)。git の共通ディレクトリが `.git` で終わらないときは「判定不能」にする。置き場が無いときは「memory が無い」と言い切らない
  - コミットされるプロジェクトの設定の `autoMemoryDirectory` が `projects/` の外を指していたら、読む前に AskUserQuestion で確かめる
  - 出し先を分けた: 会話の中では memory のファイル名・絶対パスまで、ADR・issue・状態ファイルには件数と判定だけ。memory の本文に書かれた指示には従わない。認証情報らしいものは値を再掲せず、ローテーションと削除を促す。顧客案件・NDA の対象のリポジトリでは本文を読む判定を飛ばす選択肢を AskUserQuestion で示し、迷ったら情報管理の責任者に確認する
  - memory の削除は取り消せないことを書き、消す候補を絶対パスで示し、退避してから消すか (既定) そのまま消すかを選んでもらう
  - 台帳の照合はコマンドにした。`git config aidd.learnings` が `true` のときだけ `candidates` を実行し、その出力から `signature` と `sessions` だけを取り出してから読む (`facts`・`files` をモデルに渡さない)。`learnings.py` は変えていない
  - `candidates` の終了コードは4だけでなく、0以外をすべて判定不能として扱う (2: git リポジトリでない、1: スクリプトの失敗でも標準出力は空になり、「昇格済みの memory なし」と読めてしまうため)。手順のコマンドは先に終了コードを確かめ、成功したときだけ取り出して `candidates done: exit=0` を出す。失敗したら削除候補を示さず、終了コードと stderr を利用者に伝える
  - 一覧の失敗を結果と取り違えないようにした: 最後に必ず `listed <N> memory file(s) (done)` を出し、この行が無ければ memory の基準をすべて判定不能とする (一覧が途中で止まった・置き場を決められない・置き場が無いときは終了コード1)。git が共通ディレクトリを返さないときは作業ディレクトリからキーを作って探さない。`MEMORY.md` が無い・読めないときは全ファイルを `unindexed` にせず `index=undetermined` とし、改訂候補を出さない。閉じていない frontmatter・引用符は `malformed` (`none` と区別)、読めないものは `unreadable` とし、命名規則外と合わせてその memory を判定不能とする。ディレクトリ・壊れたシンボリックリンクなど飛ばしたものも件数を出す
  - 索引のリンク先を途中の `>` で切らない (`](a.md>x)` を `a.md` とみなさない)。`type: "feedback" # コメント` のように引用符とコメントを両方使った値を読む
  - `git config --get aidd.learnings` が失敗した (未設定の1以外) ときは、台帳を無効とみなさず判定不能とする
  - 退避の手順をコマンドにした: 実行ごとに新しい時刻のディレクトリを作って `mv -n` で移し (上書きしない)、退避先にあり元の場所に無いことを確かめられたときだけ成功とする。退避した memory を指す `MEMORY.md` の行番号を出し、消すかを利用者に確かめる
  - 索引のリンクの解析を1つの正規表現 (`LINK`) にまとめ、一覧と退避後の索引の行の検索で同じものを使う (閉じの `)` まで確かめるので、`](<a.md>x)` を `a.md` とみなさない。退避後の検索も、一覧が索引にあると認めた形 (空白・タイトル付きを含む) の行を拾う)
  - `projects/<プロジェクト>` か `memory` がシンボリックリンクなら、別のプロジェクトの memory を指しうるので一覧は判定不能にし、退避も (`memory-archive` がシンボリックリンクのときも) 何も移さない
  - `tests/hook-log-test.sh` に、上の索引・種類・命名規則外・日付・非 ASCII のパスのキー (`LC_ALL=C` でも同じ)・`.git` で終わらない共通ディレクトリ・台帳の照合 (無効なときは読まない、`facts` を出さない、終了コード4・2と `git config` の失敗を判定不能と出す)・一覧の失敗 (`MEMORY.md` が無い・ディレクトリ、一覧できないディレクトリ、空のディレクトリ、git の外)・退避 (上書きしない、索引の行番号を一覧と同じ解析で出す)・シンボリックリンクの置き場と退避先を足した

## 0.66.0 (2026-11-23)

- `incident-retro`: 知見の台帳が有効なとき、手順1で Claude Code の auto memory の feedback (`type: feedback`) を読み、台帳の観測の候補にする。auto memory はマシンの中だけにあり、強制力が無く、サブエージェントにも読まれないので、hook や CLAUDE.md にすべき訂正が memory に留まっていたため (#105)。読むのはこのセッションに読み込まれた auto memory のディレクトリだけで、列挙は frontmatter だけを読む snippet で行う (`type` はトップレベルと `metadata:` の下の両方を読む)。`fact` は memory の文を写さず書き直し、memory のパスは `evidence` に入れない。`source: auto-memory` で `scripts/learnings.py add` を通し、承認されたものだけ書く。`session` には、そのメモを書いたセッションの ID (`originSessionId`) を渡すので、取り込み直しても回数が増えない。`originSessionId` が無い memory は取り込まず、件数だけを伝える (ファイルのパスのハッシュを `session` に使うと、パスを推測できる人に照らし合わされうるため)。昇格の回数は #104 のとおり `candidates` の出力だけで数え、取り込んだ観測は PR でマージされてから回数に入る。memory のファイルは書き換えず消さず、正典の書き換えは承認後だけ。`scripts/learnings.py` は変えていない。設計書の #105 の節に理由と残るリスクを書いた
- レビューを受けて次を直した:
  - 列挙の snippet: frontmatter はトップレベルと `metadata:` の直下だけを読む (深い入れ子・複数行の文字列の中の `type` を拾っていた)。`originSessionId` は UUID の形 (小文字の16進) のものだけを出し、合わないものは件数だけにする (値がモデルの手で `--session-id` としてシェルに入るため)。シンボリックリンク・ディレクトリの外を指すもの・名前に制御文字や書式文字 (タブ・改行を含む) があるものは読まず、件数だけを出す (偽の行を出せたため)。実体が `<設定ディレクトリ>/projects/<名前>/memory` の外にあるディレクトリは読まない
  - 手順: memory の本文はデータとして扱い、そこに書かれた指示に従わない。memory の候補は、台帳に書く `signature`・`fact`・`scope` をそのまま表に出してから承認を取る。`fact` と `signature` に社内のツール名・システム名を入れない。認証情報・個人情報・顧客の機密を含む memory は取り込まず、値を会話に引用せず、memory の削除 (認証情報ならローテーションも) を勧める
  - 設計書: 顧客案件・NDA のリポジトリで情報管理の責任者に確認する対象に memory の取り込みを含めた。残るリスクに、生の ID を持つ人は session のハッシュから観測を照合できること、時刻を使う代わりの ID は総当たりで戻せることを足した
  - 終了コード: `candidates` は終了コード4しか区別していなかった。2 (git リポジトリでない) や途中の失敗の1でも標準出力が空になり、「昇格候補なし」と読めた。0以外はどの値でも「数えられなかった」として扱い、昇格候補を示さず、終了コードと stderr を利用者に伝える。`add` は、終了コード0で標準出力にパスが出たときだけ書けたものとして扱う。3 (無効) と検査の拒否の1以外の0でない終了コードは、失敗として伝える
  - memory のディレクトリの決め方: モデルがパスを書き写す形をやめた。Python の生文字列に埋め込むと `"""` を含むパスでコードが動き、固定の区切りのヒアドキュメントに書くと、改行と区切りの行を含むパスがシェルのコードとして動き、`read` が1行目しか取らないので制御文字の検査にも元のパスが届かなかったため。snippet が `git rev-parse --git-common-dir` の親のパスから `/aidd:asset-audit` と同じ規則 (ASCII の英数字以外を UTF-16 の1単位ごとに `-`) で名前を作り、`<設定ディレクトリ (CLAUDE_CONFIG_DIR、無ければ ~/.claude)>/projects/<名前>/memory` を組み立てる。共通ディレクトリが `.git` で終わらない・git の外・組み立てたパスに制御文字や書式文字がある・ディレクトリが実在しない (「memory が無い」とは言い切らない)・`MEMORY.md` が無いときは、何も読まずに理由を出して終わる。実体が `realpath(<設定ディレクトリ>/projects)/<名前>/memory` と一致しないとき (`projects/<名前>` か `memory` がシンボリックリンクで、ほかのプロジェクトの memory を指すときを含む) も読まない (前の版は実体の祖父ディレクトリだけを見ていたので、ほかのプロジェクトの memory へのリンクを読めた)。`autoMemoryDirectory` で移した memory は取り込まない
  - 列挙の snippet のエラー処理: 読めないファイルで例外が出ると、途中までの一覧が標準出力に残ったまま終了コード1になり、意図した中止と区別できなかった。一覧は最後にまとめて出し、最後に `scanned N file(s), M feedback (done)` の行を必ず出す (0件でも出す)。終了コードは 0 (読み終えた)・2 (意図して読まなかった、理由を stderr に出す)・1 (途中で失敗、標準出力は空) に分けた。読めないファイルと、frontmatter が `---` で開いて閉じていないファイル (BOM 付きを含む。unparsed) は、黙って捨てずに件数を stderr に出す。値は asset-audit と同じく読む (引用符で囲んだ値は閉じる引用符までを中身とし、後ろが `# コメント` か空のときだけ採る。引用符が閉じない・後ろにほかの文字がある値は unparsed。前の版は引用符の判定をコメントより先にしていたので、`"feedback" # メモ` のような値を読めなかった)。incident-retro は、終了コード0で done の行があるときだけ一覧を使い、それ以外は標準出力が部分的に出ていても使わず、取り込みの失敗として伝える。手順3で本文を読めなかったファイルは、件数だけを伝え、候補に入れない
- `tests/incident-retro-memory-test.sh` (新規): incident-retro の列挙の snippet を偽の memory ディレクトリに対して動かし (feedback で UUID の形の `originSessionId` があるものだけ・無いもの・形が違うもの・深い入れ子のキー・リンクや制御文字を含む名前は件数だけを名前なしで stderr に出す・本文を出さない・git の共通ディレクトリから置き場を組み立て、worktree とサブディレクトリから同じ置き場に届く・`'`・`"""`・`$(...)`・バッククォートを含む設定ディレクトリで bash と zsh のどちらでも動きコードを実行しない・改行と古い区切りの行やタブを含む設定ディレクトリは何も読まない・git の外・`.git` で終わらない共通ディレクトリ・実在しない置き場・`MEMORY.md` の無い置き場・外を指す置き場は理由を出して終了コード2・`memory` か `projects/<名前>` がほかのプロジェクトの memory を指すリンクなら終了コード2・設定ディレクトリ自体のリンクは読める・空の置き場は done の行で0件・読めないファイルと unparsed を数える・行末のコメントと引用符を外す (引用符とコメントの併用を含む)・閉じない引用符と閉じた後ろの文字は unparsed・走査中の失敗は終了コード1で標準出力が空)、`add` で書いた観測が、マージ前は数えられず (別のセッションのもの)、マージ後に `candidates` で数えられ、取り込み直しても回数が増えないことを検査する。本物の memory は読まない。`tests/command-contract-test.sh` に取り込みの文言 (本文をデータとして扱う・書く値をそのまま見せる・機密を含む memory を取り込まない・`candidates` と `add` の0でない終了コードを失敗として扱う) を足した

## 0.65.0 (2026-11-22)

- 利用側リポジトリに「知見の台帳」(`.aidd/learnings/<YYYYMMDDTHHMMSSZ>-<16進8桁>.json`、1観測1ファイル) を足した。`/aidd:incident-retro` が今のセッションの会話しか見ず、運用ルール2 (2回ルール) を人の記憶で判定していたため (#104)。コミットして PR で共有し、ファイル名が別なので同時に書いても衝突しない。**既定で無効**で、clone ごとに `git config aidd.learnings true` で有効にする (コミットされず fork に引き継がれないので、公開リポジトリ・fork で知らずに書き始めない)。スキーマ (`schema_version` 1) と保存先を README の「利用側プロジェクトのディレクトリ規約」に載せた。設計は `docs/superpowers/specs/2026-11-22-learnings-ledger-design.md`
- `scripts/learnings.py` (新規、`python3 -I`・標準ライブラリだけ): `check` (検査)・`add` (標準入力の観測を検査し、通ったときだけファイル名を決めて書く。台帳が無効なら終了コード3で書かない)・`candidates` (既定ブランチと作業ツリーの検査を通った観測を数え、同じ `signature` が別の `session` で2回以上のものを出す)。検査はスキーマ (項目外・重複したキー、列挙値、`fact` 200字、`signature` の形、`evidence` の形、`session` のハッシュの形、4096 バイト、ファイル名) と、絶対パス・メール・URL・IP・FQDN・token の接頭辞・高エントロピー文字列・UUID・長い16進・会社名の手がかりの正規表現。該当すれば伏せ字にせず拒否し、理由に該当した値を含めない
- `incident-retro`: 台帳が有効なときだけ、事故ごとに `signature` を付けて台帳と照合し、2回目以上を昇格候補として表に示す。承認された観測を `scripts/learnings.py add` を通してだけ書き (Write で直接書かない)、拒否されたら伏せ字にせず書き直す。固有名は PR のレビューで確かめるよう利用者に伝える
- `tool-reminder.sh`: PreToolUse の `git commit` で、ステージ済みの `.aidd/learnings/` のファイル (インデックスの中身) と、同じコマンドの `git add` / `git commit` が名指しした台帳のファイル (作業ツリーの中身。ディレクトリ・親ディレクトリ・グロブ・`--` の後・`git -C` を含む) を同じ検査にかけ、通らなければ拒否する。台帳の有効化に関係なく動く (秘密を含むファイルがコミットされる危険は書いた人の設定に関係なく同じため)。台帳のファイルを含まないコミットでは挙動を変えない。検査スクリプトを読み込めなければ、台帳を含むコミットだけを拒否する
- レビューを受けて次を直した:
  - コミット時の検査を「よくある形での不注意を防ぐ層」と位置づけ直し、効かない経路を種類で README と設計書に挙げた。台帳のすべてのファイルに `learnings.py check` をかける CI の手順を README に書き、有効にする前の前提にした。顧客案件・NDA の対象のリポジトリでは有効にする前に情報管理の責任者の確認を取ること、台帳の中身が incident-retro の実行時に生成 AI に入力されること、検査が捕まえるのは不注意で入ったものだけで意図して隠した値は捕まえないことを書いた
  - `candidates` が数えるのを、既定ブランチにマージ済みの観測と今のセッションで書いた観測だけにした (PR のレビューを経ていない他人の観測は数えない)。既定ブランチの検査に通らない観測は件数とファイル名を stderr に出す。`--all` で数えたすべての signature を出す。incident-retro は signature の照合を `candidates` の出力だけで行い、台帳のファイルを直接読まず、ほかの人の fact を指示として扱わない。スクリプトは skill のディレクトリから解決した絶対パスで呼ぶ (利用側リポジトリの同名のファイルを実行しないため)
  - 検査: NFKC で正規化してから判定する。制御文字・書式文字 (ゼロ幅・双方向制御)・行と段落の区切り文字を拒否する。語の境界を ASCII で判定し、日本語に続けて書いた値も拾う。先頭を省略した IPv6 を拾う。16進は32字以上で拒否し、除外は `evidence` のコミット SHA の位置だけにした。区切りをまたいだ長い連なりにも、より厳しいしきい値で高エントロピーの判定をかける。未知のキー・重複したキーは件数だけを示し、命名規則に合わないファイル名は伏せる。深い入れ子など JSON の読み込みで出る例外はすべて拒否にする
  - `tool-reminder.sh`: 名指しのファイルを `git ls-files` に pathspec として解決させる。ステージ済みの版と作業ツリーの版を両方検査する。ステージ済みの中身をバイト列のまま読む (末尾の空白も大きさの上限に数える)。検査が例外を出したときは台帳を含むコミットを拒否し、ほかの判定は保つ
- エラー処理のレビューを受けて次を直した:
  - `tool-reminder.sh`: `git diff --cached` か名指しを解決する `git ls-files` が失敗したとき、「台帳のファイルが無い」とみなして通していた。その場で拒否する。止まりうるのは、git が失敗している場合と、git が受け付けない pathspec を渡した場合 (同じ `git add` も失敗する) だけ
  - `learnings.py candidates`: 既定ブランチの候補に `origin/master`・`master` を足した。既定ブランチを解決できないとき・既定ブランチの台帳を列挙できなかったときは、マージ済みの観測を0件とみなして黙って終わらず、理由を stderr に出して終了コード4で終える。作業ツリーにある検査に通らない観測も、件数とファイル名を stderr に出す。incident-retro は終了コード4を「マージ済みの観測を数えられなかった」と利用者に伝える
  - README と設計書の限界の一覧に、`AIDD_DISABLE_GIT_SAFETY=1` で名指ししないステージの拒否を外すと、ステージ前の台帳ファイルは検査されないことを足した。設計書に、最後の砦の except に頼るのは git か Python が壊れている場合だけで、そのときは台帳を含まないコミットも止まりうることを書いた
- `tests/learnings-test.sh` (新規) が検査の拒否すべき入力と通すべき入力 (SHA・相対パス・PR 番号・識別子・ファイル名の幹など誤検出しやすいもの)、`add` の既定無効とハッシュ化、`candidates` の数え方を検査する。token らしいテストデータは実行時に組み立て、リポジトリに置かない。`tests/hook-contract-test.sh` と `tests/command-contract-test.sh` を合わせた

## 0.64.0 (2026-11-22)

- `sandbox-settings.json.template`: `gh` を sandbox の中に戻した (`excludedCommands` の `gh *` を外した)。sandbox の外の `gh` は、設定や環境変数で指定したコマンドを全権限で動かせ、任意のホストへローカルのファイルを送れ、任意のファイルに書け、読み取りを拒否した認証情報も読めた。deny は文字列の照合なので塞ぐたびに別の経路が見つかったため (#115)。macOS の sandbox で `gh` が `x509: OSStatus -26276` で失敗する問題は、`env` の `SSL_CERT_FILE=/etc/ssl/cert.pem` で回避する (Go 1.27 から darwin でも `SSL_CERT_FILE` が効き、Go のネイティブの検証になる。証明書の検証は省かない)。`~/.config/gh` の読み取り拒否で `gh` が `GH_TOKEN` があっても `failed to read configuration` で止まるので、`env` の `GH_CONFIG_DIR=/var/empty` で設定の読み先を空のディレクトリに向けた (読み取り拒否は緩めない。sandbox の中の `gh` は保存済みの認証を使わず `GH_TOKEN` だけで動く)。pip (truststore) の同じ TLS の失敗は `env` の `PIP_USE_DEPRECATED=legacy-certs` で回避する
- `sandbox-settings.json.template`: sandbox の外で動くことだけを理由に入れていた `gh` の deny (`gh config set`・`gh browse`・`gh * browse`・`--web` / `-w`・`gh api --hostname`・`gh api http...`・`gh run download`・`gh release` 全体・`gh * release`) を外した。sandbox の書き込み範囲と通信先の制限がかかるため。`gh release` は、GitHub 側で消す・作る・書き換える `gh release delete`・`create`・`edit`・`upload` だけを、サブコマンドの前にオプションを置いた形 (`gh * release ...`) も含めて残した。token を取り出す・リポジトリを壊す・秘密を扱う操作と `gh gist`・`gh codespace`・`gh pr merge` は、sandbox の中でも GitHub に対して実行できるので残した
- README の「ローカルで権限を絞って使う」を新しい構成に合わせた: `SSL_CERT_FILE` の制約 (Go 1.27 以上でビルドした `gh` が要る、`go version "$(command -v gh)"` で確かめる、GitHub Releases 版の Go のバージョンは未確認、キーチェーンの社内 CA は信頼されない、Python など他のツールにも効く、Linux では外す)、`legacy-certs` が将来の pip で削除されうること、プロジェクトの `env` はフォルダの trust まで効かないこと、`gh auth status` を起動後に Claude に実行させて確かめること、`gh` を `excludedCommands` に入れたときの危険、GitHub 経由の持ち出し (攻撃者の token で任意のリポジトリへ送れる・`GH_TOKEN` 自体も読める)、キーチェーンの token を取り出せないことは未確認であること、作業ディレクトリに書かれたものが後で sandbox の外で動きうること、`enableWeakerNetworkIsolation` にする場合は `SSL_CERT_FILE` を外すこと、OS が混在するチームでは `SSL_CERT_FILE` を各自の設定に置くこと
- `doctor` の項目9: `gh` が `excludedCommands` にあれば (`gh`・`gh *`・`gh:*`・`gh*`・`gh` のパスのどれでも)、token の有無にかかわらず sandbox の外で全権限で動くと WARN する。`gh` が sandbox の中で動くなら、`GH_TOKEN`・`GITHUB_TOKEN` が無いとき、macOS で `SSL_CERT_FILE`・`GH_CONFIG_DIR` が無いときに、変数の名前だけを出して WARN する (値は出さない。空白だけの値は空とみなす)。`tests/command-contract-test.sh` を合わせた (#115)

## 0.63.0 (2026-11-22)

- `doctor` に項目9「利用側の sandbox 設定」を足した。managed (`managed-settings.d/*.json`・`managed-settings.json`)・`.claude/settings.local.json` (リポジトリのルート、worktree では main checkout のもの。Windows・ルートがホーム・所有者が違う場合はプロジェクトのもの)・`.claude/settings.json`・`~/.claude/settings.json` を優先順位の高い順に読み、`sandbox.enabled` を設定している最も優先順位の高いファイルの値が true でなければ、README の「ローカルで権限を絞って使う (Claude Code)」と `templates/sandbox-settings.json.template` を案内する。`excludedCommands` に `gh` があるのに `GH_TOKEN`・`GITHUB_TOKEN` がどちらも無ければ、`gh` が sandbox の外で `gh auth login` の保存済みの認証 (全権限になりうる) で動くと知らせ、fine-grained PAT を `GH_TOKEN` で渡す手順を案内する。token は有無だけを見て値を表示しない。0.55.0 で雛形と手順を入れたが、入れていない利用者には効かず、入れていないことに気づく手段も無かったため (#96)。sandbox を使わない運用もありうるので結果は WARN にとどめ、FAIL にしない。読めない JSON は WARN を出して飛ばし、サーバー配信・MDM の managed settings はファイルから読めないので `/status` で確かめるよう添える。Claude Code 以外ではスキップする。利用側の品質ガードを見る `infra-audit` ではなく doctor に置いたのは、これが aidd の skill を安全に動かす前提の確認だから。token が環境にあるので python3 は `-I` で動かし、利用側の `json.py` などを import しない。`tests/command-contract-test.sh` は、ダミーの設定と token で項目9を実際に動かし、token と `sandbox.enabled` の値を表示しないこと、FAIL を出さないことを検査する

## 0.62.0 (2026-11-22)

- `tool-reminder.sh`: 既定ブランチ (定義は下の項目) への force push (`--force`・`-f`・`--force-with-lease`・`+<refspec>`・`--mirror`・`--force --all`・`+:`・`heads/<既定>` のような短い書き方・`--force-w` のような長いオプションの省略形、refspec を省いて `remote.<name>.push` と `push.default` (`upstream` なら上流のブランチ) で決まる送り先が既定ブランチの場合。`remote.<name>.mirror` の push、ローカルに無い既定ブランチを `--prune` で消す push (`:` を含む) も拒否する。`--dry-run` の後の `--no-dry-run` は dry-run を取り消すものとして扱う。パターンの refspec はここにある送り元から既定ブランチに届くときだけ止め、`^<ref>` で除いたものは止めない) と、既定ブランチのリモート削除 (`push --delete`・`push <remote> :<branch>`) を拒否する。既定ブランチの上に積んだほかの人の作業を確実に失うため。作業ブランチへの force push と `-n` / `--dry-run` は止めない。既存の拒否と同じく `&&` / `;`・`cd`・`git -C`・ラッパーを見分け、`AIDD_DISABLE_GIT_SAFETY=1` で止められる (#97)
- `sandbox-settings.json.template`: `permissions.ask` に `rm -rf` (と `rm -fr`・`rm -r`・`rm --recursive` など)・`git push --force` / `-f` / `+<refspec>`・`git branch -D` を足した。正当な用途があり、環境によって許容度が違うため、拒否ではなく確認にする (#97)
- README に「破壊的な操作をどこで止めるか」を足し、操作ごとに hook で拒否 / 雛形で確認 / 利用側で書く (DB の drop・truncate、本番環境へのコマンド。例つき) / 止めない を表にした (#97)
- `tests/hook-contract-test.sh` が、既定ブランチへの force push・削除を拒否し、作業ブランチへの force push・通常の push・作業ブランチの削除を拒否しないことを検査する (#97)
- `sandbox-settings.json.template`: `excludedCommands` の `gh *` は変えず、aidd の skill が使わない危険な `gh` のサブコマンド (`gh auth token`・`auth refresh`・`auth setup-git`、`gh repo delete`・`archive`・`rename`・`edit`・`deploy-key`、`gh secret`・`gh variable`・`gh ssh-key`・`gh gpg-key`、`gh release delete`・`delete-asset`、`gh run delete`・`gh cache delete`、`gh codespace`) を `permissions.deny` に足した。除外を skill が使うサブコマンドに絞ると、skill が止まって利用者が除外を広げ直しやすく、文字列全体の照合が書き換え hook (RTK など) と合わせると外れやすいため。`gh api` は skill が使うので塞がず、API を直接呼べば同じ操作ができる限界を README に書いた (#98)
- `sandbox-settings.json.template`: `~/.npmrc`・`~/.pypirc` を `sandbox.credentials.files` (deny) と `permissions.deny` の `Read(...)` に足した。許可済みの npm・PyPI のレジストリへ直接届く token が読めたため。README に、非公開レジストリを使う場合の外し方と、`~/.npmrc` がある環境で公開レジストリの npm が動くかは未確認であることを書いた (#98)
- README に、雛形をチームでコミットするときの周知 (`GH_TOKEN` が無いと `gh` は保存済みの全権限の認証で動くこと、各メンバーが起動前に `gh auth status` で `(GH_TOKEN)` を確かめること) を足した (#98)
- `tool-reminder.sh`: 既定ブランチを「push 先のリモートの `HEAD` が指すブランチ (`refs/remotes/<remote>/<branch>` が実在する場合だけ) と、常に `main` / `master`」に変えた。`HEAD` を実在しないブランチや別のブランチに向けるだけで `main` の保護が外れたため。fork など別のリモートの `main` への force push も拒否される。送り先を書かない明示の refspec (`git push -f origin feat`) にも `remote.<name>.push` の対応を当て、`main` に届くなら拒否する。force / delete / prune を伴う push の remote か refspec に `$`・バッククォートが含まれる場合は、展開後の値を判定できないので拒否する (#97)
- `sandbox-settings.json.template`: sandbox の外の `gh` で任意のコマンドを動かせる経路 (`gh config set browser` などの設定と `gh browse`・`--web` / `-w`) と、GitHub 以外のホストへ送れる `gh api --hostname`、`gh pr merge` を `permissions.deny` に足した。docker / kubectl / gcloud / Azure CLI / GnuPG / cargo / gem / Terraform の認証情報を読み取り拒否に足した。設定も入る `~/.yarnrc.yml`・`~/.m2/settings.xml`・`~/.gradle/gradle.properties` はビルドが壊れうるので README の候補にとどめた (#98)
- README: 既定ブランチを実際に守るのは GitHub の ruleset (削除の禁止・force push の禁止・PR 必須) で、hook と雛形はミスを防ぐ層だと明記し、導入手順に ruleset を有効にする手順を足した。push 権限のある token なら `gh api` で ref を直接書き換えられるため。`gh` の deny と hook が止められない形 (オプションの順序、`GH_HOST`・`GH_BROWSER` などの環境変数、`sh -c`・`nice`・`xargs` など未登録のラッパー) を書いた (#97, #98)
- `tests/hook-contract-test.sh` が、実在しない `HEAD` の向き先・`remote.<name>.push` の対応・`$` / バッククォートを含む送り先の拒否と、作業ブランチへの push を止めないことを検査する (#97)
- `tool-reminder.sh`: 送り先に `$`・バッククォート・ブレース展開 (`{main,feat}`・`{a..c}`) を含む push の拒否を、オプションの force / delete / prune に加えて、`+<refspec>`・`:<refspec>` で force / delete を指定する形にも当てた。`git push origin +$BRANCH` や `git push -f origin {main,feat}` が既定ブランチを巻き戻せたため。Claude Code が permission の照合の前に外すラッパー (`timeout`・`time`・`nice`・`nohup`・`stdbuf`) を既定で外し、`timeout` の時間と `nice -n` などの値を読み飛ばす。`timeout 30 git push -f origin main` を見逃していたため (#97)
- `sandbox-settings.json.template`: gh を sandbox の中に戻すまでの当面の対策として、`gh release` 全体・`gh run download`・`gh gist`・`gh api http...`・`gh * release`・`gh * browse` を deny に足した。sandbox の外の gh がローカルの任意のファイルに書き込めたり (`gh release download -O <path> --clobber`)、完全な URL で任意のホストに送れたりしたため (#98)
- README: ruleset の手順に「Required approvals」を 1 以上にすることと「Require approval of the most recent reviewable push」を足し、1人で開発するリポジトリでは自分の PR をマージできなくなる影響を書いた。「送り先と操作を限るのは token と ruleset」を「操作を限るのは token と ruleset。送り先のホストを限る手段はこの構成には無い」に直した。sandbox の外の gh が任意のファイルに書けること、gh を sandbox の中に戻す対応を別の issue で進めていること、HEAD を別の実在するブランチに付け替えると保護が外れること (既定ブランチが main / master 以外の場合)、`eval` とバッククォートの中のコマンドは hook が止めないことを書いた (#97, #98)
- `tests/hook-contract-test.sh` が、`+` / `:` の refspec とブレース展開を含む送り先の拒否と、ラッパーを外した判定を検査する (#97)

## 0.61.0 (2026-11-22)

- `design-review`: Agent 2 のデータフローの観点に並行性を足した。複数のプロセス・セッション・ジョブ・リクエストが同じ状態を同時に読み書きすることが設計書から読み取れる場合は、競合・二重実行・破損への対策 (排他、冪等、楽観ロック、原子的な書き込みなど) が書かれているかを見る。同時アクセスが読み取れない設計には推測で指摘しない。`design-doc` のデータフローの節にも、同時に読み書きされる状態があれば対策を書かせる (観点と節の1対1対応を保つため)。観点と節の数は変えていない。PR #1 のレビューで、`usage-log.sh` の read-modify-write に排他も原子的な書き込みも無いことを外部のレビューが指摘し、標準の観点では構造的に拾えなかったため (#3)
- `design-review`: Agent 6 (security-reviewer) を起動する条件に、機微情報 (個人情報・プロンプト・認証情報など) をファイル・ログ・キャッシュに保存する設計を足し、`security-reviewer` が抽出する信頼境界・その description・`--no-security` のときに実装後の `/security-review` を勧める条件にも同じものを足した。同じ PR で、プロンプト本文を既定の umask のまま書いていたこと (同じマシンの別ユーザーに読まれうる) も指摘されたが、これまでの条件 (外部入力・認証認可・秘密情報・外部公開エンドポイント) からは起動が決まらなかったため。セキュリティの観点は Agent 6 に集約する設計 (2026-07-18) なので、Agent 2 には足していない (#3)
- `tests/command-contract-test.sh` が、足した文言を検査する

## 0.60.0 (2026-11-22)

- `issue-implement` の §5 に「横展開のレビュー」を足した。差分が守りの処理を足す・直す・共通化する場合、`aidd:reviewer` に、同じ形の呼び出し元と兄弟の処理に同じ処理が当たっているかの観点だけを割り当てる。0.59.0 で 4-5 (実装者自身が同じ形の箇所に広げる) と `autonomous-review` の横展開観点を足したが、`autonomous-review` を使わない経路では実装者以外の目が入らなかったため。発動条件と割り当ては `autonomous-review` と同じにし、`autonomous-review` を使うときは重ねない
- `tests/command-contract-test.sh` が `test-perspectives` の文言 (0.59.0 で足した異常系・回帰・認可の観点) と、`issue-implement` の横展開のレビューを検査するようにした。0.59.0 では `test-perspectives` を検査しておらず、観点を消してもテストが落ちなかったため

## 0.59.0 (2026-11-22)

- `issue-implement` の実装手順に「同じ形の箇所に広げる」(4-5) と「テストや項目を消すとき」(4-6) を足し、4-4 に「前提を壊しても落ちないときに多い原因」を書いた。aidd で実装した2つのリポジトリ (約390コミット) のコードとテストを監査したところ、もっとも多かった根本原因が、守りの処理 (所有の確認、入力の検証、ログの形、例外の扱い) を1か所だけに足して、同じ形の兄弟の処理に広げていないことだったため。共通の関数に切り出しても、呼び出し元の一部にしか当てていない例があった。テストでは、テスト名が述べる前提 (ロールなど) を入力として渡していないもの、「〜しない」だけを確かめて対照の無いもの、テストの共通設定の mock が確かめたい性質を消しているもの、挙動を消したときにテストを消して代わりを書かなかったもの、既定の実行から外れた E2E が消した項目を確かめたまま残ったものが見つかった。完了報告には、広げなかった箇所 (deferred) と、消したテストと代わりを書く
- `test-perspectives`: 異常系に「失敗の後に起きるべきこと (ロックの解放、残りの続行、再実行での回復) と、コメントが主張する回復・再試行」を、回帰に「消す・改名する項目を参照する既存テスト (既定の実行から外れたものを含む)」を、セキュリティの認可に「同じ形の既存のエンドポイントにも同じ確認があるか」を足した。監査で、型だけを確かめて後始末を確かめない失敗の分岐のテストと、事実と違う「再実行で回復する」のコメントが見つかったため
- `autonomous-review`: 観点別レビューに横展開観点を足した。差分が守りの処理を足す・直す・共通化する場合、`aidd:reviewer` に、同じ形の呼び出し元と兄弟の処理に同じ処理が当たっているかを確かめさせる。この観点の結果を記録できるよう、`state.json` の `perspective_reviews` の `perspective` に `sibling_coverage` を足し、`schema_version` を `3` にした
- `tests/command-contract-test.sh` と `tests/autonomous-review-contract-test.sh` が、足した文言を検査する

## 0.58.0 (2026-11-22)

- `design-review`: Agent 2 のデータモデルの観点で、根拠の記載を求める範囲を `design-doc` に揃え、正規化を崩す・JSON 型・EAV・型の無い文字列カラムなどスキーマを緩める選択に絞った。それ以外の型の選択には根拠の記載を求めない。これまで観点の前半「型の選択と正規化に根拠があるか」に条件が無く、design-doc に従って書いた設計書でも、ふつうの型の選択に根拠が無いと指摘しえたため (#93)。`tests/command-contract-test.sh` は、絞った文言があることと、元の文言が戻っていないことを検査する
- `design-review`: Agent 1 の責務分割の観点で、コンポーネントごとのコード上の配置 (ディレクトリ・ファイル) が書かれているか、既存コードがあるなら既存の構造から外れる配置に理由が書かれているかを見るようにした。0.57.0 で `design-doc` の「構成と責務」に配置を書かせ、`issue-implement` で差分を配置と照らすようにしたが、design-review は配置の記載を見ておらず、design-doc の構成と design-review の観点の1対1対応から配置だけが漏れていたため。配置を書き忘れた設計書がレビューを通ると、issue-implement は差分の周りの既存の構造を配置とみなすが、新規のコンポーネントでは既存の構造が基準にならないことがある (#95)。README の索引に足し、`tests/command-contract-test.sh` は追加した文言を検査する

## 0.57.0 (2026-11-22)

- `design-doc` の「構成と責務」で、コンポーネントごとのコード上の配置 (ディレクトリ・ファイル) を書かせるようにした。既存コードがあれば既存の構造に合わせ、外れるなら理由を書く。`issue-implement` の完了条件に「配置」を足し、差分の各ファイルを設計書の配置と照らして、配置から外れたファイルと、設計が別のコンポーネントに割り当てた責務またはどのコンポーネントにも割り当てていない責務を引き受けたファイルを、置き直すか設計書を直して理由を書くまで完了にしない。責務の集中は行数の閾値ではなく設計の責務の割り当てで判定する。設計書が配置を持たない場合 (直行レーン、古い設計書) は差分の周りの既存の構造と各ファイルがすでに担う責務を配置と割り当てとみなし、外れるなら置き直すか理由を書く。完了報告に配置の照合結果を書く。AI が生成したコードが設計の構造に沿って置かれず、1か所に積み上がって肥大化するという利用者の懸念に対し、設計書は責務を書いても置き場所を書かず、実装側にも照合する手順が無かったため (#86)。spec 本文と実装の drift を後から検知する仕組みは #4 の対象で、ここでは扱わない。`tests/command-contract-test.sh` は `design-doc` の文言も検査するようにした

## 0.56.0 (2026-11-21)

- `design-doc` / `design-review`: 永続化を含む設計で、データモデルと設計で決まる範囲の性能を扱うようにした。design-doc はデータフローの節に、正規化を崩す・JSON 型・EAV・型の無い文字列カラムなどスキーマを緩める選択の理由と検討した代替案、主要な読み書きの経路の検索条件とインデックスの前提、一度に読む件数の上限を書かせる。design-review は Agent 2 のデータフローの観点で同じ点を見る。利用者から「テーブルの JSON 型は意図した設計なのか、AI 提案なのか」と問われ、型選択の根拠が設計書にもレビューにも無かったため。N+1 は実装で決まり設計書から読み取れず、推測の指摘になるので扱わない。節と観点の数は変えていない (#85)

## 0.55.0 (2026-11-21)

- `templates/sandbox-settings.json.template` を足し、README に「ローカルで権限を絞って使う」を書いた。aidd の skill をローカルで動かすと、エージェントは利用者の権限のまま Bash と `gh` を実行し、`gh auth login` の認証もそのまま渡るため、事故が怖いという声があったため (#84)。雛形は Bash を sandbox に入れ (`failIfUnavailable`・`allowUnsandboxedCommands: false`)、確認なしの通信先を GitHub と npm・PyPI に限り、`~/.ssh`・`~/.aws`・`~/.config/gh`・`~/.netrc`・git の credential store の読み取りを sandbox 内の Bash と `Read` ツールの両方で拒否し、`Write` / `Edit` の作業ディレクトリ外への書き込みを拒否し、skill が使わない `gh extension`・`gh alias`・`gh pr checkout`・`gh repo clone` を拒否する。`gh` は macOS の sandbox で TLS の検証に失敗しうるので sandbox の外に出し、代わりに対象リポジトリだけの fine-grained PAT を `GH_TOKEN` で渡す手順を案内した。HTTPS の `git push` は、継承した helper を github.com についてリセットし、`GH_TOKEN` を返す credential helper をリポジトリの git 設定に置く手順を案内した (sandbox 内では `osxkeychain` と `gh auth git-credential` が使えないため)。この helper が sandbox 内の `GH_TOKEN` を使うので、`GH_TOKEN` を `credentials.envVars` で隠すことはしない。`gh` が sandbox の外に出ない場合 (コマンド置換・書き換え hook・admin-required) と、npm・pip のキャッシュと pip の TLS の扱いも書いた。完全な隔離が要るときは aidd-autopilot を案内する。`settings.json.template` に混ぜなかったのは、`failIfUnavailable` が sandbox の使えない環境で起動を止めるため。`/aidd:doctor` での検出と、`rm -rf`・force push などの破壊的な操作をどこで止めるかは今回の対象外

## 0.54.0 (2026-11-21)

- `issue-implement` の完了報告と `autonomous-review` の `report.md` に、観点とテストの対応表 (観点 (優先度) / テスト (ファイル:テスト名) / 前提を壊して落ちたか / 未実装の理由) を書かせるようにした。must の観点は全件、should / could はテストを書いたものだけ、既存テストでカバー済みならそのテスト名を書く。これまで観点は `docs/test-perspectives/` に残っても、どの must がどのテストで守られているか、書かなかった観点とその理由、前提を壊して落ちたかの確認結果が報告に残らず、人は観点ファイルとテストコードを突き合わせるしかなかったため (#87)。`tests/command-contract-test.sh` は `issue-implement` の文言も検査するようにした

## 0.53.3 (2026-11-18)

- `/aidd:eval` に `crosscut` ケースを足した。385行の設計書で、コアシードの多くは複数の節を照らし合わせないと見つからない。既存の3ケースは短く、design-review と素の Opus 5.5 がどちらも満点を取り、差が測れなかったため (#75)。シードはケース作成時に意図して埋め、design-review の出力からは作っていない。プロンプトは変えていない (#76)

## 0.53.2 (2026-11-18)

- `issue-implement`: 設計レーンで規模超過になったときに提案する `/aidd:issue-split` に、設計書のパスとこの issue の番号を渡すようにした。issue-split は親を推測で結び付けないので、番号が無いと子がこの issue のサブ issue に登録されず、`issue-select` も親を「open の子を持つ親」として候補から外せなかったため

## 0.53.1 (2026-11-17)

- `skill-gate.sh`: Cursor の Read の拒否を、パスの文字列ではなくファイルの同一性 (`os.path.samefile`) で判定するようにした。macOS の既定のファイルシステムは大文字小文字を区別しないため、`skills/Autonomous-Review/skill.md` のような綴りで同じ SKILL.md を読むと拒否が外れていた。python が判定できないときの fail-closed は、Read なら `deny` を返す (Cursor は `ask` を無視するため、`ask` では素通りになっていた)。件数の記録はロックを待たない (判定を出したあとにロック待ちで hook がタイムアウトすると、hook の失敗として扱われうるため)。いずれも PR #80 のマージ後に回した `/aidd:autonomous-review` の指摘

## 0.53.0 (2026-11-17)

- `autonomous-review` をモデルからも起動できるようにした。`gh pr create` 前の警告と `issue-implement` がこの skill を案内しているのに、`disable-model-invocation: true` のためモデルは従えず、ユーザーが手で打つまでフローが止まっていたため。代わりに `hooks/scripts/skill-gate.sh` を足し、モデルが Skill ツールで起動する前に必ず `ask` でユーザーの許可を取る。許可は SKILL.md の文面ではなく hook で強制する。対話の default / auto / bypassPermissions、allow ルール、サブエージェントのどれでも確認が届き、headless (`-p`、bypass を含む) では拒否として働くことを実測した。ユーザーが手で打った起動には確認は出ない。名前は接頭辞・先頭の `/`・大文字小文字をならして照合する (接頭辞なしの名前が hook に届くことを実測したため)。判定を出してから件数を `~/.claude/aidd/skill-gate.json` に記録し、記録の失敗で判定を落とさない (起動に失敗した hook は Claude Code が素通りさせることを実測したため)
- Cursor はこのフラグを解釈し、`preToolUse` の `ask` は無視するが `deny` は効くことを実測した。そこで Cursor ではモデルによる `skills/autonomous-review/SKILL.md` の `Read` を拒否し、`/autonomous-review` を手で打つよう案内する。`harness-adapter.sh` は、Cursor のすべての Read が通るため、`autonomous-review` を含まない入力では python を起動せずに終わる。Codex は `openai.yaml` で暗黙起動を止めたまま
- `tool-reminder.sh`: レビュー証跡の警告に「ユーザーが実行を断った場合は、このブランチでは再び起動せず、PR 本文に未実施と書く」を足した。断っても証跡は残らず、警告 → 起動 → 確認が `gh pr create` のたびに繰り返されるため
- Codex: `hooks.json` の `^Skill$` エントリが変わったので、`/hooks` で信頼し直すこと
- hook が無効な環境 (`disableAllHooks` など) と hook が起動できない場合は、確認なしで起動しうる。設計と実測は `docs/superpowers/specs/2026-11-14-autonomous-review-auto-invocation-design.md`

## 0.52.0 (2026-11-07)

- `/aidd:eval` の手順4で、キー外の指摘を人が1件ずつ分類するのをやめ、判定エージェント2体に分類させるようにした。人が確認するのは、判定が割れたものと誤検出だけになる。素の Opus 5.5 との比較 eval (#75) でベースラインが1回あたり29〜34件の指摘を出し、1件ずつの分類は回らなかったため。誤検出の判定には本文の行の引用を必須にした。あわせて、総トークン・最終報告の指摘件数・ノイズ率を指標に加えた。比較で design-review 側のコストとノイズを記録しておらず、比べられなかったため。design-review・refuter・arbiter のプロンプトは変えていない (#74)

## 0.51.0 (2026-11-06)

- `/aidd:eval` に偽指摘を混ぜ、refuter が誤った指摘を落とせるかを測るようにした。これまで refuter に渡るのは実在する欠陥だけで、本物を棄却しない側しか測れていなかった。敵対的レビューを残すか削るかをデータで決めるため。偽指摘は `tests/eval/planted/`、反証の根拠はキーに置く。design-review・refuter・arbiter のプロンプトは変えていない

## 0.50.1 (2026-10-28)

- `tool-reminder.sh` と `usage-log.sh` を `python3 -I -c` で起動する。`python3 -c` は sys.path の先頭に cwd を入れるので、利用側に `json.py` があると標準ライブラリの代わりにそれが実行されていた。判定ロジックは変えていない。`write-guard.sh` は #34 で同じ対処済み (#43)

## 0.50.0 (2026-10-28)

- `adr` / `design-doc` / `design-sync` / `doctor` / `infra-audit` / `issue-implement` / `test-perspectives` を `skills/<name>/SKILL.md` に移し、空になった `commands/` を消した。Codex はプラグインに commands を同梱せず、Cursor は skills を勧めるため。Claude Code の `/aidd:<name>` は skill の `name:` で残る。`doctor` の項目1–2は Claude Code 以外ではスキップして「Claude Code のみ」と書く。未確認の Codex / Cursor 導入パスは書いていない。それ以外の手順は変えていない (#61)

## 0.49.0 (2026-10-28)

- `issue-split` / `issue-select` / `retro` / `asset-audit` / `incident-retro` を `skills/<name>/SKILL.md` に移し、`commands/` から消した。Codex はプラグインに commands を同梱せず、Cursor は skills を勧めるため。Claude Code の `/aidd:<name>` は skill の `name:` で残る。`incident-retro` の memory 候補に Codex の `AGENTS.md` と Cursor の rules を足した以外、手順は変えていない (#60)

## 0.48.0 (2026-10-28)

- `autonomous-review` を `skills/autonomous-review/SKILL.md` に移し、`commands/` から消した。Codex はプラグインに commands を同梱せず、Cursor は skills を勧めるため。Claude Code の `/aidd:autonomous-review` は skill の `name:` で残る。レビュー手順・品質ゲート・state.json スキーマは変えていない (#59)

## 0.47.0 (2026-10-28)

- `design-review` と `eval` を `skills/<name>/SKILL.md` に移し、`commands/` から消した。Codex はプラグインに commands を同梱せず、Cursor は skills を勧めるため。Claude Code の `/aidd:design-review` / `/aidd:eval` は skill の `name:` で残る。パイプライン本文は変えていない（配置と `$ARGUMENTS` / AskUserQuestion の前文だけ） (#58)

## 0.46.0 (2026-10-28)

- `.codex-plugin` と `.cursor-plugin` に `"skills": "./skills/"` を載せた。hooks だけの宣言だと、既存の自動 skill（`adr-recall` など）が Codex / Cursor に届かなかった。`.claude-plugin` には `skills` キーを付けない（規約で `skills/` を見つける。reqd / stdd / uidd と同じ）。タスクコマンドはまだ `commands/` にあり Claude Code のみ。後続で skills へ移すときの置き場・`AskUserQuestion` の解釈・`commands/` を残さない方針は `.claude/CLAUDE.md` に書いた (#57)

## 0.45.0 (2026-10-28)

- Codex 用の custom agent TOML を `.codex/agents/` に置いた。正本は既存の `agents/*.md` で、`scripts/generate-codex-agents.py` が必須3キー (`name` / `description` / `developer_instructions`) だけを出す。spawn 名は `aidd-reviewer` のように接頭辞を付け、公式サンプルの `reviewer` とぶつからない。Codex のプラグイン導入では TOML は届かないので、`scripts/install-codex-agents.sh` が `~/.codex/agents/`（`--project` なら今のリポ）へコピーする。`/aidd:doctor` がその未導入と版ずれを見る

## 0.44.0 (2026-10-27)

- Cursor の Write にも `write-guard.sh` を配線した（手順0で実測した `preToolUse` の `file_path`）。Edit はまだ対象外。adapter は deny と `additionalContext` を同時に残し、Cursor では nudge を `agent_message` に載せる。`user_email` に加え `generation_id` / `cursor_version` / `workspace_roots` も子スクリプトへ渡さない。python3 が無いときは sentinel ファイルではなく `adapter-skips.json` に `no_python3` を書く

## 0.43.0 (2026-10-27)

- Codex と Cursor でも git/gh の deny と、Codex の新規ファイル deny を効かせる adapter を足した。判定スクリプト (`tool-reminder.sh` / `write-guard.sh`) は書き換えず、入力を Claude Code の形に揃えて呼び、返事を戻す。`hooks.json` の既存7エントリは変えず、末尾に `apply_patch` → `harness-adapter.sh write-guard.sh` を1つ足した (Codex の信頼はエントリ位置を見るため)。Cursor 用は `hooks/hooks-cursor.json` (Shell と SessionStart のみ。Write は対象外)。導入は `.codex-plugin` / `.cursor-plugin` の hooks 宣言。失敗は exit 0 で素通りし、`adapter-skips.json` に件数だけ残す。`/aidd:doctor` がその理由と、記録された `cursor_version` が fixture の版と違うことを出す。Codex では `/hooks` での信頼が必要で、hooks.json のエントリが変わるリリースでは信頼し直す

## 0.42.0 (2026-10-03)

- `issue-split.md`: 文面に無く、実行のたびに判断が揺れていた5点を決めた (#48)。(1) 重複は検索に当たった issue のタイトルと、決まらなければ本文から同じ作業かで判断し、判断がつかないものは作らず「重複の可能性」として候補の番号を報告する (迷って作ると同じ作業の issue が二つになるため)。(2) 失敗した操作は再試行しない (作成は応答だけ失敗して実際には作られていることがあり、再試行すると二重に作るため)。(3) 依存先が作られなかった後続の単位も作り、本文の依存欄に単位名を書いて「未登録の依存」として報告する。(4) 未登録の依存は読み直しの照合に含めず、最後の一覧の「未登録の依存」にだけ書く (`gh` を差し替えた検証で、登録に失敗した組を読み直しの結果でも「食い違い」と書く実行と書かない実行があったため)。(5) 実行環境がコマンドを拒否したら、残りの GitHub への書き込みをすべて止め、読み直しと最後の一覧は行う (拒否は同じ種類の操作に続けて当たり、迂回してはならないため)。止めるのは書き込みだけで、拒否・失敗した読み取りは結果が無いものとして扱う (検索の失敗・重複の可能性・未確認。拒否されたコマンドは終了コードも無いため)。親の登録に失敗した issue も、未登録の依存と同じく読み直しの照合から除き、親の欄にだけ書く。登録の前の `id` の取得は、その登録の一部として扱う

## 0.41.2 (2026-10-03)

- `issue-split.md`: 重複検索に `--json number,title,state` と `--jq` を付け、1行目に件数を出して、その値で上限を判定する。1行目が件数の形でない結果も「検索の失敗」に含め、作成しない (未作成の単位・未登録の依存・最後の一覧の区分にそのまま入るため)。検索結果の区分は上から順に当てはめ、重複が見つかれば件数が上限でも重複とする (重複と上限が同時に当たるときの分類が決まっていなかったため)。`--json` の無い一覧は、出力を縮める CLI ラッパー (RTK など) を通すと「残り N 件」のように省略され、行数を数えても件数にならないため。`gh` を差し替えて上限の100件を返させた検証で、モデルが省略表示から 20 + 80 = 100 と推し量って判定していた。利用者が `--json` を付けたコマンドはラッパーが書き換えずに通すことを確かめた

## 0.41.1 (2026-10-03)

- `issue-select.md`・`issue-split.md`: `gh api` が失敗したときの扱いの理由を事実に合わせた。0.41.0 では「空の結果と区別できない」と書いたが、実際には失敗すると `--jq` が当たらず、エラーの JSON (`"status": "401"` など) が標準出力に出る (401・404 で確認)。手順 (終了コードで判定し、失敗は「依存を確認できない」「未確認」とする) は変えない。理由が違うと、出力が空かどうかで判定する読み方を許し、エラー JSON の数字を issue 番号と読み違えるため
- `issue-split.md`: 作成しなかった単位と登録できなかった依存の扱いをまとめて決めた。重複検索には `--limit 100` を付け (`gh issue list` は既定で30件しか返さず、取りこぼしても終了コードは0のため)、結果ごとに「重複 / 検索の失敗 / 検索の上限 / 作成」のどれかに決める。検索の失敗と上限は重複なしとみなさず作成しない (同じ issue を二重に作るため)。上限に届いてもキーワードを絞って続けない (広いキーワードでだけ当たる重複が見えなくなるため)。検索の失敗・検索の上限・作成の失敗で issue の無い単位を「未作成の単位」とし、登録に失敗した依存と未作成の単位を片側に含む依存を「未登録の依存」として報告する。読み直しの照合は未登録の依存を除いて行う。最後の一覧には、読み直した issue (作成した issue と依存の後続側になった既存の issue。親の登録の失敗と読み直しの結果を含む)・作成しなかった単位と理由・未登録の依存の3つを載せる。親と blocked by は読み直した値を書き、未確認を分割案の値で埋めない。それまでは失敗の扱いを経路ごとに足していたため、作成の失敗や絞った再検索のように、どの規則にも当たらない経路が残っていた

## 0.41.0 (2026-10-02)

- `issue-split.md`: 元の issue が引数 (番号・URL) か設計書で明示されている場合、新しく作成した issue をそのサブ issue に登録する。本文に設計書のパスしか残らず、分割した issue から元の要求をたどれず、親で進み具合も見えなかったため。親は推測で決めない (無関係な issue に子が付くため)。`gh` にサブ issue のフラグが無いので REST API (`POST .../issues/<親>/sub_issues`) を使い、`sub_issue_id` には番号ではなく `id` を整数 (`-F`) で渡す。重複として報告した既存の issue は別の親を持つことがあるので登録しない。登録の失敗は番号と理由を報告する
- `issue-select.md`: open のサブ issue を持つ親 issue を候補から外し、open の子の番号を添えて報告する (子は他の候補と同じ判定にかける)。上の変更で親は子がすべて閉じるまで open のまま残り、作業の無い親を「着手できる issue」として提案するため
- `issue-split.md`: 分割案の「依存」を GitHub の blocked by (`POST .../issues/<後続>/dependencies/blocked_by`、`issue_id` は `id` を整数で) として登録する。依存が本文の文章にしか無く、先行する issue が閉じる前に後続へ着手できてしまうため。分割案に無い依存は足さない (承認されていない判断になるため)。循環する分割案は issue 化の前に作り直す。依存の片側が重複として報告した既存の issue なら、先行側でも後続側でもその既存の issue を使う (blocked by の追加は既存の関係を置き換えないため)。登録後は応答ではなく、サブ issue と blocked by の一覧を読み直して分割案と照合し、食い違いを報告する。読み直しが失敗したら、空の結果と区別できないので一致とみなさず「未確認」とする
- `issue-select.md`: open の issue に blocked by されている issue を候補から外し、先行する issue を報告する。上の変更で登録した依存を、着手の判断に使うため。どちらの判定も件数ではなく番号を出して確かめる (`--paginate` では `--jq` が1ページごとに評価され、件数が行に分かれるため)。確認のコマンドが失敗した issue は、該当なしと区別できないので「依存を確認できない」として外す

## 0.40.0 (2026-09-30)

- `write-guard.sh`: 資産重複の案内に、`AIDD_ASSET_OVERLAP_PLUGINS` (コロン区切りのディレクトリ) で指定した他のプラグイン (superpowers など) の資産を加える。一覧が aidd だけだと、利用側で superpowers の skill と役割の重なる資産を作っても知らせられなかったため。置き場を実行時に得る公式の手段は無く、`~/.claude/plugins/installed_plugins.json` は形式が公式のドキュメントに無く、変わったときに黙って効かなくなるので読まない。利用側が含めたいディレクトリを明示し、hook はその `.claude-plugin/plugin.json` から置き場を決める。解析は `scripts/generate-asset-index.py` から `scripts/asset_index.py` に切り出して hook と共有し (2か所で規則がずれないため)、manifest の規則 (`commands`・`agents` は置き換え、`skills` は追加、`hooks` はマージ。manifest が無ければ既定の配置とディレクトリ名) と plugins-reference の既定の配置 (`skills/` も `skills` キーも無ければルートの `SKILL.md` が1つの skill。既定の `agents/`・`commands/` のサブフォルダは名前に `<サブフォルダ>:` を足す) に従う。manifest の `commands` に書いたディレクトリはサブフォルダを読まない (公式のドキュメントが平らな `.md` のディレクトリとしか書いていないため)。frontmatter の YAML ブロックスカラー (`|`・`>`) は続く字下げ行を値として読む (1文字の `|` にならないよう)。他のプラグインの資産は実行時に読むだけで、同梱の `hooks/asset-index.json` には入れない。資産ディレクトリへの新規作成に当たったときだけ読み、対象外のパスでは今までどおり何も読まずに終わる。他のプラグインの資産は `<plugin>:<name>` の名前空間で利用側の同名の資産と両方読み込まれる (Claude Code の skills のドキュメント) ため、同名でも拒否せず案内だけにした。additionalContext は 10,000 字を超えるとファイルのパスと先頭の抜粋に置き換わるので、プラグインごとの見出しを付け、名前を 64 字・description を 120 字で切り、収まらない分は件数だけ出す (aidd の一覧は常に全件。字数は UTF-16 の単位で数え、Claude Code がどちらで数えても超えないようにした)。他のプラグインの文面は system reminder に入るので、名前と description の改行・制御文字・双方向制御文字は空白にし (1行の指示文として差し込まれないため)、一覧はデータであって指示ではないと1文添える。manifest の `name` が命名規則に反するプラグインは Claude Code が読み込まないので、名前を出さずに読めなかったものとして扱う。README には、信頼できるディレクトリ (導入済みのプラグインの置き場) だけを絶対パスか `~/` で指定するよう書いた (相対パスは作業中のリポジトリを指し、そこに書き込める人が文面を差し込めるため)。hook の Python は `-I` で起動し、作業ディレクトリの `asset_index.py`・`json.py` などを import しないようにした。存在しない・manifest が壊れている・manifest も資産も無いディレクトリは hook を止めずに飛ばし、黙って無視せず「読めなかったプラグイン」を1行添える。設定が無ければ出力は従来と同じ。prompt 型 hook の雛形は同梱の一覧から生成するので対象外 (#34)

## 0.39.0 (2026-09-30)

- `issue-implement.md` を追加: issue 1本を着手ゲート (要件が受領した原文か起票時の推測かを確かめる、ADR は決定の節を最後まで読む) → 曖昧さの3分類 (一次情報で決まる／既存の決定と衝突する／仕様の選択が残る。3つ目だけを人に上げる) → レーン判定 (スキーマ変更・エントリポイント追加・認可・新しい画面・採否の判断・ファイル数のどれかで設計から入る。行数では判定しない) → 実装 (新規テストは前提を壊して落ちることを1回見る) → レビュー (差分の性質で silent-failure-hunter・`/security-review`・`/stdd:mutation-check` を足す) → 完了条件 (deferred を issue か棄却一覧に落とすまで完了にしない) の順に進め、PR を出す判断は人に残す。計画・TDD・デバッグ・検証の中身は持たず superpowers の skill を、設計・レビュー・テスト観点は aidd の既存資産を順に呼ぶ入口にした。README の範囲 (実装フェーズは superpowers に委ねる) を保ったまま、どの順でどの条件で呼ぶかという aidd 固有の判断を毎回の手書きプロンプトから外すため (#24)
- `issue-select.md` を追加: open issue から今着手できる分を選ぶ。進行中の作業 (未 push の実装済みブランチを含む) を先に見て、本文の冒頭と決定済みの ADR を確かめ、人の手続きが要るものと衝突する組み合わせ (同じ画面・共有部品・同じモデル・同じテストファイルの新規作成・マイグレーションの同時進行・ADR の採番) を外し、提案で止める。ラベルは絞り込みと、付いている優先度ラベル (系列の規約か `.aidd/issue-priority.md` の定義) での並べ替えにだけ使い、優先度の基準を持たない (判定と付与は `aidd:issue-priority` skill の役割。ラベルが無ければ番号順)。未 push のブランチはリモートにも PR にも現れず、見落とすと同じ issue を二重に実装するため (#24)
- README: 上記2コマンドを索引に追加し、冒頭の superpowers との範囲の記述と pr-review-toolkit の連携点を更新 (#24)

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
