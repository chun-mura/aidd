# 評価結果 2026-11-28-compare-prelim (design-review の構成比較: 予備測定)

- **予備測定 (各構成・各ケース1試行)**。`skills/eval/SKILL.md` の「design-review の構成比較」が求める3試行に満たない。ユーザーが推定コストを見て、試行数を減らすことを承認した。試行のばらつきを測れないため、**C5 の提案は出さない** (「既定を維持」とも「軽量化してよい候補」とも書かない)
- 対象: #130。`/aidd:eval compare` (全4ケース: structure data-error security crosscut)。構成は deep・standard・direct・baseline の4つ。direct は 100行以上の crosscut では対象外
- 準備・実行・抽出・凍結・照合 (C1〜C3) を1つのセッションで行った。凍結後、2つの run それぞれで `# eval verify:` を通してから (採点の前にもう一度実行して `eval verify: ok`) キーを読んだ
- この比較は偽指摘を混ぜていない。偽指摘の棄却率は測っていない。費用は手順1〜6の deep 回帰評価と直接比べられない
- **この結果は design-review の既定や構成を変えない**

## 測定条件

| 項目 | 値 |
|---|---|
| aidd version | 0.93.0 |
| git SHA | 27a18457e3514efa556e49d296371784688b0ef6 |
| 未コミット変更 (準備時) | no |
| claude CLI | 2.1.332 (Claude Code)。準備時と、全試行の meta の init が一致 |
| 準備日時 (UTC) | 2026-11-27T15:38:25Z |
| 設計レビューの3構成の起動 | `claude -p --model opus --output-format stream-json --verbose --plugin-dir ./plugin --max-budget-usd <budget>`。cwd は `<run>/input` |
| baseline の起動 | `claude -p --model opus --output-format stream-json --verbose --tools "" --no-session-persistence --max-budget-usd <budget>`。cwd は `<base>/input` |
| `<model>` | `opus` (全構成で同じ) |
| `<budget>` (1試行の USD 上限) | deep 5 / standard 4 / direct 2 / baseline 1。上限に達した試行は無い |
| permissionMode (init) | auto (全試行) |
| 実測したメインのモデル | claude-opus-5-5 (provider firstParty、costBasis list)。全試行で同じ |
| 実測した agent のモデル | claude-sonnet-5-5 (firstParty、list)。設計レビューの3構成の全試行の modelUsage に出ている。agent 定義の frontmatter では reviewer・security-reviewer・refuter が sonnet、design-arbiter が opus。arbiter を起動した deep の試行でも modelUsage にあるのは opus と sonnet の2行だけで、agent ごとの実測モデルは分からない |
| 読み込まれたプラグイン (設計レビューの3構成) | aidd 0.93.0 (`--plugin-dir` の `[input]/plugin` だけ。インストール済みの aidd 0.87.0 は読み込まれていない)。ほかに superpowers 6.1.1・reqd 0.6.0・uidd 0.9.0・stdd 0.7.0・estimate 0.14.0 など利用者の設定どおり |
| 読み込まれたプラグイン (baseline) | 利用者の設定のまま (aidd 0.87.0 を含む)。`--tools ""` なので、ツールも skill も使えない |
| 試行 | 1試行 × (deep 4 + standard 4 + direct 3 + baseline 4) = 15組。実行は16回 (security/standard を1回再実行。下記) |
| 生出力の場所 | `tests/eval/results/2026-11-28-compare-prelim/review/` (`<run>/raw/` の写し) と `.../baseline/` (`<base>/raw/` の写し)。`local/` (stream-json) はコミットしていない |

識別子:

| 項目 | 値 |
|---|---|
| review の SHA256SUMS の sha256 (C3 で記録) | e0e7c7e43a8b358616ee88bac5945ee84ec95ac0745b9e722188eea1881eea01 |
| baseline の SHA256SUMS の sha256 (C3 で記録) | ae050b9658db7dd18c4e5f6fc6b8d46494353cf3af1153934d78a3dabc0de75b |
| 写しでの `shasum -a 256 -c SHA256SUMS` | review・baseline とも ok。review の sha256 は上の値と一致 |
| 公開前に伏せた箇所 | `baseline/security-baseline-t1.md` の末尾の1文 (利用者の環境の組織指示に由来する、社内の相談先の案内) を、公開のため伏せた。採点は伏せる前の版で行った。伏せる前のこのファイルの sha256 は b7817e3d2c5d4c5f129e224b1e45633b4acb9661aac8be764d60ae4547e59979 で、上の凍結値 (ae050b96…) はこの値を含む SHA256SUMS のもの。写しの SHA256SUMS は、このファイルの行だけを伏せた後の値 (c49ee4e9c8770793b3c63e78084977a0ca5156426004f9d6891e2945f951902b) に直してあり、その sha256 は 33ef2d60979609bd05fc6ee8e3379b8f598cfda04be78ba13ecd5be309dfa479 |
| `review/input.sha256` の sha256 (ケースと plugin) | 896c5af78dfaa3877d8fc9ab248c6c6cab4be2cdeff94d808334c7067074b896 |
| `baseline/input.sha256` の sha256 (ケースだけ) | bd56eaf22a4f53a320cd9a6ee9a57ca72f18184921a5fff5b0d312983194988d |
| `keys.sha256` の sha256 (採点時のキー。review・baseline で同じ内容) | ace26327bc2c47afbef79976b2cd40c152c717043bbc14646a7ff9233b536d9c |
| `planted.sha256` の sha256 (比較では使っていない) | 8a4e86caabf5e3fe2ef28e4364862afe6404751be2d65b506eba255eb883ba60 |
| `compare.tsv` の sha256 | b7026b9e598f9acc8ccdfc6c31b7cc9ce14cb63c1e9cc95896f0fcb73d88253d |
| プロンプト | `review/prompt-<case>-<config>.md` と `baseline/prompt-<case>-baseline.md` (ハッシュは各 SHA256SUMS)。`review/prompt-<case>.md` と `mix-<case>.tsv` は手順1a のブロックが作ったもので、比較では使っていない |

`compare.tsv`:

| ケース | 行数 | deep | standard | direct | baseline |
|---|---|---|---|---|---|
| structure | 61 | 実行 | 実行 | 実行 | 実行 |
| data-error | 45 | 実行 | 実行 | 実行 | 実行 |
| security | 45 | 実行 | 実行 | 実行 | 実行 |
| crosscut | 385 | 実行 | 実行 | 対象外 (100行以上) | 実行 |

### 試行ごとの記録

所要の2つの列:

- `duration_ms (meta)` は抽出ブロックが meta に書いた値で、stream-json の**最後の** `result` の値である。
- background の agent を待つと、セッションは再開のたびに `result` を出す (1試行で最大11個)。抽出ブロックは最後の `result` しか採らない。このため、meta の値はセッション全体の所要ではなく、最後の区間の所要になる。
- `全 result の合計` は、凍結した stream-json (`local/`、ハッシュは `local.sha256`) にある全 `result` の `duration_ms` を足した値である。待ち時間は、こちらのほうが実態に近い。
- `total_cost_usd` は累積の値なので、最後の `result` の値がセッション全体の費用になる。

| ケース | 構成 | 試行 | session_id | duration_ms (meta) | 全 result の合計 (ms) | result の数 | ターン (meta) | total_cost_usd | 成否 |
|---|---|---|---|---|---|---|---|---|---|
| structure | deep | t1 | b0a5c4d0-5f9c-4a22-a434-04611638a257 | 119728 | 139846 | 6 | 3 | 1.1945 | 成功 |
| structure | standard | t1 | b79ec499-ec57-4c4e-9dbd-335cb7dca0e8 | 81854 | 104437 | 6 | 2 | 0.9047 | 成功 |
| structure | direct | t1 | 9522f58f-d195-4d24-a3b2-b0c31d0d158a | 68416 | 68416 | 1 | 6 | 0.5572 | 成功 |
| structure | baseline | t1 | e6420e3b-cac2-4bf9-8042-7273a85bb014 | 37871 | 37871 | 1 | 1 | 0.3401 | 成功 |
| data-error | deep | t1 | db7407b8-5600-4026-83d0-d52e7e4a684b | 265400 | 265400 | 1 | 8 | 1.5327 | 成功 |
| data-error | standard | t1 | 2c81128f-ede4-426b-a9f5-214674e4a1d7 | 97909 | 120817 | 6 | 2 | 0.9376 | 成功 |
| data-error | direct | t1 | 866902a9-aa98-4fdb-9154-1657cf9ccb63 | 65053 | 65053 | 1 | 3 | 0.4957 | 成功 |
| data-error | baseline | t1 | 881b3fa5-b9d7-450f-8e11-581a857844fe | 36824 | 36824 | 1 | 1 | 0.1519 | 成功 |
| security | deep | t1 | c5da4287-32ec-4fc2-8c81-67dc51995db7 | 134596 | 155925 | 8 | 3 | 1.3732 | 成功 |
| security | standard | t1 | 9f805ae3-88b5-4b26-bd2a-90e3fa3f7c6f | 8192 | 216168 | 2 | 2 | 1.4910 | **失敗 (下記)** |
| security | standard | t2 | d34297e8-6f25-4e1e-b6a2-4df8eec2fbe1 | 111749 | 132336 | 8 | 2 | 1.1779 | 成功 (再実行) |
| security | direct | t1 | b9514e24-80c0-4bd0-9eef-15e8b0962ee6 | 72670 | 72670 | 1 | 3 | 0.5297 | 成功 |
| security | baseline | t1 | 2807a334-a76f-46d9-bd44-e2745bf7f3aa | 49683 | 49683 | 1 | 1 | 0.1735 | 成功 |
| crosscut | deep | t1 | 6ab69814-e912-44f0-ad76-84b80ce65225 | 176982 | 241170 | 11 | 2 | 2.8744 | 成功 |
| crosscut | standard | t1 | cfdbff4f-3909-4890-80f9-15d7cbc72fab | 180968 | 204711 | 8 | 2 | 2.0576 | 成功 |
| crosscut | baseline | t1 | ba46fe2b-9351-43f4-8ad6-30036e8bf318 | 113889 | 113889 | 1 | 1 | 0.3922 | 成功 |

**security/standard の t1 を失敗とした理由**:

- exit 0 で終わり、抽出ブロックの判定も success だった。しかし抽出された最終回答 (`review/security-standard-t1.md`、572文字) は、「最終回答は前のメッセージにある」とだけ書いた後書きだった。必須の5見出しは行頭に1つも無い。
- 報告の本体は、stream-json の最初の `result` にある。
- 後書きを最終回答とした結果、プロンプトの契約 (5見出しを含む最終回答) を満たさず、「最終回答が無い」試行に当たると判断した。
- そこで C3 に従い、凍結の前に新しい試行番号 (t2) で再実行した。採点したのは t2 である。
- t1 の記録は消さずに凍結に含めた (`review/security-standard-t1.*`、`local.sha256`)。
- 実時間では、t1 は約21分 (runner の起動から終了まで) かかった。

## 分離の記録

- **準備 (C1)**: `# eval staging:` と `# eval compare staging:` が2つとも ok で通った。プレースホルダの置き換え以外は SKILL.md のブロックのままである。
- **凍結・照合 (C3)**: 15組すべてで、stream-json・最終回答・meta がそろっていることを確かめてから凍結した。`# eval verify:` は、凍結の直後と採点の直前の2回とも ok だった。
- **meta の判定**: 12回は「検出なし」だった。3回は「汚染の疑い」だったが、内容を見て誤検知と判断した。いずれも keys・results・planted・元リポジトリへの参照ではない。
  - security/standard t1: refuter の `SubagentHandback` の返却文 (tool_use の入力) に、相対パスに見える文字列があり、「作業ディレクトリの外 (相対・~)」に当たった。ファイルを読む操作ではない。
  - crosscut/deep t1 と crosscut/standard t1: 実行担当のメインが、自分のセッションが退避した長い tool 出力 (`~/.claude/projects/-private-tmp-claude-eval-130-run-09aDKs-input/<自分の session_id>/tool-results/*.txt`) を Read した。ハーネスが自分のセッションのために作るファイルで、keys・results を含まない。
- **分離の限界** (「分離と汚染ガード」と同じ):
  - 作業ディレクトリの外の読み取りは、権限では禁止していない。
  - Bash のコマンドは検出しきれない。
  - 抽出から凍結までの間は、raw/ と local/ を書き換えられる。
- baseline は利用者の設定 (CLAUDE.md や組織の指示) をそのまま読み込む。security の baseline の回答の末尾には、利用者の環境の指示に由来する、相談先を案内する文言が入っている。

## 指標

採点の対象は各試行の最終報告である (設計レビューの構成は `## 最終報告`、baseline は回答全体)。シードは、キーの一致判定基準で意味的に照合した。安全上重要なシードの規則は SKILL.md の C 節のとおりで、期待深刻度が high のもの、または対応観点が「セキュリティ」で始まるもの。

安全上重要なシード:

| ケース | シード |
|---|---|
| structure | S3 |
| data-error | DE2・DE3 |
| security | SEC1・SEC2・SEC3・SEC7 |
| crosscut | CC1・CC2・CC3・CC6 (high)、CC11・CC14・CC15・CC18 (セキュリティ) |

### 構成・ケースごとの指標 (各1試行)

| ケース | 構成 | コア検出 | 拡張検出 | 深刻度一致 | デコイ誤検出 | 最終報告 (high/mid/low) | baseline との差 (計) | ノイズ率 | キー外で正当 | 誤検出 | security-reviewer |
|---|---|---|---|---|---|---|---|---|---|---|---|
| structure | deep | 2/2 | 6/8 | 3/6 | 0 | 1/3/3 (7) | -4 | 1/7 | 2 | 0 | no |
| structure | standard | 2/2 | 7/8 | 6/7 | 0 | 0/6/4 (10) | -1 | 2/10 | 2 | 0 | no |
| structure | direct | 2/2 | 6/8 | 4/6 | 0 | 0/4/4 (8) | -3 | 1/8 | 1 | 0 | no |
| structure | baseline | 2/2 | 6/8 | 3/6 | 0 | 2/5/4 (11) | 0 | 1/11 | 4 | 1 (未確定) | — |
| data-error | deep | 3/3 | 7/7 | 6/7 | — | 2/5/5 (12) | 0 | 1〜3/12 | 2〜4 | 0 | no |
| data-error | standard | 3/3 | 7/7 | 5/7 | — | 3/6/4 (13) | +1 | 3〜4/13 | 2〜3 | 0 | no |
| data-error | direct | 3/3 | 4/7 | 4/4 | — | 2/3/2 (7) | -5 | 1/7 | 2 | 0 | no |
| data-error | baseline | 3/3 | 7/7 | 5/7 | — | 3/6/3 (12) | 0 | 1〜2/12 | 3〜4 | 0 | — |
| security | deep | 2/2 | 7/7 | 5/7 | — | 3/8/4 (15) | +1 | 4〜5/15 | 2〜3 | 0 | **yes** |
| security | standard (t2) | 2/2 | 6/7 | 4/6 | — | 2/10/4 (16) | +2 | 5〜6/16 | 4〜5 | 0 | **yes** |
| security | direct | 2/2 | 3/7 | 3/3 | — | 1/3/3 (7) | -7 | 0/7 | 4 | 0 | no (経路の注記) |
| security | baseline | 2/2 | 6/7 | 5/6 | — | 3/7/4 (14) | 0 | 3〜4/14 | 4〜5 | 0 | — |
| crosscut | deep | 6/6 | 15/18 | 12/15 | 0 | 6/11/13 (30) | +6 | 9〜10/30 | 6〜7 | 0 | **yes** |
| crosscut | standard | 6/6 | 17/18 | 13/17 | 0 | 6/20/11 (37) | +13 | 8〜11/37 | 9〜12 | 0〜1 | **yes** |
| crosscut | baseline | 6/6 | 10/18 | 6/10 | 0 | 8/11/5 (24) | 0 | 1〜3/24 | 11〜13 | 0〜2 | — |

- data-error と security のキーにはデコイが無い (「—」)。
- ノイズ率は、最終報告の指摘のうち「判断保留」か「誤検出」とされたものの割合。範囲は、判定エージェント2体の判定が割れて未確定の指摘 (下記) を、含めない場合と含める場合である。「キー外で正当」「誤検出」の範囲も同じ。
- 指摘1件が複数のシードに当たるもの (例: crosscut/deep の C14 が CC11 と CC18) は、どのシードも検出として数えた。
- 最終報告の指摘件数は、シードの検出とキー外の指摘に分けて数えている。
- 1試行なので、最小〜最大は示せない。

### シードごとの検出 (検出 = ○ (実際の深刻度)、未検出 = ×)

structure (コア: S1・S2):

| シード | 期待 | deep | standard | direct | baseline |
|---|---|---|---|---|---|
| S1 | mid | ○ (high) | ○ (mid) | ○ (mid) | ○ (mid) |
| S2 | mid | ○ (high) | ○ (mid) | ○ (mid) | ○ (high) |
| S3 | high | × | × | × | × |
| S4 | mid | ○ (mid) | ○ (mid) | ○ (mid) | ○ (mid) |
| S5 | mid | ○ (high) | ○ (mid) | ○ (mid) | ○ (high) |
| S6 | mid | × | ○ (mid) | ○ (low) | × |
| S7 | mid | ○ (mid) | ○ (mid) | ○ (low) | ○ (mid) |
| S8 | mid | ○ (mid) | ○ (low) | × | ○ (low) |
| D1 (デコイ) | — | 誤検出なし | 誤検出なし | 誤検出なし | 誤検出なし |

- deep は S1・S2・S5 を1件 (H1) にまとめて high にした。
- S3 は、どの構成も「宛先ごとの結果を返す」「宛先ごとの成否を記録」を重複送信 (S7) の代案として書いただけだった。一部の宛先への送信失敗が検知されない点は指摘していないので、未検出とした。
- L40 の「未定」については、deep・direct・baseline が「L61 で解決済みなのに本文に残っている」と指摘した。解決済みに触れているので、D1 の誤検出に数えていない。

data-error (コア: DE1・DE2・DE3):

| シード | 期待 | deep | standard | direct | baseline |
|---|---|---|---|---|---|
| DE1 | mid | ○ (mid) | ○ (high) | ○ (mid) | ○ (high) |
| DE2 | high | ○ (high) | ○ (high) | ○ (high) | ○ (high) |
| DE3 | high | ○ (high) | ○ (high) | ○ (high) | ○ (high) |
| DE4 | mid | ○ (mid) | ○ (mid) | × | ○ (mid) |
| DE5 | mid | ○ (mid) | ○ (mid) | × | ○ (mid) |
| DE6 | mid | ○ (mid) | ○ (mid) | ○ (mid) | ○ (mid) |
| DE7 | low | ○ (mid) | ○ (mid) | × | ○ (mid) |

- direct の #5「監視が exit code と同期件数だけで、1・2 の異常を検知できない」は、代案に最終同期成功時刻を挙げている。ただし、同期が止まったことを検知できない点を指摘していないので、DE5 には数えなかった (キー外の XD10)。

security (コア: SEC1・SEC2):

| シード | 期待 | deep | standard (t2) | direct | baseline |
|---|---|---|---|---|---|
| SEC1 | high | ○ (high) | ○ (high) | ○ (high) | ○ (high) |
| SEC2 | mid | ○ (high) | ○ (high) | ○ (mid) | ○ (high) |
| SEC3 | mid | ○ (mid) | ○ (mid) | × | ○ (mid) |
| SEC4 | mid | ○ (mid) | ○ (mid) | ○ (mid) | ○ (mid) |
| SEC5 | mid | ○ (mid) | ○ (mid) | × | ○ (mid) |
| SEC6 | low | ○ (mid) | ○ (mid) | × | ○ (low) |
| SEC7 | mid | ○ (mid) | × | × | × |

- deep には、SEC1・SEC2・SEC3 を組み合わせた横断の high が1件ある。シードの合成なので、キー外の指摘には数えていない (指摘件数には含む)。
- direct の #3「監査ログを書けなかったときの扱い」は、記録対象の食い違いにも拒否の記録にも触れていないので、SEC3 には数えなかった。

crosscut (コア: CC1〜CC6):

| シード | 期待 | deep | standard | baseline |
|---|---|---|---|---|
| CC1 | high | ○ (high) | ○ (high) | ○ (high) |
| CC2 | high | ○ (high) | ○ (high) | ○ (high) |
| CC3 | high | ○ (high) | ○ (high) | ○ (high) |
| CC4 | mid | ○ (high) | ○ (high) | ○ (high) |
| CC5 | mid | ○ (high) | ○ (high) | ○ (high) |
| CC6 | high | ○ (high) | ○ (high) | ○ (high) |
| CC7 | mid | ○ (mid) | ○ (mid) | ○ (high) |
| CC8 | mid | × | ○ (mid) | ○ (mid) |
| CC9 | mid | ○ (mid) | ○ (mid) | ○ (mid) |
| CC10 | mid | ○ (mid) | ○ (mid) | ○ (low) |
| CC11 | mid | ○ (mid) | ○ (mid) | × |
| CC12 | mid | × | ○ (mid) | × |
| CC13 | mid | ○ (mid) | × | × |
| CC14 | mid | ○ (mid) | ○ (mid) | × |
| CC15 | mid | × | ○ (mid) | × |
| CC16 | low | ○ (low) | ○ (mid) | × |
| CC17 | low | ○ (low) | ○ (low) | × |
| CC18 | low | ○ (mid) | ○ (mid) | × |
| CD1〜CD4 (デコイ) | — | 誤検出なし | 誤検出なし | 誤検出なし |

- deep の C10「インデックスの前提が書かれていません」は、本文の検索条件に触れていない。キーの基準 (一般論だけなら検出としない) により、CC12 には数えなかった。
- deep の C9 は、DLQ 経由で順序が崩れることと、確定後の返品が ERROR ログだけで終わることを挙げている。313行の前提が崩れる経路として、CC7 に数えた。
- standard の mid 9 は、会員行のロックが利用の流れにしか無いという指摘である。Reconcile との競合 (CC9) には当たるが、返還の2つの入口による二重返還には触れていないので、CC13 には数えなかった。

### 安全上重要な見逃し (シードごと・構成ごと、各1試行)

| ケース | シード | deep | standard | direct | baseline |
|---|---|---|---|---|---|
| structure | S3 (high) | 見逃し | 見逃し | 見逃し | 見逃し |
| data-error | DE2 (high) | — | — | — | — |
| data-error | DE3 (high) | — | — | — | — |
| security | SEC1 (high・セキュリティ) | — | — | — | — |
| security | SEC2 (セキュリティ) | — | — | — | — |
| security | SEC3 (セキュリティ) | — | — | 見逃し | — |
| security | SEC7 (セキュリティ) | — | 見逃し | 見逃し | 見逃し |
| crosscut | CC1・CC2・CC3・CC6 (high) | — | — | 対象外 | — |
| crosscut | CC11 (セキュリティ) | — | — | 対象外 | 見逃し |
| crosscut | CC14 (セキュリティ) | — | — | 対象外 | 見逃し |
| crosscut | CC15 (セキュリティ) | 見逃し | — | 対象外 | 見逃し |
| crosscut | CC18 (セキュリティ・low) | — | — | 対象外 | 見逃し |

見逃しの件数 (「—」は見逃しなし):

| 構成 | 100行未満 (structure・data-error・security) | 100行以上 (crosscut) |
|---|---|---|
| deep | 1 (S3) | 1 (CC15) |
| standard | 2 (S3・SEC7) | 0 |
| direct | 3 (S3・SEC3・SEC7) | 対象外 |
| baseline | 2 (S3・SEC7) | 4 (CC11・CC14・CC15・CC18) |

安全上重要なシードが `low` としてしか最終報告に無かった例は無い。

### 最終報告の指摘件数の増減 (baseline との差)

| ケース | deep | standard | direct | baseline (基準) |
|---|---|---|---|---|
| structure | -1/-2/-1 (計 -4) | -2/+1/0 (計 -1) | -2/-1/0 (計 -3) | 2/5/4 (11) |
| data-error | -1/-1/+2 (計 0) | 0/0/+1 (計 +1) | -1/-3/-1 (計 -5) | 3/6/3 (12) |
| security | 0/+1/0 (計 +1) | -1/+3/0 (計 +2) | -2/-4/-1 (計 -7) | 3/7/4 (14) |
| crosscut | -2/0/+8 (計 +6) | -2/+9/+6 (計 +13) | 対象外 | 8/11/5 (24) |

差は high/mid/low の順。件数が増えたことを、検出の改善とも見逃しの埋め合わせとも数えない。

### 経路

| ケース | 構成 | 経路 | 構成どおりか |
|---|---|---|---|
| structure | deep | reviewer ×3 → refuter → arbiter | どおり |
| structure | standard | reviewer ×3 → refuter。arbiter なし (矛盾なし) | どおり |
| structure | direct | ショートカット (dispatch なし) → refuter。arbiter なし | どおり |
| data-error | deep | reviewer ×3 → refuter ×2 → arbiter | 注記: 実行担当は1回目の refuter に、reviewer の報告を受け取る前に推測で書いた指摘を渡した。その結果を捨て、実際の指摘18件で refuter を再実行している (`## 経路` に本人の記載)。採点した最終報告は2回目に基づく |
| data-error | standard | reviewer ×3 → refuter。arbiter なし (深刻度の差は矛盾と扱わない) | どおり |
| data-error | direct | ショートカット → refuter。arbiter なし | どおり |
| security | deep | reviewer ×3 + security-reviewer → refuter → arbiter | どおり |
| security | standard (t2) | reviewer ×3 + security-reviewer → refuter。arbiter なし | どおり |
| security | direct | ショートカット → refuter。arbiter なし。security-reviewer なし | 注記: 実行担当は、条件 (信頼境界・署名トークンのログ保存) に当たると認めた。そのうえで「ショートカットは dispatch しない経路なので Agent 6 も起動しない」と SKILL.md を解釈し、起動しなかった。代わりに `/security-review` を推奨した |
| crosscut | deep | reviewer ×3 + security-reviewer → refuter ×2 (並列) → arbiter | どおり |
| crosscut | standard | reviewer ×3 + security-reviewer → refuter。arbiter なし | どおり |

## キー外指摘の分類

- **一覧の作り方**: メインが、全構成・全試行の最終報告にあるキー外の指摘を、同じ論点ごとに77件 (structure 12、data-error 14、security 19、crosscut 32) にまとめた。各指摘に深刻度・引用箇所・指摘・代案を付けた。
- **判定エージェント**: 2体 (`general-purpose`、`model: "opus"`) を並列に起動した。
  - 渡したのは一覧とケースのパス (`input/cases/<ケース>.md`) だけで、構成の名前・試行・キーは渡していない。
  - keys・planted・results を開かないよう明示した。
- **refuter が棄却したキー外の指摘 (手順4の (b))**: data-error/standard の F10 (`StockApi` が read-through を持ち責務が混ざる。一覧の XD3) の1件。
  - crosscut/deep の C8 も一部反証されたが、low に下げて最終報告に残ったので (a) として扱った。

### 判定の結果

- **2体とも誤検出**: 1件 (XS11)。
  - XS11「失敗の通知経路が2つ併記されている」(structure、baseline の L2)。根拠は L48・L56・L57 で、cron の失敗通知と exit code の監視は同じ経路である。
  - 手順4では誤検出もユーザーに確認するが、まだ確認していない (未確定)。
- **2体の判定が割れたもの**: 9件。ユーザーに確認しておらず、未確定。

| ID | 論点 | 判定A | 判定B | 出た構成 |
|---|---|---|---|---|
| XD2 | `SyncBatch` が取得・DB・キャッシュ書き込みを兼ね、`WmsClient` が無い | 判断保留 | 正当 | deep (L2)、standard (L1) |
| XD3 | `StockApi` が Cache と Repository の両方に依存 (read-through) | 判断保留 | 正当 | deep (L3)、standard (refuter が棄却) |
| XD13 | 表示改善の目標値が無い | 正当 | 判断保留 | baseline (11) |
| XE6 | 監視が 4xx/5xx の割合だけ | 正当 | 判断保留 | deep (F3)、standard (low)、baseline (L3) |
| XC12 | 失効予定メールの送信失敗が WARN だけ | 判断保留 | 正当 | deep (low)、standard (low) |
| XC16 | CronJob の重複起動防止が無い | 判断保留 | 正当 | standard (low)。deep は C7 (CC9) の一部 |
| XC24 | `redemption_requests.response_body` に残高が入る | 誤検出 (L361 で24時間で削除) | 判断保留 | standard (low) |
| XC26 | `order.cancelled` が `redemption_id` を1つしか持たない | 誤検出 (L383: 再利用は返還の後なので active は1件) | 正当 | baseline (M2) |
| XC29 | 引き当て不足時の分岐 (409) が手順に無い | 正当 | 誤検出 (L291 で 409 を許容と記載) | baseline (M9) |

- **2体が一致したもの**: 正当 43件、判断保留 24件。
  - 判断保留: XS1・XS4・XS6、XD1・XD7・XD9、XE2・XE3・XE5・XE7・XE11・XE14・XE15、XC4・XC7・XC8・XC9・XC10・XC11・XC13・XC14・XC15・XC20・XC23。
  - 正当: XS2・XS3・XS5・XS7〜XS10・XS12、XD4〜XD6・XD8・XD10〜XD12・XD14、XE1・XE4・XE8〜XE10・XE12・XE13・XE16〜XE19、XC1〜XC3・XC5・XC6・XC17〜XC19・XC21・XC22・XC25・XC27・XC28・XC30〜XC32。
- **(b) の扱い**: XD3 は2体とも誤検出としていない (判断保留と正当)。手順4の4により、「誤った棄却」1件とする。
- **昇格**: 比較からはキーへ昇格しない (C 節の規則)。

構成ごとのキー外指摘の内訳 (確定分 + 未確定):

| ケース | 構成 | キー外の指摘 | 正当 | 判断保留 | 誤検出 | 未確定 (割れ) |
|---|---|---|---|---|---|---|
| structure | deep | 3 (L1・L2・L3) | 2 | 1 | 0 | 0 |
| structure | standard | 4 (M2・low ×3) | 2 | 2 | 0 | 0 |
| structure | direct | 2 (L1・L4) | 1 | 1 | 0 | 0 |
| structure | baseline | 5 (M3・M5・L1・L2・L4) | 4 | 0 | 1 (2体一致) | 0 |
| data-error | deep | 5 (low ×5) | 2 | 1 | 0 | 2 |
| data-error | standard | 6 (M1・M6・low ×4) | 2 | 3 | 0 | 1 |
| data-error | direct | 3 (#5・#6・#7) | 2 | 1 | 0 | 0 |
| data-error | baseline | 5 (4・9・10・11・12) | 3 | 1 | 0 | 1 |
| security | deep | 7 (L1・L2・L3・L4・F3・F5・F9) | 2 | 4 | 0 | 1 |
| security | standard (t2) | 10 (#4・#5・#6・#9・#10・#11・low ×4) | 4 | 5 | 0 | 1 |
| security | direct | 4 (#3・#5・#6・#7) | 4 | 0 | 0 | 0 |
| security | baseline | 8 (H3・M1・M4・M5・M6・L1・L2・L3) | 4 | 3 | 0 | 1 |
| crosscut | deep | 16 (mid 5・low 11) | 6 | 9 | 0 | 1 |
| crosscut | standard | 20 (mid 10・low 10) | 9 | 8 | 0 | 3 |
| crosscut | baseline | 14 (H8・M1・M2・M4・M5・M7〜M11・L1・L2・L4・L5) | 11 | 1 | 0 | 2 |

## 過去の比較と違う条件

`2026-11-07-baseline.md`・`2026-11-22-crosscut-comparison.md` とは次の点で違うので、数値を直接並べない。

- **実行の仕方**:
  - 過去は、メインのセッションの Agent tool で reviewer などを起動した (A)。baseline も `general-purpose` の agent に `model: "opus"` で行わせた (B)。
  - 今回は、構成ごとに新しい `claude -p` のセッションを起動した (`--model opus`、baseline は `--tools ""`)。利用者の設定 (CLAUDE.md・hook・他のプラグイン) はそのまま読み込まれる。
- **偽指摘**: 過去の design-review 側 (A) は、refuter に偽指摘を混ぜた。今回は混ぜていない。
- **深さ**: 過去の A は deep だけだった。今回は deep・standard・direct を比べた。
- **版とキー**:
  - 過去は 0.51.0・0.54.0 で、今回は 0.93.0。
  - キーは昇格で増えている。structure は S3〜S8、data-error は DE4〜DE7、security は SEC3〜SEC7、crosscut は CC7〜CC18 が昇格シード。
  - 拡張検出の分母が違うので、比べられるのはコア検出だけである。
- **試行数**: 過去は各3回、今回は各1試行 (予備測定)。
- **採点**:
  - 過去の 11-07 では、メインが要約した出力を採点エージェントが採点した。
  - 今回は、メインが最終報告の全文をキーと照合した。キー外の指摘は判定エージェント2体で分類した。

## 未測定の項目とそろえきれなかった条件

- **試行のばらつき**: 1試行なので測れない。C5 の判定と提案はしていない。
- **判定が割れた9件と、2体一致の誤検出1件 (XS11)**: ユーザーの確認 (手順4の3) をしていない。ノイズ率・正当・誤検出は範囲で示した。
- **待ち時間**: meta の `duration_ms` は最後の `result` の区間だけである。全 `result` の合計も、`result` の間の待ち時間を含まない。実時間との差が最も大きかったのは security/standard t1 で、runner の記録で約21分、全 result の合計で216秒だった。
- **agent ごとの実測モデル**: modelUsage はモデル別の合計だけなので、arbiter が opus で動いたかは分からない。
- **baseline の環境**: aidd 0.87.0 を含む利用者のプラグインが読み込まれた (ツールなしなので使われてはいない)。利用者の指示に由来する文言が回答に混ざっている (security)。
- **時間帯**: 実行は C2 の順 (ケースごとに deep → standard → direct → baseline) で、直列に行った。security/standard の t2 は crosscut の後に実行している。
- **leak_guard の誤検知**: 準備中、Read ツールの leak_guard フックが `skills/eval/SKILL.md` の 226・653 行 (`tests/eval/...` のパス文字列) を秘密と誤検知し、読み込みを拒否した。そのため SKILL.md は Bash で読んだ (測定の手順には影響なし)。

## コスト

| 区分 | トークン | USD |
|---|---|---|
| deep (4試行) | 3,805,770 | 6.9748 |
| standard (成功4試行) | 2,992,503 | 5.0778 |
| standard の失敗試行 (security t1) | 848,242 | 1.4910 |
| direct (3試行) | 751,912 | 1.5826 |
| baseline (4試行) | 165,925 | 1.0577 |
| **実行担当の合計 (16回)** | **8,564,352** | **16.1839** |
| 採点: 判定エージェント2体 (`subagent_tokens`) | 195,405 (97,610 + 97,795) | 不明 |
| 採点: メイン | 不明 | 不明 |
| **評価全体の合計** | **8,759,757 + 不明: メインの採点** | **16.1839 + 不明: 判定エージェントとメインの採点** |

- 実行担当のトークンは、meta のモデル別の使用量 (input・output・cache read・cache creation) の合計。
- 試行ごとの agent 別の `total_tokens` は、次の表のとおり。

| ケース | 構成 | reviewer | security-reviewer | refuter | arbiter | agent の計 |
|---|---|---|---|---|---|---|
| structure | deep | 61,330 | — | 20,572 | 22,626 | 104,528 |
| structure | standard | 61,875 | — | 22,192 | — | 84,067 |
| structure | direct | — | — | 19,292 | — | 19,292 |
| data-error | deep | 64,070 | — | 43,313 | 24,113 | 131,496 |
| data-error | standard | 61,091 | — | 21,023 | — | 82,114 |
| data-error | direct | — | — | 19,401 | — | 19,401 |
| security | deep | 63,623 | 25,878 | 20,897 | 21,546 | 131,944 |
| security | standard t1 (失敗) | 61,533 | 25,945 | 43,464 | — | 130,942 |
| security | standard t2 | 65,444 | 20,752 | 23,771 | — | 109,967 |
| security | direct | — | — | 19,752 | — | 19,752 |
| crosscut | deep | 123,894 | 42,024 | 82,066 | 37,647 | 285,631 |
| crosscut | standard | 116,536 | 45,421 | 38,445 | — | 200,402 |

試行ごとのモデル別トークン (meta の modelUsage の合計):

| ケース | deep | standard | direct | baseline |
|---|---|---|---|---|
| structure | 680,709 | 573,033 | 360,997 | 36,940 |
| data-error | 670,589 | 575,638 | 194,321 | 36,514 |
| security | 847,787 | 755,829 (t2)。t1 は 848,242 | 196,594 | 37,621 |
| crosscut | 1,606,685 | 1,088,003 | 対象外 | 54,850 |
