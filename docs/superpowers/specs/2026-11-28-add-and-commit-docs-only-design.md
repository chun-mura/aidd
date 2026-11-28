---
status: draft
---

# git add と git commit を1回で実行する文書だけのコミットに、test-perspectives の通知を出さない (#197)

規模: hook 1本 (`hooks/scripts/tool-reminder.sh`) の1つの通知と、その契約テストのため要約形式。

## 1. 背景と目的

`tool-reminder.sh` は PreToolUse で `git commit` を見ると `remind_test_perspectives` を呼ぶ。直近6時間に `docs/test-perspectives/` の保存が無ければ、「/aidd:test-perspectives を実行すること」と通知する。ステージ済みの変更 (`git diff --cached`) がすべて文書 (`DOCS_ONLY` = `^docs/`・`.md`・`.txt`) なら、この通知を出さない。

`git add <path> && git commit -F - …` を1回の Bash で実行すると、PreToolUse の時点では前半の `git add` がまだ実行されていない。staged が空に見えるので、文書だけかの判定 (`staged and all(...)`) が偽になり、`.md` 1ファイルのコミットでも通知が出る。明示したパスだけを add してすぐ commit するのは、エージェントでよくある形 (retro 2026-11-28 で摩擦点に選ばれた)。

目的: 同じコマンドの `commit` より前にある `git add` の明示パスを、staged と合わせて判定する。判定できないときは今までどおり通知を出す。

## 2. スコープ / やらないこと

やる:
- 同じコマンドの中で、`commit` より前の `git add` の明示パスを集め、同じリポジトリの commit の判定に足す
- 契約テストに、出す・出さないのケースを足す

やらない:
- 通知の文言、6時間の判定、`DOCS_ONLY` の定義は変えない
- `git commit <pathspec>`・`--only`・`-i` (pathspec でコミットする形) は扱わない (今も staged だけを見ている。別の問題)
- 実際に add されるファイルを git に問い合わせない (`git add --dry-run` など)。hook の中で利用者の引数を git に渡し直すことになるため

## 3. 判定

メインループで、PreToolUse の `git add` を見るたびに、その add が足すパスを記録する。`git commit` を見たら、それまでに記録した同じリポジトリの add のパスを `remind_test_perspectives(directory, added)` に渡す。

**add のパス** (既存の `scan(args, *ADD_OPTIONS)` の positionals を使う):
- `--` は区切りとして除く
- 各パスを add のディレクトリ (`simple_commands` が追跡する `cd` と `git -C` を反映済み) から解決し (`realpath` で `..`・`.`・シンボリックリンクを畳み込む)、`git rev-parse --show-toplevel` からの相対パスにして判定する (staged の `--no-relative` の出力と同じ形)。`docs/../src/app.sh` はコード、`./docs/x.md` は文書になる
- glob は文字のまま判定する (`*.md` は `.md` のファイルにしか当たらないので、`DOCS_ONLY` での当たり方は正しい)。ディレクトリ (`docs/`) は `^docs/` で判定する
- `DOCS_ONLY` の既存の粗さ (`docs/` 配下は拡張子を問わず文書) をそのまま引き継ぐ。add の判定を staged より厳しくも緩くもしない

**不明** (この add があれば、同じリポジトリの commit では通知を出す):
- `-A`・`-u`・`--all`・`--update`・`--pathspec-from-file` (名指ししない。ふだんは `deny_unsafe_git` が拒否するが、`AIDD_DISABLE_GIT_SAFETY=1` では拒否されない)
- `:` で始まる magic pathspec
- シェルがまだ展開する文字 (`$`・バッククォート・`~`・`{}`) を含むパス。hook が見るのは展開前の文字列で、`git add "docs/$X"` や `docs/{a.md,../src.sh}` は展開後に docs の外を指しうる
- パスを1つも名指ししない add (`git add -p`・`-i` など)。何でもステージしうる
- リポジトリの外、またはリポジトリ全体を指すパス (`.` や top そのもの)
- add のリポジトリの top を解決できない場合 (どの commit と同じリポジトリか分からないので、以後のすべての commit を不明にする)

**黙る条件**: staged と add のパスを合わせて空でなく、すべてが `DOCS_ONLY` に当たる。staged が取れない (`None`) とき、または add が不明のときは、今までどおり判定を続ける (6時間の判定に進む)。

**順序**: 記録するのは commit より前の add だけ (`git commit && git add x` の add は、その commit に入らない)。区切り (`&&`・`;`・`||`) は区別しない。`git add x || true; git commit` も add が先に動くので同じに扱う。`git add docs/x.md || git commit` (add が失敗したときだけ commit が動く) でも add のパスを足すので、誤って黙りうる。そのとき add はステージしていないので、staged が空なら commit は失敗し、staged にコードがあれば staged の判定で通知が出る。起きるのは通知が減ることだけなので受け入れる。

## 4. 失敗の扱い

- 判定で起きるのは通知が出る・出ないだけで、許可・拒否は変えない
- ファイルを読まない。git に問い合わせるのは、既存と同じ `rev-parse --show-toplevel` だけ
- 判定できないときは、通知を出す側に倒す

## 5. テスト (`tests/hook-contract-test.sh`)

出さない:
- `git add docs/x.md && git commit -m x` (staged は空)
- `cd docs && git add x.md && git commit -m x`
- `git -C <repo> add notes.md && git -C <repo> commit -m x`
- `git add ./docs/x.md && git commit -m x`

出す:
- `git add docs/../src/app.sh && git commit -m x`
- `git add "docs/$X"`・`docs/$(…)`・`~/x.md`・`docs/{x,y}.md` のあとの commit
- staged に文書があり、`git add -p && git commit`
- `git add src.sh && git commit`
- `git add docs/x.md src.sh && git commit`
- staged に文書以外があり、文書だけを add する
- 別のリポジトリでの add (`cd` を挟む) と、このリポジトリでの commit
- `AIDD_DISABLE_GIT_SAFETY=1` のもとでの `git add -A && git commit`、`git add :/docs && git commit`
- commit の後ろにある add (`git commit -m x && git add docs/x.md`)
- `git add ../outside.md && git commit`
