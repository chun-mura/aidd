# aidd hooks のマルチハーネス対応（入力を揃える層）設計

## 目的

aidd の強制力は hooks にしかない（`tool-reminder.sh` の git/gh の deny、`write-guard.sh` の新規ファイルの deny）。
Codex と Cursor でも、この判定を効かせる。skills と commands の移植は別の設計で扱い、ここでは hooks だけを対象にする。

判定ロジック（`hooks/scripts/*.sh`）は書き換えない。入力が Claude Code と違う経路にだけ、入力を Claude Code の形に揃え、出力を各ハーネスの形に戻す層（adapter）を置く。

### 対象範囲

| | git/gh の判定（`tool-reminder.sh`） | 新規ファイルの判定（`write-guard.sh`） |
|---|---|---|
| Claude Code | 今のまま | 今のまま |
| Codex | 今のまま効く（再生で確認） | adapter で `apply_patch` に対応する |
| Cursor | adapter で対応する | adapter で Write に対応する。Edit は未配線（入力未取得） |

## 実測の条件

2026-10-27 に、入力を保存して何も返さない記録用プラグイン（hookprobe）を各ハーネスに入れ、同じ手順を流した。
手順は、`git status` → 新規ファイル作成 → 編集 → `git add -A` → 失敗するコマンド（`git log -1 no-such-ref`）。

| ハーネス | 版 | 読み込ませ方 |
|---|---|---|
| Codex CLI | 0.163.0 | `codex plugin marketplace add` → `codex plugin add` → `/hooks` で信頼 → `codex exec --sandbox workspace-write` |
| Cursor agent CLI | 2026.10.22-27dcf5f | `cursor-agent -p --trust --plugin-dir <hookprobe>`（`--force` なし。シェルは承認待ちで拒否された） |

記録は匿名化して `tests/fixtures/hooks/{codex,cursor}/` に置いた。以下、根拠は fixture のファイル名で示す。

## aidd が入力から読む項目と、各ハーネスの実測値

| 項目（Claude Code） | Codex | Cursor |
|---|---|---|
| `hook_event_name` | `PreToolUse` など同じ表記（`codex/PreToolUse.bash-git-add-all.json`） | **`preToolUse` など camelCase**（`cursor/preToolUse.shell-git-add-all.json`） |
| `tool_name`（matcher の対象） | シェルは `Bash`。**ファイル作成・編集は `apply_patch`**（`codex/PreToolUse.apply_patch-add.json`） | シェルは **`Shell`**。編集はまず **`Read`** として届いた（`cursor/preToolUse.read-before-edit.json`） |
| `tool_input.command` | 同じ。`apply_patch` ではパッチ本文が入る | 同じ。`beforeShellExecution` だけはトップレベルの `command` |
| `tool_input.file_path` | **無い**。パスはパッチ本文の `*** Add File: <絶対パス>` 行にある | Read と Write では有る（`cursor/preToolUse.write.json`）。Edit の preToolUse は未取得 |
| `cwd` | セッションの作業ディレクトリ | **空文字**。作業ディレクトリは `workspace_roots[0]` と `CURSOR_PROJECT_DIR` にある |
| hook プロセスのカレントディレクトリ | 作業ディレクトリ（`codex/_process.json`） | **プラグインのディレクトリ**（`cursor/_process.json`） |
| `CLAUDE_PROJECT_DIR` | 設定されない | 全イベントで作業ディレクトリ（`cursor/_process.json`） |
| `session_id` | 有る | 有る（`conversation_id` と同じ値） |
| `prompt`（UserPromptSubmit） | 有る（`codex/UserPromptSubmit.json`） | `beforeSubmitPrompt` は未取得 |
| 失敗したコマンド | **`PostToolUse` として届く**。`tool_response` は出力の文字列だけで、終了コードは無い（`codex/PostToolUse.bash-failed.json`） | `postToolUseFailure` は有る（`cursor/postToolUseFailure.read-denied.json`） |
| プラグインのルート | `PLUGIN_ROOT` と `CLAUDE_PLUGIN_ROOT`（同じ値） | `CURSOR_PLUGIN_ROOT` と `CLAUDE_PLUGIN_ROOT`。**sessionStart 以外では、別のプラグインのディレクトリを指していた**（`cursor/_process.json` の `env_by_event`） |
| 余分な項目 | `turn_id`, `permission_mode`, `model` | `cursor_version`, `workspace_roots`, `user_email`, `generation_id` |

### 再生で確かめたこと

記録した入力を、今の `tool-reminder.sh` と `write-guard.sh` にそのまま流した。

| 入力 | 結果 |
|---|---|
| Codex の `git add -A` | deny が返る。**揃えなくても効く** |
| Cursor の `git add -A`（そのまま） | **出力なしで素通り**。`hook_event_name` が `preToolUse` なので、`== "PreToolUse"` の分岐に入らない |
| 同じ入力で `hook_event_name` だけ `PreToolUse` に直したもの | deny が返る |
| Codex の `apply_patch` で `.env.local` を新規作成（パスだけ差し替え） | **素通り**。`tool_input.file_path` が無い。さらに matcher `Write\|Edit\|NotebookEdit` に当たらないので、実際には起動もされない |
| 同じ内容を Claude 形式の `Write` で渡したもの | deny が返る |

### Cursor は Claude Code の hooks を Cursor の形のまま実行する

- `~/.claude/settings.json` の hooks が、Cursor のセッションでも実行された。matcher は読み替えられる（Claude の `Bash` が Cursor の `Shell` に、`Read` が `Read` に当たった）。
- 入力は Cursor の形のまま渡る。Read を見張るユーザーの hook が ValueError を起こして**非0で終了すると、Read が拒否された**。その後、エージェントは grep ツールで同じファイルを読んで処理を続けた。
- `updatedInput` は反映される。rtk の書き換えで、preToolUse より後のイベントでは `rtk git add -A` になっていた。
- `CURSOR_PLUGIN_ROOT` が、Claude Code に入っている別のプラグインを指していた。このことから、**Cursor は Claude Code に入れたプラグインの hooks も読んでいる**と推測する。aidd の hooks.json が実行されたかどうかは直接は確かめていない（未確認 1）。

### deny と信頼の実測

同じ日に、印の付いたコマンド（`AIDD_DENY_PROBE` を含むもの）と、`deny-probe` を含むパッチだけを deny する hook（denyprobe）で確かめた。

| 確かめたこと | 結果 |
|---|---|
| Codex：`hookSpecificOutput.permissionDecision: deny`（Bash） | **止まった**。印の無い `echo hello` は実行された |
| Codex：同じ出力（`apply_patch` で `deny-probe.txt` を新規作成） | **止まった**。ファイルは作られなかった。このときパッチの `Add File:` は**相対パス**（`deny-probe.txt`）だった |
| Cursor：`{"permission":"deny","user_message":…,"agent_message":…}`（Shell、`--plugin-dir` で読み込み） | **止まった**。拒否の理由に hook の文言が入っていた。印の無いコマンドは承認待ちで拒否され、理由は空だった |
| Codex：スクリプト本体だけを変えて再導入 | `trusted_hash` は変わらず、**再信頼なしで新しい本体が実行された** |
| Codex：hooks.json のコマンド文字列を変えて再導入 | **未信頼になり、何も表示されずに実行されなかった**。印付きのコマンドがそのまま実行された |

## 方式

### 1. adapter は変換が要る経路にだけ置く

Claude Code と Codex の Bash の経路は、今の hooks.json の直接呼び出しのまま変えない。adapter を通すのは次の2つだけにする。

- Codex の `apply_patch`（hooks.json に1エントリ追加）
- Cursor の全経路（`hooks/hooks-cursor.json`）

全エントリを adapter 経由にしない理由：
- 今動いている判定を、新しい層の不具合（実行権限の喪失、typo）で黙って失う経路を作らないため
- `tool-reminder.sh` 冒頭の bash による事前判定（git/gh を含まないコマンドで python を起動しない）の節約を、Claude Code と Codex で保つため
- Codex は、hooks.json のエントリが変わると未信頼にして、何も表示せずに実行しない（「deny と信頼の実測」）。信頼キーはエントリの位置を含む（`<plugin>:hooks/hooks.json:<event>:<i>:<j>`）。既存エントリを書き換えず末尾に足すだけにすれば、既存の判定は信頼が切れずに動き続け、信頼し直しが要るのは新しいエントリだけになる

### 2. adapter の契約

`hooks/scripts/harness-adapter <script>`：入力を揃えて `<script>` を呼び、その出力をハーネスの形に戻す。呼ぶスクリプトの選択は呼び出し側（各ハーネスの matcher）が持ち、adapter は振り分けない。

**入力の判定**
- stdin を JSON として解析し、**トップレベルのキーだけ**を見る（`tool_input` の中の文字列はモデル由来なので見ない）
- Cursor と判定する条件：`cursor_version` がある、または `hook_event_name` が小文字で始まる
- それ以外は Claude Code / Codex として扱う（入力が互換なので区別しない）
- 環境変数では判定しない。Cursor は `CLAUDE_PLUGIN_ROOT` と `CLAUDE_PROJECT_DIR` も設定し、Claude 用に登録した hook にも Cursor の入力を渡すため

**正規化**
- イベント名：`preToolUse`→`PreToolUse`、`postToolUse`→`PostToolUse`、`postToolUseFailure`→`PostToolUseFailure`、`sessionStart`→`SessionStart`
- ツール名：`Shell`→`Bash`
- `cwd`：入力の `cwd` が空でなければそれを使う。空なら `CURSOR_PROJECT_DIR` → `workspace_roots[0]` の順に埋める（どちらも実測で全イベントとも作業ディレクトリを指していた。信用しないのは `*_PLUGIN_ROOT` だけ）。**すべて空なら `<script>` を呼ばずに終わる**（hook プロセスのカレントディレクトリは Cursor ではプラグインのディレクトリなので、そこで判定させない）
- `CLAUDE_PLUGIN_ROOT`：adapter 自身の位置（`$0` から2階層上）で上書きして export してから `<script>` を呼ぶ。`write-guard.sh` はこの変数を優先して `hooks/asset-index.json` を読むため（`write-guard.sh:9`）
- `user_email`・`generation_id`・`cursor_version`・`workspace_roots` は落とす
- `apply_patch`：パッチ本文から、**行頭の** `*** Add File: <path>` と `*** Move to: <path>` を取り出す。それぞれを `{"tool_name":"Write","tool_input":{"file_path":<path>}}` の1件として `<script>` を呼ぶ（Move to は移動先に新しいファイルを作るため）。`Update File` と `Delete File` は新しいファイルを作らないので呼ばない。相対パスは `cwd` を基準に解決する。パッチを解析できなければ `<script>` を呼ばずに終わる

**`<script>` を複数回呼んだときの集約**
- deny が1件でもあれば deny とし、理由は改行でつなぐ。同じ結果に `additionalContext` があれば残す
- `additionalContext` は重複を除いてつなぐ
- 出力は常に JSON 1つにする（Claude Code は1回の hook につき返信を1つ読む。`tool-reminder.sh:3-4`）

**出力の変換**

stdout を JSON オブジェクトとして解析できればそれを、できなければプレーンテキストとして扱う。

| `<script>` の出力 | Claude Code / Codex へ | Cursor へ |
|---|---|---|
| `permissionDecision: deny` と理由 | そのまま（`additionalContext` があれば残す） | `{"permission":"deny","user_message":理由,"agent_message":理由}`。`additionalContext` があれば `agent_message` の末尾に足す |
| `additionalContext`（PreToolUse） | そのまま | `agent_message` |
| `additionalContext`（PostToolUse / PostToolUseFailure / SessionStart） | そのまま | `additional_context` |
| プレーンテキスト（`session-start.sh`） | そのまま | `additional_context` |
| 上記以外のキー | そのまま | 捨てる |
| 空 | 何も出さない | 何も出さない |

deny の形は、Codex と Cursor の両方で実際にコマンドが止まることを確かめた（「deny と信頼の実測」）。`agent_message` と `additional_context` は公式ドキュメントに基づき、未実測。

**失敗時**
- adapter は**どの失敗でも exit 0 で終わり、変換できなかった出力は返さない**。Cursor は hook の非0終了でツールを拒否する（上の実測）ので、adapter の例外が全ツールの停止につながる
- 対象となる失敗：入力が JSON でない、`cwd` を決められない、パッチを解析できない、`<script>` が見つからない・実行できない、`<script>` の出力を変換できない、python3 が無い
- それぞれの理由を §5 の記録に残す
- 既存の方針（判定できなければ素通り）は変えない。Cursor の `failClosed` も使わない

### 3. 配線

- `hooks/hooks.json`（Claude Code と Codex）
  - 既存の7エントリは変えない
  - PreToolUse の末尾に、matcher `apply_patch` で `harness-adapter write-guard.sh` を呼ぶエントリを1つ足す。Claude Code には同名のツールが無いので発火しない
- `hooks/hooks-cursor.json` と `.cursor-plugin/plugin.json`（Cursor だけを使う人向け）
  - `"version": 1`
  - `preToolUse`（matcher `Shell`）、`postToolUse`（matcher `Shell`）、`postToolUseFailure`（matcher `Shell`）で、`harness-adapter tool-reminder.sh` を呼ぶ
  - `sessionStart` で `harness-adapter session-start.sh` を呼ぶ
  - `preToolUse`（matcher `Write`）で `harness-adapter write-guard.sh` を呼ぶ。Edit と `beforeSubmitPrompt`（`usage-log.sh`）は配線しない。Edit の入力が未取得のため
  - `beforeShellExecution` も配線しない。preToolUse(Shell) と同じコマンドで二重に判定することになり、しかも rtk の書き換え後の文字列が来るため
  - コマンドのパスは `./hooks/...` の相対にする。`CURSOR_PLUGIN_ROOT` は sessionStart 以外で信用できない
  - hooks-cursor.json で matcher が効くかは未実測（実測したのは、Claude 用に登録した hook での読み替え）。効かなければ matcher を外し、adapter 側で `tool_name` が `Shell` 以外なら何もせず終える
- `.codex-plugin/plugin.json`：`"hooks": "./hooks/hooks.json"`

### 4. 移せないもの・変わるもの

| 対象 | 扱い |
|---|---|
| `usage-log.sh` の `PreToolUse(^Skill$)` | Codex と Cursor には Skill ツールが無い。利用回数の記録は Claude Code だけで行う |
| Cursor の `write-guard.sh` | Write のみ配線。Edit は対象外 |
| `session-start.sh` のプレーンテキスト出力 | Cursor は adapter が `additional_context` に変換する。Codex がプレーンテキストを文脈に入れるかは未確認 3 |
| `PostToolUseFailure`（Codex） | 失敗も `PostToolUse` で届く。commit 後の Why の確認は PostToolUse でも動くので影響しない。push が失敗しても PR 更新を促す文が出るが、促しは「push 後の PR 更新を忘れない」ためのもので、失敗時に出ても害が小さいので許容する |
| `additionalContext` の 10,000 文字の前提 | Claude Code の仕様。Codex と Cursor の上限は未確認 4 |

### 5. 実行時の記録

素通りが静かに起きることが今回の問題の本体なので、契約テストだけでなく実行時にも記録する。

- adapter は、§2 の「失敗時」で終わったとき、`~/.claude/aidd/adapter-skips.json` に `{harness, harness_version, event, tool_name, reason}` ごとの件数と最終日時を加算する。**入力の本文は残さない**
- `harness_version` は Cursor の `cursor_version`（Codex は入力に版が無いので記録しない）
- `/aidd:doctor` は次の2つを表示する
  - 直近の素通りの理由と件数
  - 記録された `cursor_version` が fixture を取った版（本書「実測の条件」）と違うこと。fixture を取り直すきっかけにする

### 6. リリース条件

- ~~deny を返す hook で、Codex と Cursor の両方で実際にコマンドが止まることを実測する~~：2026-10-27 に確認済み（「deny と信頼の実測」）。adapter を実装したら、adapter を通した deny で同じ確認をもう一度行う
- ~~Codex の信頼が、スクリプト本体の変更を検出するかを実測する~~：検出しない、と確認済み。README とリリースノートには §7 の内容を書く
- 二重実行（未確認 1）を確かめるまでは、Cursor 用プラグインの README に「Claude Code に入れた aidd と併用しない」と書く。併用すると、usage.json の二重加算や `additional_context` の重複が起きうるため

### 7. Codex の信頼（trust）の運用

- 信頼していない hook は、`codex exec` では**何の表示もなく実行されない**。実測では、信頼する前は記録が0件、信頼した後に17件取れた
- 信頼は `~/.codex/config.toml` の `[hooks.state."<plugin>@<marketplace>:hooks/hooks.json:<event>:<i>:<j>"]` に `trusted_hash` として保存される
- `codex plugin remove` をしても、この信頼の記録は残った
- `trusted_hash` が見ているのは hooks.json のエントリで、スクリプト本体ではない（「deny と信頼の実測」）
  - スクリプトだけを直すアップデートは、再信頼なしで効く
  - hooks.json のエントリを足す・変えるアップデートは、利用者が `/hooks` で信頼し直すまで、**そのエントリの判定が黙って止まる**
  - 信頼はスクリプトの中身を保証しない。aidd のスクリプトの改変は、信頼済みのまま実行される
- README とリリースノートに書くこと
  - 導入後に `/hooks` で aidd の hook を信頼する手順
  - hooks.json のエントリが変わるリリースでは、信頼し直しが要ること（そのリリースノートに必ず書く）
  - `/hooks` 画面で、aidd 以外の hook の有効・無効を変えないこと。今回の実測では、信頼の操作のあとに、利用者が無効にしていた別の hook が2回とも有効に戻っていた（原因は切り分けていない）

## 採らなかった案

- **hooks.json の全エントリを adapter 経由にする**：今動いている Claude Code と Codex の判定を、新しい層の失敗点の後ろに移すことになる。既存エントリが変わるので、Codex の信頼も切れうる
- **スクリプトごとにハーネスの分岐を書く**：4本・計1159行のそれぞれに入力の差を持ち込むことになり、どこかで揃え忘れると素通りが静かに起きる
- **ハーネスごとにスクリプトを複製する**：判定ロジックが3重になる。すでに `generate-asset-index.py` が持っている「正本1つ」の原則に反する
- **変換ツール（TokenRollAI/acplugin など）**：hooks を Cursor では警告だけ、Codex では AGENTS.md の文章に変える。強制力が消えるので、aidd の目的に合わない
- **superpowers 式に、環境変数で出力形式だけ切り替える**：superpowers は SessionStart しか持たないので成り立つ。Cursor は Claude 用に登録した hook にも Cursor の入力を渡し、`CLAUDE_PLUGIN_ROOT` も設定するので、環境変数ではハーネスを判定できない
- **adapter が `tool_name` で呼ぶスクリプトを選ぶ**：hooks.json の matcher と同じ対応表を2箇所で持つことになる

## テスト方針

`tests/hook-contract-test.sh` に、fixture を adapter に流すケースを足す。

- `cursor/preToolUse.shell-git-add-all.json` → Cursor 形式の `permission: deny` が返る
- 同じ入力から `cursor_version` を消したもの → Cursor と判定され、deny が返る（判定の補助条件の確認）
- `cwd` が空で `CURSOR_PROJECT_DIR` がある Cursor の入力 → そのリポジトリで git の判定が行われる
- `cwd`・`CURSOR_PROJECT_DIR`・`workspace_roots` がすべて空 → 何も出さずに exit 0、`adapter-skips.json` に記録される
- `CLAUDE_PLUGIN_ROOT` が別のディレクトリを指す → `write-guard.sh` が aidd の `asset-index.json` を読む
- `codex/PreToolUse.apply_patch-add.json` のパスを `.env.local` に差し替えたもの → deny が返る
- `Add File: .env.local`（相対パス。Codex は相対パスでも送ってくる）のパッチ → `cwd` を基準に解決され、deny が返る
- `Update File` + `Move to: .env.local` のパッチ → deny が返る
- `Add File` が2件（`.env.local` と通常のファイル）のパッチ → JSON 1つで deny が返る
- 解析できないパッチ、JSON でない入力、存在しない `<script>`、`<script>` がテキストでも JSON でもない出力 → 何も出さずに exit 0、理由が記録される
- `session-start.sh` のプレーンテキスト → Cursor では `additional_context` の JSON になる
- `cursor/preToolUse.write.json` のパスを `.env.local` に差し替えたもの → Cursor 形式の deny が返る
- python3 が無い → `adapter-skips.json` に `no_python3` が残る
- 子へ渡した JSON に `user_email` / `generation_id` / `cursor_version` / `workspace_roots` が無い
- deny と `additionalContext` が同時の Cursor 入力 → `agent_message` に nudge が残る

### fixture の取り直し

fixture は実測値なので、`/aidd:doctor` が版の違いを示したら取り直す。手順は「実測の条件」に従う。コミットする前に、次の置き換えをして、元の値が残っていないことを grep で確かめる。

- 作業ディレクトリ → `/work/repo`、プラグインのディレクトリ → `/plugins/hookprobe`、ホーム → `/home/user`
- `user_email` → `user@example.com`
- UUID → `00000000-0000-0000-0000-000000000000`
- `transcript_path` の中のディレクトリ名 → 固定値
- 環境変数は `*_PLUGIN_ROOT`・`*_PLUGIN_DATA`・`*_PROJECT_DIR` だけを残す（記録を起動した親プロセスから引き継いだ値は落とす）

## 未確認

1. Cursor が、Claude Code に入れた aidd の `hooks/hooks.json` を実行するか。実行する場合は次の問題が起きる
   - `${CLAUDE_PLUGIN_ROOT}` が別のプラグインに展開される
   - Cursor 用プラグインと併用すると二重に実行される
2. ~~各ハーネスが deny の出力を実際に守るか~~：守る（「deny と信頼の実測」）。Cursor で確かめたのは `--plugin-dir` で読み込んだプラグインの hook。`agent_message` / `additional_context` が文脈に入るかは未実測
3. Codex の SessionStart がプレーンテキストを文脈に入れるか
4. Codex と Cursor の `additionalContext` の文字数の上限
5. 未信頼の hook を CLI から列挙する方法（`/aidd:doctor` で検出するため）。`trusted_hash` がスクリプト本体を見ないことは確認済み
6. ~~Cursor の Write の preToolUse の入力~~：取得済み（`cursor/preToolUse.write.json`）。Edit、`afterFileEdit`・`beforeSubmitPrompt`・`stop` は未取得
7. Cursor のマルチルートのワークスペースで、`workspace_roots[0]` 以外のリポジトリでコマンドを実行したときの入力（`cwd` が埋まるか）
8. adapter の遅延。Claude Code と Codex の Bash 経路には挟まらない。Cursor の Shell 経路に挟まる分を実装時に測る
