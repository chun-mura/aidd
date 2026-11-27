# ローカルで権限を絞って使う (Claude Code)

[README に戻る](../../README.md) / 関連: [利用側プロジェクトの設定](project-setup.md) / [hooks の運用と調査](hooks-operations.md)

## いつ使うか

`/aidd:issue-implement` などの aidd の skill を、利用者のマシンで Claude Code に自動で動かす前。sandbox・`gh` に渡す token・既定ブランチの ruleset を設定し、どの破壊的な操作をどこで止めるか (止められないものは何か) を確かめるときに読む。`/aidd:doctor` が sandbox 設定の WARN で案内する「手順2」はこのページの手順2を指す。この文書のパス (`templates/...` など) は aidd リポジトリのルートからの相対で書く。

## 手順

`/aidd:issue-implement` などをローカルで動かすと、エージェントは利用者の権限で Bash と `gh` を実行する。次の4つで書き込み範囲・通信先・GitHub の権限を絞り、既定ブランチを守る。

1. **sandbox を有効にする**: `templates/sandbox-settings.json.template` の内容を利用プロジェクトの `.claude/settings.json` (自分だけなら `.claude/settings.local.json`) にマージする。効いているかは、Claude に `touch ~/sandbox-probe` を実行させて 失敗する (macOS は `Operation not permitted`、Linux・WSL2 は `Read-only file system`) ことで確かめる (公式の確認手順。`!` から自分で打つと sandbox の外で動くので確認にならない)。
   - Bash の書き込みは作業ディレクトリと `$TMPDIR` に限られる (sandbox の既定)。作業ディレクトリに書かれたもの (`.envrc`・`.mcp.json`・`package.json` の scripts・`Makefile`・`.vscode/tasks.json` など) は、後で sandbox の外で `direnv`・`npm test`・`make` や次の起動を通して利用者の全権限で動きうる。セッションの後は `git status` と未追跡のファイルを確かめてから、それらを動かす。`Write` / `Edit` も `permissions.blockWritesOutsideWorkingDirectories` で作業ディレクトリの外を拒否する (Claude Code v2.1.314 以降)
   - Bash の通信は `allowedDomains` (GitHub と npm・PyPI のレジストリ) だけが確認なしで通る。ほかのホストは許可モードに応じて確認か拒否になり、`bypassPermissions` モードでは確認なしで通る。確認ではなく拒否にしたいときは `"sandbox": {"network": {"strictAllowlist": true}}` を `~/.claude/settings.json` に書く (プロジェクトの設定ファイルでは効かない)。このときプロジェクトの `allowedDomains` は無視されるので、雛形の `allowedDomains` も `~/.claude/settings.json` に移す。使うレジストリが違えば `allowedDomains` を書き換える。`github.com` のような広いドメインを許すと、そこへデータを送り出す経路は残る (公式の Security limitations)
   - npm と pip は既定のキャッシュ (`~/.npm`、macOS の pip は `~/Library/Caches/pip`) に書けない。npm は `EPERM` で失敗し、pip は警告を出してキャッシュなしで動く。どちらかで対処する
     - コマンドごとに `$TMPDIR` の下を使う (`npm --cache "$TMPDIR/npm-cache" ...`、`PIP_CACHE_DIR="$TMPDIR/pip-cache" pip ...`): 共有のキャッシュに触れないが、セッションをまたいで再利用されない
     - `sandbox.filesystem.allowWrite` に `~/.npm` などを足す: キャッシュが残るが、sandbox 内のコマンドがほかのプロジェクトと共有するキャッシュを書き換えられるようになる
   - macOS では、OS の証明書ストアで TLS を検証する pip (truststore、pip 24.2 以降) が sandbox 内で `OSStatus -26276` で失敗する。雛形は `env` に `PIP_USE_DEPRECATED=legacy-certs` を入れ、pip 同梱の証明書で検証させている (証明書の検証自体は省かない)。`legacy-certs` は pip が廃止予定としている指定で、将来の pip で削除されうる。キーチェーンに入れた社内 CA はこの指定では信頼されない
   - `~/.ssh`・`~/.aws`・`~/.config/gh`・`~/.netrc`・git の credential store (`~/.git-credentials`・`~/.config/git/credentials`)・npm と PyPI の token を置く `~/.npmrc`・`~/.pypirc`・docker / kubectl / gcloud / Azure CLI / GnuPG / cargo / gem / Terraform の認証情報 (`~/.docker/config.json`・`~/.kube/config`・`~/.config/gcloud`・`~/.azure`・`~/.gnupg`・`~/.cargo/credentials.toml`・`~/.gem/credentials`・`~/.terraform.d/credentials.tfrc.json`) は sandbox 内のコマンドから読めない。認証情報の既定の拒否リストは無いので、ほかの認証情報のパスは利用側で足す。設定と token が同じファイルに入る `~/.yarnrc.yml`・`~/.m2/settings.xml`・`~/.gradle/gradle.properties` は、拒否すると通常のビルドが設定を読めずに壊れうるので雛形に入れていない。token を書いているなら、ビルドが動くことを確かめてから足す候補にする。`~/.gnupg` を拒否すると sandbox 内の `git commit -S` (署名つきコミット) が鍵を読めずに失敗する。署名する場合はその行を外す。SSH の鍵が読めないため、git の remote は HTTPS にし、push の認証は手順2の credential helper で `GH_TOKEN` から渡す (macOS では、継承した `osxkeychain` の helper が sandbox 内で使えず、push が失敗することがある)
   - `~/.npmrc`・`~/.pypirc` を拒否すると、そこに書いた設定 (非公開レジストリの URL と token、proxy など) を npm・pip・twine が読めなくなる。非公開レジストリを sandbox 内で使う場合は、そのファイルの行を `sandbox.credentials.files` と `permissions.deny` の両方から外し、token はそのレジストリだけに届く読み取り専用のものにする。公開レジストリの `npm install` / `pip install` が、`~/.npmrc` が存在して読めない状態で動くかは未確認 (`~/.pypirc` が読めない状態での `pip download` は動いた。`~/.npmrc` が無い環境でしか試していない)。初回に実機で確かめる
   - sandbox が使えない環境では起動を止め (`failIfUnavailable`)、エージェントによる sandbox の外での再実行を許さない (`allowUnsandboxedCommands: false`)。sandbox の外で動かす必要があるコマンドは `excludedCommands` に足す。足したコマンドは利用者の全権限で、書き込み範囲・通信先・認証情報の読み取り拒否のどれも効かずに動く。雛形は何も足していない
   - sandbox がかかるのは Bash のコマンドだけ。`Read` ツールには効かないので、雛形は同じ認証情報のパスを `permissions.deny` の `Read(...)` でも拒否している。ほかに `Read` ツールで読ませたくないファイルも `permissions.deny` に書く
2. **`gh` には対象リポジトリだけの fine-grained PAT を渡す**: 雛形では `gh` も sandbox の中で動く。書き込みは作業ディレクトリと `$TMPDIR` に、確認なしの通信先は `allowedDomains` に限られ、認証情報ファイルは読めない。`gh` が GitHub で何をできるかは token の権限で絞る。
   - macOS の sandbox (Seatbelt) の中では、`gh` が OS の証明書ストアで TLS を検証できず、`x509: OSStatus -26276` で失敗する。雛形は `env` に `SSL_CERT_FILE=/etc/ssl/cert.pem` を入れ、`gh` (Go) にこのファイルの証明書で検証させている (証明書の検証自体は省かない)。制約がある
     - `gh` は Go 1.27 以上でビルドしたものが要る。Go 1.27 から、darwin でも `SSL_CERT_FILE` が効き、Go のネイティブの検証になる ([Go 1.27 Release Notes](https://go.dev/doc/go1.27))。手元の `gh` のビルドに使った Go は `go version "$(command -v gh)"` で確かめる (Homebrew の gh 2.103.2 は go1.27.3)。GitHub Releases で配布されている版の Go のバージョンは未確認
     - キーチェーンに入れた社内 CA (TLS を検査する社内プロキシなど) は信頼されない。`/etc/ssl/cert.pem` に入っていない CA が要る環境では、その CA を足した証明書ファイルを用意して `SSL_CERT_FILE` をそこに向けるか、公式の `sandbox.enableWeakerNetworkIsolation` を検討する。後者にする場合は `env` の `SSL_CERT_FILE` を外す (残すと `gh` はキーチェーンを使わず、このファイルだけで検証し続ける)。trustd を通した持ち出しの経路ができる (公式の settings)
     - `SSL_CERT_FILE` は Claude Code が動かすすべてのコマンドに渡り、Python (OpenSSL) など、この変数を読む他のツールの検証にも効く
     - Linux では sandbox で TLS は失敗しないので、`SSL_CERT_FILE` は要らない。ディストリビューションによって `/etc/ssl/cert.pem` は無いので、その行を外す。macOS と Linux のメンバーが混在するチームでは、`SSL_CERT_FILE` をプロジェクトの設定に入れず、macOS のメンバーが各自の `~/.claude/settings.json` の `env` に置く
   - 雛形は `env` に `GH_CONFIG_DIR=/var/empty` (中身が空で、利用者が書けないディレクトリ) も入れている。雛形は `~/.config/gh` の読み取りを拒否しているので、`gh auth login` をした環境では、`gh` は `GH_TOKEN` があっても設定ファイルを読めずに `failed to read configuration` で止まる。`GH_CONFIG_DIR` を向け替えると、`gh` は設定ファイルが無いものとして `GH_TOKEN` だけで動く。sandbox の中の `gh` は `gh auth login` で保存した認証を使わない (読み取り拒否はそのまま)。`gh config set` などの設定の書き込みは失敗する
   - `env` は Claude Code が動かすコマンドに渡る (公式の env-vars・sandboxing。`~/.claude/settings.json` の `env` が sandbox の中の Bash に届くことは実測した)。プロジェクトの `.claude/settings.json` の `env` の多くは、フォルダを trust するまで効かない (公式の settings「A committed key doesn't reach teammates」)。trust していないと、`gh` は TLS で失敗する
   - sandbox の中の `gh` も、許可したホスト (`github.com` など) へは、読めるファイルを送れる (`--body-file`・`gh api -F key=@<file>` など)。送り先を GitHub に限っても、持ち出しの経路は残る。注入された指示に攻撃者自身の token が入っていれば、github.com 上の任意のリポジトリ (攻撃者のものを含む) へ送れる。sandbox の中のコマンドは `GH_TOKEN` 自体も読めるので、token の値も持ち出されうる。token は対象リポジトリだけ・短い有効期限にし、漏れたら失効させる。許可外のホストへの送信 (`gh api --hostname <host>`・`gh api https://<host>/...`・`GH_HOST`) は、ほかのコマンドと同じく sandbox のネットワーク制限にかかる (確認か拒否。`bypassPermissions` モードでは確認なしで通る。手順1の `strictAllowlist` を参照)。設定や環境変数で指定したブラウザ・ページャ・エディタのコマンドも sandbox の中で動く
   - 雛形は aidd の skill が使わない `gh extension`・`gh alias`・`gh pr checkout`・`gh repo clone` を `permissions.deny` で拒否している。あわせて、token を表示するもの (`gh auth token`)、認証の範囲や git の helper を変えるもの (`gh auth refresh`・`gh auth setup-git`)、リポジトリを消す・設定を変えるもの (`gh repo delete`・`archive`・`rename`・`edit`・`deploy-key`)、Actions の secret・変数や鍵を扱うもの (`gh secret`・`gh variable`・`gh ssh-key`・`gh gpg-key`)、消すもの (`gh run delete`・`gh cache delete`・`gh release delete`)、リリースを作る・書き換えるもの (`gh release create`・`edit`・`upload`。リリースを契機に動く workflow がありうる)、対象リポジトリの外へ内容を出すもの (`gh gist`)、codespace を作って動かすもの (`gh codespace`)、PR をマージするもの (`gh pr merge`。aidd の skill はマージしない) も拒否している。これらは sandbox の中でも許可したホスト (GitHub) に対して実行できるので残している。`gh release download`・`gh run download`・`gh config set`・`gh browse`・`--web`・`gh api --hostname`・`gh api https://...` は拒否していない。sandbox の書き込み範囲と通信先の制限がかかるため
   - skill が使う issue・pr の create / view / list / edit / comment、`gh api`、`gh label list`、`gh repo view`、`gh auth status` は塞がない。`gh api` は skill が使うので塞がず、`gh api -X DELETE repos/<owner>/<repo>` のように API を直接呼べば上の拒否と同じ操作ができる。これを止めるのは token の権限だけなので、token には下の権限しか付けない。拒否は呼び出しの文字列との照合で、`gh` が引数をどう解釈するかとは一致しない (公式の permissions も、引数を絞るパターンは壊れやすいとしている)。オプションの順序や綴りを変えた形 (`gh -R <owner>/<repo> secret list` のようにサブコマンドの前にオプションを置いた形など) は一致しない (公式の「What a Bash rule doesn't match」)。deny はうっかり使うのを防ぐ層にとどまる。GitHub での操作を限るのは token の権限と GitHub 側の ruleset で、既定ブランチの force 更新・削除は `git push` だけでなく `gh api` (refs の API) でもでき、Contents: write の token では止まらないので、手順3の ruleset を必ず有効にする。`Bash(gh *)` を `permissions.allow` に入れたり、`bypassPermissions` モードで動かしたりしない
   - `gh *` を `excludedCommands` に入れない。入れると `gh` は sandbox の外で利用者の全権限で動き、ローカルのどのファイルも読んで任意のホストへ送れ、`gh release download -O <path> --clobber` などでどのファイルにも書け、`gh config set browser "<コマンド>"` の後の `gh browse` などで任意のコマンドを動かせる。`allowedDomains` も認証情報の読み取り拒否も効かない (0.63.0 までの雛形はこの構成だった)
   - GitHub の Settings > Developer settings > Personal access tokens > Fine-grained tokens で token を作る。有効期限を付け、Repository access は「Only select repositories」で対象リポジトリだけを選ぶ。Permissions は aidd の skill が使う Issues・Pull requests・Contents だけにし、読むだけなら read、issue へのコメント・PR 作成・push をさせる項目だけ write にする
   - Claude Code を起動するシェルで `GH_TOKEN` に入れる。`GH_TOKEN` は `gh auth login` で保存した認証より優先される。token は `.claude/settings.json` の `env` やコミットされるファイルに書かない
   - `GH_TOKEN` が空のまま起動すると、sandbox の中の `gh` は `GITHUB_TOKEN` があればそれを使い、無ければ認証できずに失敗する想定である (`GH_CONFIG_DIR` が空のディレクトリを指し、`~/.config/gh` も読めないため)。ただし、`gh auth login` がキーチェーンに保存した全権限の token を sandbox の中のコマンドが取り出せないことは未確認。気になる場合は、このマシンで `gh auth logout` してキーチェーンの gh の項目を消し、`GH_TOKEN` だけで使う (sandbox の中では git の `osxkeychain` の helper が使えないことは確かめている)。下の例は `GH_TOKEN` が空なら起動しない。起動後に Claude に `gh auth status` を実行させ、出力に `(GH_TOKEN)` と出れば、sandbox の中の `gh` が TLS を通り、token を使っている

     ```bash
     # paste the token; it is neither echoed nor kept in shell history, and claude starts only with it exported
     read -rs GH_TOKEN && [ -n "$GH_TOKEN" ] && export GH_TOKEN && claude
     ```

   - `git push` (HTTPS) にも同じ token を使う。利用プロジェクトで1回だけ次を実行する。1行目の空の値は、継承した helper (`osxkeychain`、`gh auth setup-git` が足す `gh auth git-credential` など) を github.com についてだけリセットする。2行目の helper は `get` のときに環境変数 `GH_TOKEN` を読んで返すだけで、token をファイルに書かず、`store` / `erase` では何も出力しない

     ```bash
     git config --local --replace-all credential.https://github.com.helper ''
     git config --local --add credential.https://github.com.helper '!f() { if [ "$1" = get ] && [ -n "$GH_TOKEN" ]; then echo username=x-access-token; echo "password=$GH_TOKEN"; fi; }; f'
     ```

     `gh auth setup-git` は使わない (雛形も拒否している)。`~/.gitconfig` に helper を書くので sandbox の中では失敗し、外で実行するとこのリポジトリ以外の push にも効く。この helper は `gh` を呼ばず、 sandbox の中に `GH_TOKEN` があることを前提にするため、`sandbox.credentials.envVars` で `GH_TOKEN` を deny にしない (deny にすると push が認証できない。代わりに sandbox 内のコマンドも token を読めるので、token の権限は対象リポジトリだけに絞る)

     sandbox の中からは `.git/config` に書けない。`git push -u` は push 自体は通るが、upstream の保存で失敗する。新しいブランチは `git push origin HEAD` のように push 先を毎回指定する

   - **雛形をチームでコミットするとき**: `.claude/settings.json` に入れた sandbox と拒否はクローンした全員に効くが、`GH_TOKEN` は各自のシェルの環境変数なので届かない。`GH_TOKEN` を渡さずに起動したメンバーの `gh` は認証できずに止まる (シェルに `GITHUB_TOKEN` があればそれで動く)。`env` の多くはフォルダを trust するまで効かないので、trust していないメンバーの `gh` は macOS では TLS で失敗する。コミットと同時に、次の3点をチームに知らせる (README・PR 本文・チームの手順書など、メンバーが起動前に読む場所に書く)
     - 起動前に対象リポジトリだけの fine-grained PAT を作り、上の `read -rs GH_TOKEN ...` の形で `GH_TOKEN` に入れて起動する
     - `claude` を起動したら、Claude に `gh auth status` を実行させ、出力に `(GH_TOKEN)` と出ることを確かめる。`x509: OSStatus -26276` が出たら、フォルダを trust しているか、`gh` が Go 1.27 以上でビルドされているかを確かめる
     - macOS で `gh` を Go 1.27 未満でビルドした版 (古い Homebrew の gh など) を使っていると、sandbox の中で動かない。`gh` を更新する

3. **対象リポジトリの既定ブランチに ruleset をかける**: 既定ブランチを実際に守るのは GitHub 側の branch protection / ruleset で、hook と雛形はミスを防ぐ層にとどまる。push 権限 (Contents: write) のある token なら、`gh api -X PATCH` / `-X DELETE` で `repos/<owner>/<repo>/git/refs/heads/<既定>` を直接書き換えたり消したりでき、hook も deny も文字列の書き方を変えれば外れる。リポジトリの Settings > Rules > Rulesets で New branch ruleset を作り、Enforcement status を Active、Target branches に既定ブランチを入れ、Branch protections の「Restrict deletions」「Block force pushes」「Require a pull request before merging」を有効にする。「Require a pull request before merging」の中で「Required approvals」を 1 以上にし、「Require approval of the most recent reviewable push」を有効にする (承認の後に積んだコミットを、別の人の承認なしにマージさせない)。承認を必須にすると、自分の PR を自分では承認できないので、1人で開発するリポジトリでは PR をマージできなくなる。その場合は承認を求めず、force push と削除の禁止だけをかける (このとき `gh pr merge` は ruleset では止まらない) (公式: GitHub Docs「Creating rulesets for a repository」「Available rules for rulesets」)。利用できるプランとリポジトリの種類は「About rulesets」で確かめる。ruleset を迂回できる bypass list に、エージェントに渡す token の持ち主を入れない

4. **完全な隔離が必要なら aidd-autopilot を使う**: 上の設定は利用者のマシンとアカウントの上での制限にとどまる。コンテナ隔離・egress 許可リスト・fine-grained PAT で skill を動かすなら aidd-autopilot (issue のラベルを契機に、隔離した Docker コンテナで headless の Claude Code を動かす) を使う。

## 破壊的な操作をどこで止めるか

既定ブランチを実際に守るのは GitHub 側の ruleset (上の手順3) で、これを必須にする。そのうえで、他人の作業を確実に失う操作は aidd の hook (`tool-reminder.sh`) で拒否し、環境によって許容度が違う操作は雛形の `permissions.ask` で確認を出す。hook と雛形はエージェントのミスを手元で止める層で、書き方を変えた呼び出しや `gh api` による ref の直接の書き換えは止められない。hook は aidd を入れれば雛形を使わなくても効き、`ask` は利用側で外せる。

| 操作 | どこで止めるか | 理由・範囲 |
|------|--------------|-----------|
| 既定ブランチの force 更新・削除 (手段を問わず。`gh api` による ref の書き換え、`gh pr merge` を含む) | GitHub の ruleset (必須) | push 権限のある token ならどの経路でもできるので、サーバー側で止める。`gh pr merge` を ruleset で止められるのは「Required approvals」を 1 以上にした場合に限る。雛形は `gh pr merge` も deny に入れている |
| 既定ブランチへの force push (`--force`・`-f`・`--force-with-lease`・`+<refspec>`・`--mirror`・`--force --all`・`+:`・`heads/<既定>` のような短い書き方・`--force-w` のような省略形。refspec を省いた場合は `remote.<name>.push` と `push.default` で決まる送り先が既定ブランチなら) | hook で拒否 | 既定ブランチの上に積んだほかの人の作業を失う。既定ブランチは、push 先のリモート (無ければ `origin`) の `HEAD` が指すブランチ (`refs/remotes/<remote>/<branch>` が実在する場合だけ) と、常に `main`・`master`。そのため fork など別のリモートの `main` / `master` への force push も拒否する。送り先 (remote か refspec) に `$`・バッククォートを含む force / delete / prune の push は、展開後の値を判定できないので拒否する。`-n` / `--dry-run` は止めない |
| 既定ブランチのリモート削除 (`git push --delete <既定>`・`git push <remote> :<既定>`・ローカルに無い既定ブランチを消す `--prune`) | hook で拒否 | 同上 |
| 作業ブランチへの force push | 雛形の `ask` で確認 (hook は止めない) | rebase 後の push など正当な用途がある。雛形の `Bash(git push --force*)`・`Bash(git push -f*)`・`Bash(git push * +*)` などが既定ブランチ以外の force push にも確認を出す |
| `rm -rf` (と `rm -fr`・`rm -Rf`・`rm -r`・`rm --recursive` など) | 雛形の `ask` で確認 | ビルド成果物の削除など正当な用途が多い。sandbox 内の Bash は作業ディレクトリと `$TMPDIR` の外に書けないので、消せる範囲もそこに限られる |
| `git branch -D` | 雛形の `ask` で確認 | マージ済みでないブランチのコミットを失いうるが、ローカルの reflog に残り、不要なブランチの整理にも使う |
| 未コミットの作業を失う git 操作 (`reset --hard`・`stash`・`clean` など) と指名しないステージ | hook で拒否 (既存) | [hooks-operations.md の `tool-reminder.sh`](hooks-operations.md#tool-remindersh) を参照 |
| DB の drop・truncate、本番環境へのコマンド | 利用側の `permissions.deny` / `ask` (雛形には入れない) | CLI と接続先の指定方法がプロジェクトごとに違う。下の例を自分の CLI に合わせて書く |
| それ以外 (`git push` の通常の push、`git reset --soft` など) | 止めない | 作業を失わない、または取り戻せる |

`permissions.ask` に当たると、bypassPermissions モードと auto モードでも確認が出る。headless (`-p`) と `dontAsk` モードでは確認できないので拒否になる。`ask` と `deny` は呼び出しの文字列との照合なので、オプションの書き方や順序を変えた形 (`rm -v -rf`、`git branch --delete --force`)、`git -C . push`、`bash -c '...'` には当たらない (公式の「What a Bash rule doesn't match」)。既定ブランチへの force push は hook が `git -C`・`cd`・ラッパーを見分けて拒否する。ただし hook もコマンドの文字列と git の設定から判定するので、`bash -c '...'`・`sh -c '...'`・`sudo`・`xargs` など登録していないラッパー (`AIDD_COMMAND_WRAPPERS` で足せる。Claude Code が permission の照合の前に外す `timeout`・`time`・`nice`・`nohup`・`stdbuf` は既定で外す)・git のエイリアス・オプション自体を変数で渡した形 (`git push $FLAGS origin main`)・refspec 全体を変数で渡した形 (`git push origin "$BRANCH"` で値が `+main` の場合。force の指定が無い `$` の push は、正当な push を止めないため拒否しない)・`eval` やバッククォートの中のコマンド (`eval "git push -f origin main"`)・`git -c` や `GIT_DIR` で渡した設定・既定ブランチを取れないリモート (`refs/remotes/<remote>/HEAD` が無いか実在しないブランチを指し、既定ブランチの名前が `main` / `master` でもない) では止まらない。既定ブランチが `main` / `master` 以外のリポジトリでは、`refs/remotes/<remote>/HEAD` を別の実在するブランチに付け替えると (`git remote set-head` など)、本来の既定ブランチの保護が外れる。git の呼び出しが失敗したときも止めずに通す。

DB と本番環境の例 (利用側の `.claude/settings.json` に足す。コマンド名・接続先の名前は自分のものに置き換える):

```json
{
  "permissions": {
    "deny": [
      "Bash(psql * -h prod-db.example.com*)",
      "Bash(kubectl --context prod *)"
    ],
    "ask": [
      "Bash(psql *DROP *)",
      "Bash(psql *TRUNCATE *)",
      "Bash(mysql *DROP *)",
      "Bash(rails db:drop*)",
      "Bash(npx prisma migrate reset*)",
      "Bash(terraform apply*)",
      "Bash(terraform destroy*)"
    ]
  }
}
```

SQL を対話シェルやファイル (`psql -f`) で流すと文字列に `DROP` が現れないので、これらの規則は当たらない。本番に届くかどうかは、本番の認証情報を sandbox 内から読めなくし (`sandbox.credentials`)、本番のホストを `allowedDomains` に入れないことで止める。
