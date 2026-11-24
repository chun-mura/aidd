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
- Claude Code では実行環境で分岐しない。`ask` は対話の default・auto・bypassPermissions・allow ルール・サブエージェントのどれでもユーザーに届き、headless（`-p`）では auto・bypassPermissions・`--dangerously-skip-permissions` のどれでも拒否として働く（実測 R2・R5〜R8・R13）。aidd-autopilot のような無人実行で、Issue 本文に誘導されて起動することはない。
- Codex は対象外とし、今の挙動（ユーザー起動のみ）を残す。Codex の暗黙起動は Skill ツールを通らず、gate を掛けられないため。`openai.yaml` の `allow_implicit_invocation: false` で止まる。
- Cursor では、モデルの起動を `deny` で止め、手で打つよう案内する。SKILL.md の frontmatter は Cursor と共有で、Cursor はこのフラグを解釈するため、外すとモデルから起動できるようになる（R10）。Cursor の `preToolUse` は `ask` を無視するが `deny` は効き、モデルの skill 読み込みは SKILL.md の `Read` として届く。ユーザーが手で打った起動は `Read` を通らない（R11・R12）。手で打つこと自体を、ユーザーの許可とみなす。

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
- 判定の順序:
  1. 判定は python で行う。stdin の JSON から `tool_name` と `tool_input` を読む。
  2. `tool_name` が `Skill` のとき、`tool_input.skill` を正規化して照合する。前後の空白と先頭の `/` を除き、小文字にして、`:` で区切った最後の要素が `autonomous-review` なら対象とする（`aidd:autonomous-review`、`autonomous-review`、`/aidd:autonomous-review`、`AIDD:Autonomous-Review` を同じに扱う）。`skill` が文字列でなければ、解釈できない入力として 4 に回す。
  3. `tool_name` が `Read` のときは、下の Cursor の節の判定を使う。
  4. fail-closed: python が無い、JSON を解釈できない、`tool_input` が無い、`skill` が文字列でない、python が例外で止まったときは、生の入力に `autonomous-review` が大文字小文字を区別せずに含まれていれば `ask` を返す。含まれなければ何も出さない。この照合は bash（`grep -qi`）で行う。正常な入力に対する前段の絞り込みには使わない（大文字・エスケープ違いのすり抜けを防ぐため）。
- 対象でなければ何も出さずに exit 0 とする。他の skill を巻き込まない。
- 対象なら `permissionDecision: "ask"` を返す。
- **出力を先に、記録は後に**: 判定の JSON を stdout に書き終えてから記録する。記録は best-effort とし、`~/.claude/aidd` に書けない、`skill-gate.json` が壊れている、同時に書かれたなどの失敗は黙って捨て、終了コードと出力に影響させない。スクリプトは常に exit 0 で終える。記録の書き方は `usage-log.sh` に合わせる（flock、一時ファイルからの `os.replace`、umask 077、壊れた JSON は作り直す）。`AIDD_DISABLE_USAGE_LOG=1` なら記録しない（判定は変えない）。
- `permissionDecisionReason` は短い固定文にし、SKILL.md の手順（ラウンド数など）は書かない。ユーザーへの確認として読める文にし、実行を宣言しない（headless では拒否の理由としてモデルに返るため。R2）。例: 「autonomous-review の実行にはユーザーの許可が必要です。許可すると、リポジトリのコードと差分を外部の Codex に送り、指摘に応じてコードを修正し、品質ゲートを実行します。時間がかかります。」再提案を控える指示はここに書かない（ユーザーにも表示されるため）。`tool-reminder.sh` の警告文の側に書く（下の節）。
- 記録: `~/.claude/aidd/skill-gate.json` に、返した判定の種類ごとの件数と最終日時を残す。キーは `ask`（Skill への通常の判定）、`ask_failclosed`（4 の経路）、`deny_cursor_read`（Cursor の Read）。プロンプト・差分・パスは書かない。承認されたか拒否されたかは hook からは分からないので数えない。これは「確認を出した回数」と「Cursor で止めた回数」の記録であり、拒否率の算出には使わない。
- `usage-log.sh` は変えない。同じ PreToolUse で数えるため、ユーザーが拒否した起動も `usage.json` に入る。これは許容し、`usage.json` は「起動の試み」の回数として読む。

### `hooks/scripts/tool-reminder.sh` の警告文

- `gh pr create` 前の証跡なしの警告に1文足す: 「ユーザーが autonomous-review の実行を断った場合は、このブランチでは再び起動せず、PR 本文に未実施と書くこと。」拒否しても証跡は残らないので、足さないと `gh pr create` のたびに警告 → 起動 → 確認が繰り返される。強制はできない（既知の限界）。
- 判定条件は変えない。

### Cursor: `hooks/hooks-cursor.json` と `harness-adapter.sh`

- `hooks-cursor.json` の `preToolUse` の末尾に、matcher `Read` で `harness-adapter.sh skill-gate.sh` を足す。
- `harness-adapter.sh` の入力変換は変えない。Cursor の `Read` は既に `tool_name: "Read"`・`tool_input.file_path` で届き（R11）、`normalize()` がそのまま通す。出力の `deny` は既存の変換（`permission: deny`）で Cursor に返る。
- `harness-adapter.sh` の先頭（`input=$(cat)` の直後、python の確認より前）に事前の絞り込みを1つ足す: 呼ぶスクリプトが `skill-gate.sh` で、入力に `autonomous-review` が大文字小文字を区別せずに含まれなければ、何も出さずに exit 0。Cursor ではすべての Read がこの hook を通るので、無関係な Read のたびに python を起動しないため（`tool-reminder.sh` が git/gh を含まないコマンドで python を起動しないのと同じ考え方）。対象のパスは必ずこの文字列を含むので、絞り込みで gate が外れることはない。
  - 改訂（#120）: この前提は誤りだった。別名リンク（`alias.md`）・JSON エスケープ（`\u` 表記）の Read はこの文字列を含まず、gate を素通りした。絞り込みは、`file_path` が無いとき、または絶対パスで、存在し（`[ -e ]`）、`..` を含まず、bash の `-ef` で対象と別ファイルだと分かったときだけ抜ける判定に改めた。それ以外（存在しないパス、`..` を含むパス、相対パスまたは `~`、名前を含む、バックスラッシュを含む、`file_path` が複数）はすべて python と gate に回す。条件を1つずつ足すと末尾の `/.` や `//` のような同種の漏れが続いたため、抜ける側を絞った。gate は相対パスを入力の `cwd` から、`~` をホームから解決する。
- `skill-gate.sh` は `tool_name` が `Read` のとき、`file_path` を実パスに解決し、**この plugin のルート**（スクリプト自身の位置から求める。`usage-log.sh` の `PLUGIN_ROOT` と同じ方法）の `skills/autonomous-review/SKILL.md` と一致すれば `deny` を返す。理由は「autonomous-review はモデルからは起動できません。ユーザーに `/autonomous-review` を手で実行するよう依頼してください。」（Cursor ではこの文が `user_message` と `agent_message` の両方に入る）。plugin ルートの外にある同名のファイル（aidd リポジトリ自体を Cursor で開いて編集するときなど）は止めない。`file_path` が無い・文字列でない・実パスに解決できないときは、生のパスに `skills/autonomous-review/SKILL.md` が含まれ、かつ plugin ルートの文字列で始まる場合だけ `deny` にし、それ以外は何も出さない（すべての Read を巻き込まないため）。
  - 改訂（#120）: 実装は上の文字列の比較ではなく、ファイルの同一性で判定する。`file://` で始まる値を、Cursor の Read（Node の `fileURLToPath`）が開くパスに寄せて変換し（タブ・改行と末尾の制御文字・空白を除き、`\` を `/` とみなし、ホスト・クエリ・フラグメントを無視してパーセントデコードする。ホストを無視するので、Cursor が開かない別ホストの URI も止める側に倒れる）、変換が失敗すると Cursor は元の文字列をパスとして開くので、元の文字列も候補に残す。各候補について `~` をホームに、相対パスを入力の `cwd` から解決したうえで、そのパスと、文字の上で正規化したパス（`os.path.normpath`）の両方を `os.path.samefile` で対象と比べ、どちらかが一致すれば `deny` にする。存在しないディレクトリの後の `..` や PATH_MAX を超えるパスのように OS では解決できないが、正規化すると対象を指すパスも止めるため。どちらでも解決できない・パスとして不正（NUL を含む）なときは何も出さない。
    - 変換前の文字列を Cursor が解決する基点は確かめられていない（GUI から起動した macOS アプリの cwd は通常 `/`）。そのため変換前の候補は、`os.path.normpath` した相対パスから先頭の `..` を外した残りを、`/` と入力の `cwd` のすべての祖先（`cwd` 自身を含む）に繋ぎ、どれかで対象と一致すれば `deny` にする。基点に依存しない代わりに、止める側に倒れる範囲は SKILL.md を名指しする URI に限られる。
    - 既知の限界: 文字の上の正規化は symlink をたどらないので、plugin の中の symlink の後ろに `..` があるパスは、実際には別のファイルを指していても `deny` になりうる（止める側に倒れる誤り）。
- Claude Code では `Read` を gate に配線しない（skill は Skill ツールで起動するため）。
- `harness-adapter.sh` は失敗時に exit 0 で終わる（Cursor は hook の非0終了で全ツールを止めるため。既存の方針）。adapter が失敗する（python3 が無い、入力が JSON でない など）と Cursor の gate は fail-open になる。失敗は `adapter-skips.json` に理由別に数えられ、`/aidd:doctor` で見られる。
- Cursor に skill が届く経路と gate の効き方:
  - plugin として入れた aidd の skill（`.cursor-plugin` の `"skills": "./skills/"`）: gate が効く。
  - 利用者が SKILL.md を `.cursor/skills/` などにコピーしたもの: plugin ルートの外なので gate は効かない。コピーはこの plugin の配布経路ではなく、受容する（既知の限界）。
  - 別 version の plugin キャッシュ: そのキャッシュの hook は、そのキャッシュのルートを基準に判定するので、同じ version の skill と hook が組で働く。

### 規約・索引

- `.claude/CLAUDE.md` を3か所直す。
  - 「Adding a user-invoked skill」: autonomous-review だけは例外で、`disable-model-invocation` を持たず、`skill-gate.sh` で許可を取る、と書く。一般則にはしない（例が1つだけのため、2回ルール）。
  - Architecture 節のユーザー起動 skill の説明: autonomous-review を例外として注記する。
  - hooks の説明: 「8 entries across 5 events to 5 scripts」を「6 scripts」に直し、`skill-gate.sh` の1項目を足す（エントリ数は既存の `^Skill$` エントリに足すので 8 のまま）。
- `python3 scripts/generate-asset-index.py` を同じコミットで実行する（description と hook が変わるため）。`skill-gate.sh` の shebang 直後の1行目のコメントを、索引に載る説明として書く。
- `shellcheck` の対象に `skill-gate.sh` が入ることを確かめる（CI は `hooks/scripts/*.sh`）。
- README の索引、CHANGELOG、3つの plugin.json の version を更新する。README と CHANGELOG には、Codex で `/hooks` の信頼し直しが要ることと、hook が無効な環境では gate が働かないことを書く。

### テスト

- `tests/hook-contract-test.sh` に足す。
  - `aidd:autonomous-review`、`autonomous-review`、`/aidd:autonomous-review`、`AIDD:Autonomous-Review` で `ask` を返す
  - 他の aidd skill（例: `aidd:design-review`）では何も出さない
  - 壊れた JSON に `autonomous-review`（大文字を含む形も）を含むとき `ask` を返す。含まないとき何も出さない
  - `skill` が文字列でない入力で、生の入力に名前を含むとき `ask` を返す
  - python を PATH から外して、対象のとき `ask` を返す
  - `AIDD_TEST_STATE_DIR` を書き込めないパスにしても、対象なら `ask` を返し、exit 0 で終わる
  - `tool_name: "Read"` で、plugin ルートの `skills/autonomous-review/SKILL.md` なら `deny`、plugin ルートの外にある同名ファイルなら何も出さない
  - Cursor 形式の `preToolUse`（`Read`）を `harness-adapter.sh skill-gate.sh` に通すと `permission: deny` が返る。無関係なファイルの Read では何も出さない
  - `hooks.json` の `^Skill$` エントリに `usage-log.sh` と `skill-gate.sh` の両方がある
- `tests/hook-contract-test.sh` の既存の検査を直す: Cursor の `preToolUse` の matcher 列の完全一致（958行付近、`["Shell", "Write"]`）を `["Shell", "Write", "Read"]` にし、3つ目のコマンドが `harness-adapter.sh skill-gate.sh` であることを足す。
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
8. `claude -p` と `--permission-mode bypassPermissions`（`--dangerously-skip-permissions` も）を組み合わせたときに、hook の `ask` がどう扱われるか。拒否として働くなら方針どおり。確認なしで通るなら、hook 入力の `permission_mode` が `bypassPermissions` で、かつ対話でないと判別できるかを調べ、判別できればその場合を `deny` にする。判別できなければ既知の限界として README に書くか、設計を取り下げるかを決め直す。

## ロールバック

`disable-model-invocation: true` を frontmatter に戻し、`skill-gate.sh` を `hooks.json` と `hooks-cursor.json` から外して、version を上げる。両方が同じ version で配られるので、片方だけ古い状態は生まれない。

Codex の信頼し直し: この変更は `hooks.json` の既存の `^Skill$` エントリの中身を変える。README の導入節のとおり、Codex ではエントリが変わったリリースで `/hooks` から信頼し直す必要がある（信頼しないとそのエントリの hook が黙って動かない）。Codex の動作（`openai.yaml` で暗黙起動を止める）には影響しないが、`usage-log.sh` の記録が止まる。README と CHANGELOG にこのリリースで信頼し直しが要ることを書く。ロールバックでも同じ。

ロールバックを考える目安（リリース後、利用者の報告と `skill-gate.json` で見る）:
- 通常のコード PR でも確認が毎回出る（`ask` の件数が PR の数に近い）。description の絞り込みが効いていない。
- 手で打った起動に確認が出る、または止まる（R4・R12 と違う挙動）。
- Cursor で、無関係な Read が止まる、または遅くなる。

## 既知の限界

- モデルが `.aidd/autonomous-review/` に証跡を自分で書けば、`tool-reminder.sh` の警告は消える。gate はこれを防げない。警告は注意喚起であり、強制ではない。
- 拒否後の再提案は、`tool-reminder.sh` の警告文で抑えるだけで強制されない。
- hook が起動できないとき（実行ファイルが見つからない、plugin のデータディレクトリを作れない など）、Claude Code はエラーを記録したうえで Skill を実行する（実測結果 R1）。スクリプト内の fail-closed はこの経路を防げない。debug ログの `Hook failed to run` にだけ残る。
- Cursor では `harness-adapter.sh` が失敗すると exit 0 で終わり、gate は fail-open になる（`adapter-skips.json` に残る）。
- **hook が無効な環境では gate は働かない**（`disableAllHooks`、組織のポリシーで plugin の hook を止めている、Cursor で hook を信頼していない など）。`disable-model-invocation` を外すので、そうした環境ではモデルが確認なしで起動できる。hook を無効にするのは利用者の意図した設定で、その場合は aidd の他の gate もすべて止まる。これは受容し、README に書く。
- モデルが SKILL.md を Skill ツール以外の手段で読み、その指示に従う経路は防げない（Claude Code の Read、Cursor の Shell（`cat`）やワークスペース内のコピー、plugin ルート外のコピー など）。今の `disable-model-invocation: true` でも同じで、この変更で生まれる経路ではない。

## 未決

- `ask` を無効にして自動で起動したい利用者向けの opt-out（`AIDD_*` 環境変数）は、要望が出るまで足さない。
- Codex でモデルから起動できるようにするかは、許可を取る仕組みが見つかってから改めて決める。

## 実測結果

使い捨て plugin（PreToolUse / PostToolUse `^Skill$` と UserPromptSubmit で入力を記録し、対象 skill に `ask` を返す hook）を `claude --plugin-dir` で読み込んで測った。

### 2026-11-17 / Claude Code 2.1.326

- **R1（hook が起動できない場合）**: sandbox 内で実行し、plugin のデータディレクトリ（`~/.claude/plugins/data/<plugin>-inline`）を作れずに hook が `EPERM` で起動失敗した。debug ログに `Hook failed to run (PreToolUse:Skill)` が出たうえで Skill は実行され、本文が読み込まれた。hook の起動失敗は fail-open になる。
- **R2（項目5のうち headless・項目2の一部）**: `claude -p`（hook 入力の `permission_mode` は `auto`）で、モデルが Skill ツールで対象 skill を呼んだ。PreToolUse hook が `ask` を返すと、確認は出ず、Skill ツールは `permissionDecisionReason` の文をエラーとして返した。skill の本文は読み込まれず、PostToolUse は発火しなかった。headless では `ask` が拒否として働く。
- **R3（項目6の一部）**: モデルに `gateprobe:probe-review` と名前を指定して呼ばせた場合、`tool_input.skill` は `gateprobe:probe-review`（plugin 名つき）だった。接頭辞なしの名前を受け付けるかはまだ測っていない。

以下は対話セッション（`claude --plugin-dir`）で、ユーザーが操作して測った。

- **R4（項目1）**: ユーザーが `/gateprobe:probe-review` と打つと、記録は UserPromptSubmit だけで、PreToolUse(Skill) は発火しなかった。手で打ったときに gate の確認は出ない（二重確認なし）。
- **R5（項目2）**: default モードでモデルが起動すると、本文の読み込み前に確認が出た。拒否すると PostToolUse は発火せず、skill は実行されなかった。
- **R6（項目3）**: 対話の auto mode（`permission_mode: auto`）でも確認はユーザーに出た。分類器による自動許可は起きなかった。許可すると PostToolUse が発火した。
- **R7（項目4）**: サブエージェントが Skill ツールで起動すると、hook 入力に `agent_id` が入り、確認は親のユーザーに届いた。許可すると実行された。
- **R8（項目5）**: `--permission-mode bypassPermissions` でも、`--allowedTools "Skill(gateprobe:probe-review)"` でも確認が出た。どちらも拒否すると skill は実行されなかった。hook の `ask` は bypass と allow ルールより優先される。
- **R9（項目6）**: 接頭辞なしで呼ばせると、`tool_input.skill` は `probe-review` だった（hook は判定の前に受け取る）。完全一致の照合ならすり抜けていた。拒否したので、Skill ツールがその名前を解決できるかは測っていない。正規化した照合は残す。
- **R10（項目7、Cursor）**: `.cursor/skills/` に、フラグなしの `probe-on` と `disable-model-invocation: true` の `probe-off` を置いた。Agent に使える skill の一覧を聞くと `probe-on` だけが出た。**Cursor はこのフラグを解釈する。**「run the probe off」と頼むと、モデルは `probe-on` の SKILL.md を読んだあと、ワークスペースを検索して `probe-off` の SKILL.md を直接読み、その指示に従った。これは skill としての起動ではなく、ファイルの読み取りである。Cursor の skill の読み込みも UI 上は「Explored SKILL.md」と表示された。

- **R13（項目8）**: `claude -p --permission-mode bypassPermissions` と `claude -p --dangerously-skip-permissions` のそれぞれで、モデルに Skill ツールで対象 skill を呼ばせた（ユーザーが実行）。hook 入力の `permission_mode` はどちらも `bypassPermissions`。hook が `ask` を返すと、Skill ツールは理由の文をエラーとして返し、本文は読み込まれず、PostToolUse は発火しなかった。headless では bypass でも `ask` は拒否として働く。

### 実測から分かったこと

- 項目1〜6の前提は成り立った。Claude Code では、対話・auto・bypass・allow ルール・サブエージェントのどれでも `ask` がユーザーに届き、headless では拒否として働く。確認が届かない環境を見分けて `deny` にする分岐（方針の4つ目）は不要になる。
- 項目7は成り立たなかった。フラグを外すと Cursor ではモデルが起動できる。ただし R11・R12 により、Cursor でもモデルの起動だけを `deny` で止められる。Cursor は `ask` を使えないので、手で打つ案内に縮退する（方針の Cursor の項）。
- 2回目の design-review で、項目5の `-p` と bypassPermissions の組み合わせが測られていないと分かり、項目8として測った（R13）。拒否として働くので、分岐は要らない。
- 以上で、実装前に測る項目は残っていない。

### 2026-11-17 / Cursor（実測用 `.cursor/hooks.json` で preToolUse・beforeReadFile・beforeSubmitPrompt を記録）

- **R11（Cursor の `ask`）**: モデルが `probe-on` を起動すると、`preToolUse` に `tool_name: "Read"`・`tool_input.file_path` が SKILL.md の入力が届いた。hook が `{"permission":"ask", ...}` を返しても確認は出ず、本文は読み込まれて実行された。Cursor の `preToolUse` は `ask` を無視する。
- **R12（Cursor の `deny` と手入力）**: 同じ条件で `{"permission":"deny", ...}` を返すと、モデルは本文を読めずに止まり、拒否されたことをユーザーに伝えた。ユーザーが `/probe-on` と打つと、記録は `beforeSubmitPrompt` だけで `Read` を通らず、skill は実行された。
- モデルは SKILL.md をファイルとして直接読み、その指示に従うことができる（R10）。これは今の `disable-model-invocation: true` でも同じで、この変更で新しく生まれる経路ではない。gate はこの経路を防げない。
