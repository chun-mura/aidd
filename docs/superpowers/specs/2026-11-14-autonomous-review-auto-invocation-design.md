# autonomous-review をモデルから起動できるようにする

## 目的

`/aidd:autonomous-review` は `disable-model-invocation: true` で、モデルは Skill ツールから呼べない。一方でフローの2か所がこの skill を案内している。

- `tool-reminder.sh`: `gh pr create` の直前に、証跡が無ければ「/aidd:autonomous-review を実行すること」と警告する
- `skills/issue-implement/SKILL.md` 55行: 自動マージ可否まで要るなら `/aidd:autonomous-review` を使う

どちらもモデルに向けた案内だが、モデルは従えず、ユーザーが手で打つまで止まる。PR 前のレビューを AI 駆動開発フローに組み込むため、モデルが起動できるようにする。ただし、実行前に必ずユーザーの許可を取る。Codex へのコード送信・コード修正・品質ゲートまで走り、時間とトークンを多く使うため。

## 方針

- Claude Code の対話セッションでは `disable-model-invocation` を外し、起動の直前に hook で許可を取る。
- 許可は SKILL.md の文面ではなく hook で強制する。文面の指示はモデルが破りうる。
- gate は fail-closed にする。入力を解釈できないときに許可なしで通さない。
- ユーザーに確認が届かない実行環境（headless・bypassPermissions など）では、gate が拒否して手で打つよう案内する。aidd-autopilot のような無人実行で、Issue 本文に誘導されて起動しないため。
- Codex は対象外とし、今の挙動（ユーザー起動のみ）を残す。Codex の暗黙起動は Skill ツールを通らず、gate を掛けられないため。`openai.yaml` の `allow_implicit_invocation: false` で止まる。
- Cursor は実測で決める。SKILL.md の frontmatter は Cursor と共有で、Cursor がこのフラグを解釈するなら、外した時点で gate なしにモデルから起動できてしまう。

### 採らない案

- **permissions の `Skill(aidd:autonomous-review)` を `ask` にする**: plugin の skill（`plugin:skill`）に効くかが公式ドキュメントに書かれていない。plugin から permissions を配る仕組みも見当たらず、利用者ごとの設定に頼ることになる。
- **SKILL.md の冒頭で AskUserQuestion を出す**: 強制されない。さらに、ユーザーが自分で打ったのかモデルが起動したのかを skill の中から見分ける手段が書かれていない。

## 変更

実装は「実装前に実測すること」がすべて済んでから始める。`disable-model-invocation` を外すコミットと gate を足すコミットは分けず、1つの version で同時に出す（片方だけの版を作らない）。

### `skills/autonomous-review/SKILL.md`

- frontmatter から `disable-model-invocation: true` を外す。
- `description` を自動起動用に書き換え、`issue-implement` 55行と同じ範囲に絞る。例: 「Use before opening a PR when the branch's auto-merge eligibility must be judged locally (cross-model review, quality gates, risk classification). For an ordinary code review use superpowers:requesting-code-review instead. Not for docs-only changes or someone else's PR.」
  - 通常のコード PR まで含めると、許可の確認が毎回出て読まれなくなる。
  - `tool-reminder.sh` の警告文には依存させない。警告から起動へのつなぎは警告文の側が担う（既に `/aidd:autonomous-review --base … --head …` を案内している）。
- 本文の手順は変えない。

### `skills/autonomous-review/agents/openai.yaml`

変えない（`allow_implicit_invocation: false` のまま）。

### hook: `hooks/scripts/skill-gate.sh`（新規）と `hooks/hooks.json`

- `hooks.json` の既存の PreToolUse `^Skill$` エントリの `hooks` 配列に、`usage-log.sh` と並べて足す。matcher の列は変えない（`tests/hook-contract-test.sh:939-945` の matcher 列の検査はそのまま通る）。
- 対象の判定: `tool_input.skill` を正規化して照合する。前後の空白と先頭の `/` を除き、小文字にして、`:` で区切った最後の要素が `autonomous-review` なら対象とする（`aidd:autonomous-review`、`autonomous-review`、`/aidd:autonomous-review` を同じに扱う）。
- 対象でなければ何も出さずに exit 0 とする。他の skill を巻き込まない。
- 対象なら次を返す。
  - ユーザーに確認が届く実行環境: `permissionDecision: "ask"`
  - 届かない実行環境（実測項目3・5で判別方法を決める）: `permissionDecision: "deny"`。理由に「ユーザーに `/aidd:autonomous-review` を手で実行してもらうこと」を書く
- fail-closed: stdin の JSON を解釈できない、`tool_input` が無い、python が無いときは、生の入力に `autonomous-review` という文字列が含まれていれば `ask` を返す。含まれなければ exit 0。判定の第一段は python を使わず、bash の文字列照合で行う。
- `permissionDecisionReason` は短い固定文にし、SKILL.md の手順（ラウンド数など）は書かない。例: 「autonomous-review を実行します。リポジトリのコードと差分を外部の Codex に送り、指摘に応じてコードを修正し、品質ゲートを実行します。時間がかかります。断った場合、このブランチでは再提案しないでください。」
- 記録: `ask` / `deny` / fail-closed の `ask` を返した回数を `~/.claude/aidd/skill-gate.json` に数える。件数と最終日時だけを残し、プロンプトや差分は書かない（`usage-log.sh` と同じ方針）。承認されて実行された回数は、消費側の `.aidd/autonomous-review/*/state.json` の数で分かるので、新しく記録しない。
- `usage-log.sh` は変えない。同じ PreToolUse で数えるため、ユーザーが拒否した起動も `usage.json` に入る。これは許容し、`usage.json` は「起動の試み」の回数として読む。拒否が多いかは `skill-gate.json` の件数と state.json の数の差で見る。

### 規約・索引

- `.claude/CLAUDE.md` を3か所直す。
  - 「Adding a user-invoked skill」: autonomous-review だけは例外で、`disable-model-invocation` を持たず、`skill-gate.sh` で許可を取る、と書く。一般則にはしない（例が1つだけのため、2回ルール）。
  - Architecture 節のユーザー起動 skill の説明: autonomous-review を例外として注記する。
  - hooks の説明: 「8 entries across 5 events to 5 scripts」を「6 scripts」に直し、`skill-gate.sh` の1項目を足す（エントリ数は既存の `^Skill$` エントリに足すので 8 のまま）。
- `python3 scripts/generate-asset-index.py` を同じコミットで実行する（description と hook が変わるため）。`skill-gate.sh` の shebang 直後の1行目のコメントを、索引に載る説明として書く。
- `shellcheck` の対象に `skill-gate.sh` が入ることを確かめる（CI は `hooks/scripts/*.sh`）。
- README の索引、CHANGELOG、3つの plugin.json の version を更新する。

### テスト

- `tests/hook-contract-test.sh` に足す。
  - `aidd:autonomous-review`、`autonomous-review`、`/aidd:autonomous-review` で `ask` を返す
  - 他の aidd skill（例: `aidd:design-review`）では何も出さない
  - 壊れた JSON に `autonomous-review` を含むとき `ask` を返す。含まないとき何も出さない
  - python を PATH から外して、対象のとき `ask` を返す
  - 確認が届かない実行環境の入力（実測で決めた判別用の値）で `deny` を返す
  - `hooks.json` の `^Skill$` エントリに `usage-log.sh` と `skill-gate.sh` の両方がある
- `tests/autonomous-review-contract-test.sh` は、`disable-model-invocation` が無いことと、description に「auto-merge eligibility」が含まれることを確かめる。

## 実装前に実測すること

ドキュメントで確かめられなかった前提。結果はこの文書の末尾に「実測結果」の節を作り、日付・Claude Code の版と一緒に書く。

1. ユーザーが `/aidd:autonomous-review` と打ったときに PreToolUse(Skill) が発火するか。発火するなら、手で打ったときも確認が出る。これは安全側なので許容し、二重の確認として記録する。
2. Skill ツールへの PreToolUse hook が `ask` を返すと、skill の本文が読み込まれる前にユーザーへの確認が出ること。拒否すると skill が実行されないこと。**成り立たなければ設計を取り下げる。**
3. auto mode で `ask` がどう扱われるか。ユーザーに確認が出るなら対話扱い。分類器が判定するなら、hook 入力の `permission_mode` などで auto mode を判別して `deny` にする。
4. サブエージェントの中から Skill ツールで起動したときに、確認が親のユーザーに届くこと。届かないなら、サブエージェント内の起動を判別して `deny` にする。判別できなければ設計を取り下げる。
5. headless（`claude -p`）、`bypassPermissions`、ユーザー設定の allow ルール（例: `Skill(aidd:*)`）があるときに、hook の `ask` がどう扱われるか。確認が出ずに通る環境を hook 入力から判別できるか。判別できる環境は `deny` にする。判別できず、確認なしで通る環境が残るなら、それを既知の限界として README に書くか、設計を取り下げるかを決め直す。
6. Skill ツールが `tool_input.skill` にどの形の名前を入れるか（`aidd:` の有無）。照合の正規化がそれを含むことを確かめる。
7. Cursor が SKILL.md の `disable-model-invocation` を解釈するか。解釈しないなら、今の挙動のまま（変更の影響なし）。解釈するなら、`hooks-cursor.json` と `harness-adapter.sh` で Cursor の skill 起動に同じ gate を掛けられるかを確かめ、掛けられなければ設計を取り下げる。

## ロールバック

`disable-model-invocation: true` を frontmatter に戻し、`skill-gate.sh` を hooks.json から外して、version を上げる。両方が同じ version で配られるので、片方だけ古い状態は生まれない。Codex は frontmatter のフラグに依存しない（`openai.yaml` で止まる）ため、Codex の `/hooks` の信頼し直しはこの変更では起きない。

## 既知の限界

- モデルが `.aidd/autonomous-review/` に証跡を自分で書けば、`tool-reminder.sh` の警告は消える。gate はこれを防げない。警告は注意喚起であり、強制ではない。
- 拒否後の再提案は、許可の文面で抑えるだけで強制されない。
- hook が起動できないとき（実行ファイルが見つからない、plugin のデータディレクトリを作れない など）、Claude Code はエラーを記録したうえで Skill を実行する（実測結果 R1）。スクリプト内の fail-closed はこの経路を防げない。

## 未決

- `ask` を無効にして自動で起動したい利用者向けの opt-out（`AIDD_*` 環境変数）は、要望が出るまで足さない。
- Codex でモデルから起動できるようにするかは、許可を取る仕組みが見つかってから改めて決める。

## 実測結果

使い捨て plugin（PreToolUse / PostToolUse `^Skill$` と UserPromptSubmit で入力を記録し、対象 skill に `ask` を返す hook）を `claude --plugin-dir` で読み込んで測った。

### 2026-11-17 / Claude Code 2.1.326

- **R1（hook が起動できない場合）**: sandbox 内で実行し、plugin のデータディレクトリ（`~/.claude/plugins/data/<plugin>-inline`）を作れずに hook が `EPERM` で起動失敗した。debug ログに `Hook failed to run (PreToolUse:Skill)` が出たうえで Skill は実行され、本文が読み込まれた。hook の起動失敗は fail-open になる。
- **R2（項目5のうち headless・項目2の一部）**: `claude -p`（hook 入力の `permission_mode` は `auto`）で、モデルが Skill ツールで対象 skill を呼んだ。PreToolUse hook が `ask` を返すと、確認は出ず、Skill ツールは `permissionDecisionReason` の文をエラーとして返した。skill の本文は読み込まれず、PostToolUse は発火しなかった。headless では `ask` が拒否として働く。
- **R3（項目6の一部）**: モデルに `gateprobe:probe-review` と名前を指定して呼ばせた場合、`tool_input.skill` は `gateprobe:probe-review`（plugin 名つき）だった。接頭辞なしの名前を受け付けるかはまだ測っていない。

未実測: 項目1、2（対話セッション）、3（対話の auto mode）、4、5（bypassPermissions・allow ルール）、6（接頭辞なし）、7。`bypassPermissions` での nested session の起動は、このセッションの auto mode の分類器に拒否されたため、ユーザーが手で測る。
