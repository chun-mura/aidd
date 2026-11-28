# test-perspectives・design-doc・design-review は対話に近い使い方で起動されすぎないか (#204)

0.95.0 (#196) で3つの skill をモデルから起動できるようにした。#196 の測定は、`/aidd:issue-implement` の中での起動と、使うべきでない依頼3件だけだった。ここでは、ふだんの対話で出る依頼を広げて、モデルが自分の判断で3つを起動するかを記録した。**依頼ごとに1試行**なので、起動されなかったことは「この依頼で起動されやすくはない」ことの参考値で、起動されないことの保証ではない。

## 条件

| 項目 | 値 |
|---|---|
| 日時 | 2026-11-28 |
| CLI | Claude Code 2.1.332。`claude -p --model opus --output-format stream-json --verbose --permission-mode acceptEdits --allowedTools Bash --max-budget-usd <上限>` |
| aidd | `--plugin-dir` で作業ツリー (main `dd74699`、0.97.1 と同じ skill と hook) |
| 記録用プラグイン | `--plugin-dir` で別に読み込んだ使い捨てのプラグイン。UserPromptSubmit と PreToolUse(`^Skill$`) の入力をそのままファイルに追記するだけ |
| 対象 | 依頼ごとに作り直す使い捨てのローカル repo (架空の `wordfreq`: Python の関数1つとテスト1件、CLI の設計書、brainstorming で合意したという CSV 出力の spec、未コミットの差分1件)。GitHub には何も書いていない |
| 1ターンの依頼 | プロンプトを引数で渡し、stdin は `/dev/null` |
| 複数ターンの依頼 | `--input-format stream-json` で1つのセッションを保ち、前のターンの `result` を受け取ってから次の発言を送った (先に全部を送ると、2つの発言が1ターンにまとめて処理された: m1) |
| 分離 | HOME は分離していない (利用者の global の設定・CLAUDE.md・ほかのプラグインが効いている)。aidd の状態ファイルは `AIDD_TEST_STATE_DIR` で実行ごとの一時ディレクトリに向けた |

## 結果

「起動」は stream-json の Skill ツールの呼び出しで数え、記録用プラグインの PreToolUse(Skill) の記録と一致した。費用はセッションの `total_cost_usd` (複数ターンでは最後の result の値。セッションの累計)。

### 使うべきでない依頼

| ID | 依頼 | 費用 | Skill の呼び出し | 何をしたか |
|---|---|---|---|---|
| n1 | brainstorming で合意した spec について「区切り文字をカンマ固定にした判断に無理がないか意見をください」 | $0.33 | なし | spec を読んで直接答えた |
| n2 | 「未コミットの変更をレビューして。修正はしないで」 | $0.38 | なし | `git diff` とテストで直接レビューした |
| n3 | 「cli-design.md では `--top` に 0 を渡したときの終了コードは何?」 | $0.31 | なし | 設計書の該当行を引いて答えた |
| n4 | 「README の typo を直して」 | $0.32 | なし | 1か所を直した |
| n5 | 「aidd の design-review と autonomous-review はどう使い分ければいい?」 | $0.27 | なし | ツールを使わずに答えた |
| m1 | (2発言、1ターンにまとまった) spec に1行追記 → 「次に何をすべき? 提案だけ」 | $0.45 | なし | 追記し、次の手として writing-plans を提案した |
| b1 | (3ターン) 「CSV 出力を足したい。一緒に考えて」→「おすすめで決めて spec を書いて」→「この spec で進めて大丈夫そう? 気になる点は?」 | $0.58 | `superpowers:brainstorming` (1ターン目) | 3ターン目は spec を読み返して直接答えた。design-review は起動しなかった |
| b2 | (2ターン) 小さなバグ修正 (句読点を語に含める) →「ほかにやっておくことは? 提案だけ」 | $0.44 | なし | 修正とテスト追加をした |
| b3 | (2ターン) b2 と同じ修正 →「この修正をコミットして」 | $0.50 | なし | ブランチを切ってコミットした。test-perspectives は起動しなかった (下の注) |

b3 の注: 同じ状態 (コードの変更を stage して `git commit`) を `tool-reminder.sh` に再生すると、「直近6時間に観点が無い。この変更で出していなければ `/aidd:test-perspectives` を実行する。trivial な変更や実装済みなら実行しない」という通知を返す。stream-json には hook の `additionalContext` が出ないので、b3 のセッションでこの通知がモデルに届いたことは確かめていない (未確認)。届いていたとしても、通知の「実装済みなら作らない」に沿った振る舞いである。

### 使うべき依頼

| ID | 依頼 | 費用 | Skill の呼び出し | 何をしたか |
|---|---|---|---|---|
| p1 | 「cli-design.md の設計書を、実装に入る前に設計レビューして」 | $0.52 | `aidd:design-review` | 12行の設計書なので、手順どおりエージェントを起動せずに直接レビューし、high/mid の4件を `aidd:refuter` (1体) にかけた |
| p2 | 「cli-design.md の設計で CLI を実装する。実装の前にテスト観点を優先度つきで洗い出して」 | $0.43 | `aidd:test-perspectives` | `docs/test-perspectives/` に観点を保存した |
| p3 | 「`--json` 出力を足したい。エントリポイントと出力形式が増えるので、実装の前に設計書を書いて」 | $0.37 | `aidd:design-doc` | 現状を調べ、決めてほしい点3つを質問して止まった (手順どおり) |

- 使うべきでない依頼9件 (ターンでは13) で、3つの skill は1回も起動されなかった。brainstorming の spec への相談 (n1・b1 の3ターン目)、コードの差分のレビュー (n2)、文書への質問 (n3)、小さな変更 (n4・b2・b3)、skill の名前を含む質問 (n5) のどれでも起動されていない
- 使うべき依頼3件では、それぞれ該当する skill が1回だけ起動され、ほかの2つは起動されなかった
- 起動しすぎは見つからなかったので、description は変えない

## 費用

合計 $4.90 (12セッション)。1セッションあたり $0.27〜0.58。上限は1ターンの使うべきでない依頼が $0.6、使うべき依頼が $1.5、複数ターンが $1.0〜2.0 で、上限に達したセッションは無い。

## usage.json での利用者の起動とモデルの起動

記録用プラグインの記録では、モデルが Skill ツールで起動した p1〜p3 と b1 で PreToolUse(Skill) が発火した (入力に `agent_id` は無く、`permission_mode` は `acceptEdits`)。利用者の発言は UserPromptSubmit だけを通った。利用者が打った slash コマンドは PreToolUse(Skill) を通らないこと (2026-11-14 の設計の R4・R15) と合わせると、hook のイベントの種類で両者を区別できる。

これを使って、0.98.0 で `usage-log.sh` が PreToolUse(Skill) の回数を `usage.json` の `model_counts` にも記録するようにした (`command_counts` はその合計のまま)。この測定の p1〜p3 の実行では `model_counts` を持たない版 (0.97.1) の hook が動いており、`command_counts` に1ずつ入った。

## 対話との違い (この測定の限界)

- `claude -p` は対話の画面ではない。権限の確認 (`AskUserQuestion` を含む) に人が答えられず、`acceptEdits` と `Bash` の許可で代えている。対話では、確認のたびに利用者が介入できるので、起動に至る前に流れが変わりうる
- 複数ターンは stream-json で再現したが、ターン数は2〜3で、長いセッションでの文脈の積み上がり (compact の後、多数の hook の通知が溜まった後など) は再現していない
- サブエージェントの中からの起動、Cursor での起動は測っていない
- 1依頼1試行。モデルの揺らぎで起動される確率が低くても0ではない可能性は残る
- HOME を分離していないので、利用者の global の CLAUDE.md・ほかのプラグイン (superpowers など) の影響を受けた状態の結果である

## 残していないもの

- stream-json の生の出力と使い捨ての repo は、利用者の環境のパスを含むので保存していない
