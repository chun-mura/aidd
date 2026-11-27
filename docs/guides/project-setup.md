# 利用側プロジェクトの設定

[README に戻る](../../README.md) / 関連: [ローカルで権限を絞って使う](local-permissions.md) / [hooks の運用と調査](hooks-operations.md)

## いつ使うか

aidd を入れたプロジェクトで、skill と hook が前提にするディレクトリの置き場を確かめるとき、または任意機能の知見の台帳 (`.aidd/learnings/`) を有効にするか検討するとき。台帳は既定で無効で、通常の導入では設定しなくてよい。

## ディレクトリ規約

commands / hooks は cwd 相対で以下を前提とする:

| パス | 用途 |
|------|------|
| `docs/design/` | `/aidd:design-doc` の出力先、`/aidd:design-sync` の検査対象 |
| `docs/adr/` | `/aidd:adr` の出力先、adr-recall スキルの参照先 |
| `docs/test-perspectives/` | `/aidd:test-perspectives` の出力先。hook が6時間以内の更新有無を見る |
| `.aidd/design-perspectives.md` | `/aidd:design-review` のプロジェクト固有観点 (任意)。`cp templates/design-perspectives.md.template .aidd/design-perspectives.md` で可観測性・ドメイン固有の観点から始められる |
| `.aidd/issue-priority.md` | issue-priority スキルの優先度ラベル名・段数 (並べた順で上位から下位)・追加の軸 (任意)。無ければ既定の `priority:P0`〜`P3` |
| `.aidd/learnings/<YYYYMMDDTHHMMSSZ>-<16進8桁>.json` | 知見の台帳 (任意、**既定で無効**)。通常の導入では設定しない。有効にする前の前提と項目は [知見の台帳](#知見の台帳-任意既定で無効) |

## 知見の台帳 (任意、既定で無効)

有効にする前に、下の [有効にする前の前提](#有効にする前の前提) (台帳を検査する CI と秘密検出) と [顧客案件・NDA の対象のリポジトリ](#顧客案件nda-の対象のリポジトリ) の確認を済ませる。

### 保存先と項目

保存先: `.aidd/learnings/<YYYYMMDDTHHMMSSZ>-<16進8桁>.json`

知見の台帳 (任意、**既定で無効**)。`/aidd:incident-retro` が事故の観測と、Claude Code の auto memory の feedback から取り込んだ観測 (`source: auto-memory`) を、`/aidd:autonomous-review` が confirmed・deferred の指摘の型を1観測1ファイルで書き、同じ `signature` が別のセッションで2回以上あれば昇格候補として示す (2回ルールをチームで数える。数えるのは既定ブランチにマージ済みの観測と今回のセッションで書いた観測だけ)。同じセッション・同じ `signature` の観測は1件だけ書く (2件目は `fact` が違っても `scripts/learnings.py add` が終了コード5で書かない)。コミットして PR で共有する。clone ごとに `git config aidd.learnings true` で有効にする (`.git/config` に入るのでコミットされず、fork にも引き継がれない)。項目 (`schema_version` 1、すべて必須、ほかのキーは拒否): `schema_version`・`source` (`incident-retro` / `auto-memory` / `autonomous-review`)・`scope` (`project` / `tool` / `aidd`)・`status` (`observed` / `applied` / `declined`)・`signature` (コマンド名・ツール名とサブコマンド・フラグだけ。`autonomous-review` は `review <category> <type words>` で、`scope` は `project`、`evidence` は SHA と `#番号` だけ)・`fact` (200字以内の事実。唯一の自由記述)・`evidence` (コミット SHA・`#番号`・リポジトリ相対パスだけ)・`session` (セッション ID の SHA-256 の先頭12桁)。作成者名は持たない

### 知見の台帳に機密を入れない4層

詳細は [`docs/superpowers/specs/2026-11-22-learnings-ledger-design.md`](../superpowers/specs/2026-11-22-learnings-ledger-design.md):

1. 項目の制限 (上の [保存先と項目](#保存先と項目))
2. 書く時点の検査: incident-retro と autonomous-review は `scripts/learnings.py add` を通してだけ書く。NFKC で正規化したうえで、スキーマと、絶対パス・メール・URL・IP・FQDN・token の接頭辞・高エントロピー文字列・UUID・長い16進・会社名の手がかり (`株式会社`・`Inc.` など) の正規表現にかけ、制御文字・書式文字 (ゼロ幅・双方向制御)・行や段落の区切り文字を含むものも含めて、該当すれば伏せ字にせず拒否する
3. コミット時の検査 (`tool-reminder.sh`): **よくある形での不注意を防ぐ層**で、すべてのコミットを止めるものではない。Claude Code が実行する `git commit` の前に、ステージ済みの台帳ファイルと、同じコマンドの `git add` / `git commit` が名指しした台帳ファイル (pathspec は git 自身に解決させる) の両方の版を同じ検査にかけ、通らなければ拒否する (有効化の有無に関係なく動く)。次の経路では効かない、または効くとは限らない:
   - git が解決できない、またはこの層が読み取れない pathspec の書き方と `--pathspec-from-file`
   - git のエイリアス (`git -c alias.*` を含む)、`GIT_INDEX_FILE`、`--git-dir` / `--work-tree`、`bash -c` などコマンドを文字列で渡す形
   - 名指ししないステージ (`add -p`・`add -u`・`commit -a`。`add -A` / `-u` と `commit -a` は別の判定が拒否するが、`AIDD_DISABLE_GIT_SAFETY=1` でその拒否を外すと、ステージ前の台帳ファイルは検査されない)
   - `git commit` 以外でコミットを作る操作 (merge・cherry-pick・rebase・am・revert)、低レベルのコマンド (`update-index`・`commit-tree` など)
   - Claude Code を通さないコミット (人の手・ほかのツール)。Codex・Cursor の adapter 経由で同じように効くかは未検証
4. PR での人のレビュー: 顧客名・業務の固有名・社内ホスト名だけの名前は正規表現で捕まらない。これが最後の防衛線になる。マージ後に消すには履歴の書き換えが要る

**検査が捕まえるのは不注意で入ったものだけで、意図して隠した値は捕まえない。**

### 有効にする前の前提

3層目が止められない経路を補うため、台帳を有効にする前に、台帳のすべてのファイルに `learnings.py check` をかける CI を利用側リポジトリに入れ、既定ブランチの ruleset で必須のチェックにする。例 (GitHub Actions。`ref` は導入している aidd のコミット SHA に固定する。検査の規則を足した aidd の版が出たら、`ref` もその版に追従する。古い版に固定したままだと、足した規則が CI で効かない):

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

### 顧客案件・NDA の対象のリポジトリ

**顧客案件・NDA の対象のリポジトリ**では、台帳を有効にする前に情報管理の責任者の確認を取る。台帳の中身 (`fact` など) は、incident-retro と autonomous-review の実行時に生成 AI に入力される。
