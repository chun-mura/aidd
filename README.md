# aidd — AI-Driven Development Knowledge Base

AI駆使のための実行可能資産 + 知見。Claude Code プラグインとして導入可能な、タスク特化コマンド・エージェント・スキル・テンプレート・方法論の集約。

**superpowers プラグイン必須**: aidd は設計・レビュー・運用強制のみを担当し、実装フェーズ (brainstorming・TDD・デバッグ・計画立案) は superpowers に委ねる設計 ([棲み分け原則](docs/tips/superpowers-usage.md))。`/aidd:issue-implement` も実装フェーズの中身は持たず、着手・レーン・レビュー追加・完了の判断の間で superpowers の skill を順に呼ぶ入口である。`plugin.json` の `dependencies` で `superpowers@superpowers-marketplace` を宣言しているため、`/plugin install aidd@aidd` 時に自動導入・有効化される (Claude Code v2.1.110+ が必要)。古いバージョンでは session-start hook が未導入を検知して警告するが、ブロックはしない (検知はベストエフォート)。

**pr-review-toolkit プラグイン推奨**: aidd:reviewer は成果物単体の検収用で、PR全体のレビュー (スタイル・テストカバレッジ・サイレント障害・型設計など多観点) は pr-review-toolkit の担当。導入しなくても aidd の各機能は動くが、PRレビューの網羅性が下がる。

**UI・デザイン特化の資産は [uidd](https://github.com/chun-mura/uidd)**: Storybook 中心の UI 提案・デザインシステム構築ワークフローは uidd が担当する (aidd は汎用タスクのみ。重複資産は作らない)。

**テスト設計手法特化の資産は [stdd](https://github.com/chun-mura/stdd)**: BVA/ECP/デシジョンテーブル/PBT/mutation 等の手法カタログ・選択ガイド・ケース導出は stdd が担当する (aidd は観点洗い出しと手法適用フラグのみ。重複資産は作らない)。

**要件の形式化・曖昧さ検査は [reqd](https://github.com/chun-mura/reqd)**: メモ・Issue・対話結果を構造化された要件定義書に変換し曖昧さを lint する (aidd は設計=HOW。`/reqd:new` の出力パスを `/aidd:design-doc` の引数に渡す)。発散・対話ヒアリングは superpowers (brainstorming) の担当。

**工数見積もりは [estimate](https://github.com/chun-mura/estimate-workload)**: 仕様・Issue・短い作業説明から WBS + 3点見積もり + モンテカルロで P50/P80 を出す (aidd は見積もりしない。`/reqd:new` や設計書のパスを `/estimate:new` に渡す)。

## 導入 (他プロジェクトから使う)

### 個人で使う

```bash
/plugin marketplace add chun-mura/aidd
/plugin install aidd@aidd
# 実装フェーズを担う superpowers は dependencies 宣言により自動導入される

# 推奨: PR全体レビューを担う pr-review-toolkit も導入
/plugin marketplace add anthropics/claude-plugins-official
/plugin install pr-review-toolkit@claude-plugins-official
```

### チームで使う (プロジェクト単位で自動導入)

利用プロジェクトの `.claude/settings.json` に `templates/team-settings.json.template` の内容をマージしてコミットすると、プロジェクトフォルダを trust したメンバーに aidd のインストールが自動で提案される。各自が手で `/plugin marketplace add` する必要はない。

更新の配信は `plugin.json` の `version` に固定される (version を上げない限りメンバーに更新が届かない)。リリース時は必ず version を上げて CHANGELOG に記録すること (運用ルール3)。メンバー側は `/plugin update aidd` で追従する。

### ローカルで権限を絞って使う (Claude Code)

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

#### 破壊的な操作をどこで止めるか

既定ブランチを実際に守るのは GitHub 側の ruleset (上の手順3) で、これを必須にする。そのうえで、他人の作業を確実に失う操作は aidd の hook (`tool-reminder.sh`) で拒否し、環境によって許容度が違う操作は雛形の `permissions.ask` で確認を出す。hook と雛形はエージェントのミスを手元で止める層で、書き方を変えた呼び出しや `gh api` による ref の直接の書き換えは止められない。hook は aidd を入れれば雛形を使わなくても効き、`ask` は利用側で外せる。

| 操作 | どこで止めるか | 理由・範囲 |
|------|--------------|-----------|
| 既定ブランチの force 更新・削除 (手段を問わず。`gh api` による ref の書き換え、`gh pr merge` を含む) | GitHub の ruleset (必須) | push 権限のある token ならどの経路でもできるので、サーバー側で止める。`gh pr merge` を ruleset で止められるのは「Required approvals」を 1 以上にした場合に限る。雛形は `gh pr merge` も deny に入れている |
| 既定ブランチへの force push (`--force`・`-f`・`--force-with-lease`・`+<refspec>`・`--mirror`・`--force --all`・`+:`・`heads/<既定>` のような短い書き方・`--force-w` のような省略形。refspec を省いた場合は `remote.<name>.push` と `push.default` で決まる送り先が既定ブランチなら) | hook で拒否 | 既定ブランチの上に積んだほかの人の作業を失う。既定ブランチは、push 先のリモート (無ければ `origin`) の `HEAD` が指すブランチ (`refs/remotes/<remote>/<branch>` が実在する場合だけ) と、常に `main`・`master`。そのため fork など別のリモートの `main` / `master` への force push も拒否する。送り先 (remote か refspec) に `$`・バッククォートを含む force / delete / prune の push は、展開後の値を判定できないので拒否する。`-n` / `--dry-run` は止めない |
| 既定ブランチのリモート削除 (`git push --delete <既定>`・`git push <remote> :<既定>`・ローカルに無い既定ブランチを消す `--prune`) | hook で拒否 | 同上 |
| 作業ブランチへの force push | 雛形の `ask` で確認 (hook は止めない) | rebase 後の push など正当な用途がある。雛形の `Bash(git push --force*)`・`Bash(git push -f*)`・`Bash(git push * +*)` などが既定ブランチ以外の force push にも確認を出す |
| `rm -rf` (と `rm -fr`・`rm -Rf`・`rm -r`・`rm --recursive` など) | 雛形の `ask` で確認 | ビルド成果物の削除など正当な用途が多い。sandbox 内の Bash は作業ディレクトリと `$TMPDIR` の外に書けないので、消せる範囲もそこに限られる |
| `git branch -D` | 雛形の `ask` で確認 | マージ済みでないブランチのコミットを失いうるが、ローカルの reflog に残り、不要なブランチの整理にも使う |
| 未コミットの作業を失う git 操作 (`reset --hard`・`stash`・`clean` など) と指名しないステージ | hook で拒否 (既存) | 上の Hooks の表を参照 |
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

### Codex CLI (hooks・skills・custom agents)

```bash
codex plugin marketplace add chun-mura/aidd
codex plugin add aidd@aidd
```

導入後に `/hooks` で aidd の hook を信頼する。信頼していない hook は何も表示されずに実行されない。`hooks.json` のエントリが変わるリリースでは、そのエントリを `/hooks` で信頼し直す (スクリプト本体だけの修正では不要)。0.53.0 は Claude Code 用の `^Skill$` エントリに `skill-gate.sh` を足したので、信頼し直しが要る (しないと `usage-log.sh` の記録が止まる。Codex の skill の起動は変わらない)。`/hooks` 画面では aidd 以外の hook の有効・無効を変えないこと (信頼の操作のあとに、無効にしていた別の hook が有効に戻った実測がある)。

`.codex-plugin` は `skills/` も宣言する。既存の自動 skill に加え、`design-review` / `eval` / `autonomous-review` / `issue-split` / `issue-select` / `retro` / `asset-audit` / `incident-retro` / `adr` / `design-doc` / `design-sync` / `doctor` / `infra-audit` / `issue-implement` / `test-perspectives` は `$aidd:<name>` で起動できる。`commands/` は無い。

custom agents はプラグイン導入だけでは届かない。Codex が読むのは `~/.codex/agents/` か、今のリポの `.codex/agents/` だけだからである。プラグインのディレクトリで次を実行する:

```bash
bash scripts/install-codex-agents.sh            # このマシンの全プロジェクト
bash scripts/install-codex-agents.sh --project  # 今のリポだけ（チーム共有）
```

spawn 名は `aidd-reviewer` / `aidd-refuter` / `aidd-design-arbiter` / `aidd-scout` / `aidd-security-reviewer` / `aidd-source-verifier`。`agents/*.md` を変えたら `python3 scripts/generate-codex-agents.py` を同じコミットで回す。`/aidd:doctor` が未コピーと正本とのずれを見る。

### Cursor agent CLI (hooks と skills)

```bash
cursor-agent --trust --plugin-dir <aidd を clone したパス>
```

`.cursor-plugin` は `skills/` も宣言する。既存の自動 skill に加え、`/design-review` / `/eval` / `/autonomous-review` / `/issue-split` / `/issue-select` / `/retro` / `/asset-audit` / `/incident-retro` / `/adr` / `/design-doc` / `/design-sync` / `/doctor` / `/infra-audit` / `/issue-implement` / `/test-perspectives` が起動できる（名前空間は付かない）。`commands/` は無い。

Claude Code に入れた aidd と、この Cursor 用プラグインは併用しない。併用すると usage.json の二重加算や案内文の重複が起きうる。Cursor は Claude Code に入っているプラグインの skill も読むので、Claude 側だけ入れてある場合は自動 skill は見える。Cursor の編集は `preToolUse` では `tool_name` `Write` として届くので、Write 配線で足りる。専用の Edit matcher は無い。Cursor のモデルは skill を SKILL.md の `Read` で読み込むので、`Read` 配線で `/autonomous-review` のモデル起動を拒否し、手で打つよう案内する (Cursor の `preToolUse` は `ask` を無視するため。手で打った起動は `Read` を通らないので止まらない)。

## 前提環境と利用側プロジェクトの規約

**実行環境** (hooks が依存):

- OS: macOS / Linux (`usage-log.sh` が `fcntl` を使うため Windows 非対応)
- 必須コマンド: `bash`, `python3`, `git`。`gh` は PR/issue 関連の hooks・commands が対象とする操作で使用

**利用側プロジェクトのディレクトリ規約** (commands / hooks は cwd 相対で以下を前提とする):

| パス | 用途 |
|------|------|
| `docs/design/` | `/aidd:design-doc` の出力先、`/aidd:design-sync` の検査対象 |
| `docs/adr/` | `/aidd:adr` の出力先、adr-recall スキルの参照先 |
| `docs/test-perspectives/` | `/aidd:test-perspectives` の出力先。hook が6時間以内の更新有無を見る |
| `.aidd/design-perspectives.md` | `/aidd:design-review` のプロジェクト固有観点 (任意)。`cp templates/design-perspectives.md.template .aidd/design-perspectives.md` で可観測性・ドメイン固有の観点から始められる |
| `.aidd/issue-priority.md` | issue-priority スキルの優先度ラベル名・段数 (並べた順で上位から下位)・追加の軸 (任意)。無ければ既定の `priority:P0`〜`P3` |
| `.aidd/learnings/<YYYYMMDDTHHMMSSZ>-<16進8桁>.json` | 知見の台帳 (任意、**既定で無効**)。`/aidd:incident-retro` が事故の観測と、Claude Code の auto memory の feedback から取り込んだ観測 (`source: auto-memory`) を、`/aidd:autonomous-review` が confirmed・deferred の指摘の型を1観測1ファイルで書き、同じ `signature` が別のセッションで2回以上あれば昇格候補として示す (2回ルールをチームで数える。数えるのは既定ブランチにマージ済みの観測と今回のセッションで書いた観測だけ)。同じセッション・同じ `signature` の観測は1件だけ書く (2件目は `fact` が違っても `scripts/learnings.py add` が終了コード5で書かない)。コミットして PR で共有する。clone ごとに `git config aidd.learnings true` で有効にする (`.git/config` に入るのでコミットされず、fork にも引き継がれない)。項目 (`schema_version` 1、すべて必須、ほかのキーは拒否): `schema_version`・`source` (`incident-retro` / `auto-memory` / `autonomous-review`)・`scope` (`project` / `tool` / `aidd`)・`status` (`observed` / `applied` / `declined`)・`signature` (コマンド名・ツール名とサブコマンド・フラグだけ。`autonomous-review` は `review <category> <type words>` で、`scope` は `project`、`evidence` は SHA と `#番号` だけ)・`fact` (200字以内の事実。唯一の自由記述)・`evidence` (コミット SHA・`#番号`・リポジトリ相対パスだけ)・`session` (セッション ID の SHA-256 の先頭12桁)。作成者名は持たない |

**知見の台帳に機密を入れない4層** (詳細は `docs/superpowers/specs/2026-11-22-learnings-ledger-design.md`):

1. 項目の制限 (上の表)
2. 書く時点の検査: incident-retro と autonomous-review は `scripts/learnings.py add` を通してだけ書く。NFKC で正規化したうえで、スキーマと、絶対パス・メール・URL・IP・FQDN・token の接頭辞・高エントロピー文字列・UUID・長い16進・会社名の手がかり (`株式会社`・`Inc.` など) の正規表現にかけ、制御文字・書式文字 (ゼロ幅・双方向制御)・行や段落の区切り文字を含むものも含めて、該当すれば伏せ字にせず拒否する
3. コミット時の検査 (`tool-reminder.sh`): **よくある形での不注意を防ぐ層**で、すべてのコミットを止めるものではない。Claude Code が実行する `git commit` の前に、ステージ済みの台帳ファイルと、同じコマンドの `git add` / `git commit` が名指しした台帳ファイル (pathspec は git 自身に解決させる) の両方の版を同じ検査にかけ、通らなければ拒否する (有効化の有無に関係なく動く)。次の経路では効かない、または効くとは限らない:
   - git が解決できない、またはこの層が読み取れない pathspec の書き方と `--pathspec-from-file`
   - git のエイリアス (`git -c alias.*` を含む)、`GIT_INDEX_FILE`、`--git-dir` / `--work-tree`、`bash -c` などコマンドを文字列で渡す形
   - 名指ししないステージ (`add -p`・`add -u`・`commit -a`。`add -A` / `-u` と `commit -a` は別の判定が拒否するが、`AIDD_DISABLE_GIT_SAFETY=1` でその拒否を外すと、ステージ前の台帳ファイルは検査されない)
   - `git commit` 以外でコミットを作る操作 (merge・cherry-pick・rebase・am・revert)、低レベルのコマンド (`update-index`・`commit-tree` など)
   - Claude Code を通さないコミット (人の手・ほかのツール)。Codex・Cursor の adapter 経由で同じように効くかは未検証
4. PR での人のレビュー: 顧客名・業務の固有名・社内ホスト名だけの名前は正規表現で捕まらない。これが最後の防衛線になる。マージ後に消すには履歴の書き換えが要る

**検査が捕まえるのは不注意で入ったものだけで、意図して隠した値は捕まえない。**

**有効にする前の前提**: 3層目が止められない経路を補うため、台帳を有効にする前に、台帳のすべてのファイルに `learnings.py check` をかける CI を利用側リポジトリに入れ、既定ブランチの ruleset で必須のチェックにする。例 (GitHub Actions。`ref` は導入している aidd のコミット SHA に固定する。検査の規則を足した aidd の版が出たら、`ref` もその版に追従する。古い版に固定したままだと、足した規則が CI で効かない):

```yaml
name: learnings-ledger
on: [pull_request, push]
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/checkout@v4
        with:
          repository: chun-mura/aidd
          ref: <aidd のコミット SHA>
          path: .aidd-plugin
      - name: Check every ledger file
        run: |
          git ls-files -z -- .aidd/learnings/ \
            | xargs -0 -r python3 -I .aidd-plugin/scripts/learnings.py check
```

あわせて gitleaks などの秘密検出も CI で動かす (雛形は未提供)。

**顧客案件・NDA の対象のリポジトリ**では、台帳を有効にする前に情報管理の責任者の確認を取る。台帳の中身 (`fact` など) は、incident-retro と autonomous-review の実行時に生成 AI に入力される。

## インデックス

### Skills (利用者が呼ぶ。モデルからは自動起動しない)

| Skill | 用途 | Claude Code | Codex | Cursor |
|---|---|---|---|---|
| `design-review/` | 設計や実装方針を多観点レビュー。既定の `--depth=standard` は必要時だけ refuter / arbiter を起動し、反証済み指摘を直接報告する。`--depth=deep` は品質重視の完全経路。再レビューでは `--review-delta=<変更範囲>` で差分と周辺文脈に絞る。`--verify-sources` で外部情報源検証を追加。信頼境界を跨ぐ設計では security-reviewer (STRIDE) を条件起動 (`--security` / `--no-security` で強制・抑止)。構造の観点でコンポーネントごとのコード上の配置の記載と、既存の構造から外れる理由も見る。永続化を含む設計では、スキーマを緩める選択 (JSON 型など) の理由と代替案、検索条件のインデックスの前提、上限の無い全件ロードも見る。同時に読み書きされる状態が設計書から読み取れる場合は、競合・二重実行・破損への対策を見る。機微情報をファイル・ログ・キャッシュに保存する設計でも security-reviewer を起動する | `/aidd:design-review` | `$aidd:design-review` | `/design-review` |
| `eval/` | design-review パイプラインの精度測定。`tests/eval/` のゴールデンセット (シード欠陥入り設計書 + 正解キー) にレビューを実行し、検出率・反証誤棄却・偽指摘の棄却率・デコイ誤検出・ノイズ率・総トークン等を採点して `tests/eval/results/` に記録する。レビューはケースごとに新しいセッション (`claude -p`) が、keys・results・Git 履歴・planted のファイルを含まない一時ディレクトリで実行し (偽指摘は中立な ID でプロンプトに付ける)、生出力と stream-json をハッシュで凍結して照合してから採点する。モデル・CLI・git SHA・入力/キー/プロンプトのハッシュ、パイプラインと採点のコスト (トークン/USD) を記録する (aidd リポジトリ自身で実行) | `/aidd:eval` | `$aidd:eval` | `/eval` |
| `autonomous-review/` | ローカル差分または `--base` / `--head` で指定した2ブランチ間の差分を、既定の Codex read-only 異種AIレビュー（`--reviewer claude` で同一モデル自己レビュー）、差分の性質に応じた観点別レビュー (エラーハンドリング / セキュリティ / 横展開) の条件付き追加、現物反証、品質ゲート、リスク判定で最大3ラウンド検査し、`deferred` は追跡先 (issue 番号 or `review-dismissed.md`) の確定を終了条件にし、ロジックを変えた場合は `report.md` に観点とテストの対応表を書き、自動マージ可否だけを判定する。知見の台帳 (既定で無効) を有効にしたリポジトリでは、最終判定のあと、利用者の承認を得た指摘の型 (`review <category> <type words>`) を台帳に書き、別のセッションで2回以上出た型を `.aidd/design-perspectives.md` への昇格候補として示す (判定は変えない)。未指定の `--base` / `--head` / `--reviewer` は AskUserQuestion で決める。`--reviewer claude` 時は最終判定が常に `human_required`。push・PR作成・マージは行わない。Claude Code ではモデルも起動できるが、起動の前に `skill-gate.sh` が必ずユーザーに許可を求める (Codex は手で起動したときだけ、Cursor はモデルの起動を拒否する) | `/aidd:autonomous-review` | `$aidd:autonomous-review` | `/autonomous-review` |
| `issue-split/` | 設計を独立マージ可能なPR単位 (縦切り・5ファイル以内目安) に分割し、承認後に GitHub issue 化 (作成前に `gh issue list --search` で重複を確認。元の issue が引数か設計書で明示されていれば、新規作成分をそのサブ issue に登録。分割案の依存を blocked by として登録し、読み直して確認)。design-doc が規模超過を検知すると提案 | `/aidd:issue-split` | `$aidd:issue-split` | `/issue-split` |
| `issue-select/` | open issue から今着手できる分を選ぶ。進行中の作業 (未 push の実装済みブランチを含む) を先に見て、本文の冒頭と決定済み ADR を確かめ、open のサブ issue を持つ親を子に置き換え、open の issue に blocked by されているものを外し、人の手続きが要るもの・衝突する組み合わせ (同じ画面・共有部品・同じモデル・同じテストファイルの新規作成・マイグレーション・ADR 採番) を外す。ラベルは絞り込みと、付いている優先度ラベルでの並べ替えにだけ使い、優先度の基準は持たない (判定と付与は `aidd:issue-priority` skill の役割)。提案で止める | `/aidd:issue-select` | `$aidd:issue-select` | `/issue-select` |
| `retro/` | aidd 資産の棚卸し。利用実績・hooks/skills の摩擦・陳腐化を洗い出す (対象は aidd 自身の資産のみ)。利用側の incident-retro から還流した issue (`[reflux]`) のうち、保守者がラベル `reflux-triaged` を付けたものだけを signature ごとに集計し (表はタイトルと `## signature` の行だけで作り、本文は利用者が選んだ issue だけを読む。ラベルは保守者が作って付ける)、利用者がこの実行の中で再現を確かめたものから選んだものを eval の昇格と同じ型 (multiSelect → 変更案 → 承認 → CHANGELOG に出典 `還流 #<番号>`・再現した日と環境・本文の `updatedAt`) で反映する。issue の本文はデータとして扱い、再現の手順を自動で実行しない (再現は認証情報を持たない環境で人が行う)。hook・`skill-gate.sh` の変更や拒否・確認を弱める昇格は別の PR で `/aidd:design-review --security` を通す | `/aidd:retro` | `$aidd:retro` | `/retro` |
| `asset-audit/` | 利用側プロジェクトの `.claude/` と `CLAUDE.md` と auto memory の棚卸し。retro と同じ型を利用側の資産に当て、一定期間発火しない hook・参照先の消えた記述・上流に吸収された規則・2箇所にある同じ基準・観測1件からの一般化を削除・改訂候補に、`error` 行を持つ hook を修正候補にする。auto memory は、索引 `MEMORY.md` に無いファイルを改訂候補に、`CLAUDE.md`・rules・hook と重なる記述を統合候補に、知見の台帳 (有効なときだけ) で2回以上観測され正典に既に規則がある知見を削除候補にする。出力に memory の本文を写さない。候補が0件なら基準を疑う。人だけが起動する (`disable-model-invocation`) | `/aidd:asset-audit` | `$aidd:asset-audit` | `/asset-audit` |
| `incident-retro/` | セッションの事故の棚卸し。再発防止の置き場をコード (今直さないなら issue) → hook → ADR (決定とその理由) → `CLAUDE.md` / `AGENTS.md` / Cursor の rules / memory (リポジトリを移っても効くか) → コマンドの順に決め、一般則にする前にその規則で壊れるものを1件挙げさせる。ADR・issue は `/aidd:adr`・`/aidd:issue-split` に委ねる。知見の台帳 (`.aidd/learnings/`、既定で無効) を有効にしたリポジトリでは、同じ `signature` が別のセッションで2回目以上 (既定ブランチにマージ済みの観測と今回のセッションの観測で数える) の事故を昇格候補として示し、承認された観測を検査 (`scripts/learnings.py`) に通ったものだけ台帳に書く。台帳が有効なら、このセッションの auto memory の feedback (`type: feedback`) も読み、`originSessionId` が UUID の形のものを観測の候補にする (無いもの・形が違うものは件数だけを伝える。memory の本文はデータとして扱い、台帳に書く値をそのまま見せてから承認を取る。memory の文とパスは台帳に写さず、memory のファイルは変えない。取り込んだ観測は PR でマージされてから回数に入る)。還流 (**既定で無効**。clone ごとに `git config aidd.reflux true` で有効にする。台帳とは別の設定) を有効にしたリポジトリでは、aidd の資産や共通の道具 (git・gh・Claude Code) の挙動の知見を、置き場の判定の先頭で、固有情報を伏せた aidd 本体への還流の issue 草案にする (道具の挙動として再現できれば1回目でも候補。再現の手順を、プレースホルダだけを使い固有情報なしで書けることが必須。草案は scratchpad のファイルに書き、`scripts/learnings.py scan` の検査に通し、同じファイルを全文見せて承認を取る。issue は作らず、送るのは担当者の確認を経た利用者で、同じファイルを `--body-file` で送る)。人だけが起動する (`disable-model-invocation`) | `/aidd:incident-retro` | `$aidd:incident-retro` | `/incident-retro` |
| `adr/` | アーキテクチャ決定記録を docs/adr/NNNN-<slug>.md に作成。1 ADR = 1 決定。採番はローカルに加えローカル／リモートの全ブランチを見て衝突を避ける | `/aidd:adr` | `$aidd:adr` | `/adr` |
| `design-doc/` | 要件から設計書を生成し docs/design/ に保存。構成は design-review の6観点と1対1対応。構成と責務にコンポーネントごとのコード上の配置を書く。永続化を含む設計では、データフローの節にデータモデル (スキーマを緩める選択の理由と代替案) と主要な経路のインデックスの前提・読む件数の上限を書かせる。同時に読み書きされる状態があれば、データフローの節に競合・二重実行・破損への対策を書かせる | `/aidd:design-doc` | `$aidd:design-doc` | `/design-doc` |
| `design-sync/` | 設計書と実装の乖離を検知し、status を最新化する | `/aidd:design-sync` | `$aidd:design-sync` | `/design-sync` |
| `doctor/` | aidd/superpowers の導入状態・バージョン整合・hooks 実行可否・Codex custom agents の導入を診断する。利用側の sandbox 設定も見て、`sandbox.enabled` が true でなければ、`gh` を `excludedCommands` で sandbox の外に出していれば、また sandbox の中の `gh` に `GH_TOKEN`・`GITHUB_TOKEN` か (macOS では) `SSL_CERT_FILE`・`GH_CONFIG_DIR` が無ければ WARN を出す (token の値は表示しない)。項目1–2（`claude plugin list` と `installed_plugins.json`）と sandbox 設定の項目は Claude Code 以外ではスキップして「Claude Code のみ」と書く | `/aidd:doctor` | `$aidd:doctor` | `/doctor` |
| `infra-audit/` | 利用側プロジェクトの静的解析(複雑度制御)・重複コード検出(jscpd/knip)・多OS CI の導入状況を診断する。doctor が aidd 自身を診断するのに対し、こちらは利用側プロジェクトの品質ガードを対象とする | `/aidd:infra-audit` | `$aidd:infra-audit` | `/infra-audit` |
| `issue-implement/` | issue 1本を着手ゲート (要件が受領した原文か起票時の推測か、ADR の決定の節) → 曖昧さの3分類 (仕様の選択だけを人に上げる) → レーン判定 (行数でなくスキーマ・エントリポイント・認可・画面・採否・ファイル数で設計から入るか決める) → 実装 → 条件付きレビュー追加 → 完了条件の順に進める入口。実装の中身は superpowers と aidd の既存資産に委ねる。完了前に差分を設計書の配置と照らし、配置からのずれと責務の集中を確かめる。deferred を issue か棄却一覧に落とすまで完了にしない。完了報告に観点とテストの対応表 (must は全件、前提を壊して落ちたか、未実装の理由) を書く。push・PR作成は行わない | `/aidd:issue-implement` | `$aidd:issue-implement` | `/issue-implement` |
| `test-perspectives/` | 実装対象・変更差分からテスト観点 (6分類 + 信頼境界に触れる変更・機微情報をファイル・ログ・キャッシュに保存する変更のみセキュリティ分類) を洗い出し、BVA/ECP 適用フラグを付ける (手法の導出は stdd の担当) | `/aidd:test-perspectives` | `$aidd:test-perspectives` | `/test-perspectives` |

### Agents (サブエージェント定義)

| ファイル | 説明 |
|---------|------|
| `design-arbiter.md` | design-review の統合裁定エージェント (opus)。メインのモデルに依らず重い判断を opus に固定 |
| `refuter.md` | レビュー指摘の反証専任エージェント (sonnet)。high/mid 指摘を現物に照らして積極的に反証し、耐えた指摘だけを昇格させる。design-review・review-loop から起動 |
| `reviewer.md` | 成果物の検収用エージェント (sonnet)。PR全体のレビューは pr-review-toolkit の担当 |
| `scout.md` | 軽量読み取り調査エージェント (haiku)、ファイル検索・コードベース偵察用 |
| `security-reviewer.md` | 信頼境界を跨ぐ設計 (機微情報をファイル・ログ・キャッシュに保存する設計を含む) への STRIDE ベース脅威レビュー (sonnet)。design-review が条件起動。攻撃経路を構成できる懸念のみ high/mid で報告 |
| `source-verifier.md` | 設計書の外部検証可能な主張を信頼できる情報源と突き合わせる (sonnet, WebSearch/WebFetch)。design-review の `--verify-sources` 専用 |
| `.codex/agents/aidd-*.toml` | 上の6定義の Codex 用写し。必須キーは `name` / `description` / `developer_instructions` だけ。`scripts/generate-codex-agents.py` が生成し、`scripts/install-codex-agents.sh` が利用側へコピーする |

### Skills (自動トリガする知見)

| ファイル | 発火条件 |
|---------|------|
| `adr-recall/` | アーキ変更・既存構造変更・設計判断の前 |
| `model-selection/` | サブエージェント起動時・model 指定に迷ったとき |
| `four-kinds-check/` | コミット直前に、staged diff の追加行にコメントやテスト名があるとき・コミット本文を書くとき (CLAUDE.md の「コメントの置き場所」を採るか `AIDD_COMMIT_WHY_CANON` を設定したプロジェクトだけ。コメントは Why not 以外を置き場所へ移し、テスト名は What、本文は Why を言っているかを見る) |
| `issue-priority/` | 優先度ラベルの付与や見直しを頼まれたとき・優先度ラベルを使うリポジトリで issue を起票するとき (`AIDD_REQUIRED_LABEL_PREFIX`・`.aidd/issue-priority.md`・`gh label list` の優先度ラベルがどれも無ければ何もしない。深刻さ×広さに放置コストを足して判定。最上位は根拠を示して確認、既存ラベルは黙って張り替えない、系列独自の運用があれば従う。ラベル名・段数・追加の軸は `.aidd/issue-priority.md` で上書き) |
| `parallel-coordinator/` | 複数の issue・タスクを worker に並行実装させるコーディネーターの立場のとき (superpowers に無い差分のみ) |
| `review-loop/` | レビュー→修正のラウンドを反復するとき・指摘が尽きないとき・重要度語彙が混在したとき (最大3ラウンド、終了条件、deferred mid と認める追跡先、棄却指摘の持ち越しを規定) |

### Hooks (強制力のある運用)

| スクリプト | 動作 |
|---------|------|
| `session-start.sh` | SessionStart で aidd 資産の使いどころと「実装を左右する不明点は、このセッションが実際に持つ手段で確認する (対話なら AskUserQuestion、監督下なら親への返答)」を注入。`/aidd:asset-audit` の最終実施日 (未実施なら `aidd-hook-log.sh` が最初の hook の記録を始めた日) から一定期間 (既定30日) が過ぎたプロジェクトでだけ、棚卸しを促す1文を足す。superpowers 未導入を検知して警告 |
| `usage-log.sh` | 起動を2経路で記録し、aidd コマンド使用数・最終利用時刻を `~/.claude/aidd/usage.json` に残す (`/aidd:retro` が読む): 行頭が `/aidd:<name>` のプロンプト (UserPromptSubmit) と、Skill ツール経由の起動 (PreToolUse、サブエージェント内の起動もここに入る)。文中で名前に触れただけのプロンプトは計上しない。実在するコマンド・skill 名だけを計上し、旧版が残した `prompt_log` は起動時に削除する |
| `tool-reminder.sh` | `git commit` 前の test-perspectives 確認、`gh pr/issue create・edit` 前の日本語確認、`gh pr create` 前のレビュー証跡の確認、`git push` 後の PR 同期確認、`git commit` 後の HEAD の件名 (Conventional Commits 形式) と本文の有無の検査を1本で処理 (ここまでは非ブロック。コミットの検査はコマンド文字列でなく確定後の HEAD を SHA ごとに1回だけ読み、規約を採るリポジトリだけで行う。後続のコマンドが失敗した場合 (PostToolUseFailure) もコミットは検査する)。加えて、未コミットの作業を失う git 操作 (`stash`・`reset --hard`・パスを指定した `checkout` (`checkout -- <path>` / `checkout .` / `checkout <path>` / `checkout HEAD <path>`)・`checkout -f`・`switch -f` / `--discard-changes`・`--staged` だけでない `restore`・`-n` の無い `clean`) と指名しないステージ (`add -A` / `-u`、`.` / `./` / `..` / `:/` のように作業ディレクトリやルートを指すパス、`commit -a`) を拒否する。既定ブランチ (push 先のリモートの `HEAD` が指す実在のブランチと、常に `main` / `master`) への force push (`--force`・`-f`・`--force-with-lease`・`+<refspec>`・`--mirror`・`--force --all`・`+:`・`heads/<既定>` のような短い書き方・`--force-w` のような省略形。refspec を省いた場合は `remote.<name>.push` と `push.default` で決まる送り先が既定ブランチなら) と既定ブランチのリモート削除 (`push --delete`・`push <remote> :<branch>`) も拒否し (送り先に `$`・バッククォートを含む force / delete / prune の push も、判定できないので拒否する)、作業ブランチへの force push と `-n` / `--dry-run` は止めない (どの操作をどこで止めるかは「破壊的な操作をどこで止めるか」)。主ツリーを別のセッションが直近に使っているときは相手ごとに1回だけ worktree への移動を促し (拒否はしない。`session_id` は resume / compact の前後で同じと保証されていない)、`git commit` は、ステージ済みか同じコマンドの `git add` / `git commit` が名指しした知見の台帳 (`.aidd/learnings/`) のファイルが検査 (`scripts/learnings.py`) に通らなければ拒否する (よくある形での不注意を防ぐ層で、効かない経路は「利用側プロジェクトのディレクトリ規約」の4層の節にある。台帳の有効化に関係なく動き、台帳のファイルを含まないコミットでは何もしない。検査スクリプトを読み込めない・検査が途中で失敗したときは台帳を含むコミットを拒否し、git が台帳のファイルを列挙できなかったときもコミットを拒否する)。`gh issue create` は同じセッションで直近に同じリポジトリ (`-R` / `--repo`、無ければ cwd の `origin`) に対して `gh issue list --search` を実行していなければ拒否する。`AIDD_REQUIRED_LABEL_PREFIX` を設定すると、その接頭辞のラベルが無い `gh issue create` も拒否する。コマンドは引用符・`&&` / `;` の連結・`#` のコメント・`if` / `then` / `do` などの制御構文・`cd`・`git -C`・前置のラッパー (`rtk` など) を見分けて判定し、1回の起動で当たった判定は JSON 1つにまとめて返す。コマンドに `git` / `gh` の語が無ければ python を起動せずに終わる。レビュー証跡の確認は、`--head` のブランチ (未指定なら cwd のブランチ) が基点ブランチに対してコードを変更しているのに、どの worktree の `.aidd/autonomous-review/` にもそのブランチの `state.json` が無いときだけ、変更ファイルの一覧つきで警告する (docs だけの変更では鳴らさない) |
| `skill-gate.sh` | モデルが Skill ツールで `autonomous-review` を起動する前に、PreToolUse で `ask` を返してユーザーの許可を取る (名前は接頭辞・先頭の `/`・大文字小文字の違いをならして照合する)。対話の default / auto / bypassPermissions、allow ルール、サブエージェントのどれでも確認がユーザーに届き、headless (`-p`) では拒否として働く。ユーザーが手で打った起動は Skill ツールを通らないので確認は出ない。判定を出してから件数を記録し、入力を解釈できなくても `autonomous-review` を含めば `ask` を返す。Cursor では adapter 経由で、この plugin の `skills/autonomous-review/SKILL.md` の `Read` を拒否する。hook が起動できないときや hook が無効な環境 (`disableAllHooks` など) では確認なしで起動しうる (hook の起動失敗は Claude Code が素通りさせる) |
| `write-guard.sh` | Write・Edit・NotebookEdit の PreToolUse を1本で処理する。対象はまだ存在しないファイルだけで、既存ファイルと対象外のパスでは何も出さずに終わる。サンドボックスの読み取り拒否によく入る名前 (`.env*`・`*.pem`・`*secret*`・`*credential*` など) のファイルを新しく作ろうとしたら拒否する (作った後に git・テスト・シェルから読めなくなるため)。Claude Code には読み取り拒否の既定リストが無いので、パターンは `AIDD_UNREADABLE_NAME_PATTERNS` で利用側の設定に合わせて差し替える。あわせて、`.claude/{hooks,skills,commands,rules,agents}/` (プロジェクト側・`~/.claude/` 側の両方) に新しい資産を作ろうとしたら、同梱の `hooks/asset-index.json` から aidd の資産一覧 (名前と description) を additionalContext で渡し、役割が重なるならそれを使うか aidd への要望として起票するよう促す。重なりの判断はモデルに任せ、aidd の command・skill・agent と同名のときだけ拒否する (command・agent は種類のディレクトリ直下のファイルだけ比べる。`commands/adr/new.md` は `/adr:new` になり、agent の名前は frontmatter で決まるため)。既存の資産と既存 skill 内のファイルは対象外。`AIDD_ASSET_OVERLAP_PLUGINS` で指定した他のプラグインの資産も、そのディレクトリの `.claude-plugin/plugin.json` から実行時に読んで一覧に加える (同梱の一覧には入れない。`<plugin>:<name>` の名前空間で利用側の同名の資産と共存するため、案内だけで拒否しない) |
| `harness-adapter.sh` | Codex の `apply_patch` と Cursor の Shell / Write / Read / SessionStart を、既存スクリプトが読める形に揃えて呼び、返事を各ハーネスの形に戻す。判定ロジックは持たない。adapter 自体は常に exit 0。子の起動失敗 (`script_failed`)、非0終了 (`script_nonzero_exit`)、シグナル終了 (`script_signaled`) を `adapter-skips.json` に計数する。異常終了時は有効な拒否 JSON のみ保持し、通知 JSON・テキストは破棄する。複数ファイルの一部で失敗しても、他ファイルの拒否を保持する。Cursor の Read は `autonomous-review` を含むものだけ python を起動して `skill-gate.sh` に渡す |

#### Hooks の書き込み先と無効化

hooks は上記スクリプトをセッション中に自動実行する。ファイル書き込みは `~/.claude/aidd/` 配下のみで、外部送信は一切しない:

| 書き込み先 | 内容 | 書き込み元 |
|-----------|------|-----------|
| `~/.claude/aidd/usage.json` | `/aidd:*` コマンドの使用数・最終使用時刻 | `usage-log.sh` |
| `~/.claude/aidd/main-tree.json` | 主ツリーごとの、git を実行したセッション ID と最終時刻 (失効時間を過ぎたものは削除)、警告済みの組 (相手の占有が失効したら削除) | `tool-reminder.sh` |
| `~/.claude/aidd/issue-search.json` | セッション ID とリポジトリの組ごとの、最後に `gh issue list --search` を実行した時刻 (1日を過ぎたものは削除) | `tool-reminder.sh` |
| `~/.claude/aidd/commit-why.json` | コミットの検査で判定済みの SHA と判定時刻 (新しい 200 件まで) | `tool-reminder.sh` |
| `~/.claude/aidd/skill-gate.json` | `skill-gate.sh` が返した判定の種類 (`ask` / `ask_failclosed` / `deny_cursor_read`) ごとの件数と最終日時 (skill 名・パス・入力は残さない。承認・拒否の結果は hook から見えないので数えない) | `skill-gate.sh` |
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

### Templates (設定雛形)

| ファイル | 説明 |
|---------|------|
| `CLAUDE.md.template` | プロジェクト概要・技術スタック・コマンド・AI運用をまとめるテンプレート。コメントの置き場所 (How はコード / What はテスト / Why はコミットログ / Why not はコメント) を規約として同梱 |
| `settings.json.template` | Claude Code 権限設定の基本構成テンプレート |
| `sandbox-settings.json.template` | ローカル実行で権限を絞るときに `.claude/settings.json` にマージする。Bash を sandbox に入れ、通信先を GitHub と主要レジストリに、書き込みを作業ディレクトリに限り、`gh` も sandbox の中で動かし (macOS では `env` の `SSL_CERT_FILE` で TLS を通す)、認証情報ファイルの読み取りと危険な `gh` のサブコマンドを拒否し、`rm -rf`・`git push --force`・`git branch -D` に確認を出す (手順は「ローカルで権限を絞って使う」) |
| `team-settings.json.template` | チーム導入用。利用プロジェクトの `.claude/settings.json` にマージすると aidd が自動提案される |
| `design-perspectives.md.template` | `.aidd/design-perspectives.md` の出発点。可観測性・プロジェクト固有観点 (design-review の Agent 4 が読む) |
| `asset-overlap-prompt-hook.json.template` | 資産の重複を厳格に止めたい利用側向けの prompt 型 PreToolUse hook (既定では無効。`.claude/settings.json` の `hooks` にマージして有効化)。`.claude/{hooks,skills,commands,rules,agents}/` への Write をモデルが aidd の資産一覧と照らし、役割が重なれば拒否する。`scripts/generate-asset-index.py` が生成する |
| `aidd-hook-log.sh` | 利用側の `.claude/settings.json` に書いた hook を包み、発火と失敗 (`error` 行) を `~/.claude/aidd/` 配下に記録するラッパー。包んだ hook の stdin・stdout・stderr・終了コードはそのまま通す。`/aidd:asset-audit` の「一定期間発火しない hook」「記録が壊れている hook」の判定に使う |

#### `aidd-hook-log.sh` の導入 (利用側プロジェクト)

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

### Tips (方法論の知見)

| ファイル | 説明 |
|---------|------|
| `superpowers-usage.md` | superpowers スキルとの棲み分け、二重実装の回避 |

## 依存プラグインの互換方針

- **superpowers (必須)**: `plugin.json` の `dependencies` で `superpowers@superpowers-marketplace` を宣言しており、インストール・有効化時に自動解決される (Claude Code v2.1.110+)。古いバージョン向けのフォールバックとして `session-start.sh` が `~/.claude/plugins/installed_plugins.json` の `superpowers@` エントリで導入有無を検知する (ベストエフォート、非ブロック)。`docs/tips/superpowers-usage.md` が superpowers のスキル名を参照するため、superpowers 側の破壊的変更 (スキル改名・削除) で連携が壊れても aidd 自体の commands / agents / hooks は動作する。壊れた疑いがあるときは `/aidd:doctor` で診断する
- **pr-review-toolkit (推奨)**: 連携点は `/aidd:issue-implement` の条件付きレビュー (silent-failure-hunter) だけで、未導入なら `aidd:reviewer` のエラーハンドリング観点で代える。未導入でも aidd の全機能が動作し、PRレビューの網羅性だけが下がる

## 運用ルール

1. **1ファイル1関心事**: 各ファイルは単一トピックに集中。docs は冒頭に「いつ使うか」を明記
2. **2回ルール**: 同じプロンプトを2回以上使ったものだけ commands/skills に昇格
3. **README更新**: 資産追加時は本インデックスを更新し、`.claude-plugin` / `.codex-plugin` / `.cursor-plugin` の `version` を同じ値に上げて CHANGELOG に記録。command・skill・agent・hook の追加・削除・改名、frontmatter の `name`・`description` の変更、`hooks/hooks.json` の配線や hook スクリプトの shebang 直後のコメント行の変更、plugin.json の `commands`・`skills`・`agents`・`hooks` の宣言の変更をしたら `python3 scripts/generate-asset-index.py` で資産一覧を再生成する (CI の `python3 scripts/generate-asset-index.py --check` と `tests/hook-contract-test.sh` が不一致で落ちる)。`agents/*.md` の本文や frontmatter を変えたら `python3 scripts/generate-codex-agents.py` も同じコミットで回す (CI の `--check` が stale で落ちる)
4. **重複禁止**: superpowers・reqd・estimate・uidd・stdd・グローバル資産と被る機能は作らず、ポインタのみ記載
5. **受動ドキュメント禁止**: セッション中に効かせたい知見は docs でなく skills (自動トリガ) か hooks (強制) にする
6. **パイプライン変更時の評価**: `skills/design-review/SKILL.md`・`agents/refuter.md`・`agents/design-arbiter.md`・`agents/security-reviewer.md`・`agents/reviewer.md` のプロンプトを変更するリリースは、リリース前に `/aidd:eval` を実行し結果を `tests/eval/results/` に残す (退行の検知はこの記録の比較でのみ可能)

## 設計ドキュメント

詳細な設計・運用ガイドは以下を参照:

- `docs/superpowers/specs/2026-07-08-aidd-knowledge-base-design.md` — 全体設計、ディレクトリ構成、スコープの棲み分け
