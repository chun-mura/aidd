---
name: eval
description: design-review パイプラインをゴールデンセットで評価し、検出率・誤棄却率を測定する。impl を付けると、実装レビューを同種 (claude -p) と異種 (codex exec) で同じ欠陥セットに対して比べる
argument-hint: [ケース名 (structure / data-error / security / crosscut)。省略時は全ケース] | impl [ケース名 (tests/eval/impl/cases/ の名前)。省略時は全ケース]
disable-model-invocation: true
---

**パスと引数と質問の扱い**: この文書の相対パスは、この SKILL.md があるディレクトリを起点にする。`$ARGUMENTS` が文字のまま残っている場合（Codex・Cursor など）は、この skill を呼び出したメッセージのうち skill 名以外の部分を `$ARGUMENTS` とみなす。`AskUserQuestion` と書かれた箇所は、ユーザーに質問するツールがあればそれを使い、無ければ質問を書いて作業を止め、回答を待つ。回答が無いまま推測で進めない。

対象ケース: $ARGUMENTS (未指定なら `tests/eval/cases/` 配下の全 `.md`)。先頭が `impl` なら、この下の design-review の手順ではなく、末尾の「実装レビューの比較 (同種・異種)」を行う

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
        if any(k in folded for k in ("tests/eval/keys", "tests/eval/results", "tests/eval/impl/keys", "tests/eval/impl/rubric")):
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

## 注意

- 結果はパイプラインの非決定性を含む1標本にすぎない。1回の悪化で即プロンプトをいじらず、変更判断の前に再実行して再現を確認する
- ゴールデンセットの拡充 (新ケース追加・キー外指摘の昇格) は /aidd:retro の棚卸し対象。ケースを増やしたら本コマンドの argument-hint も更新する
