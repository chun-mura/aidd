---
name: eval
description: design-review パイプラインをゴールデンセットで評価し、検出率・誤棄却率を測定する。impl を付けると、実装レビューを同種 (claude -p) と異種 (codex exec) で同じ欠陥セットに対して比べる。compare を付けると、design-review の deep・standard・小規模の直接レビューと単体モデルを同じケースとキーで比べる。branch を付けると、design-review の条件付きの agent (プロジェクト固有観点・外部情報の検証・セキュリティ) の起動と判定を未見ケースで測る
argument-hint: [ケース名 (structure / data-error / security / crosscut)。省略時は全ケース] | impl [ケース名 (tests/eval/impl/cases/ の名前)。省略時は全ケース] | compare [ケース名 (tests/eval/cases/ の名前)。省略時は全ケース] | branch [変種名 (tests/eval/branch/variants.tsv の1列目)。省略時は全変種]
disable-model-invocation: true
---

**パスと引数と質問の扱い**: この文書の相対パスは、この SKILL.md があるディレクトリを起点にする。`$ARGUMENTS` が文字のまま残っている場合（Codex・Cursor など）は、この skill を呼び出したメッセージのうち skill 名以外の部分を `$ARGUMENTS` とみなす。`AskUserQuestion` と書かれた箇所は、ユーザーに質問するツールがあればそれを使い、無ければ質問を書いて作業を止め、回答を待つ。回答が無いまま推測で進めない。

対象ケース: $ARGUMENTS (未指定なら `tests/eval/cases/` 配下の全 `.md`)。先頭が `impl` なら、この下の design-review の手順ではなく、末尾の「実装レビューの比較 (同種・異種)」を行う。先頭が `compare` なら、末尾の「design-review の構成比較 (deep・standard・直接・単体モデル)」を、先頭が `branch` なら、末尾の「design-review の条件分岐の評価 (Agent 4・5・6)」を行う

design-review パイプラインの精度を、欠陥を意図的に埋め込んだ設計書 (ゴールデンセット) で測定してください。このコマンドは aidd プラグインリポジトリ自身で実行する前提 (`tests/eval/` が存在すること。なければその旨を報告して終了)。

## 分離と汚染ガード (最重要)

レビューの実行と採点を別の工程に分ける。メイン (このセッション) は準備・凍結・採点を受け持ち、レビューはケースごと・試行ごとに起動する新しい実行担当 (別のセッション) が行う。

- **準備 (メイン)**: 実行担当に渡す入力を、元リポジトリの外の一時ディレクトリにコピーだけで作り、その中に keys・results・Git 履歴が無いことを検証する。実行担当へのプロンプトはこの文書の固定プロンプトから作り、メインはプロンプトに文言を足さない (過去の結果・キー・前回の指摘を書き加えない)
- **実行 (新しい実行担当)**: 作業ディレクトリは一時ディレクトリの `input/`。渡すのは固定プロンプトと `input/` だけで、keys・results・Git 履歴・過去の採点結果は入力にも作業ディレクトリにも文脈にも含めない
- **凍結と採点 (メイン)**: 全ケース・全試行の実行が終わったら生出力をハッシュで凍結し、照合してから初めて `tests/eval/keys/` と過去の結果を読む。採点は凍結した生出力だけを根拠にし、レビュー結果を書き換えない
- **偽指摘**: `tests/eval/planted/` は `input/` に置かない。準備のブロックが表の行だけを取り出して ID を M1, M2, … に振り直し、固定プロンプトの末尾に「混ぜる指摘」として付ける (M の ID と元の ID の対応は `raw/mix-<ケース>.tsv`)。実行担当は reviewer の high/mid 指摘と混ぜて中立な ID (F1, F2, …) に振り直して refuter に渡し、どれが偽指摘かを知らせない。reviewer の high/mid が0件でも、偽指摘だけで refuter を起動する。refuter の後、arbiter に渡す前に偽指摘を取り除く。reviewer・arbiter には渡さない。偽指摘の反証根拠はキー側にあるため、キーを読まない規則はそのまま守る

**分離の限界**:

- これは入力・作業ディレクトリ・文脈の分離であり、OS やハーネスの権限による読み取りの禁止ではない。実行担当や agent による、作業ディレクトリの外の絶対パスによる読み取りは防げない
- 手順1の抽出で調べるのは stream-json に残った tool_use の入力だけ。パスの引数 (Read・Glob・Grep などの `file_path`・`path`・`notebook_path`、Glob の `pattern`) は作業ディレクトリの外かどうかを見る。どの引数でも、run ディレクトリの `raw/`・`local/` のパス、`../`、先頭が `~` の値は参照として記録する。Bash のコマンドは任意の書き方ができるので、検出しきれない (元リポジトリのパスと keys・results の文字列が入っているかしか見ない)
- 実行担当は「混ぜる指摘」が偽指摘だと分かる立場にある (混ぜる役だから)。refuter には知らせず、`input/` にも置かない (planted のファイル・見出し・元の ID は run ディレクトリの `raw/` と元リポジトリにしか無い) が、実行担当が渡し方で偏らせる可能性と、agent が `raw/`・`local/` を絶対パスで読む可能性は残る
- 抽出から凍結までの間は、raw/ と local/ を書き換えられる。凍結の後に書き換えて SHA256SUMS を作り直しても、採点前に記録した SHA256SUMS の sha256 と食い違うので見つかるが、記録した値ごと書き換えられたら見つけられない
- 実行担当は user 設定 (CLAUDE.md・hook・他のプラグイン) をそのまま読み込むので、文脈に keys・results が無いことは保証するが、それ以外の文脈は init の記録で追う。採点工程の判定エージェント (手順4) はメインの作業ディレクトリ (元リポジトリ) で動くので、キーを開かない規則は指示の文言による

## 手順

**1. レビュー実行** — 準備・実行・凍結の順に行う。評価は最も厳密な経路 (`--depth=deep`、小規模対象ショートカットなし、`--security` なし) に固定して測り、通常の `standard` 最適化による skip と混同しない。

**1a. 準備 (メイン)** — 対象ケースと試行数を決める (既定は各ケース1試行)。元リポジトリの外に run ディレクトリを作り (`mktemp -d "${TMPDIR:-/tmp}/aidd-eval.XXXXXX"` など)、次のブロックの `<repo>` (このリポジトリのルートの絶対パス)・`<run>` (run ディレクトリ)・`<cases>` (空白区切りのケース名) を置き換えてファイルに書き、`bash` で実行する。

ブロックがすること: `input/` にケースと plugin (`.claude-plugin/plugin.json`・`agents/`・`skills/design-review/`) だけをコピーする。次のどれかに当たれば止まる。

- ケースが無い、ケース名が英小文字・数字・`-` 以外を含む、ケース・planted・キーのどれかが無い、planted に表の行が無いか、`| PL-` で始まる行の数と取り出せた行の数が違う
- run ディレクトリが元リポジトリの中にある、`input/` か `raw/` が既にある、`input/` がどこかの Git の作業ツリーの中にある
- `input/` のファイルが許可した一覧と完全に一致しない (シンボリックリンクを含む)、コピー元と内容が違う、名前が `.git`・`keys`・`results` のもの (大文字小文字を区別しない) がある、内容が `tests/eval/keys/`・`tests/eval/results/` のどれかのファイルと同じ
- `input/` かプロンプトに元リポジトリの絶対パス (渡した表記と `pwd -P` の表記。大文字小文字を区別しない) がある、プロンプトに `tests/eval/` か planted の ID が残っている

`raw/` には、固定プロンプトの末尾に「混ぜる指摘」を付けたもの (`prompt-<ケース>.md`)・M の ID の対応 (`mix-<ケース>.tsv`)・入力のハッシュ (`input.sha256`)・キーと planted のハッシュ (`keys.sha256`・`planted.sha256`、レビュー前に固定する)・測定条件 (`conditions.md`) を書く。失敗したら原因を直し、新しい run ディレクトリでやり直す。検証を省いて先へ進めない。

```bash
# eval staging: copy only the allowed files into <run>/input, write the prompts and hashes into <run>/raw, and check the separation
repo='<repo>'; run='<run>'; cases='<cases>'
set -euo pipefail
fail() { echo "eval staging: $*" >&2; exit 1; }
[ -n "$(printf '%s' "$cases" | tr -d ' \t\n')" ] || fail "no cases"
for c in $cases; do
  case "$c" in *[!abcdefghijklmnopqrstuvwxyz0123456789-]*) fail "bad case name: $c" ;; esac
done
repo_given=$repo
repo=$(cd "$repo" && pwd -P); run=$(cd "$run" && pwd -P)
case "$run/" in "$repo/"*) fail "the run directory is inside the repository" ;; esac
in="$run/input"; raw="$run/raw"
if [ -e "$in" ] || [ -e "$raw" ]; then fail "input/ or raw/ already exists in $run"; fi
for c in $cases; do
  for d in cases planted keys; do
    [ -f "$repo/tests/eval/$d/$c.md" ] || fail "no case, planted or key for $c"
  done
done
mkdir -p "$in/cases" "$in/plugin/.claude-plugin" "$in/plugin/skills" "$raw" "$run/local"
: > "$run/allowed"
for c in $cases; do
  cp "$repo/tests/eval/cases/$c.md" "$in/cases/$c.md"
  printf 'cases/%s.md\ttests/eval/cases/%s.md\n' "$c" "$c" >> "$run/allowed"
done
cp "$repo/.claude-plugin/plugin.json" "$in/plugin/.claude-plugin/plugin.json"
cp -R "$repo/agents" "$in/plugin/agents"
cp -R "$repo/skills/design-review" "$in/plugin/skills/design-review"
(cd "$repo" && find .claude-plugin/plugin.json agents skills/design-review -type f) \
  | while read -r f; do printf 'plugin/%s\t%s\n' "$f" "$f"; done >> "$run/allowed"
if [ -n "$(find "$in" \( -iname .git -o -iname keys -o -iname results \))" ]; then fail "input has a .git, keys or results entry"; fi
(cd "$in" && find . ! -type d | sed 's|^\./||' | LC_ALL=C sort) > "$run/found"
cut -f1 "$run/allowed" | LC_ALL=C sort > "$run/expected"
cmp -s "$run/found" "$run/expected" || fail "input holds files outside the allowed list"
while IFS=$'\t' read -r dst src; do
  cmp -s "$in/$dst" "$repo/$src" || fail "$dst differs from $src"
done < "$run/allowed"
if env -u GIT_DIR -u GIT_WORK_TREE git -C "$in" rev-parse --git-dir > /dev/null 2>&1; then fail "input is inside a git work tree"; fi
(cd "$repo/tests/eval" && for d in keys results; do
  if [ -d "$d" ]; then find "$d" -type f -size +0; fi
done | while read -r f; do shasum -a 256 "$f"; done) | awk '{print $1}' | LC_ALL=C sort -u > "$run/forbidden"
(cd "$in" && find . -type f | while read -r f; do shasum -a 256 "$f"; done) | awk '{print $1}' | LC_ALL=C sort -u > "$run/inhash"
if [ -n "$(comm -12 "$run/forbidden" "$run/inhash")" ]; then fail "input has the same content as a file under tests/eval/keys or results"; fi
for c in $cases; do
  prompt="$raw/prompt-$c.md"
  sed -n '/^# eval executor prompt/,/^# end eval executor prompt$/p' "$repo/skills/eval/SKILL.md" \
    | sed "s/<case>/$c/g" > "$prompt"
  [ -s "$prompt" ] || fail "skills/eval/SKILL.md has no executor prompt"
  printf '\n## 混ぜる指摘\n\n| ID | 深刻度 | 引用箇所 | 指摘 | 代案 |\n|---|---|---|---|---|\n' >> "$prompt"
  awk -v map="$raw/mix-$c.tsv" '/^\| PL-[A-Z]+[0-9]+ \|/ {
    n++; id = $2; gsub(/ /, "", id); rest = $0; sub(/^\| PL-[A-Z]+[0-9]+ \|/, "", rest)
    printf "| M%d |%s\n", n, rest; printf "M%d\t%s\n", n, id > map
  }' FS='|' "$repo/tests/eval/planted/$c.md" >> "$prompt"
  [ -s "$raw/mix-$c.tsv" ] || fail "no planted rows for $c"
  planted_rows=$(grep -c '^| PL-' "$repo/tests/eval/planted/$c.md" || true)
  [ "$planted_rows" -eq "$(wc -l < "$raw/mix-$c.tsv")" ] || fail "planted rows and mixed rows differ for $c"
done
case "$repo_given" in /*) ;; *) repo_given=$repo ;; esac
if grep -rqiF -e "$repo" -e "$repo_given" "$in" "$raw"; then fail "the repository path appears in the input or a prompt"; fi
if grep -qF 'tests/eval/' "$raw"/prompt-*.md; then fail "a prompt names tests/eval/"; fi
if grep -qF 'PL-' "$raw"/prompt-*.md; then fail "a prompt shows a planted ID"; fi
(cd "$in" && find . -type f | LC_ALL=C sort | while read -r f; do shasum -a 256 "$f"; done) > "$raw/input.sha256"
(cd "$repo/tests/eval" && for c in $cases; do shasum -a 256 "keys/$c.md"; done) > "$raw/keys.sha256"
(cd "$repo/tests/eval" && for c in $cases; do shasum -a 256 "planted/$c.md"; done) > "$raw/planted.sha256"
version=$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' "$repo/.claude-plugin/plugin.json" 2>/dev/null) || version=不明
sha=$(git -C "$repo" rev-parse HEAD 2>/dev/null) || sha=不明
if status=$(git -C "$repo" status --porcelain 2>/dev/null); then
  if [ -n "$status" ]; then dirty=yes; else dirty=no; fi
else
  dirty=不明
fi
cli=$(claude --version 2>/dev/null < /dev/null) || cli=
[ -n "$cli" ] || cli=不明
{
  printf '| 項目 | 値 |\n|---|---|\n'
  printf '| aidd version | %s |\n' "$version"
  printf '| git SHA | %s |\n' "$sha"
  printf '| 未コミット変更 | %s |\n' "$dirty"
  printf '| CLI (準備時) | %s |\n' "$cli"
  printf '| 対象ケース | %s |\n' "$cases"
  printf '| 準備日時 (UTC) | %s |\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$raw/conditions.md"
rm -f "$run/found" "$run/expected" "$run/forbidden" "$run/inhash"
echo "eval staging: ok ($run)"
# end eval staging
```

実行担当の固定プロンプト (上のブロックが `<case>` をケース名に置き換え、末尾に「混ぜる指摘」の表を付けて `raw/prompt-<ケース>.md` に書く。ここを変えたら、それはプロンプトの版が変わったことになり、ハッシュで追える):

```text
# eval executor prompt (case: <case>)
あなたは aidd の design-review を評価する実行担当です。採点は、あなたの実行が終わった後に別の工程で行います。作業ディレクトリの中のファイルだけを使い、親ディレクトリや作業ディレクトリの外の絶対パスを開かないでください。

1. `plugin/skills/design-review/SKILL.md` を読み、対象 `cases/<case>.md` に `--depth=deep` で適用する (並列 dispatch → refuter → arbiter)。`--security` と `--verify-sources` は付けない (security-reviewer の起動は条件判定に任せる)。対象が1ファイル・100行未満でも、小規模対象ショートカットは適用しない。作業ディレクトリに `.aidd/` は無い。
2. 各 agent への dispatch では、対象ケースのパスと担当観点だけを渡し、「このファイルだけをレビューする」と明示する。
3. 指摘の混入: reviewer の high/mid 指摘と、このプロンプトの末尾にある「混ぜる指摘」の表の行を順不同に混ぜ、すべてを中立な ID (F1, F2, …) に振り直して同じ形式で refuter に渡す。どの指摘を混ぜたかは refuter に知らせない。reviewer の high/mid が無くても、混ぜる指摘だけで refuter を起動する。refuter の後、arbiter に渡す前に混ぜた指摘を取り除く。reviewer・arbiter には混ぜる指摘を渡さない。
4. ユーザーには質問しない (答えは返らない)。判断が要るところは、判断と理由を出力に書いて進める。
5. 最後に、次の見出しをこの順ですべて含む Markdown を最終回答にする。中身が無い節には「なし」、取れない値には「不明」と書く。
   - `## reviewer の生指摘` (agent ごとに、深刻度・引用箇所・指摘・代案)
   - `## refuter への入力と対応表` (中立 ID ごとに元の ID。reviewer の指摘は agent と番号、混ぜた指摘は M の ID)
   - `## refuter の判定` (中立 ID ごとに、反証成立/反証失敗と根拠)
   - `## arbiter の最終報告` (全文と、high/mid/low 別の件数)
   - `## security-reviewer の起動` (yes/no と理由)
# end eval executor prompt
```

**1b. 実行 (新しい実行担当)** — ケースごと・試行ごとに新しいセッションを1つ起動する (ケースの間で文脈を持ち越さない)。Claude Code では次のとおり (`<case>` はケース名、`<trial>` は 1 から数える試行番号):

```bash
cd "<run>/input" && claude -p --output-format stream-json --verbose --plugin-dir ./plugin < "<run>/raw/prompt-<case>.md" > "<run>/local/<case>-t<trial>.jsonl"
```

- 1回に数分から十数分かかる。ハーネスの待ち時間の上限 (Bash の既定120秒など) に掛からないよう、バックグラウンドで実行して終了を待つ
- user 設定・hook・他のプラグインは変えずにそのまま読み込ませる。permissionMode も user 設定に従い、init の記録に残る。`input/plugin/` には hook を入れないので、評価対象の aidd の hook は動かない
- 実行担当のセッションも、ふだんのセッションと同じように run ディレクトリの外へ書き込む。確認済み (2026-11-23、サンドボックスの中): subagent の出力ファイルが一時ディレクトリの `claude-<uid>/<cwd を変換した名前>/<session_id>/tasks/` にできた。init の `memory_paths` は `~/.claude/projects/<cwd を変換した名前>/memory/` を指したが、そのディレクトリは作られていなかった。未確認: サンドボックスの外での会話記録 (`~/.claude/projects/<cwd を変換した名前>/`)、読み込まれた hook の書き込み (aidd をインストールしていれば `~/.claude/aidd/` など)。いずれも元リポジトリの keys・results は含まない
- 確認済みの範囲 (2026-11-23、Claude Code 2.1.330、subagent を1回だけ呼ぶ短いプロンプト): サンドボックスの中から起動できた。init の `plugins` に `--plugin-dir` の aidd が出た。subagent の tool_use が `parent_tool_use_id` 付きで stream-json に出た。result の `total_cost_usd` と `modelUsage` に subagent のモデルの分も入っていた。`task_notification` の `usage.total_tokens` に agent ごとのトークンが出た。実際の eval の規模 (並列 dispatch・長時間の実行) では未確認
- ほかのハーネスでは、同じプロンプトを、作業ディレクトリを `<run>/input` にした新しいセッションに手で渡し (agent は `input/plugin/agents/` の定義をそのハーネスの方法で読み込む)、最終回答を `<run>/raw/<case>-t<trial>.md` に保存する。下の抽出は使えないので、`<run>/raw/<case>-t<trial>.meta.md` を手で作り、取れない値 (モデル・コスト・agent ごとのトークン・プラグイン・cwd の検査) は「不明」と書く

実行のたびに次のブロックで stream-json から記録を取り出す (`<run>`・`<case>`・`<trial>`・`<repo>` を置き換える)。ケース名は英小文字・数字・`-`、試行番号は数字だけで、それ以外なら何も書かずに止まる。`raw/<case>-t<trial>.md` に実行担当の最終回答を、`raw/<case>-t<trial>.meta.md` に測定条件 (session_id・CLI・モデル・permissionMode・cwd・所要時間・ターン数・コスト・読み込まれたプラグインの名前と版・モデル別の使用量・agent 別のトークン・作業ディレクトリの外や keys・results への参照) を書く。絶対パスは大文字小文字を区別せずに `[input]`・`[run]`・`[repo]`・`~` に置き換える (置き換え以外は変えない)。同じ試行番号の記録は上書きしない。最終回答が無い・エラーで終わった試行は0以外で終わるので、失敗した試行として記録し、成功扱いしない。やり直すときは新しい試行番号で実行する。判定に「汚染の疑い」が出た試行 (aidd が `input/plugin` の1つだけではない、cwd が `input/` ではない、作業ディレクトリの外・元リポジトリ・keys・results を参照した) は、捨てずにその旨を結果に記録する。init が無いなど検査できなかった項目は、判定に「不明」として出る。

```bash
# eval extract: <run>/local/<case>-t<trial>.jsonl -> <run>/raw/<case>-t<trial>.md and .meta.md
python3 -I - '<run>' '<case>' '<trial>' '<repo>' <<'PY'
import json, os, re, sys

run_arg, case, trial, repo_arg = sys.argv[1:5]
if not re.fullmatch(r"[a-z0-9-]+", case) or not re.fullmatch(r"[0-9]+", trial):
    sys.exit(f"eval extract: bad case or trial: {case!r} {trial!r}")
run, repo = os.path.realpath(run_arg), os.path.realpath(repo_arg)
staged = os.path.join(run, "input")
stem = f"{case}-t{trial}"
subs = sorted({(staged, "[input]"), (os.path.join(run_arg, "input"), "[input]"), (run, "[run]"), (run_arg, "[run]"),
               (repo, "[repo]"), (repo_arg, "[repo]"), (os.path.expanduser("~"), "~")}, key=lambda s: -len(s[0]))


def clean(value):
    text = str(value)
    for path, name in subs:
        if len(path) > 1:
            text = re.sub(re.escape(path), lambda _: name, text, flags=re.IGNORECASE)
    return text


def cell(value):
    return "不明" if value is None or value == "" else clean(value).replace("|", "\\|").replace("\n", " ")


init = result = None
agents, finished, refs = {}, {}, []
try:
    with open(os.path.join(run, "local", stem + ".jsonl"), encoding="utf-8") as f:
        lines = f.readlines()
except OSError:
    lines = []
for line in lines:
    try:
        m = json.loads(line)
    except ValueError:
        continue
    if not isinstance(m, dict):
        continue
    if (m.get("type"), m.get("subtype")) == ("system", "init"):
        init = m
    elif (m.get("type"), m.get("subtype")) == ("system", "task_notification"):
        finished[m.get("tool_use_id")] = m
    elif m.get("type") == "result":
        result = m
    message = m.get("message")
    content = message.get("content") if isinstance(message, dict) else None
    for c in content if isinstance(content, list) else []:
        if not (isinstance(c, dict) and c.get("type") == "tool_use"):
            continue
        args = c.get("input") if isinstance(c.get("input"), dict) else {}
        if c.get("name") in ("Agent", "Task"):
            agents[c.get("id")] = args.get("subagent_type") or "不明"
        text = json.dumps(args, ensure_ascii=False)
        folded = text.casefold()
        reasons = []
        if repo.casefold() in folded or repo_arg.casefold() in folded:
            reasons.append("元リポジトリのパス")
        if any(k in folded for k in ("tests/eval/keys", "tests/eval/results", "tests/eval/impl/keys", "tests/eval/branch/keys", "tests/eval/impl/rubric")):
            reasons.append("keys・results")
        if any(os.path.join(p, d).casefold() in folded for p in (run, run_arg) for d in ("raw", "local")):
            reasons.append("run の raw・local")
        if "../" in text or any(isinstance(v, str) and v.startswith("~") for v in args.values()):
            reasons.append("作業ディレクトリの外 (相対・~)")
        base = staged.casefold()
        for key in ("file_path", "path", "notebook_path") + (("pattern",) if c.get("name") == "Glob" else ()):
            value = args.get(key)
            if not isinstance(value, str):
                continue
            real = os.path.realpath(value).casefold()
            if ".." in value.split("/") or (value.startswith("/") and real != base and not real.startswith(base + os.sep)):
                reasons.append("作業ディレクトリの外")
        if reasons:
            refs.append((c.get("name"), m.get("parent_tool_use_id"), "・".join(dict.fromkeys(reasons)), text))

i, r = init or {}, result or {}
suspect, unknown = [], []
plugins = i.get("plugins") if isinstance(i.get("plugins"), list) else None
aidd = [p for p in plugins or [] if isinstance(p, dict) and p.get("name") == "aidd"]
if init is None:
    unknown.append("init が無く、プラグイン・cwd の検査は不明")
else:
    if plugins is None:
        unknown.append("plugins が無く、プラグインの検査は不明")
    elif os.path.isdir(os.path.join(staged, "plugin")) and (
            len(aidd) != 1 or os.path.realpath(str(aidd[0].get("path"))) != os.path.join(staged, "plugin")):
        suspect.append("aidd が input/plugin の1つだけではない")
    if not i.get("cwd"):
        unknown.append("cwd が無く、cwd の検査は不明")
    elif os.path.realpath(i["cwd"]) != staged:
        suspect.append("cwd が input/ ではない")
if refs:
    suspect.append(f"作業ディレクトリの外・元リポジトリ・keys・results への参照 {len(refs)} 件")
verdict = ("汚染の疑い: " + " / ".join(suspect)) if suspect else "検出なし (stream-json に残った tool_use に限る)"
if unknown:
    verdict += " / 不明: " + " / ".join(unknown)
ok = bool(result) and not r.get("is_error") and isinstance(r.get("result"), str)

plugin_list = "; ".join(f"{p.get('name')} {p.get('version')}" for p in plugins if isinstance(p, dict)) if plugins is not None else None
rows = [
    ("session_id", r.get("session_id") or i.get("session_id")),
    ("Claude Code (init)", i.get("claude_code_version")),
    ("メインのモデル (init)", i.get("model")),
    ("permissionMode", i.get("permissionMode")),
    ("cwd", i.get("cwd")),
    ("終了", f"{r.get('subtype')} / is_error={r.get('is_error')}" if result else None),
    ("duration_ms", r.get("duration_ms")),
    ("num_turns", r.get("num_turns")),
    ("total_cost_usd", r.get("total_cost_usd")),
    ("プラグイン (init)", plugin_list),
    ("読み込まれた aidd", "; ".join(f"{p.get('version')} {p.get('source')} {p.get('path')}" for p in aidd) if plugins is not None else None),
    ("判定", verdict),
]
out = [f"# 実行担当の記録: {case} 試行 {trial}", "", "| 項目 | 値 |", "|---|---|"]
out += [f"| {k} | {cell(v)} |" for k, v in rows]
out += ["", "## モデル別 (modelUsage)", "",
        "| モデル | provider | costBasis | input | output | cache read | cache creation | costUSD |", "|---|---|---|---|---|---|---|---|"]
usage = r.get("modelUsage") if isinstance(r.get("modelUsage"), dict) else {}
for model, u in usage.items():
    u = u if isinstance(u, dict) else {}
    out.append("| " + " | ".join(cell(v) for v in (model, u.get("provider"), u.get("costBasis"), u.get("inputTokens"), u.get("outputTokens"),
                                                      u.get("cacheReadInputTokens"), u.get("cacheCreationInputTokens"), u.get("costUSD"))) + " |")
if not usage:
    out.append("| 不明 | 不明 | 不明 | 不明 | 不明 | 不明 | 不明 | 不明 |")
out += ["", "## agent 別 (task_notification の usage.total_tokens)", "", "| tool_use_id | subagent_type | status | total_tokens |", "|---|---|---|---|"]
for tid, kind in agents.items():
    n = finished.get(tid) or {}
    tokens = n.get("usage", {}).get("total_tokens") if isinstance(n.get("usage"), dict) else None
    out.append(f"| {cell(tid)} | {cell(kind)} | {cell(n.get('status'))} | {cell(tokens)} |")
if not agents:
    out.append("| なし | | | |")
out += ["", "## 作業ディレクトリの外・元リポジトリ・keys・results への参照 (tool_use)", ""]
if refs:
    out += ["| tool | 呼んだ側 | 理由 | 入力 |", "|---|---|---|---|"]
    out += [f"| {cell(name)} | {cell(agents.get(parent, 'メイン') if parent else 'メイン')} | {cell(why)} | {cell(text[:300])} |"
            for name, parent, why, text in refs]
else:
    out.append("なし")
raw = os.path.join(run, "raw")
with open(os.path.join(raw, stem + ".meta.md"), "x", encoding="utf-8") as f:
    f.write("\n".join(out) + "\n")
with open(os.path.join(raw, stem + ".md"), "x", encoding="utf-8") as f:
    f.write(clean(r["result"]).rstrip("\n") + "\n" if ok else "実行担当の最終回答なし (失敗した試行)\n")
print(f"eval extract: {stem}: {verdict}")
if not ok:
    print(f"eval extract: {stem}: the run has no final answer or ended with an error", file=sys.stderr)
    sys.exit(1)
PY
```

**1c. 凍結 (メイン)** — 全ケース・全試行の実行と抽出が終わったら、次のブロックを実行する。各 stream-json に抽出した記録 (`raw/<case>-t<trial>.md` と `.meta.md`) があることを確かめ、`local/` の全ファイルのハッシュを `raw/local.sha256` に、`raw/` の全ファイルのハッシュを `raw/SHA256SUMS` に書き、両方を読み取り専用にして、SHA256SUMS 自身の sha256 を表示する。表示された SHA256SUMS の sha256 を、採点を始める前にユーザーへの途中報告に書き、結果ファイルの測定条件にも書く。手順2の照合はこの値で行う。これ以後 `raw/`・`local/` を変えない。

```bash
# eval freeze: hash <run>/local/*.jsonl and every file in <run>/raw, make them read-only, and print the hash of SHA256SUMS
run='<run>'
set -euo pipefail
run=$(cd "$run" && pwd -P); raw="$run/raw"
if [ -e "$raw/SHA256SUMS" ]; then echo "eval freeze: $raw is already frozen" >&2; exit 1; fi
for j in "$run"/local/*.jsonl; do
  [ -e "$j" ] || continue
  stem=$(basename "$j" .jsonl)
  if [ ! -f "$raw/$stem.md" ] || [ ! -f "$raw/$stem.meta.md" ]; then
    echo "eval freeze: no extracted record for local/$stem.jsonl" >&2; exit 1
  fi
done
(cd "$run" && find local -type f | LC_ALL=C sort | while read -r f; do shasum -a 256 "$f"; done) > "$raw/local.sha256"
(cd "$raw" && find . -type f | sed 's|^\./||' | LC_ALL=C sort | while read -r f; do shasum -a 256 "$f"; done) > "$run/SHA256SUMS.tmp"
mv "$run/SHA256SUMS.tmp" "$raw/SHA256SUMS"
find "$raw" "$run/local" -type f -exec chmod a-w {} +
echo "eval freeze: SHA256SUMS sha256 $(shasum -a 256 "$raw/SHA256SUMS" | awk '{print $1}')"
# end eval freeze
```

**2. 採点** — 先に次のブロックで照合する (`<sums>` は手順1cで表示された SHA256SUMS の sha256)。凍結した生出力・stream-json (どちらもファイルの追加・削除を含む)・準備のときの `input/`・キーのどれかが変わっていたら止まる。通らなければ採点しない。

```bash
# eval verify: before reading the keys, check the frozen output against the hash printed by the freeze, the input and the keys
run='<run>'; repo='<repo>'; sums='<sums>'
set -euo pipefail
fail() { echo "eval verify: $*" >&2; exit 1; }
run=$(cd "$run" && pwd -P); raw="$run/raw"
[ "$(shasum -a 256 "$raw/SHA256SUMS" | awk '{print $1}')" = "$sums" ] || fail "SHA256SUMS differs from the hash printed at the freeze"
listed=$(awk '{print $2}' "$raw/SHA256SUMS" | LC_ALL=C sort)
present=$(cd "$raw" && find . ! -type d ! -name SHA256SUMS | sed 's|^\./||' | LC_ALL=C sort)
[ "$listed" = "$present" ] || fail "files were added to or removed from raw/ after the freeze"
(cd "$raw" && shasum -a 256 -c SHA256SUMS > /dev/null 2>&1) || fail "a file in raw/ changed after the freeze"
listed=$(awk '{print $2}' "$raw/local.sha256" | LC_ALL=C sort)
present=$(cd "$run" && find local ! -type d | LC_ALL=C sort)
[ "$listed" = "$present" ] || fail "files were added to or removed from local/ after the freeze"
(cd "$run" && shasum -a 256 -c "$raw/local.sha256" > /dev/null 2>&1) || fail "local/ changed after the freeze"
listed=$(awk '{print $2}' "$raw/input.sha256" | LC_ALL=C sort)
present=$(cd "$run/input" && find . ! -type d | LC_ALL=C sort)
[ "$listed" = "$present" ] || fail "files were added to or removed from input/ after staging"
(cd "$run/input" && shasum -a 256 -c "$raw/input.sha256" > /dev/null 2>&1) || fail "input/ changed after staging"
(cd "$repo/tests/eval" && shasum -a 256 -c "$raw/keys.sha256" > /dev/null 2>&1) || fail "the keys changed after staging"
echo "eval verify: ok"
# end eval verify
```

照合が通ったら、ここで初めて `tests/eval/keys/<ケース名>.md` と過去の結果を読む。採点の材料は `raw/<case>-t<trial>.md` (reviewer の生指摘・refuter の判定と対応表・arbiter の最終報告・security-reviewer の起動)・`raw/<case>-t<trial>.meta.md`・`raw/mix-<case>.tsv` (M の ID → planted の ID) だけ。シード欠陥ごとに指摘と意味的に照合する (キーの「一致判定基準」に従う。文言の一致ではなく、同じ問題を同じ場所に指摘しているかで判定)。

**3. 指標の算出** — 検出率・深刻度一致・デコイ誤検出は、偽指摘を含めずに算出する。定義:

| 指標 | 定義 |
|---|---|
| コア検出率 | **コアシード** (ケース作成時の意図的シード。キーに「コアシード」と明記されたもの) のうち arbiter の最終報告に残った割合。**バージョン間比較はこの指標のみで行う** (キーは評価のたびに昇格で成長するため、全キー分母では分母が動き比較できない) |
| 拡張検出率 | コアシード + 昇格シードの全体での検出割合 (参考値。分母が版によって異なることを併記する) |
| 反証誤棄却 | reviewer が検出したが refuter に棄却されたシード欠陥の数 (refuter の false refutation) |
| 深刻度一致 | 最終報告に残ったシード欠陥のうち、深刻度がキーの期待値と一致した割合 |
| デコイ誤検出 | キーがデコイと定義した論点を最終報告で指摘した数 (読了プロトコルの検証) |
| セキュリティ条件起動 | security ケースで Agent 6 が自動起動したか (yes/no) |
| 偽指摘の棄却率 | 偽指摘のうち、refuter が反証成立とし、かつ根拠がキーの「偽指摘」節の根拠と一致した割合。反証成立でも根拠が一致しないものは「根拠不一致」として件数を別に記す |
| refuter のコスト | ケースごとの refuter のトークン (meta の agent 別の `total_tokens`) |
| 総トークン | ケースごとの、起動した全エージェント (reviewer・security-reviewer・refuter・arbiter) のトークンの合計 (meta の agent 別の `total_tokens`。実行担当自身の分は含めない) |
| パイプラインのコスト | 試行ごとの実行担当のセッション全体のコスト (meta の `total_cost_usd` とモデル別の使用量。実行担当自身と agent の分を含む) |
| 採点のコスト | 判定エージェント2体のトークン (完了通知の `subagent_tokens`)。メイン自身の採点の分は取れなければ「不明」 |
| 最終報告の指摘件数 | arbiter の最終報告の指摘件数 (high/mid/low 別) |
| ノイズ率 | 最終報告の指摘のうち、手順4で「判断保留」または「誤検出」とされたものの割合。シード検出と「正当」の割合も併記する |

**4. キー外指摘の分類** — 本文と照らせば確かめられる判定は判定エージェントに任せ、ユーザーは判定が割れたものと誤検出だけを確認する。

1. メインが2つの一覧を作る: (a) 最終報告にあるがキーにない指摘、(b) refuter が棄却したキー外の reviewer 指摘 (偽指摘を除く)
2. 判定エージェントを2体、1つのメッセージで並列に起動する (`general-purpose`、`model: "opus"` を明示)。渡すのは対象ケースのパス (run ディレクトリの `input/cases/<ケース名>.md`) と一覧の指摘 (深刻度・引用箇所・指摘・代案) だけで、キーは渡さず、`tests/eval/keys/` と `tests/eval/planted/` を開かないよう明示する。各指摘を次の基準で分類させる:
   - **誤検出**: 引用した行と主張が矛盾している、または本文に根拠がない。根拠となる本文の行を引用させる。引用のない判定は無効とし、判定が割れたものとして扱う
   - **判断保留**: 同じ種類のどの設計書にもそのまま言える一般論で、この本文に固有の根拠がない
   - **正当**: 上のどちらにも当たらない
3. 2体の判定が一致したものは、そのまま採用する。判定が割れたものと、誤検出と判定されたものだけを AskUserQuestion でユーザーに確認する (件数が多ければケースごとに1問にまとめる)
4. (b) は、誤検出と確定したものを「正しい棄却」、それ以外を「誤った棄却」とする
5. 「正当」と確定した (a) の指摘は、キーへの昇格の候補として AskUserQuestion (multiSelect) で示す。選ばれた指摘は該当キーのシード欠陥表への追記案を提示し、承認後に「昇格シード (昇格日付き)」と明記して追記する (コアシードとは区別する。コア検出率の分母を凍結するため)

誤検出数・誤った棄却の数・ノイズ率・判定エージェント2体のトークンを結果に記録する。

**5. 結果の保存** — `tests/eval/results/YYYY-MM-DD.md` に保存する (日付は `date +%F`。同日再実行時は `-2` 等の連番を付ける)。ディレクトリがなければ作成する。結果ファイルの名前から `.md` を除いたものを run-id とし、`raw/` を `tests/eval/results/<run-id>/` にコピーして、そこで `shasum -a 256 -c SHA256SUMS` が通ること、SHA256SUMS の sha256 が手順1cで記録した値と同じことを確かめる。コミットするのは実行担当の最終回答・meta・プロンプト・M の ID の対応・ハッシュ・測定条件 (`raw/` の中身) で、stream-json の全文はコミットしない (`local/` は絶対パスや環境の情報を含むので手元にだけ置く。ハッシュは `local.sha256` に残る)。取れない値は「不明」と書き、実測していないモデル名・provider・試行数・コストを断定しない。記載内容:

- 測定条件の表:
  - aidd version・git SHA・未コミット変更の有無・CLI の版 (`raw/conditions.md` と meta の init)・実行担当の起動コマンド・permissionMode・読み込まれたプラグイン
  - 実測したモデル (meta のモデル別の表のモデル名・provider・costBasis) と、agent 定義の frontmatter にあるモデルを別の列に書く
  - 対象ケース・試行数・試行ごとの session_id・所要時間・ターン数・成否
  - 識別子: 手順1cで記録した SHA256SUMS の sha256、ケース・plugin のハッシュ (`input.sha256`)、planted (`planted.sha256`)、プロンプト (`prompt-<ケース>.md` のハッシュ)、採点時のキー (`keys.sha256`)。手順4でキーに昇格を追記したら、昇格後のキーの sha256 を別に書く
  - 生出力の場所 (`tests/eval/results/<run-id>/`)
- 分離の記録: 準備と照合の結果、試行ごとの meta の判定 (汚染の疑いと不明の項目)、「分離の限界」の要約 (作業ディレクトリの外の読み取りは権限で禁止していない、Bash は検出しきれない、抽出から凍結までは書き換えられる)
- コストの表: パイプラインと採点のコストを分け、評価全体の合計も示す。列はトークンと USD に分ける。パイプラインはケース・試行ごとのトークン (モデル別の使用量の合計) と `total_cost_usd`、採点は判定エージェント2体のトークン (USD は不明) とメインの分 (取れなければ両方「不明」)。合計の行は、列ごとに既知の分の合計と、不明の項目名を書く (例: 「1,234,567 + 不明: メインの採点」)
- ケース別テーブル: シード欠陥ごとの 検出/未検出/反証誤棄却、深刻度の期待値と実際
- 指標サマリ (上記の指標)
- キー外指摘とその分類結果。判定エージェント2体が一致して確定したものと、ユーザーが確認したものを区別して書く
- 偽指摘の判定表 (元の ID、判定、refuter の根拠、キーとの一致)
- `tests/eval/results/` に過去の結果ファイルがあれば、直近1件と指標サマリを比較する表を付ける

**6. 報告** — 指標サマリ・コストの表・前回比較を提示する。検出率の低下・反証誤棄却の増加があれば、どの段 (reviewer / refuter / arbiter) で失われたかを生出力から特定して1行で付記する。汚染の疑いがある試行や失敗した試行があれば、それも書く。

refuter について次の目安を付記する。偽指摘の棄却率が高く、かつ誤った棄却 (反証誤棄却とキー外の誤った棄却の合計) が0件なら、refuter は機能している。偽指摘をほとんど落とせないなら、refuter は判子を押すだけになっており、削減を検討する。いずれも1標本なので、変更を判断する前に再実行して再現を確かめる。

## 実装レビューの比較 (同種・異種)

`/aidd:eval impl [ケース名]` で行う。autonomous-review の主レビューを、同じ実装差分・同じ固定プロンプト・同じ JSON 契約・同じ正解キーで、新しい文脈の同種モデル (`claude -p`) と異種モデル (`codex exec`) に複数回行わせ、シード欠陥の検出・誤検出・危険な変更への判定・コストを比べる。素材は `tests/eval/impl/` (`cases/<ケース>/` に変更前のファイル `before/`・差分 `change.patch`・変更目的と不変条件と懸念点 `brief.md`、`keys/<ケース>.md` に正解キー、`rubric.md` に採点基準)。design-review の `tests/eval/cases/` とは別のケースで、欠陥の無い対照の差分も含む。

- 分離は上の「分離と汚染ガード」と同じ考え方で、手順1b の抽出・1c の凍結・2 の照合のブロックをそのまま使う。偽指摘は使わない。「分離の限界」もそのまま当てはまる
- **この評価は autonomous-review の適格条件を緩めない**。結果から作るのは `rubric.md` の規則による提案だけで、適格条件を変えるかは人が決める
- 試行は、各ケース・各方式で3試行以上。試行数を減らさない。実測していないモデル名・provider・コストを断定しない

**I1. ケースの確認と凍結 (ユーザー)** — 初めて実行する前と、`tests/eval/impl/` のケース・キー・`rubric.md`、下の固定プロンプトか I2 の準備のブロックを変えたときに行う。本実行とは別のセッションで行う (凍結の後に本実行のセッションを始める)。

1. 各ケースの `brief.md`・`change.patch`・キーと `rubric.md` をユーザーに示し、確認を AskUserQuestion で求める。直す点があれば直してから示し直す
2. 承認されたら、次のブロックの `<repo>` を置き換えて実行する。`tests/eval/impl/freeze.sha256` (ケース・キー・`rubric.md` のハッシュと、固定プロンプトと I2 の準備のブロック (プロンプトの組み立て方) のハッシュ) を書き、その sha256 を表示する。既にあれば止まる。作り直すのは、ユーザーが新しい版を承認したときだけで、そのときはユーザーが古いファイルを消す
3. ユーザーが `freeze.sha256` をコミットする。準備 (I2) は、`freeze.sha256` がコミットされていない、今のファイルと一致しない、`tests/eval/impl/` か `skills/eval/SKILL.md` に未コミットの変更がある、のどれかなら止まる。凍結したコミットは結果に書く

```bash
# eval impl freeze-cases: after the user approved the cases, keys and rubric, write tests/eval/impl/freeze.sha256
repo='<repo>'
set -euo pipefail
fail() { echo "eval impl freeze-cases: $*" >&2; exit 1; }
impl="$repo/tests/eval/impl"
[ -d "$impl/cases" ] && [ -d "$impl/keys" ] && [ -f "$impl/rubric.md" ] || fail "no cases, keys or rubric.md"
[ ! -e "$impl/freeze.sha256" ] || fail "freeze.sha256 already exists; only the user removes it, after approving a new version"
for d in "$impl"/cases/*/; do
  c=$(basename "$d")
  case "$c" in *[!abcdefghijklmnopqrstuvwxyz0123456789-]*) fail "bad case name: $c" ;; esac
  [ -d "$d/before" ] && [ -f "$d/change.patch" ] && [ -f "$d/brief.md" ] && [ -f "$impl/keys/$c.md" ] || fail "case $c lacks before/, change.patch, brief.md or its key"
done
if [ -n "$(find "$impl/cases" "$impl/keys" ! -type f ! -type d)" ]; then fail "a symbolic link or a special file under cases/ or keys/"; fi
prompt=$(sed -n '/^# eval impl prompt$/,/^# end eval impl prompt$/p' "$repo/skills/eval/SKILL.md" | shasum -a 256 | awk '{print $1}')
staging=$(sed -n '/^# eval impl staging:/,/^# end eval impl staging$/p' "$repo/skills/eval/SKILL.md" | shasum -a 256 | awk '{print $1}')
(cd "$impl" && { find cases keys rubric.md -type f | LC_ALL=C sort | while read -r f; do shasum -a 256 "$f"; done
  printf '%s  %s\n' "$prompt" prompt "$staging" staging; }) > "$impl/freeze.sha256.tmp"
mv "$impl/freeze.sha256.tmp" "$impl/freeze.sha256"
echo "eval impl freeze-cases: freeze.sha256 sha256 $(shasum -a 256 "$impl/freeze.sha256" | awk '{print $1}')"
# end eval impl freeze-cases
```

**I2. 準備 (メイン)** — ケースごとに新しい run ディレクトリを作り (`mktemp -d "${TMPDIR:-/tmp}/aidd-eval-impl.XXXXXX"` など。ケースの間で `input/` を共有しない)、次のブロックの `<repo>`・`<run>`・`<case>` を置き換えて実行する。同種と異種は同じ run の同じ `input/` と同じプロンプトでレビューする。

ブロックがすること: 凍結を確かめ、`input/` に `before/` をコピーして `change.patch` を当てる (変更後のスナップショット。Git の履歴なし)。次のどれかに当たれば止まる。

- ケース名が英小文字・数字・`-` 以外を含む、ケースかキーが無い、凍結 (I1 の 3) が確かめられない
- run ディレクトリが元リポジトリの中にある、`input/` か `raw/` が既にある、`input/` がどこかの Git の作業ツリーの中にある、`change.patch` が当たらない
- `input/` に `before/` と差分の対象以外のファイル・シンボリックリンク・名前が `.git`・`keys`・`results` のものがある、内容が `tests/eval/keys/`・`tests/eval/results/`・`tests/eval/impl/keys/`・`rubric.md` のどれかと同じ
- `input/` かプロンプトに元リポジトリの絶対パス・`tests/eval/`・`シード`・`デコイ`・`正解キー` がある

`raw/` には、固定プロンプトの後に `brief.md` と差分を付けたもの (`prompt-<case>.md`)・入力のハッシュ (`input.sha256`)・キーと採点基準のハッシュ (`keys.sha256`)・凍結のマニフェストの写し (`freeze.sha256`)・測定条件 (`conditions.md`) を書く。

```bash
# eval impl staging: copy one frozen case into <run>/input, apply its change, and write the prompt and hashes into <run>/raw
repo='<repo>'; run='<run>'; case='<case>'
set -euo pipefail
fail() { echo "eval impl staging: $*" >&2; exit 1; }
case "$case" in ''|*[!abcdefghijklmnopqrstuvwxyz0123456789-]*) fail "bad case name: $case" ;; esac
repo_given=$repo
repo=$(cd "$repo" && pwd -P); run=$(cd "$run" && pwd -P)
case "$run/" in "$repo/"*) fail "the run directory is inside the repository" ;; esac
in="$run/input"; raw="$run/raw"; impl="$repo/tests/eval/impl"; src="$impl/cases/$case"
if [ -e "$in" ] || [ -e "$raw" ]; then fail "input/ or raw/ already exists in $run"; fi
[ -d "$src/before" ] && [ -f "$src/change.patch" ] && [ -f "$src/brief.md" ] && [ -f "$impl/keys/$case.md" ] || fail "no case or key for $case"
[ -f "$impl/freeze.sha256" ] || fail "the cases are not frozen (no tests/eval/impl/freeze.sha256)"
prompt_sha=$(sed -n '/^# eval impl prompt$/,/^# end eval impl prompt$/p' "$repo/skills/eval/SKILL.md" | shasum -a 256 | awk '{print $1}')
staging_sha=$(sed -n '/^# eval impl staging:/,/^# end eval impl staging$/p' "$repo/skills/eval/SKILL.md" | shasum -a 256 | awk '{print $1}')
(cd "$impl" && { find cases keys rubric.md -type f | LC_ALL=C sort | while read -r f; do shasum -a 256 "$f"; done
  printf '%s  %s\n' "$prompt_sha" prompt "$staging_sha" staging; }) > "$run/manifest"
cmp -s "$run/manifest" "$impl/freeze.sha256" || fail "the cases, keys, rubric, prompt or staging block differ from freeze.sha256"
git -C "$repo" ls-files --error-unmatch tests/eval/impl/freeze.sha256 > /dev/null 2>&1 || fail "freeze.sha256 is not committed"
[ -z "$(git -C "$repo" status --porcelain -- tests/eval/impl skills/eval/SKILL.md)" ] || fail "tests/eval/impl or skills/eval/SKILL.md has uncommitted changes"
if [ -n "$(find "$src" ! -type f ! -type d)" ]; then fail "the case has a symbolic link or a special file"; fi
mkdir -p "$in" "$raw" "$run/local"
if env -u GIT_DIR -u GIT_WORK_TREE git -C "$in" rev-parse --git-dir > /dev/null 2>&1; then fail "input is inside a git work tree"; fi
cp -R "$src/before/." "$in/"
(cd "$in" && env -u GIT_DIR -u GIT_WORK_TREE git apply --whitespace=nowarn "$src/change.patch") || fail "change.patch does not apply to before/"
if [ -n "$(find "$in" \( -iname .git -o -iname keys -o -iname results \))" ]; then fail "input has a .git, keys or results entry"; fi
if [ -n "$(find "$in" ! -type f ! -type d)" ]; then fail "input has a symbolic link or a special file"; fi
{ (cd "$src/before" && find . -type f | sed 's|^\./||'); sed -n 's|^+++ b/||p' "$src/change.patch"; } | LC_ALL=C sort -u > "$run/expected"
(cd "$in" && find . -type f | sed 's|^\./||' | LC_ALL=C sort) > "$run/found"
[ -z "$(comm -23 "$run/found" "$run/expected")" ] || fail "input holds files outside before/ and the change"
(cd "$repo/tests/eval" && { for d in keys results impl/keys; do if [ -d "$d" ]; then find "$d" -type f -size +0; fi; done; echo impl/rubric.md; } \
  | while read -r f; do shasum -a 256 "$f"; done) | awk '{print $1}' | LC_ALL=C sort -u > "$run/forbidden"
(cd "$in" && find . -type f | while read -r f; do shasum -a 256 "$f"; done) | awk '{print $1}' | LC_ALL=C sort -u > "$run/inhash"
if [ -n "$(comm -12 "$run/forbidden" "$run/inhash")" ]; then fail "input has the same content as a key, a result or the rubric"; fi
prompt="$raw/prompt-$case.md"
sed -n '/^# eval impl prompt$/,/^# end eval impl prompt$/p' "$repo/skills/eval/SKILL.md" | sed '1d;$d' > "$prompt"
[ -s "$prompt" ] || fail "skills/eval/SKILL.md has no impl prompt"
{ printf '\n'; cat "$src/brief.md"; printf '\n## 差分\n\n```diff\n'; cat "$src/change.patch"; printf '```\n'; } >> "$prompt"
case "$repo_given" in /*) ;; *) repo_given=$repo ;; esac
if grep -rqiF -e "$repo" -e "$repo_given" "$in" "$raw"; then fail "the repository path appears in the input or the prompt"; fi
if grep -rqF -e 'tests/eval/' -e 'シード' -e 'デコイ' -e '正解キー' "$in" "$prompt"; then fail "the input or the prompt names the eval assets or the answers"; fi
(cd "$in" && find . -type f | LC_ALL=C sort | while read -r f; do shasum -a 256 "$f"; done) > "$raw/input.sha256"
(cd "$repo/tests/eval" && shasum -a 256 "impl/keys/$case.md" impl/rubric.md) > "$raw/keys.sha256"
cp "$impl/freeze.sha256" "$raw/freeze.sha256"
version=$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' "$repo/.claude-plugin/plugin.json" 2>/dev/null) || version=不明
sha=$(git -C "$repo" rev-parse HEAD 2>/dev/null) || sha=不明
frozen=$(git -C "$repo" log -1 --format=%H -- tests/eval/impl/freeze.sha256 2>/dev/null) || frozen=
if status=$(git -C "$repo" status --porcelain 2>/dev/null); then
  if [ -n "$status" ]; then dirty=yes; else dirty=no; fi
else
  dirty=不明
fi
cli=$(claude --version 2>/dev/null < /dev/null) || cli=
codex_cli=$(codex --version 2>/dev/null < /dev/null) || codex_cli=
{
  printf '| 項目 | 値 |\n|---|---|\n'
  printf '| aidd version | %s |\n' "$version"
  printf '| git SHA | %s |\n' "$sha"
  printf '| 未コミット変更 | %s |\n' "$dirty"
  printf '| 凍結したコミット | %s |\n' "${frozen:-不明}"
  printf '| freeze.sha256 の sha256 | %s |\n' "$(shasum -a 256 "$impl/freeze.sha256" | awk '{print $1}')"
  printf '| claude CLI (準備時) | %s |\n' "${cli:-不明}"
  printf '| codex CLI (準備時) | %s |\n' "${codex_cli:-不明}"
  printf '| 対象ケース | %s |\n' "$case"
  printf '| 準備日時 (UTC) | %s |\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$raw/conditions.md"
rm -f "$run/manifest" "$run/expected" "$run/found" "$run/forbidden" "$run/inhash"
echo "eval impl staging: ok ($run)"
# end eval impl staging
```

レビュー担当の固定プロンプト (上のブロックが先頭と末尾の行を除き、後ろに `brief.md` と差分を付けて `raw/prompt-<case>.md` に書く。ここを変えたら I1 の凍結からやり直す):

```text
# eval impl prompt
あなたはコードレビューの担当です。作業ディレクトリは、下の差分を当てた後のリポジトリのスナップショットです (Git の履歴はありません)。下の「変更目的」「守る不変条件」「具体的な懸念点」と差分を読み、この差分が持ち込む問題を指摘してください。

- 作業ディレクトリの中のファイルだけを読む。親ディレクトリや作業ディレクトリの外の絶対パスを開かない
- ファイルを変更しない。ユーザーには質問しない (答えは返らない)
- 最終回答は次の JSON オブジェクトだけにする (Markdown のコードフェンスや前後の説明を付けない)。`file` は作業ディレクトリからの相対パス、`line` は変更後のファイルの行番号。問題が無ければ `findings` を空の配列にし、`verdict` を `approved` にする
- `severity` の目安: `blocker` はマージすると壊れる・危険、`major` はマージ前に直すべき欠陥、`minor` は直すとよい点、`nit` は好みの問題

{
  "verdict": "approved" | "changes_requested",
  "findings": [
    {
      "id": "R1",
      "severity": "blocker" | "major" | "minor" | "nit",
      "file": "relative/path",
      "line": 123,
      "title": "短い表題",
      "claim": "何が問題か",
      "evidence": "コード、仕様、テストに基づく根拠",
      "verification": "確認手順"
    }
  ]
}
# end eval impl prompt
```

**I3. 実行 (新しいセッション)** — 試行ごとに、同種と異種を交互に1回ずつ起動する (`<trial>` は 1 から。同種の t1 → 異種の t1 → 同種の t2 → …)。どちらも1回ずつ新しいセッションで、前の試行の文脈を持ち越さない。課金のある実行なので、ユーザーが推定コストを見て承認してから始める。

```bash
cd "<run>/input" && claude -p --output-format stream-json --verbose --tools Read,Grep,Glob --no-session-persistence --max-budget-usd <budget> < "<run>/raw/prompt-<case>.md" > "<run>/local/<case>-claude-t<trial>.jsonl"
cd "<run>/input" && codex exec --sandbox read-only --skip-git-repo-check --ephemeral --json -C "<run>/input" -o "<run>/local/<case>-codex-t<trial>.last.txt" "$(cat "<run>/raw/prompt-<case>.md")" < /dev/null > "<run>/local/<case>-codex-t<trial>.jsonl" 2> "<run>/local/<case>-codex-t<trial>.stderr.txt"
```

- 同種: `--tools Read,Grep,Glob` でファイルの読み取りだけにする (書き込み・コマンドの実行はできない)。`<budget>` は1試行の USD の上限で、ユーザーが承認した値にする。上限で止まった試行は失敗として記録する
- 異種: autonomous-review の主レビューと同じく `--sandbox read-only --skip-git-repo-check -C <スナップショット>` で起動し、stdin を閉じ、`-o` の最終メッセージだけを最終回答とする。起動の確認と時間の上限 (Bash の `timeout` 600000ms) も autonomous-review のとおり。`--json` と `--ephemeral` は記録のために足したもので、レビューの中身には関わらない
- どちらも利用者の設定をそのまま読み込む。そろえきれない条件 (異種は読み取り専用のコマンドを実行でき、読み取りは作業ディレクトリの外にも届く。同種はコマンドを実行できない) は `rubric.md` のとおり結果に書く

実行のたびに記録を取り出す。同種は手順1b の `# eval extract:` のブロックを、`<case>` を `<case>-claude` に置き換えて使う (`input/plugin/` が無いので、aidd のプラグインの検査はせず、読み込まれたプラグインの一覧だけを記録する)。異種は次のブロックを使う。`raw/<case>-codex-t<trial>.md` に `-o` の最終メッセージを、`.meta.md` に thread_id・終了の状態・トークン・実行したコマンドとその判定を書く。絶対パスは、存在するパスだけを作業ディレクトリの外として数える (`sed` のアドレス `/def f/` のような、パスに見える文字列を数えないため。存在しないパスの読み取りは何も読めていない)。codex の `--json` の形式 (`thread.started`・`turn.completed` の `usage`・`item.completed` の `command_execution`) は codex-cli 0.163.0 で実測していない。取れなかった値は「不明」になるので、成功扱いにも0扱いにもしない。モデル名は event に無ければ「不明」と書く。

```bash
# eval codex extract: <run>/local/<case>-codex-t<trial>.{jsonl,last.txt} -> <run>/raw/<case>-codex-t<trial>.md and .meta.md
python3 -I - '<run>' '<case>' '<trial>' '<repo>' <<'PY'
import json, os, re, sys

run_arg, case, trial, repo_arg = sys.argv[1:5]
if not re.fullmatch(r"[a-z0-9-]+", case) or not re.fullmatch(r"[0-9]+", trial):
    sys.exit(f"eval codex extract: bad case or trial: {case!r} {trial!r}")
run, repo = os.path.realpath(run_arg), os.path.realpath(repo_arg)
staged = os.path.join(run, "input")
stem = f"{case}-codex-t{trial}"
local = os.path.join(run, "local")
subs = sorted({(staged, "[input]"), (os.path.join(run_arg, "input"), "[input]"), (run, "[run]"), (run_arg, "[run]"),
               (repo, "[repo]"), (repo_arg, "[repo]"), (os.path.expanduser("~"), "~")}, key=lambda s: -len(s[0]))
system_dirs = ("/bin/", "/usr/", "/opt/homebrew/", "/dev/null")


def clean(value):
    text = str(value)
    for path, name in subs:
        if len(path) > 1:
            text = re.sub(re.escape(path), lambda _: name, text, flags=re.IGNORECASE)
    return text


def cell(value):
    return "不明" if value is None or value == "" else clean(value).replace("|", "\\|").replace("\n", " ")


def read(name):
    try:
        with open(os.path.join(local, name), encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


events = []
for line in (read(stem + ".jsonl") or "").splitlines():
    try:
        m = json.loads(line)
    except ValueError:
        continue
    if isinstance(m, dict):
        events.append(m)
thread = model = None
usage, turns, errors, commands, refs = {}, 0, [], [], []
for m in events:
    kind = m.get("type")
    if kind == "thread.started":
        thread = m.get("thread_id")
    elif kind == "turn.completed":
        turns += 1
        u = m.get("usage") if isinstance(m.get("usage"), dict) else {}
        for k, v in u.items():
            if isinstance(v, int) and not isinstance(v, bool):
                usage[k] = usage.get(k, 0) + v
    elif kind in ("turn.failed", "error"):
        errors.append(json.dumps(m, ensure_ascii=False)[:300])
    if isinstance(m.get("model"), str):
        model = m["model"]
    item = m.get("item") if isinstance(m.get("item"), dict) else {}
    if kind == "item.completed" and item.get("type") in ("command_execution", "file_change"):
        text = item.get("command") if item.get("type") == "command_execution" else json.dumps(item, ensure_ascii=False)
        text = str(text)
        commands.append((item.get("type"), text))
        folded = text.casefold()
        reasons = []
        if item.get("type") == "file_change":
            reasons.append("ファイルの変更")
        if repo.casefold() in folded or repo_arg.casefold() in folded:
            reasons.append("元リポジトリのパス")
        if any(k in folded for k in ("tests/eval/keys", "tests/eval/results", "tests/eval/impl/keys", "tests/eval/impl/rubric")):
            reasons.append("keys・results")
        if any(os.path.join(p, d).casefold() in folded for p in (run, run_arg) for d in ("raw", "local")):
            reasons.append("run の raw・local")
        if "../" in text or re.search(r"(^|[\s'\"=])~", text):
            reasons.append("作業ディレクトリの外 (相対・~)")
        for p in re.findall(r"(?:^|[\s'\"=<>])(/[^\s'\";|&<>]+)", text):
            real = os.path.realpath(p).casefold()
            if os.path.exists(p) and not p.startswith(system_dirs) and real != staged.casefold() \
                    and not real.startswith(staged.casefold() + os.sep):
                reasons.append("作業ディレクトリの外 (絶対パス)")
        if reasons:
            refs.append(("・".join(dict.fromkeys(reasons)), text))

last = read(stem + ".last.txt")
ok = bool(last and last.strip())
suspect = [f"作業ディレクトリの外・元リポジトリ・keys・results への参照かファイルの変更 {len(refs)} 件"] if refs else []
verdict = ("汚染の疑い: " + " / ".join(suspect)) if suspect else "検出なし (--json に残ったコマンドに限る)"
if not events:
    verdict += " / 不明: --json の記録が無く、コマンドの検査は不明"
rows = [
    ("thread_id", thread),
    ("モデル (event)", model),
    ("終了", f"turn.completed {turns} 回 / エラー {len(errors)} 件" if events else None),
    ("エラー", " / ".join(errors) if errors else ("なし" if events else None)),
    ("トークン (turn.completed の usage の合計)", "; ".join(f"{k}={v}" for k, v in usage.items()) if usage else None),
    ("USD", None),
    ("実行したコマンド・ファイルの変更", len(commands) if events else None),
    ("判定", verdict),
]
out = [f"# 異種のレビューの記録: {case} 試行 {trial}", "", "| 項目 | 値 |", "|---|---|"]
out += [f"| {k} | {cell(v)} |" for k, v in rows]
out += ["", "## 実行したコマンド・ファイルの変更 (item.completed)", ""]
if commands:
    out += ["| 種類 | 内容 |", "|---|---|"] + [f"| {cell(t)} | {cell(c[:300])} |" for t, c in commands]
else:
    out.append("なし" if events else "不明")
out += ["", "## 作業ディレクトリの外・元リポジトリ・keys・results への参照かファイルの変更", ""]
if refs:
    out += ["| 理由 | 内容 |", "|---|---|"] + [f"| {cell(why)} | {cell(c[:300])} |" for why, c in refs]
else:
    out.append("なし")
raw = os.path.join(run, "raw")
with open(os.path.join(raw, stem + ".meta.md"), "x", encoding="utf-8") as f:
    f.write("\n".join(out) + "\n")
with open(os.path.join(raw, stem + ".md"), "x", encoding="utf-8") as f:
    f.write(clean(last).rstrip("\n") + "\n" if ok else "実行担当の最終回答なし (失敗した試行)\n")
print(f"eval codex extract: {stem}: {verdict}")
if not ok:
    print(f"eval codex extract: {stem}: no last message (-o) was written", file=sys.stderr)
    sys.exit(1)
PY
```

**I4. 凍結と照合 (メイン)** — ケースごとに、そのケースの全試行の実行と抽出が終わったら、手順1c の `# eval freeze:` のブロックで run を凍結し、表示された SHA256SUMS の sha256 を採点の前にユーザーへの途中報告と結果に書く。手順2 の `# eval verify:` のブロックで照合する (キーと `rubric.md` の照合を含む)。照合が通るまで `tests/eval/impl/keys/`・`rubric.md`・過去の結果を読まない。

**I5. 採点 (メイン)** — 照合の後、次のブロックで各試行の最終回答を JSON 契約に照らし、指摘ごとに `file`・`line` が `input/` にあるかを確かめる (読むだけで、run を書き換えない)。そのあと `rubric.md` とキーを読み、`rubric.md` の基準で採点する。キー外の blocker / major は手順4と同じく判定エージェント2体で分類する (渡す対象は run の `input/` の該当ファイル。キー・`rubric.md`・`tests/eval/impl/` を開かないよう明示する)。

```bash
# eval impl parse: check every final answer in <run>/raw against the JSON contract and the snapshot in <run>/input
python3 -I - '<run>' <<'PY'
import json, os, re, sys

run = os.path.realpath(sys.argv[1])
raw, staged = os.path.join(run, "raw"), os.path.join(run, "input")
SEVERITY = ("blocker", "major", "minor", "nit")
FIELDS = ("id", "severity", "file", "line", "title", "claim", "evidence", "verification")


def contract(text):
    try:
        data = json.loads(text)
    except ValueError:
        fenced = re.fullmatch(r"```[a-z]*\n(.*)\n```", text, re.S)
        try:
            json.loads(fenced.group(1)) if fenced else None
        except ValueError:
            fenced = None
        return None, "コードフェンス付き" if fenced else "JSON ではない"
    if not isinstance(data, dict) or data.get("verdict") not in ("approved", "changes_requested") \
            or not isinstance(data.get("findings"), list):
        return None, "verdict か findings が契約と違う"
    for f in data["findings"]:
        if not isinstance(f, dict) or any(k not in f for k in FIELDS) or f["severity"] not in SEVERITY \
                or not isinstance(f["file"], str) or isinstance(f["line"], bool) or not isinstance(f["line"], int):
            return None, "指摘の項目が契約と違う"
    return data, None


def valid(f):
    path = os.path.realpath(os.path.join(staged, f["file"]))
    if not path.startswith(staged + os.sep) or not os.path.isfile(path):
        return False
    with open(path, encoding="utf-8", errors="replace") as fh:
        return 1 <= f["line"] <= len(fh.read().splitlines())


def tsv(*values):
    print("\t".join(str(v).replace("\t", " ").replace("\n", " ") for v in values))


trials, findings = [], []
for name in sorted(os.listdir(raw)):
    m = re.fullmatch(r"([a-z0-9-]+)-(claude|codex)-t([0-9]+)\.md", name)
    if not m:
        continue
    with open(os.path.join(raw, name), encoding="utf-8") as fh:
        text = fh.read().strip()
    if text.startswith("実行担当の最終回答なし"):
        trials.append((name[:-3], "失敗した試行", "", "", "", "", "", ""))
        continue
    data, why = contract(text)
    if data is None:
        trials.append((name[:-3], "契約違反: " + why, "", "", "", "", "", ""))
        continue
    count = {s: 0 for s in SEVERITY}
    invalid = 0
    for f in data["findings"]:
        ok = valid(f)
        invalid += not ok
        count[f["severity"]] += ok
        findings.append((name[:-3], f["id"], f["severity"], f"{f['file']}:{f['line']}", "有効" if ok else "無効", f["title"]))
    trials.append((name[:-3], "契約どおり", data["verdict"], *(count[s] for s in SEVERITY), invalid))
tsv("trial", "contract", "verdict", *SEVERITY, "invalid")
for row in trials:
    tsv(*row)
print()
tsv("trial", "id", "severity", "file:line", "valid", "title")
for row in findings:
    tsv(*row)
PY
```

**I6. 結果の保存** — `tests/eval/results/YYYY-MM-DD-impl.md` に保存する (同日に再実行したら `-2` などの連番)。各ケースの run の `raw/` を `tests/eval/results/<run-id>/<case>/` にコピーし、そこで `shasum -a 256 -c SHA256SUMS` が通ること、SHA256SUMS の sha256 が I4 で記録した値と同じことを確かめる。`local/` (stream-json・`--json`・stderr の全文) はコミットしない。記載内容:

- 測定条件の表: 手順5の項目 (aidd version・git SHA・未コミット変更・CLI の版・起動コマンド・実測したモデルと provider・試行ごとの session_id か thread_id・所要時間・成否) に加え、凍結したコミット・`freeze.sha256` の sha256・ケースごとの SHA256SUMS の sha256・`<budget>`
- `rubric.md` の指標を方式ごと・ケースごと・試行ごとに書いた表と、3試行の最小〜最大。失敗した試行・契約違反・無効な指摘も消さずに書く
- 異種が同種より良かった結果と悪かった結果の両方 (異種だけが検出・異種だけが誤検出、など)
- `rubric.md` の規則で作った提案 (同種で許容できる範囲の候補・人の判断に残す範囲) と、提案が当てはまる条件 (実測したモデル・版・この5ケース・この固定プロンプト)
- 未測定の項目とそろえきれなかった条件
- コストの表: 同種・異種・採点を分け、評価全体の合計も示す。列はトークンと USD に分け、合計の行は既知の分の合計と不明の項目名を書く

**I7. 報告** — 指標の表・提案・コストの表・未測定の項目を示す。提案は適格条件の変更ではないことを添える。

## design-review の構成比較 (deep・standard・直接・単体モデル)

`/aidd:eval compare [ケース名]` で行う。同じケース (`tests/eval/cases/`) と同じ正解キー (`tests/eval/keys/`) で、design-review の構成と単体モデルを比べ、シード欠陥の検出・安全上重要な見逃し・誤検出・ノイズ・待ち時間・総費用を記録する。実行担当のメインのモデルは、全構成で同じ `--model <model>` に固定する (agent のモデルは agent 定義の frontmatter のまま)。

| 構成 | 内容 | 対象 |
|---|---|---|
| `deep` | `--depth=deep`。小規模対象ショートカットを使わず、並列 dispatch → refuter → arbiter | 全ケース |
| `standard` | 既定の `--depth=standard`。小規模対象ショートカットを使わず並列 dispatch し、refuter・arbiter は design-review の standard の条件に従う | 全ケース |
| `direct` | `--depth=standard` の小規模対象ショートカット (reviewer を dispatch せず、メインが直接レビューする。Agent 6 の起動条件に当たれば Agent 6 だけは dispatch する) | 100行未満のケースだけ (今は structure・data-error・security)。100行以上は「対象外」として記録する |
| `baseline` | aidd を使わない単体モデル。`2026-11-07-baseline.md`・`2026-11-22-crosscut-comparison.md` と同じ文言のプロンプトに行番号付きの本文を埋め込み、ツールなし (`--tools ""`) で答えさせる | 全ケース |

- **既存の deep 回帰評価 (手順1〜6) を置き換えない**。運用ルール6の評価は今までどおり手順1〜6で行う。この比較は偽指摘を混ぜない (構成の間で refuter の起動条件と費用をそろえるため) ので、偽指摘の棄却率は測らず、費用は手順1〜6の結果と直接比べない
- **比較の結果だけで構成を削除しない**。結果から作るのは C5 の規則による提案だけで、design-review の既定や構成を変えるかは人が決める
- 試行は、各ケース・各構成で3試行以上。試行数を減らさない。実測していないモデル名・provider・コストを断定しない
- 例外は**予備測定**だけ: ユーザーが推定コストを見て試行数を減らすことを承認した場合に限り、各構成3試行未満で行える。予備測定では C5 の提案を出さず (試行のばらつきを測れないため、「既定を維持」とも「軽量化してよい候補」とも書かない)、結果は `tests/eval/results/YYYY-MM-DD-compare-prelim.md` に保存し、冒頭に予備測定であることと試行数を書く。手順 C1〜C4・C6 の残りと C7 はそのまま行う
- 比較からはキーへ昇格しない (昇格すると構成の間で分母が動くため)。キー外の正当な指摘を昇格するかは、手順1〜6の評価で扱う
- 分離は「分離と汚染ガード」と同じ。手順1a の準備・1b の抽出・1c の凍結・2 の照合のブロックをそのまま使い、「分離の限界」もそのまま当てはまる

**安全上重要なシード** (実行の前に固定した規則): キーのシード欠陥表で、期待深刻度が `high` のもの、または対応観点が「セキュリティ」で始まるもの (コアシードと昇格シードの両方)。**安全上重要な見逃し**は、そのシードが最終報告に無いこと、または `low` としてしか無いこと。見逃しは最終報告の指摘件数とは別の表に書き、件数が増えたことを検出の改善とも見逃しの埋め合わせとも数えない。

**C1. 準備 (メイン)** — 比べる資産 (`skills/eval/SKILL.md`・`skills/design-review/`・`agents/`・`.claude-plugin/plugin.json`・`tests/eval/cases/`・`tests/eval/keys/`) に未コミットの変更が無い状態で行う (下のブロックが止める。安全上重要なシードの規則・提案の規則・固定プロンプトを、結果を見る前のコミットで固定するため)。元リポジトリの外に run ディレクトリを2つ作る: 設計レビューの3構成用の `<run>` と、単体モデル用の `<base>` (`mktemp -d "${TMPDIR:-/tmp}/aidd-eval-compare.XXXXXX"` など)。

1. `<run>` で手順1a の `# eval staging:` のブロックを、比べるケースをすべて渡して実行する (`raw/prompt-<ケース>.md`・`mix-<ケース>.tsv`・`planted.sha256` もできるが、比較では使わない)
2. 次のブロックの `<repo>`・`<run>`・`<base>`・`<cases>` (1 と同じ) を置き換えて実行する

ブロックがすること: `<run>/raw/` に構成ごとのプロンプト (`prompt-<ケース>-<構成>.md`、偽指摘は付けない) と構成の一覧 (`compare.tsv`、ケースの行数と `direct` の対象外を含む) を書く。`<base>/input/` にケースだけをコピーし、`<base>/raw/` に単体モデルのプロンプト (`prompt-<ケース>-baseline.md`、行番号付きの本文入り)・入力のハッシュ (`input.sha256`)・`<run>` と同じ `keys.sha256`・測定条件 (`conditions.md`) を書く。次のどれかに当たれば止まる。

- ケース名が英小文字・数字・`-` 以外を含む、`<run>` が手順1a で準備されていない・既に凍結されている・比較のプロンプトが既にある、ケースが `<run>/input/` に無いか `tests/eval/cases/` と違う
- `<base>` が元リポジトリか `<run>` の中にある、`<base>` に `input/` か `raw/` が既にある、`<base>/input/` がどこかの Git の作業ツリーの中にある
- 比べる資産に未コミットの変更がある。手順1a で `<run>/input/` にコピーしたファイル (`<run>/allowed` の全件) が今の元ファイルと違う、または `<run>` を準備したコミット (`conditions.md` の git SHA) が今の HEAD と違う (未コミットの資産で準備した後に戻した・コミットした場合も止めるため)
- プロンプトかケースのコピーに元リポジトリの絶対パスがある、プロンプトに `tests/eval/`・planted の ID・置き換え忘れの `<case>`・`<config>`・`<rule>` が残っている (単体モデルのプロンプトは本文を埋め込むので、`tests/eval/` と planted の ID を見る)

失敗したら原因を直し、新しい run ディレクトリ2つでやり直す。

```bash
# eval compare staging: after the eval staging of <run>, write the per-config prompts into <run>/raw and stage the baseline run <base>
repo='<repo>'; run='<run>'; base='<base>'; cases='<cases>'
set -euo pipefail
fail() { echo "eval compare staging: $*" >&2; exit 1; }
[ -n "$(printf '%s' "$cases" | tr -d ' \t\n')" ] || fail "no cases"
for c in $cases; do
  case "$c" in *[!abcdefghijklmnopqrstuvwxyz0123456789-]*) fail "bad case name: $c" ;; esac
done
repo_given=$repo
repo=$(cd "$repo" && pwd -P); run=$(cd "$run" && pwd -P); base=$(cd "$base" && pwd -P)
skill="$repo/skills/eval/SKILL.md"; raw="$run/raw"; bin="$base/input"; braw="$base/raw"
[ -f "$raw/conditions.md" ] && [ -f "$raw/keys.sha256" ] && [ -f "$raw/input.sha256" ] || fail "$run is not staged by the eval staging block"
[ ! -e "$raw/SHA256SUMS" ] || fail "$run is already frozen"
[ ! -e "$raw/compare.tsv" ] || fail "the comparison prompts already exist in $run"
case "$base/" in "$repo/"*|"$run/"*) fail "the baseline run directory is inside the repository or the run" ;; esac
if [ -e "$bin" ] || [ -e "$braw" ]; then fail "input/ or raw/ already exists in $base"; fi
status=$(git -C "$repo" status --porcelain -- skills/eval/SKILL.md skills/design-review agents .claude-plugin/plugin.json tests/eval/cases tests/eval/keys) \
  || fail "cannot read the git status of the repository"
[ -z "$status" ] || fail "the compared assets have uncommitted changes"
[ -f "$run/allowed" ] || fail "$run has no allowed list from the eval staging block"
while IFS=$'\t' read -r dst src; do
  cmp -s "$run/input/$dst" "$repo/$src" || fail "the staged $dst differs from $src"
done < "$run/allowed"
head=$(git -C "$repo" rev-parse HEAD) || fail "cannot read the HEAD of the repository"
grep -qF "| git SHA | $head |" "$raw/conditions.md" || fail "$run was staged at another commit"
mkdir -p "$bin/cases" "$braw" "$base/local"
if env -u GIT_DIR -u GIT_WORK_TREE git -C "$bin" rev-parse --git-dir > /dev/null 2>&1; then fail "the baseline input is inside a git work tree"; fi
printf 'case\tlines\tconfig\tprompt\n' > "$run/compare.tmp"
for c in $cases; do
  src="$run/input/cases/$c.md"
  [ -f "$src" ] || fail "case $c is not staged in $run"
  lines=$(awk 'END { print NR }' "$src")
  for config in deep standard direct; do
    if [ "$config" = direct ] && [ "$lines" -ge 100 ]; then
      printf '%s\t%s\t%s\t対象外 (100行以上)\n' "$c" "$lines" "$config" >> "$run/compare.tmp"
      continue
    fi
    rule=$(sed -n '/^# eval compare configs$/,/^# end eval compare configs$/p' "$skill" | sed -n "s/^$config: //p")
    [ -n "$rule" ] || fail "skills/eval/SKILL.md has no rule for $config"
    prompt="$raw/prompt-$c-$config.md"
    sed -n '/^# eval compare prompt (/,/^# end eval compare prompt$/p' "$skill" \
      | sed -e "s/<case>/$c/g" -e "s/<config>/$config/g" \
      | awk -v rule="$rule" '{ i = index($0, "<rule>"); if (i) $0 = substr($0, 1, i - 1) rule substr($0, i + 6); print }' > "$prompt"
    [ -s "$prompt" ] || fail "skills/eval/SKILL.md has no compare prompt"
    printf '%s\t%s\t%s\tprompt-%s-%s.md\n' "$c" "$lines" "$config" "$c" "$config" >> "$run/compare.tmp"
  done
  cp "$src" "$bin/cases/$c.md"
  prompt="$braw/prompt-$c-baseline.md"
  sed -n '/^# eval compare baseline prompt$/,/^# end eval compare baseline prompt$/p' "$skill" | sed '1d;$d' > "$prompt"
  [ -s "$prompt" ] || fail "skills/eval/SKILL.md has no baseline prompt"
  printf '\n' >> "$prompt"
  awk '{ printf "%d\t%s\n", NR, $0 }' "$src" >> "$prompt"
done
case "$repo_given" in /*) ;; *) repo_given=$repo ;; esac
if grep -rqiF -e "$repo" -e "$repo_given" "$bin" "$braw" "$raw"/prompt-*-*.md; then fail "the repository path appears in the input or a prompt"; fi
if grep -qF -e 'tests/eval/' -e 'PL-' -e '<case>' -e '<config>' -e '<rule>' "$raw"/prompt-*-*.md; then fail "a prompt names tests/eval/, shows a planted ID or keeps a placeholder"; fi
if grep -qF -e 'tests/eval/' -e 'PL-' "$braw"/prompt-*.md; then fail "a baseline prompt names tests/eval/ or shows a planted ID"; fi
(cd "$bin" && find . -type f | LC_ALL=C sort | while read -r f; do shasum -a 256 "$f"; done) > "$braw/input.sha256"
cp "$raw/keys.sha256" "$braw/keys.sha256"
{ cat "$raw/conditions.md"; printf '| 比較の run | 単体モデル (baseline)。設計レビューの構成は同じ準備の別の run |\n'; } > "$braw/conditions.md"
mv "$run/compare.tmp" "$raw/compare.tsv"
echo "eval compare staging: ok ($run, $base)"
# end eval compare staging
```

設計レビューの構成の固定プロンプト (上のブロックが `<case>`・`<config>` を置き換え、`<rule>` を下の構成の一覧の行に置き換えて `raw/prompt-<ケース>-<構成>.md` に書く):

```text
# eval compare prompt (case: <case>, config: <config>)
あなたは aidd の design-review を評価する実行担当です。採点は、あなたの実行が終わった後に別の工程で行います。作業ディレクトリの中のファイルだけを使い、親ディレクトリや作業ディレクトリの外の絶対パスを開かないでください。

1. `plugin/skills/design-review/SKILL.md` を読み、対象 `cases/<case>.md` に次の構成で適用する。`--security` と `--verify-sources` は付けない (security-reviewer の起動は条件判定に任せる)。作業ディレクトリに `.aidd/` は無い。
   構成: <rule>
2. dispatch する場合は、各 agent に対象ケースのパスと担当観点だけを渡し、「このファイルだけをレビューする」と明示する。
3. ユーザーには質問しない (答えは返らない)。判断が要るところは、判断と理由を出力に書いて進める。
4. 最後に、次の見出しをこの順ですべて含む Markdown を最終回答にする。中身が無い節には「なし」、取れない値には「不明」と書く。
   - `## 経路` (dispatch した agent、refuter・arbiter を起動したかとその理由、小規模対象ショートカットを使ったか)
   - `## reviewer の生指摘` (agent ごと、またはメインが直接レビューした指摘。深刻度・引用箇所・指摘・代案)
   - `## refuter の判定` (指摘ごとに、反証成立/反証失敗と根拠)
   - `## 最終報告` (design-review がユーザーに返す最終の報告の全文と、high/mid/low 別の件数)
   - `## security-reviewer の起動` (yes/no と理由)
# end eval compare prompt
```

構成の一覧 (`<rule>` に入る行。ここか上のプロンプトを変えたら、プロンプトの版が変わったことになり、ハッシュで追える):

```text
# eval compare configs
deep: `--depth=deep` で適用する (並列 dispatch → refuter → arbiter)。対象が1ファイル・100行未満でも、小規模対象ショートカットは使わない。
standard: `--depth=standard` で適用する (既定の深さ。refuter・arbiter は design-review の standard の条件に従う)。対象が1ファイル・100行未満でも、小規模対象ショートカットは使わず、並列 dispatch する。
direct: `--depth=standard` で適用し、小規模対象ショートカットを使う (reviewer を dispatch せず、メインが design-review の観点で直接レビューする。Agent 6 の起動条件に当たれば Agent 6 だけは dispatch する)。その後の refuter・arbiter は design-review の standard の条件に従う。
# end eval compare configs
```

単体モデルの固定プロンプト (`2026-11-07-baseline.md` の文言のまま。上のブロックが先頭と末尾の行を除き、空行と行番号付きの本文 (`<行番号><タブ><本文>`) を付けて `prompt-<ケース>-baseline.md` に書く):

```text
# eval compare baseline prompt
次の設計書をレビューし、問題点を列挙してください。各指摘に深刻度 (high/mid/low)、該当行、理由、代案を付けてください。

ファイルは読まず、ツールも使わず、以下の本文だけを根拠に回答してください（左の数字は行番号です）。
# end eval compare baseline prompt
```

**C2. 実行 (新しいセッション)** — 課金のある実行なので、ユーザーが推定コストを見て承認してから始める。推定は、ケース × 構成 × 試行の回数と、過去の結果の総トークン・USD (どの結果ファイルの値かを書く) から出し、`<model>` と構成ごとの `<budget>` と一緒に示す。試行ごとに、ケースごとに `deep` → `standard` → `direct` → `baseline` の順で1回ずつ起動する (`<trial>` は 1 から。時間帯の偏りを構成の間で散らすため)。どれも新しいセッションで、前の試行の文脈を持ち越さない。

```bash
[ ! -e "<run>/local/<case>-<config>-t<trial>.jsonl" ] && cd "<run>/input" && claude -p --model <model> --output-format stream-json --verbose --plugin-dir ./plugin --max-budget-usd <budget> < "<run>/raw/prompt-<case>-<config>.md" > "<run>/local/<case>-<config>-t<trial>.jsonl"
[ ! -e "<base>/local/<case>-baseline-t<trial>.jsonl" ] && cd "<base>/input" && claude -p --model <model> --output-format stream-json --verbose --tools "" --no-session-persistence --max-budget-usd <budget> < "<base>/raw/prompt-<case>-baseline.md" > "<base>/local/<case>-baseline-t<trial>.jsonl"
```

- `<model>` は全構成で同じ値 (既定 `opus`)。`<budget>` は構成ごとの1試行の USD の上限で、ユーザーが承認した値にする。上限で止まった試行は失敗として記録する。`compare.tsv` で `direct` が対象外のケースは、`direct` を起動しない。既にある試行番号の stream-json には書き込まない (上のコマンドの先頭の検査が止める)。起動し直すときは新しい試行番号を使う
- 1回に数分から十数分かかる。手順1b と同じく、バックグラウンドで実行して終了を待つ。user 設定・hook・他のプラグインは変えずにそのまま読み込ませる (単体モデルも同じ。`--tools ""` でツールは使えない)
- 抽出は手順1b の `# eval extract:` のブロックを、`<run>` を各 run に、`<case>` を `<case>-<config>` (単体モデルは `<case>-baseline`) に置き換えて使う。`<base>/input/` には `plugin/` が無いので、aidd のプラグインの検査はせず、読み込まれたプラグインの一覧だけを記録する

**C3. 凍結と照合 (メイン)** — 凍結の前に、`compare.tsv` の対象外でない行と単体モデルの各ケースについて、試行 1〜N のすべてで `local/<case>-<config>-t<trial>.jsonl` と `raw/<case>-<config>-t<trial>.md`・`.meta.md` がそろっていることを確かめる。欠けた組が1つでもあれば凍結しない (起動し忘れた試行があっても、凍結と照合は通ってしまうため)。失敗した試行 (上限で止まった・エラーで終わった・最終回答が無い) がある構成・ケースは、凍結の前に新しい試行番号で再実行し、全構成の成功した試行の数をそろえる (凍結した後は run に試行を足せない)。全試行の実行と抽出が終わったら、2つの run それぞれに手順1c の `# eval freeze:` と手順2 の `# eval verify:` を使う。SHA256SUMS の sha256 は2つとも、採点の前にユーザーへの途中報告と結果に書く。照合が両方通るまで、キーと過去の結果を読まない。

**C4. 採点 (メイン)** — 対象は各試行の最終報告 (設計レビューの構成は `## 最終報告`、単体モデルは回答全体)。シードは手順2と同じく、キーの一致判定基準で意味的に照合する。キー外の指摘は手順4と同じく判定エージェント2体で分類する。全構成・全試行のキー外指摘を同じ論点ごとにまとめて渡し、判定エージェントには構成の名前と出た試行を渡さない (どの構成の指摘かで判定が偏らないようにするため)。論点の分類を、その論点に当たる各試行の指摘に当てはめる。指標:

| 指標 | 定義 |
|---|---|
| コア検出率・拡張検出率・深刻度一致・デコイ誤検出 | 手順3と同じ (arbiter の最終報告を、各構成の最終報告と読み替える) |
| 安全上重要な見逃し | 上の定義による見逃しの件数と、見逃したシードの ID |
| 最終報告の指摘件数 | high/mid/low 別。同じケースの `baseline` との差も書く |
| ノイズ率・誤検出 | 手順3・4と同じ |
| キー外で正当 | 手順4で「正当」と確定した件数 |
| 経路 | 実行担当の `## 経路` (dispatch した agent、refuter・arbiter・security-reviewer の起動、ショートカットの有無)。構成どおりでない経路 (`direct` で reviewer を dispatch した、`deep` で arbiter を起動しなかった など) は、その試行に注記する |
| 待ち時間 | meta の `duration_ms` |
| 総費用 | meta の `total_cost_usd` と、モデル別の使用量のトークンの合計。agent 別の `total_tokens` も書く |

**C5. 提案 (実行の前に固定した規則)** — ケースを100行未満と100行以上に分けて判定する。軽い構成 (`standard`・`direct`・`baseline`) を「既定を軽量化してよい候補」にするのは、そのケース群の全ケース・全試行で次をすべて満たすときだけ。1つでも満たさなければ「既定を維持」とする。

1. 安全上重要なシードごとに、見逃した試行の数が `deep` 以下 (`deep` も見逃したシードは、`deep` より多く見逃さなければよい)
2. コア検出が、どの試行も `deep` の最小値以上
3. デコイ誤検出が、どの試行も `deep` の最大値以下

失敗した試行 (上限で止まった・エラーで終わった・最終回答が無い) を `deep` の最小値・最大値・見逃しの数にも、軽い構成の判定にも入れない。C3 で成功した試行の数をそろえられなかったケース群は判定せず「既定を維持」とする (`deep` の失敗が基準を緩め、実行の失敗が軽量化の根拠に紛れ込むため)。

指摘件数・ノイズ率・費用・待ち時間は、候補の中から選ぶ材料にだけ使い、上の3つを満たさない構成を候補にする理由にしない。提案には当てはまる条件 (実測したモデル・版・比べたケース・この固定プロンプト・試行数) を書き、ほかのケースやモデルに一般化しない。

**C6. 結果の保存** — `tests/eval/results/YYYY-MM-DD-compare.md` に保存する (同日に再実行したら `-2` などの連番)。`<run>/raw/` を `tests/eval/results/<run-id>/review/` に、`<base>/raw/` を `tests/eval/results/<run-id>/baseline/` にコピーし、それぞれで `shasum -a 256 -c SHA256SUMS` が通ることと、SHA256SUMS の sha256 が C3 で記録した値と同じことを確かめる。`local/` はコミットしない。記載内容:

- 測定条件の表: 手順5の項目に加え、`<model>`・構成ごとの `<budget>`・2つの SHA256SUMS の sha256・`compare.tsv`
- 構成ごと・ケースごと・試行ごとの指標の表と、3試行の最小〜最大 (平均だけにしない)。失敗した試行・構成どおりでない経路も消さずに書く
- 安全上重要な見逃しの表 (シードごと・構成ごと・試行ごと) と、最終報告の指摘件数の増減の表を分ける
- C5 の規則による提案と、提案が当てはまる条件。過去の比較 (`2026-11-07-baseline.md`・`2026-11-22-crosscut-comparison.md`) と違う条件 (実行の仕方・偽指摘の有無・モデル・版)
- 未測定の項目とそろえきれなかった条件
- コストの表: 構成ごとと採点を分け、評価全体の合計も示す。列はトークンと USD に分け、合計の行は既知の分の合計と不明の項目名を書く

**C7. 報告** — 指標の表・安全上重要な見逃しの表・提案・コストの表・未測定の項目を示す。提案は design-review の既定や構成の変更ではないことを添える。

## design-review の条件分岐の評価 (Agent 4・5・6)

`/aidd:eval branch [変種名]` で行う。design-review が条件で起動する Agent 4 (プロジェクト固有観点)・Agent 5 (`--verify-sources` の source-verifier)・Agent 6 (security-reviewer) を、手順1〜6のケースとは別の未見ケース (`tests/eval/branch/`) で測る。測るのは、起動すべきときに起動し、起動すべきでないときに起動しないか (機微情報の保存だけで Agent 6 が起動するか、非機微な内部処理で過剰に起動しないか、`.aidd/design-perspectives.md` の有無で Agent 4 が分かれるか)、起動した agent が担当の欠陥を最終報告に残したか、source-verifier が外部の主張を正しく判定し、到達できない資料を確認済みにしないか。

素材は `tests/eval/branch/`: `cases/<ケース>.md` (設計書)、`perspectives/<名前>.md` (Agent 4 用の `.aidd/design-perspectives.md` の中身)、`variants.tsv` (変種ごとに `変種名<TAB>ケース<TAB>観点 (無ければ -)<TAB>フラグ (- か --verify-sources)`)、`keys/<ケース>.md` (変種ごとの起動の期待・シード・外部情報の主張の期待判定)、`freeze.sha256`。

- **コアと拡張の分母を混ぜない**。この評価の数字は手順3のコア検出率・拡張検出率に足さず、手順1〜6の結果ファイルにも書かない。キーの「コアシード」はこの評価の中での分母で、拡張シードは別に数える。ケースごと・変種ごとの分母を書き、合算した率だけにしない
- **到達できない外部資料を確認済みと採点しない** (B5 の規則)
- 分離は「分離と汚染ガード」と同じ。手順1b の抽出・1c の凍結・2 の照合のブロックをそのまま使い、「分離の限界」もそのまま当てはまる。偽指摘は使わない
- 試行は既定で各変種1試行。率は参考値として書き、1回の結果で design-review を変えない (「注意」のとおり再実行で再現を確かめる)
- 分岐評価からはキーへ昇格しない。キー外の指摘は件数と内容を記録するだけにする

**B1. ケースの確認と凍結 (ユーザー)** — 初めて実行する前と、`tests/eval/branch/` のケース・観点・変種・キー、下の固定プロンプトか B2 の準備のブロックを変えたときに行う。本実行とは別のセッションで行う。

1. 各ケース・観点・`variants.tsv`・キーをユーザーに示し、確認を AskUserQuestion で求める。外部情報の主張は、キーに書いた版を固定した一次資料で期待判定を確かめてから示す
2. 承認されたら、次のブロックの `<repo>` を置き換えて実行する。`tests/eval/branch/freeze.sha256` (ケース・観点・`variants.tsv`・キーのハッシュと、固定プロンプトと B2 の準備のブロックのハッシュ) を書き、その sha256 を表示する。既にあれば止まる。作り直すのは、ユーザーが新しい版を承認したときだけで、そのときはユーザーが古いファイルを消す
3. ユーザーが `freeze.sha256` をコミットする。準備 (B2) は、`freeze.sha256` がコミットされていない、今のファイルと一致しない、評価する資産に未コミットの変更がある、のどれかなら止まる。キーはレビューの実行より前のこのコミットで固定される

```bash
# eval branch freeze-cases: after the user approved the cases, perspectives, variants and keys, write tests/eval/branch/freeze.sha256
repo='<repo>'
set -euo pipefail
fail() { echo "eval branch freeze-cases: $*" >&2; exit 1; }
br="$repo/tests/eval/branch"
[ -d "$br/cases" ] && [ -d "$br/keys" ] && [ -f "$br/variants.tsv" ] || fail "no cases, keys or variants.tsv"
[ ! -e "$br/freeze.sha256" ] || fail "freeze.sha256 already exists; only the user removes it, after approving a new version"
if [ -n "$(find "$br" ! -type f ! -type d)" ]; then fail "a symbolic link or a special file under tests/eval/branch"; fi
while IFS=$'\t' read -r v c p f; do
  for n in "$v" "$c"; do
    case "$n" in ''|*[!abcdefghijklmnopqrstuvwxyz0123456789-]*) fail "bad variant or case name: $n" ;; esac
  done
  [ -f "$br/cases/$c.md" ] && [ -f "$br/keys/$c.md" ] || fail "variant $v lacks its case or key"
  [ "$p" = - ] || [ -f "$br/perspectives/$p.md" ] || fail "variant $v lacks its perspectives"
  case "$f" in -|--verify-sources) ;; *) fail "variant $v has unsupported flags: $f" ;; esac
  grep -qF "| $v |" "$br/keys/$c.md" || fail "the key of $c has no expectation for $v"
done < "$br/variants.tsv"
prompt=$(sed -n '/^# eval branch prompt$/,/^# end eval branch prompt$/p' "$repo/skills/eval/SKILL.md" | shasum -a 256 | awk '{print $1}')
staging=$(sed -n '/^# eval branch staging:/,/^# end eval branch staging$/p' "$repo/skills/eval/SKILL.md" | shasum -a 256 | awk '{print $1}')
(cd "$br" && { find cases keys variants.tsv $( [ -d perspectives ] && echo perspectives ) -type f | LC_ALL=C sort | while read -r f; do shasum -a 256 "$f"; done
  printf '%s  %s\n' "$prompt" prompt "$staging" staging; }) > "$br/freeze.sha256.tmp"
mv "$br/freeze.sha256.tmp" "$br/freeze.sha256"
echo "eval branch freeze-cases: freeze.sha256 sha256 $(shasum -a 256 "$br/freeze.sha256" | awk '{print $1}')"
# end eval branch freeze-cases
```

**B2. 準備 (メイン)** — 変種ごとに新しい run ディレクトリを作り (`mktemp -d "${TMPDIR:-/tmp}/aidd-eval-branch.XXXXXX"` など。変種の間で `input/` を共有しない。`.aidd/` の有無が変種で違うため)、次のブロックの `<repo>`・`<run>`・`<variant>` を置き換えて実行する。

ブロックがすること: 凍結を確かめ、`input/` にケースと plugin (`.claude-plugin/plugin.json`・`agents/`・`skills/design-review/`)、観点がある変種では `.aidd/design-perspectives.md` だけをコピーする。次のどれかに当たれば止まる。

- 変種名が英小文字・数字・`-` 以外を含む、`variants.tsv` に変種が1行だけ無い、ケース・キー・観点が無い、フラグが `-`・`--verify-sources` 以外
- 凍結 (B1 の 3) が確かめられない、`tests/eval/branch/`・`skills/eval/SKILL.md`・`skills/design-review/`・`agents/`・`.claude-plugin/plugin.json` に未コミットの変更がある
- run ディレクトリが元リポジトリの中にある、`input/` か `raw/` が既にある、`input/` がどこかの Git の作業ツリーの中にある
- `input/` のファイルが許可した一覧と完全に一致しない、コピー元と内容が違う、名前が `.git`・`keys`・`results` のものがある、内容が `tests/eval/keys/`・`tests/eval/results/`・`tests/eval/branch/keys/` のどれかのファイルと同じ
- `input/` かプロンプトに元リポジトリの絶対パスがある、プロンプトに `tests/eval/`・変種名・置き換え忘れの `<case>`・`<flags>` が残っている

`raw/` には、固定プロンプトの `<case>`・`<flags>` を置き換えたもの (`prompt-<変種>.md`)・入力のハッシュ (`input.sha256`)・キーのハッシュ (`keys.sha256`、`tests/eval/` からの相対パス)・凍結のマニフェストの写し (`freeze.sha256`)・測定条件 (`conditions.md`) を書く。

```bash
# eval branch staging: copy one frozen variant into <run>/input, write its prompt and hashes into <run>/raw, and check the separation
repo='<repo>'; run='<run>'; variant='<variant>'
set -euo pipefail
fail() { echo "eval branch staging: $*" >&2; exit 1; }
case "$variant" in ''|*[!abcdefghijklmnopqrstuvwxyz0123456789-]*) fail "bad variant name: $variant" ;; esac
repo_given=$repo
repo=$(cd "$repo" && pwd -P); run=$(cd "$run" && pwd -P)
case "$run/" in "$repo/"*) fail "the run directory is inside the repository" ;; esac
in="$run/input"; raw="$run/raw"; br="$repo/tests/eval/branch"
if [ -e "$in" ] || [ -e "$raw" ]; then fail "input/ or raw/ already exists in $run"; fi
[ -f "$br/variants.tsv" ] || fail "no tests/eval/branch/variants.tsv"
rows=$(awk -F '\t' -v v="$variant" '$1 == v' "$br/variants.tsv")
[ -n "$rows" ] && [ "$(printf '%s\n' "$rows" | wc -l | tr -d ' ')" = 1 ] || fail "no single row for $variant in variants.tsv"
IFS=$'\t' read -r _ case persp flags <<< "$rows"
case "$case" in ''|*[!abcdefghijklmnopqrstuvwxyz0123456789-]*) fail "bad case name: $case" ;; esac
case "$persp" in -) ;; ''|*[!abcdefghijklmnopqrstuvwxyz0123456789-]*) fail "bad perspectives name: $persp" ;; esac
case "$flags" in -) flags= ;; --verify-sources) flags=' --verify-sources' ;; *) fail "unsupported flags: $flags" ;; esac
[ -f "$br/cases/$case.md" ] && [ -f "$br/keys/$case.md" ] || fail "no case or key for $variant"
[ "$persp" = - ] || [ -f "$br/perspectives/$persp.md" ] || fail "no perspectives $persp for $variant"
[ -f "$br/freeze.sha256" ] || fail "the cases are not frozen (no tests/eval/branch/freeze.sha256)"
prompt_sha=$(sed -n '/^# eval branch prompt$/,/^# end eval branch prompt$/p' "$repo/skills/eval/SKILL.md" | shasum -a 256 | awk '{print $1}')
staging_sha=$(sed -n '/^# eval branch staging:/,/^# end eval branch staging$/p' "$repo/skills/eval/SKILL.md" | shasum -a 256 | awk '{print $1}')
(cd "$br" && { find cases keys variants.tsv $( [ -d perspectives ] && echo perspectives ) -type f | LC_ALL=C sort | while read -r f; do shasum -a 256 "$f"; done
  printf '%s  %s\n' "$prompt_sha" prompt "$staging_sha" staging; }) > "$run/manifest"
cmp -s "$run/manifest" "$br/freeze.sha256" || fail "the cases, perspectives, variants, keys, prompt or staging block differ from freeze.sha256"
git -C "$repo" ls-files --error-unmatch tests/eval/branch/freeze.sha256 > /dev/null 2>&1 || fail "freeze.sha256 is not committed"
[ -z "$(git -C "$repo" status --porcelain -- tests/eval/branch skills/eval/SKILL.md skills/design-review agents .claude-plugin/plugin.json)" ] \
  || fail "the evaluated assets have uncommitted changes"
mkdir -p "$in/cases" "$in/plugin/.claude-plugin" "$raw" "$run/local"
if env -u GIT_DIR -u GIT_WORK_TREE git -C "$in" rev-parse --git-dir > /dev/null 2>&1; then fail "input is inside a git work tree"; fi
cp "$br/cases/$case.md" "$in/cases/$case.md"
printf 'cases/%s.md\ttests/eval/branch/cases/%s.md\n' "$case" "$case" > "$run/allowed"
cp "$repo/.claude-plugin/plugin.json" "$in/plugin/.claude-plugin/plugin.json"
cp -R "$repo/agents" "$in/plugin/agents"
mkdir -p "$in/plugin/skills"
cp -R "$repo/skills/design-review" "$in/plugin/skills/design-review"
(cd "$repo" && find .claude-plugin/plugin.json agents skills/design-review -type f) \
  | while read -r f; do printf 'plugin/%s\t%s\n' "$f" "$f"; done >> "$run/allowed"
if [ "$persp" != - ]; then
  mkdir -p "$in/.aidd"
  cp "$br/perspectives/$persp.md" "$in/.aidd/design-perspectives.md"
  printf '.aidd/design-perspectives.md\ttests/eval/branch/perspectives/%s.md\n' "$persp" >> "$run/allowed"
fi
if [ -n "$(find "$in" \( -iname .git -o -iname keys -o -iname results \))" ]; then fail "input has a .git, keys or results entry"; fi
(cd "$in" && find . ! -type d | sed 's|^\./||' | LC_ALL=C sort) > "$run/found"
cut -f1 "$run/allowed" | LC_ALL=C sort > "$run/expected"
cmp -s "$run/found" "$run/expected" || fail "input holds files outside the allowed list"
while IFS=$'\t' read -r dst src; do
  cmp -s "$in/$dst" "$repo/$src" || fail "$dst differs from $src"
done < "$run/allowed"
(cd "$repo/tests/eval" && for d in keys results branch/keys; do
  if [ -d "$d" ]; then find "$d" -type f -size +0; fi
done | while read -r f; do shasum -a 256 "$f"; done) | awk '{print $1}' | LC_ALL=C sort -u > "$run/forbidden"
(cd "$in" && find . -type f | while read -r f; do shasum -a 256 "$f"; done) | awk '{print $1}' | LC_ALL=C sort -u > "$run/inhash"
if [ -n "$(comm -12 "$run/forbidden" "$run/inhash")" ]; then fail "input has the same content as a key or a result"; fi
prompt="$raw/prompt-$variant.md"
sed -n '/^# eval branch prompt$/,/^# end eval branch prompt$/p' "$repo/skills/eval/SKILL.md" | sed '1d;$d' \
  | sed -e "s/<case>/$case/g" -e "s/<flags>/$flags/g" > "$prompt"
[ -s "$prompt" ] || fail "skills/eval/SKILL.md has no branch prompt"
case "$repo_given" in /*) ;; *) repo_given=$repo ;; esac
if grep -rqiF -e "$repo" -e "$repo_given" "$in" "$raw"; then fail "the repository path appears in the input or the prompt"; fi
if grep -qF -e 'tests/eval/' -e '<case>' -e '<flags>' "$prompt"; then fail "the prompt names tests/eval/ or keeps a placeholder"; fi
if [ "$variant" != "$case" ] && grep -qF -- "$variant" "$prompt"; then fail "the prompt shows the variant name"; fi
(cd "$in" && find . -type f | LC_ALL=C sort | while read -r f; do shasum -a 256 "$f"; done) > "$raw/input.sha256"
(cd "$repo/tests/eval" && shasum -a 256 "branch/keys/$case.md") > "$raw/keys.sha256"
cp "$br/freeze.sha256" "$raw/freeze.sha256"
version=$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' "$repo/.claude-plugin/plugin.json" 2>/dev/null) || version=不明
sha=$(git -C "$repo" rev-parse HEAD 2>/dev/null) || sha=不明
frozen=$(git -C "$repo" log -1 --format=%H -- tests/eval/branch/freeze.sha256 2>/dev/null) || frozen=
cli=$(claude --version 2>/dev/null < /dev/null) || cli=
{
  printf '| 項目 | 値 |\n|---|---|\n'
  printf '| aidd version | %s |\n' "$version"
  printf '| git SHA | %s |\n' "$sha"
  printf '| 凍結したコミット | %s |\n' "${frozen:-不明}"
  printf '| freeze.sha256 の sha256 | %s |\n' "$(shasum -a 256 "$br/freeze.sha256" | awk '{print $1}')"
  printf '| CLI (準備時) | %s |\n' "${cli:-不明}"
  printf '| 変種 | %s (ケース %s、観点 %s、フラグ %s) |\n' "$variant" "$case" "$persp" "${flags:- -}"
  printf '| 準備日時 (UTC) | %s |\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$raw/conditions.md"
rm -f "$run/manifest" "$run/allowed" "$run/expected" "$run/found" "$run/forbidden" "$run/inhash"
echo "eval branch staging: ok ($run)"
# end eval branch staging
```

実行担当の固定プロンプト (上のブロックが先頭と末尾の行を除き、`<case>` をケース名に、`<flags>` を変種のフラグ (無ければ空) に置き換えて `raw/prompt-<変種>.md` に書く。変種名・期待する起動は書かない。ここを変えたら B1 の凍結からやり直す):

```text
# eval branch prompt
あなたは aidd の design-review を評価する実行担当です。採点は、あなたの実行が終わった後に別の工程で行います。作業ディレクトリの中のファイルだけを使い、親ディレクトリや作業ディレクトリの外の絶対パスを開かないでください (Web の検索・取得は、design-review の手順が求める場合に使ってよい)。

1. `plugin/skills/design-review/SKILL.md` を読み、対象 `cases/<case>.md` に `--depth=standard<flags>` で適用する。対象が1ファイル・100行未満でも、小規模対象ショートカットは使わず、並列 dispatch する。`--security` と `--no-security` は付けない。どの条件付きの agent を起動するかは、design-review の条件どおりに判断する (作業ディレクトリは対象プロジェクトのルートとして扱う)。
2. 各 agent への dispatch では、対象ケースのパスと担当観点だけを渡し、「このファイルだけをレビューする」と明示する。
3. ユーザーには質問しない (答えは返らない)。判断が要るところは、判断と理由を出力に書いて進める。
4. 最後に、次の見出しをこの順ですべて含む Markdown を最終回答にする。中身が無い節には「なし」、取れない値には「不明」と書く。
   - `## 経路` (dispatch した agent ごとに、どの観点の agent として起動したか。条件付きの agent それぞれについて、起動したか・しなかったかと、その理由)
   - `## reviewer の生指摘` (agent ごとに、深刻度・引用箇所・指摘・代案)
   - `## source-verifier の判定` (起動した場合だけ。agent の返答を書き換えずに)
   - `## refuter の判定` (指摘ごとに、反証成立/反証失敗と根拠)
   - `## 最終報告` (design-review がユーザーに返す最終の報告の全文と、high/mid/low 別の件数)
   - `## security-reviewer の起動` (yes/no と理由)
# end eval branch prompt
```

**B3. 実行 (新しい実行担当)** — 変種ごと・試行ごとに新しいセッションを1つ起動する。課金のある実行なので、ユーザーが推定コストを見て承認してから始める (`<budget>` は1試行の USD の上限で、ユーザーが承認した値)。

```bash
[ ! -e "<run>/local/<variant>-t<trial>.jsonl" ] && cd "<run>/input" && claude -p --output-format stream-json --verbose --plugin-dir ./plugin --max-budget-usd <budget> < "<run>/raw/prompt-<variant>.md" > "<run>/local/<variant>-t<trial>.jsonl"
```

- 手順1b と同じく、バックグラウンドで実行して終了を待つ。user 設定・hook・他のプラグインは変えずにそのまま読み込ませる。上限で止まった試行は失敗として記録する
- Web に出られない環境 (サンドボックスの通信の制限など) で動かした場合も、そのまま記録する。source-verifier の到達の可否は下の記録で採点する
- 実行のたびに、手順1b の `# eval extract:` のブロックを `<case>` を `<variant>` に置き換えて使い、続けて次のブロックで、実際に dispatch された agent・Web の呼び出しの成否・source-verifier の返答を `raw/<variant>-t<trial>.tools.md` に書く (`<run>`・`<variant>`・`<trial>`・`<repo>` を置き換える)。起動の判定は実行担当の `## 経路` (自己申告) ではなく、この記録で行う

```bash
# eval branch tools: <run>/local/<variant>-t<trial>.jsonl -> <run>/raw/<variant>-t<trial>.tools.md (dispatched agents, web calls and the source-verifier reply)
python3 -I - '<run>' '<variant>' '<trial>' '<repo>' <<'PY'
import json, os, re, sys

run_arg, variant, trial, repo_arg = sys.argv[1:5]
if not re.fullmatch(r"[a-z0-9-]+", variant) or not re.fullmatch(r"[0-9]+", trial):
    sys.exit(f"eval branch tools: bad variant or trial: {variant!r} {trial!r}")
run, repo = os.path.realpath(run_arg), os.path.realpath(repo_arg)
staged = os.path.join(run, "input")
stem = f"{variant}-t{trial}"
subs = sorted({(staged, "[input]"), (os.path.join(run_arg, "input"), "[input]"), (run, "[run]"), (run_arg, "[run]"),
               (repo, "[repo]"), (repo_arg, "[repo]"), (os.path.expanduser("~"), "~")}, key=lambda s: -len(s[0]))


def clean(value):
    text = str(value)
    for path, name in subs:
        if len(path) > 1:
            text = re.sub(re.escape(path), lambda _: name, text, flags=re.IGNORECASE)
    return text


def cell(value):
    return "不明" if value is None or value == "" else clean(value).replace("|", "\\|").replace("\n", " ")


def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(c.get("text", "") for c in content if isinstance(c, dict) and c.get("type") == "text")
    return ""


markers = []
try:
    with open(os.path.join(staged, ".aidd", "design-perspectives.md"), encoding="utf-8") as f:
        markers = [s for s in (line.strip().lstrip("-# ").strip() for line in f) if len(s) >= 12]
except OSError:
    pass
uses, results = {}, {}
try:
    with open(os.path.join(run, "local", stem + ".jsonl"), encoding="utf-8") as f:
        lines = f.readlines()
except OSError:
    sys.exit(f"eval branch tools: no local/{stem}.jsonl")
for line in lines:
    try:
        m = json.loads(line)
    except ValueError:
        continue
    message = m.get("message") if isinstance(m, dict) else None
    content = message.get("content") if isinstance(message, dict) else None
    for c in content if isinstance(content, list) else []:
        if not isinstance(c, dict):
            continue
        if c.get("type") == "tool_use":
            args = c.get("input") if isinstance(c.get("input"), dict) else {}
            uses[c.get("id")] = (c.get("name"), args, m.get("parent_tool_use_id"))
        elif c.get("type") == "tool_result":
            results[c.get("tool_use_id")] = (bool(c.get("is_error")), text_of(c.get("content")))
agents = {i: a for i, (n, a, _) in uses.items() if n in ("Agent", "Task")}
kind = {i: str(a.get("subagent_type") or "不明") for i, a in agents.items()}


def is_kind(i, name):
    return kind.get(i, "").split(":")[-1] == name


def perspective(args):
    prompt = str(args.get("prompt") or "")
    return "design-perspectives" in prompt or any(s in prompt for s in markers)


a4 = [i for i in agents if is_kind(i, "reviewer") and perspective(agents[i])]
a5 = [i for i in agents if is_kind(i, "source-verifier")]
a6 = [i for i in agents if is_kind(i, "security-reviewer")]
web = [(i, n, a, p) for i, (n, a, p) in uses.items() if n in ("WebSearch", "WebFetch")]
web_ok = [w for w in web if w[0] in results and not results[w[0]][0]]
web_a5 = [w for w in web if w[3] in a5]
web_a5_ok = [w for w in web_a5 if w in web_ok]
if not a5:
    reach = "起動なし"
elif web_a5_ok:
    reach = f"到達あり (成功 {len(web_a5_ok)} / 呼び出し {len(web_a5)})"
else:
    reach = f"実行不能 (成功 0 / 呼び出し {len(web_a5)})"
out = [f"# 起動と Web の記録: {variant} 試行 {trial}", "", "| 項目 | 値 |", "|---|---|",
       f"| Agent 4 (プロジェクト固有観点を渡した reviewer) | {'yes' if a4 else 'no'} ({len(a4)}) |",
       f"| Agent 5 (source-verifier) | {'yes' if a5 else 'no'} ({len(a5)}) |",
       f"| Agent 6 (security-reviewer) | {'yes' if a6 else 'no'} ({len(a6)}) |",
       f"| reviewer の dispatch 数 | {sum(1 for i in agents if is_kind(i, 'reviewer'))} |",
       f"| source-verifier の Web 到達 | {reach} |",
       "", "## dispatch した agent", "", "| tool_use_id | subagent_type | 呼んだ側 | プロジェクト固有観点 | 返答 |", "|---|---|---|---|---|"]
for i, a in agents.items():
    parent = uses[i][2]
    res = results.get(i)
    out.append(f"| {cell(i)} | {cell(kind[i])} | {cell(kind.get(parent, 'メイン') if parent else 'メイン')} | "
               f"{'yes' if is_kind(i, 'reviewer') and perspective(a) else 'no'} | {'なし' if res is None else ('エラー' if res[0] else 'あり')} |")
if not agents:
    out.append("| なし | | | | |")
out += ["", "## Web の呼び出し", "", "| tool | 呼んだ側 | 入力 | 結果 |", "|---|---|---|---|"]
for i, n, a, p in web:
    res = results.get(i)
    target = a.get("url") or a.get("query") or json.dumps(a, ensure_ascii=False)
    out.append(f"| {n} | {cell(kind.get(p, 'メイン') if p else 'メイン')} | {cell(str(target)[:200])} | "
               f"{'結果なし' if res is None else ('エラー: ' + cell(res[1][:160]) if res[0] else '成功')} |")
if not web:
    out.append("| なし | | | |")
out += ["", "## source-verifier の返答", ""]
for i in a5:
    res = results.get(i)
    out += [f"### {cell(i)}", "", clean(res[1]).rstrip() if res else "返答なし", ""]
if not a5:
    out.append("起動なし")
with open(os.path.join(run, "raw", stem + ".tools.md"), "x", encoding="utf-8") as f:
    f.write("\n".join(out).rstrip("\n") + "\n")
print(f"eval branch tools: {stem}: A4={'yes' if a4 else 'no'} A5={'yes' if a5 else 'no'} A6={'yes' if a6 else 'no'} web={reach}")
PY
```

**B4. 凍結と照合 (メイン)** — 変種ごとに、その変種の全試行の実行と記録が終わったら、手順1c の `# eval freeze:` のブロックで run を凍結し、表示された SHA256SUMS の sha256 を採点の前にユーザーへの途中報告と結果に書く。手順2 の `# eval verify:` のブロックで照合する (キーの照合を含む)。凍結の前に、各試行に `raw/<variant>-t<trial>.md`・`.meta.md`・`.tools.md` がそろっていることを確かめる。照合が通るまで `tests/eval/branch/keys/` と過去の結果を読まない。

**B5. 採点 (メイン)** — 照合の後にキーを読む。材料は凍結した `raw/` の最終回答・meta・tools だけ。

| 指標 | 定義 |
|---|---|
| 起動判定 | 変種ごと・Agent 4/5/6 ごとに、tools の記録 (実際の dispatch) をキーの「起動の期待」と比べ、一致・過剰起動・起動漏れのどれかにする。Agent 4 は、プロジェクト固有観点 (`.aidd/design-perspectives.md` の文言) を渡した reviewer の dispatch があれば起動とする。実行担当の `## 経路` が dispatch と食い違えば「自己申告の食い違い」として別に記す |
| 分岐シードの検出 | キーのコアシードのうち最終報告に残った数 / コアシードの数を、ケースと変種ごとに書く。Agent 4 のシード (キーで観点つきの変種だけに数えると書いたもの) は観点つきの変種の分母にだけ入れ、観点なしの変種で検出されたら「観点なしでの検出」として記録する。拡張シードは別の列にする。手順3の指標には足さない |
| 深刻度一致・デコイ | 手順3と同じ (最終報告で数える) |
| 外部情報の判定 | 主張ごとに、source-verifier の返答 (tools の記録) の判定をキーの期待判定と比べる。**確認済み・反証ありは、その主張に出典 URL があり、かつ tools の記録で source-verifier の Web 呼び出しが1件以上成功している場合だけ一致に数える**。それ以外の確認済み・反証ありは「根拠なし」とし、一致に数えない。期待判定が未確認 (到達不能・一次資料なし) の主張を確認済み・反証ありとしたら「到達不能の誤採点」とし、失敗に数える。source-verifier が起動したのに Web 呼び出しが1件も成功していなければ、その試行を「実行不能」と記録し、未確認以外の判定はすべて根拠なしとする (実行不能は design-review の誤りとは数えないが、正誤は「未測定」と書く) |
| コスト | meta の `total_cost_usd` とモデル別の使用量。agent 別の `total_tokens` |

キー外の指摘は件数と内容だけを記録し、手順4の判定エージェントは使わない (分岐評価では昇格しないため)。

**B6. 結果の保存** — `tests/eval/results/YYYY-MM-DD-branch.md` に保存する (同日に再実行したら `-2` などの連番)。各変種の run の `raw/` を `tests/eval/results/<run-id>/<variant>/` にコピーし、そこで `shasum -a 256 -c SHA256SUMS` が通ること、SHA256SUMS の sha256 が B4 で記録した値と同じことを確かめる。`local/` はコミットしない。記載内容:

- 測定条件の表: 手順5の項目に加え、凍結したコミット・`freeze.sha256` の sha256・変種ごとの SHA256SUMS の sha256・`<budget>`・Web に出られたか (実行した環境の通信の制限)
- 起動判定の表 (変種 × Agent 4/5/6 の期待・実際・判定・自己申告)
- 分岐シードの検出の表 (ケース・変種ごとの分母を書く。コアと拡張を分ける)
- 外部情報の判定の表 (主張ごとの期待・実際・出典・Web 到達・判定)。実行不能の試行は消さずに書く
- 未測定の項目とケースの限界 (変種と試行の数、ケースが1つずつであること、Web の到達が環境に依存すること)
- コストの表 (変種ごとと合計。採点のメインの分は取れなければ「不明」)

**B7. 報告** — 起動判定・外部情報の判定・分岐シードの検出・コストの表を示す。起動漏れ・過剰起動・到達不能の誤採点があれば、どの段 (実行担当の判定・agent の返答) で起きたかを生出力から1行で付記する。結果は design-review の変更の根拠にする前に、再実行で再現を確かめる。

## 注意

- 結果はパイプラインの非決定性を含む1標本にすぎない。1回の悪化で即プロンプトをいじらず、変更判断の前に再実行して再現を確認する
- ゴールデンセットの拡充 (新ケース追加・キー外指摘の昇格) は /aidd:retro の棚卸し対象。ケースを増やしたら本コマンドの argument-hint も更新する
