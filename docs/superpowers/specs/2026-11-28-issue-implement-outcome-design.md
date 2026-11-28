---
status: draft
---

# issue-implement の終了状態を outcome.json に残す (#191)

規模: skill 1本の文言 + 検証スクリプト1本 + テスト1本のため要約形式。

## 1. 背景と目的

非対話のホスト (`claude -p`・Agent SDK) が `/aidd:issue-implement <N>` を起動したとき、完了したのか、質問で止まったのか、止まったのかを最終テキストから推測するしかない。終了時に機械可読の `outcome.json` を残し、ホストがこれだけで次の動作 (依頼者に質問を渡す・人に回す・レビューへ進む) を決められるようにする。

ホストは質問で止まったセッションを再開せず、回答を issue に書き足してから issue とブランチで新しく実行し直す前提とする (非エンジニア向け改修依頼システムの設計での決定。#191 本文の `--resume` 前提から変えた)。このため質問は、前の会話を読まなくても分かる文にする。

## 2. スコープ / やらないこと

やる:
- 実行の最初に実行IDディレクトリを作り、止まるたびに `.aidd/issue-implement/<実行ID>/outcome.json` を書く (status・reason・questions・completion・artifacts)
- スキーマを検証スクリプトで固定する (書き込み時に検証し、外れた値は書かない)
- SKILL.md の停止点ごとに、書く status と reason を機械で読める印で明記する

変わる挙動 (対話セッション): 手順・質問の仕方・完了報告の中身は変えない。ただし止まる前に `python3` でスクリプトを1回実行するので、権限設定によっては実行の許可を求める確認が増える。

やらない:
- 費用 (`total_cost_usd`) を outcome に持たない。セッションは自分の費用を知らず、値はホストが読む `result` イベントにある。1件の費用は実装後に別途測って `tests/eval/results/` に記録する
- 再開の仕組み (前回の outcome を読んで続きから進める) を持たない。再実行は毎回最初から
- 中断 (セッションの強制終了・時間切れ) を outcome で表さない。書かれないこと自体が異常終了の印になる (5 を参照)
- autonomous-review の最終判定を outcome に写さない。ホストは autonomous-review を別に起動し、その `state.json` を読む
- ホスト側 (aidd-autopilot) の変更

## 3. 構成と責務

| コンポーネント | 配置 | 責務 |
|---|---|---|
| 停止点と status の対応 | `skills/issue-implement/SKILL.md` (新しい節「8. 終了状態の記録」と、各停止点の行末の印) | どの停止点でどの status・reason を書くかを決める。判断は model が行う |
| スキーマと書き込み | `scripts/issue-outcome.py` (標準ライブラリだけ、`python3 -I` で実行) | 実行IDディレクトリの作成、入力の検証、原子的な書き込み、ホスト向けの検証。判断はしない |
| 契約テスト | `tests/issue-outcome-test.sh` | スクリプトの拒否条件を1件ずつ確かめ、SKILL.md の印・8 節の表・スクリプトの列挙値の3つが一致することを確かめる |

スクリプトは `learnings.py` と同じく、SKILL.md のディレクトリを起点に `../../scripts/issue-outcome.py` を解決した絶対パスで呼ぶ (利用側リポジトリの同名ファイルを実行しないため)。

## 4. インターフェース

```
python3 -I <issue-outcome.py> start            # .aidd/issue-implement/<実行ID>/ を作り、その絶対パスを1行で出す
python3 -I <issue-outcome.py> write <run-dir>  # stdin の JSON を検証し <run-dir>/outcome.json に書く (git を呼ばない)
python3 -I <issue-outcome.py> check <file> [--issue N]  # ホスト用: 検証だけして結果を出す
```

- `start` は 1 の着手ゲートの前に必ず1回呼ぶ。git のトップレベルの下に作る。環境変数 `AIDD_ISSUE_IMPLEMENT_RUN_ID` があれば、その値 (形式を検証する) を実行IDに使う。ホストが自分の実行の outcome の場所を事前に知るため
- `write` は git もネットワークも使わない。5 の「監査の新しいセッションを起動した run のあと」でも、この1回だけは実行してよい (SKILL.md :59 の例外として明記する)
- 終了コード: 0 = 成功 / 1 = 入力が検証に通らない (理由を stderr に1行ずつ。値は繰り返さない) / 2 = 実行の失敗 (git のトップレベルが無い、書き込めない、ディレクトリが既にある等)

`write` に渡す JSON (`schema_version` と `run_id` はスクリプトが run-dir の名前から付ける):

```json
{
  "issue": "191",
  "status": "needs_input",
  "reason": null,
  "questions": [
    {"question": "…", "kind": "spec_choice",
     "options": [{"label": "…", "effect": "選ぶと何が起きるか"}, {"label": "…", "effect": "…"}]}
  ],
  "completion": null,
  "artifacts": {"design_doc": null, "test_perspectives": "docs/test-perspectives/2026-11-28-x.md"}
}
```

| キー | 型 | 値 |
|---|---|---|
| `schema_version` | number | `2` だけ (#223 で `completion.security_review` を足して 1 から上げた) |
| `run_id` | string | `YYYYMMDDTHHMMSSZ-<8桁の16進>`。run-dir の名前と同じ |
| `issue` | string \| null | 対象 issue の番号 (`^[1-9][0-9]*$`)。取得できなければ `null` |
| `status` | string | `done` / `needs_input` / `blocked` |
| `reason` | string \| null | `blocked` のときだけ下表の値。ほかは `null` |
| `questions` | array | `needs_input` のときだけ1件以上。ほかは空配列 |
| `questions[].kind` | string | `spec_choice` (仕様の選択) / `approval` (起票・棄却などの承認) |
| `questions[].options` | array | 2〜4件。各 `{label, effect}` |
| `completion` | object \| null | `done` のときだけ `{"verification": "passed", "undecided_rows": 0, "untracked_deferred": 0, "security_review": "ran" \| "not_required"}` (この値以外は拒否)。ほかは `null` |
| `artifacts` | object | キーは `design_doc` と `test_perspectives` の2つだけ。値は `null` か、トップからの相対パスで実在する通常のファイル (途中を含めシンボリックリンクをたどらない) |

`write` / `check` が拒否する条件 (契約テストで1件ずつ確かめる):

- JSON として読めない (深すぎる入れ子を含む)、ID・issue 番号に末尾の改行がある、パスに NUL がある、最上位がオブジェクトでない、キーの重複、表に無いキー・欠けたキー (入れ子も)
- 型・列挙値の外れ、上の status ごとの組み合わせ (reason・questions・completion) の外れ
- stdin・ファイルが UTF-8 でない、文字列が UTF-8 にできない (孤立サロゲート)
- `question`・`label`・`effect` が文字列でない・空白だけ、または長すぎる (`question` 1000字、`label` 80字、`effect` 400字を超える)。options の `label` の重複
- `artifacts` のパスが絶対パス・`..` を含む・実在しない・通常のファイルでない
- `write`: run-dir がトップの下の `.aidd/issue-implement/<実行IDの形式>` でない、run-dir かその親 (`.aidd`・`.aidd/issue-implement`) がシンボリックリンク、`outcome.json` がシンボリックリンク
- `check`: ファイルが `.aidd/issue-implement/<実行IDの形式>/outcome.json` の配置に無い、その途中か `outcome.json` がシンボリックリンク、通常のファイルでない、`--issue` を渡したのに `issue` と一致しない、`run_id` がファイルのあるディレクトリの名前と一致しない

停止点と status の対応 (SKILL.md の節番号。各行に `outcome: <status>/<reason か kind>` の印を付ける):

| 停止点 | status | reason / kind |
|---|---|---|
| 1 `gh` が使えず本文が無い | blocked | `gh_unavailable` |
| 2 の3つ目 (仕様の選択)、既存の決定を覆すか | needs_input | `spec_choice` |
| 3 design-doc が規模超過を報告し issue-split を提案 | blocked | `split_proposed` |
| 3・5 review-loop が上限まで回しても収束しない | blocked | `review_unconverged` |
| 5 監査の新しいセッションを起動した run のあと | blocked | `audit_session_launched` |
| 5 必要な `/security-review` が最後まで実行されなかった (拒否・エラー・未実施) | blocked | `required_check_not_run` |
| 6 deferred の起票・棄却の承認待ち | needs_input | `approval` |
| 6 検証が通らず、systematic-debugging でもこの実行の中で直せない | blocked | `verification_failed` |
| 7 「未判断」の行が残る | needs_input (`spec_choice` か `approval`)。人に上げる質問の形にできないときだけ blocked | `undecided_rows` |
| 7 完了条件 (6) を満たさずに止まり、上のどれにも当たらない (配置の外れを解消できない、検証を実行できない、issue 番号が無い等) | blocked | `incomplete` |
| 7 完了条件 (6) をすべて満たした | done | — |

- 止まる理由が複数あるときは、最初に止まった停止点の値を書く
- 委譲先の skill (design-doc・brainstorming など) が人に質問する場合、仕様の選択なら `needs_input` (`spec_choice`)。実装の進め方の選択 (writing-plans の実行方式など) は依頼者に渡さず、2 の1つ目として自分で決める
- 対話セッションで質問するときは、質問の直前に `needs_input` を書く。回答を得て続けたら、次に止まったときに書き直す (最後の書き込みが最終状態)

## 5. データフロー

- 状態の持ち主は issue-implement の1回の実行。outcome.json はその実行IDディレクトリにだけ書き、ほかの実行の outcome を読まない
- 書き込みは同じディレクトリに `O_EXCL | O_NOFOLLOW` で作った一時ファイルに書き、`os.replace` で置き換える。ホストが書き込みの途中を読まないため、監査セッションがディレクトリを差し替えていてもリポジトリの外へ書かないため
- 実行IDは時刻とランダム値 (またはホストが渡した値) なので、並行する別の実行とディレクトリが重ならない。`start` は `mkdir` (既存なら終了コード2) で作る
- ホストの読み方: `AIDD_ISSUE_IMPLEMENT_RUN_ID` を渡して起動し、`.aidd/issue-implement/<その値>/outcome.json` を `check --issue N` で検証する。無い・通らない = 異常終了 (done とみなさない)。前回の実行の outcome が作業ツリーに残っていても、実行IDが違うので拾わない

## 6. エラー処理

| 失敗 | 対処 |
|---|---|
| `write` の検証に通らない | ファイルを書かず終了コード1。model は理由を見て直して書き直す。直せなければ完了報告に「outcome を書けなかった」と理由を書く |
| `start`・`write` の実行の失敗 | 終了コード2。完了報告に書く。ホストからは outcome が無い = 異常終了に見える |
| model が誤って `done` を書く | `completion` の4つの値を明示しないと `done` は書けない。値が実態と違うかはスクリプトでは判断できないので、SKILL.md で5・6・7の確認結果から書くと定める |
| 必要な監査が実行できないまま `done` を書く (#223) | `completion.security_review` は `ran` か `not_required` だけを受け付ける。拒否された・エラーで終わった・未実施の監査を `ran` と書けば通るので、値の正しさは SKILL.md の定義 (5 の項に当たるか、最後まで実行したか) に頼る。#133 の試行では、`/security-review` が権限で拒否されても `done` が書けた (`tests/eval/results/2026-11-28-develop.md`) |
| 質問の文が前の会話に依存する | スキーマでは検出できない。SKILL.md に「issue と outcome だけで読める文にする」と書く |

## 7. 運用

- ロールバックは revert のみ (スクリプトと SKILL.md の追加だけで、既存の成果物の形は変えない)
- `.aidd/issue-implement/` をコミットするかは利用側の方針に委ねる (autonomous-review と同じ)
- 同じ変更で、CI の contract-tests の matrix と `.claude/CLAUDE.md` のテスト一覧 (本数を含む) に `issue-outcome-test.sh` を足し、shellcheck の対象は変えない (python のため)。README の索引・CHANGELOG・3つの plugin.json の version を更新する
