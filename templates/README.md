# templates

新規プロジェクト立ち上げ時にコピーして使う雛形。

いつ使うか: Claude Code を新しいリポジトリで使い始めるとき。

- `CLAUDE.md.template` — プロジェクトの CLAUDE.md の出発点。コメントを埋めて `.template` を外す。「コードから読み取れないことだけ書く」が原則
- `settings.json.template` — `.claude/settings.json` の出発点。read-only git 操作を許可し、機密ファイルを deny する最小構成

使い方: `cp templates/CLAUDE.md.template <project>/CLAUDE.md` して編集。
