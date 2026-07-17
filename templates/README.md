# templates

新規プロジェクト立ち上げ時にコピーして使う雛形。

## いつ使うか

Claude Code を新しいリポジトリで使い始めるとき。

- `CLAUDE.md.template` — プロジェクトの CLAUDE.md の出発点。コメントを埋めて `.template` を外す。「コードから読み取れないことだけ書く」が原則
- `settings.json.template` — `.claude/settings.json` の出発点。read-only git 操作を許可し、機密ファイルを deny する最小構成
- `team-settings.json.template` — チームで aidd を使うとき、利用プロジェクトの `.claude/settings.json` にマージしてコミットする。フォルダを trust したメンバーに aidd のインストールが自動提案される (`extraKnownMarketplaces` + `enabledPlugins`)
- `design-perspectives.md.template` — `.aidd/design-perspectives.md` の出発点。OWASP ASVS 5.0 抜粋のセキュリティ観点 + 可観測性観点。プロジェクトに合わない項目を削って使う

使い方: `cp templates/CLAUDE.md.template <project>/CLAUDE.md` して編集。

permission の allow リストは、しばらく運用してから `/fewer-permission-prompts` で実際の利用実績に基づき拡張するのが確実。
