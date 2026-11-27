# templates

新規プロジェクト立ち上げ時にコピーして使う雛形。

## いつ使うか

Claude Code を新しいリポジトリで使い始めるとき。

- `CLAUDE.md.template` — プロジェクトの CLAUDE.md の出発点。コメントを埋めて `.template` を外す。「コードから読み取れないことだけ書く」が原則。「AI運用」節は Issue の実装を `/aidd:issue-implement` に、Issue を使わない開発を既存 skill に案内するだけで、設計書・レビューの要否の条件は issue-implement の「レーン判定」を正として書き写さない
- `settings.json.template` — `.claude/settings.json` の出発点。read-only git 操作を許可し、機密ファイルを deny する最小構成
- `sandbox-settings.json.template` — aidd の skill をローカルで動かすとき、利用プロジェクトの `.claude/settings.json` (自分だけなら `.claude/settings.local.json`) にマージする。Bash を sandbox に入れ、通信先を GitHub と主要レジストリに、書き込みを作業ディレクトリに限り、認証情報ファイルの読み取りと危険な `gh` のサブコマンドを拒否し、`rm -rf`・`git push --force`・`git branch -D` に確認を出す。`gh` も sandbox の中で動き (macOS では `env` の `SSL_CERT_FILE` で TLS を通す。Go 1.27 以上でビルドした `gh` が要る)、対象リポジトリだけの fine-grained PAT を `GH_TOKEN` で渡す (手順は aidd の [ローカルで権限を絞って使う](../docs/guides/local-permissions.md))
- `team-settings.json.template` — チームで aidd を使うとき、利用プロジェクトの `.claude/settings.json` にマージしてコミットする。フォルダを trust したメンバーに aidd のインストールが自動提案される (`extraKnownMarketplaces` + `enabledPlugins`)
- `design-perspectives.md.template` — `.aidd/design-perspectives.md` の出発点。可観測性・プロジェクト固有観点。信頼境界のセキュリティは Agent 6 (STRIDE) が担当する
- `asset-overlap-prompt-hook.json.template` — aidd と役割の重なる資産を厳格に止めたいときだけ、利用プロジェクトの `.claude/settings.json` の `hooks` にマージする (既定では無効)。aidd 同梱の `write-guard.sh` は一覧を渡して同名だけ拒否するのに対し、こちらは `.claude/{hooks,skills,commands,rules,agents}/` への Write ごとにモデルが意味の近さを判定して拒否する。制約: prompt 型 hook はファイルの有無を見られないため、既存資産の Write による上書きも判定される / Write ごとにモデル呼び出しが1回増える / `if` は作業ディレクトリ配下にしか当たらず `~/.claude/` は対象外 / 一覧はコピー時点の aidd のもので、aidd を更新したら貼り直す
- `aidd-hook-log.sh` — 利用側プロジェクトの `.claude/hooks/` にコピーし、`.claude/settings.json` の既存 hook のコマンドの前に `aidd-hook-log.sh <hook-id>` を足す。発火と失敗を `~/.claude/aidd/` 配下に記録し、`/aidd:asset-audit` が読む (手順は aidd の [hooks の運用と調査「`aidd-hook-log.sh` の導入」](../docs/guides/hooks-operations.md#aidd-hook-logsh-の導入-利用側プロジェクト))

使い方: `cp templates/CLAUDE.md.template <project>/CLAUDE.md` して編集。

permission の allow リストは、しばらく運用してから `/fewer-permission-prompts` で実際の利用実績に基づき拡張するのが確実。
