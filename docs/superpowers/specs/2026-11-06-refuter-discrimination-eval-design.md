# eval で refuter の弁別力を測る

## 目的

`/aidd:eval` では、refuter が誤った指摘を落とせるか（弁別力）を測れない。refuter に渡るのは reviewer の指摘だけで、キーのシード欠陥はすべて実在するため、測れるのは「本物を棄却しない側」だけになっている（2026-07-18 の結果: 8件すべてが生存）。

一方で、敵対的レビューはトークンの無駄であり、実行による検証に置き換えるべきだという意見がある（2026-11 の X 投稿、pstack interrogate の方針転換）。設計書のレビューでは実行による検証が使えないうえ、LLM の要件レビューは誤検出が多いという報告もある。refuter を残すか削るかを、データで決められるようにする。

## 方針

各ケースに、反証できる偽の high/mid 指摘を混ぜて refuter に渡し、偽指摘をどれだけ落とせるかを測る。refuter の有無で2回実行して比べる方式は、コストが約2倍になり、非決定性のノイズに差が埋もれるため採らない。

## 変更

### `tests/eval/planted/<ケース>.md`（新規）

ケースごとに偽指摘を2〜3件置く。各偽指摘は reviewer の出力と同じ形式（ID・深刻度・引用箇所・指摘内容）で書く。内容は、ケース設計書の別の節（後ろの節、決定事項、補足など）を読めば反証できるものにする。

- ここには反証の根拠を書かない。この文書は採点前にメインループが読むため。
- 偽指摘の深刻度は high/mid に限る。low は refuter を通らないため。

### `tests/eval/keys/<ケース>.md`

「偽指摘」の節を追加し、planted の各 ID について、反証の根拠になる節と内容を書く。キーと同じく、全ケースのレビューが終わるまで読まない。

### `skills/eval/SKILL.md`

- **汚染ガード**: `tests/eval/planted/` はレビュー前に読んでよいが、reviewer・arbiter には渡さない。refuter には、どれが偽指摘かを知らせない。
- **手順1**:
  1. reviewer の high/mid 指摘と planted の偽指摘を順不同に混ぜ、同じ形式で refuter に渡す。reviewer の high/mid が0件でも、偽指摘だけで refuter を起動する。
  2. refuter の後、arbiter に渡す前に偽指摘を取り除く。既存の指標（検出率・深刻度一致・デコイ誤検出）は従来どおり偽指摘を含まずに算出する。
  3. 中間データに、偽指摘ごとの判定と根拠、refuter の完了通知の `subagent_tokens` を加える。
- **手順3（指標）**: 次の行を追加する。
  - 偽指摘の棄却率: planted のうち、refuter が反証成立とし、かつ根拠がキーの根拠と一致した割合。反証成立でも根拠がキーと一致しないものは「根拠不一致」として別に数える。
  - refuter のコスト: ケースごとの `subagent_tokens`。
- **手順4**: refuter が棄却したキー外の reviewer 指摘も、AskUserQuestion でユーザーに分類させる（正しい棄却／誤った棄却）。誤った棄却の数を結果に記録する。
- **手順5**: 結果ファイルに、偽指摘の判定表と上記の指標を加える。
- **手順6（報告）**: 次の目安を付記する。
  - 偽指摘の棄却率が高く、かつ誤棄却（シード欠陥とキー外を合わせて）が0件 → refuter は機能している。
  - 偽指摘をほとんど落とせない → refuter は判子を押すだけになっている。削減を検討する。
  - いずれも1標本であり、変更を判断する前に再実行して再現を確かめる（既存の注意どおり）。

### 付随作業（運用ルール3）

- `tests/command-contract-test.sh` に、eval の新しい必須文言（planted を arbiter の前に取り除くこと、偽指摘の棄却率）の確認を追加する。
- README の索引の該当箇所、CHANGELOG、3つの plugin.json の `version` を更新し、`python3 scripts/generate-asset-index.py` を実行する。

## 検証

- 契約テスト、shellcheck、`generate-asset-index.py --check`、`claude plugin validate . --strict` が通る。
- 変更後に `/aidd:eval` を3ケースすべてで実行し、結果を `tests/eval/results/2026-11-06.md` に保存する（運用ルール6）。

## 非対象

- design-review、refuter、arbiter のプロンプト変更（測定の結果を見てから判断する）
- autonomous-review の実行ベースの検証（別の spec で扱う）
- refuter の有無での比較実行
