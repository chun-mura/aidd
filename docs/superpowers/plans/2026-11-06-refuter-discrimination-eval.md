# eval で refuter の弁別力を測る 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `/aidd:eval` に偽指摘を混ぜ、refuter が誤った指摘を落とせるかを測れるようにする。

**Architecture:** ケースごとの偽指摘を `tests/eval/planted/` に置き、その反証根拠をキーに書く。eval の手順で偽指摘を reviewer の指摘に混ぜて refuter に渡し、arbiter の前に取り除く。採点時に偽指摘の棄却率と refuter のトークンを記録する。

**Tech Stack:** Markdown（skill・データ）、bash（契約テスト）

**Spec:** `docs/superpowers/specs/2026-11-06-refuter-discrimination-eval-design.md`

## Global Constraints

- 偽指摘の深刻度は high / mid のみ（low は refuter を通らない）
- 反証根拠は planted 側に書かず、キー側にだけ書く
- 偽指摘は refuter に渡す前に中立な ID（F1, F2, …）に振り直し、元の ID を refuter に見せない
- design-review・refuter・arbiter のプロンプトは変更しない
- 版は 0.50.1 → 0.51.0（3つの plugin.json を同じ値に）

---

### Task 1: 偽指摘データと、その整合性を見る契約テスト

**Files:**
- Create: `tests/eval/planted/structure.md`, `tests/eval/planted/data-error.md`, `tests/eval/planted/security.md`
- Modify: `tests/eval/keys/structure.md`, `tests/eval/keys/data-error.md`, `tests/eval/keys/security.md`（末尾に「偽指摘」節を追加）
- Test: `tests/command-contract-test.sh`

**Interfaces:**
- Produces: planted 表の列 `| ID | 深刻度 | 引用箇所 | 指摘 | 代案 |`、ID 形式 `PL-S<n>` / `PL-DE<n>` / `PL-SEC<n>`。キーの節見出し `## 偽指摘 (refuter の弁別力測定)`、列 `| ID | 反証の根拠 (節・行) | 内容 |`

- [ ] **Step 1: 失敗する契約テストを書く**

`tests/command-contract-test.sh` の末尾に追加する:

```bash
# Every eval case has planted false findings (high/mid only), and every planted ID has
# its refutation evidence in the key, so the refuter's discrimination can be scored.
for case_file in "$repo_root"/tests/eval/cases/*.md; do
  name=$(basename "$case_file" .md)
  planted="$repo_root/tests/eval/planted/$name.md"
  key="$repo_root/tests/eval/keys/$name.md"
  [ -f "$planted" ]
  ids=$(grep -oE '^\| PL-[A-Z]+[0-9]+ ' "$planted" | tr -d '| ')
  [ -n "$ids" ]
  # `! cmd` never trips set -e, so fail explicitly on a low/unknown severity row.
  if grep -E '^\| PL-' "$planted" | grep -qvE '^\| PL-[A-Z]+[0-9]+ \| (high|mid) \|'; then
    echo "planted finding with non high/mid severity: $planted" >&2
    exit 1
  fi
  grep -F -- '## 偽指摘 (refuter の弁別力測定)' "$key"
  for id in $ids; do grep -qE "^\| $id \|" "$key"; done
done
```

- [ ] **Step 2: 失敗を確認する**

Run: `bash tests/command-contract-test.sh`
Expected: 非0で終了（`tests/eval/planted/structure.md` が無い）

- [ ] **Step 3: planted ファイルを作る**

`tests/eval/planted/structure.md`:

```markdown
# 偽指摘: cases/structure.md

/aidd:eval が refuter の弁別力を測るために、reviewer の指摘へ混ぜる偽の指摘。いずれも設計書の別の箇所で反証できる。反証の根拠は keys 側にだけ書く。refuter へは表の行の内容だけを、中立な ID に振り直して渡す (このファイルの見出し・説明・ID は渡さない)。

| ID | 深刻度 | 引用箇所 | 指摘 | 代案 |
|---|---|---|---|---|
| PL-S1 | mid | cases/structure.md:49 (エラー処理) | SMTP 送信失敗時の再試行方針が定義されておらず、一時的な接続障害でもレポート送信がそのまま失敗する | 再試行回数と間隔を定義する |
| PL-S2 | mid | cases/structure.md:50 (エラー処理) | テンプレート整形が途中で失敗した場合に、整形済みの部分だけのレポートが送信され得る | 整形失敗時は送信を中止する |
| PL-S3 | mid | cases/structure.md:44 (データフロー) | 集計処理が `usage_events` を更新し得る設計で、利用イベントの持ち主が不明確になっている | `usage_events` は読み取り専用とし、持ち主を明記する |
```

`tests/eval/planted/data-error.md`:

```markdown
# 偽指摘: cases/data-error.md

/aidd:eval が refuter の弁別力を測るために、reviewer の指摘へ混ぜる偽の指摘。いずれも設計書の別の箇所で反証できる。反証の根拠は keys 側にだけ書く。refuter へは表の行の内容だけを、中立な ID に振り直して渡す (このファイルの見出し・説明・ID は渡さない)。

| ID | 深刻度 | 引用箇所 | 指摘 | 代案 |
|---|---|---|---|---|
| PL-DE1 | high | cases/data-error.md:38 (エラー処理) | WMS API が全面停止すると全商品がタイムアウト扱いで在庫0として同期され、バッチは正常終了する。全商品が在庫切れ表示になっても監視に現れない | 全面停止を検知してバッチを失敗させる |
| PL-DE2 | mid | cases/data-error.md:34 (データフロー) | `StockApi` が Redis にキーが無い場合の挙動が定義されておらず、キャッシュミス時に在庫数を返せない | キャッシュミス時は DB を読む |
| PL-DE3 | mid | cases/data-error.md:30 (インターフェース) | `GET /internal/stock/{product_id}` が外部に公開される前提なのに、認証・アクセス制御の設計が無い | 内部ネットワークからのみ到達可能にする |
```

`tests/eval/planted/security.md`:

```markdown
# 偽指摘: cases/security.md

/aidd:eval が refuter の弁別力を測るために、reviewer の指摘へ混ぜる偽の指摘。いずれも設計書の別の箇所で反証できる。反証の根拠は keys 側にだけ書く。refuter へは表の行の内容だけを、中立な ID に振り直して渡す (このファイルの見出し・説明・ID は渡さない)。

| ID | 深刻度 | 引用箇所 | 指摘 | 代案 |
|---|---|---|---|---|
| PL-SEC1 | high | cases/security.md:22 (構成と責務) | `POST /api/files` がファイル種別を検証せずに S3 へ保存するため、PDF 以外の任意ファイル (実行ファイル等) を取引先に配布できる | Content-Type とマジックバイトで PDF を検証し、サイズ上限を設ける |
| PL-SEC2 | mid | cases/security.md:33 (データフロー) | 発行した署名付きURLを `contract_files` テーブルに保存しており、DB が漏えいすると有効なダウンロードURLが流出する | 署名付きURLは保存せず都度発行する |
| PL-SEC3 | mid | cases/security.md:37 (エラー処理) | 存在しない `file_id` への応答に S3 のキーやバケット名が含まれ得て、内部構成が露出する | 404 には存在有無以外の情報を含めない |
```

- [ ] **Step 4: キーに「偽指摘」節を追加する**

`tests/eval/keys/structure.md` の末尾に追加:

```markdown

## 偽指摘 (refuter の弁別力測定)

`tests/eval/planted/structure.md` の各偽指摘を反証できる根拠。refuter が「反証成立」とし、かつ根拠がこの節・内容に一致した場合だけ「棄却」に数える。反証成立でも根拠が異なれば「根拠不一致」とする。

| ID | 反証の根拠 (節・行) | 内容 |
|---|---|---|
| PL-S1 | エラー処理 (49行) | SMTP 送信失敗は3回リトライすると定義済み |
| PL-S2 | エラー処理 (50行) | 整形失敗時は例外で中断し、部分的なレポートは送らないと定義済み |
| PL-S3 | データフロー (44行) | `usage_events` が唯一の持ち主で、集計は読み取りのみと定義済み |
```

`tests/eval/keys/data-error.md` の末尾に追加:

```markdown

## 偽指摘 (refuter の弁別力測定)

`tests/eval/planted/data-error.md` の各偽指摘を反証できる根拠。refuter が「反証成立」とし、かつ根拠がこの節・内容に一致した場合だけ「棄却」に数える。反証成立でも根拠が異なれば「根拠不一致」とする。

| ID | 反証の根拠 (節・行) | 内容 |
|---|---|---|
| PL-DE1 | エラー処理 (40行) | WMS API の全面停止 (認証エラー・5xx連続) は例外でバッチを失敗させると定義済み。在庫0埋めは個別商品のタイムアウトだけ (シード DE3 とは別論点) |
| PL-DE2 | データフロー (34行) | `StockApi` はキャッシュミス時に DB を読むと定義済み |
| PL-DE3 | インターフェース (30行) | サイト内部からのみ参照すると定義済み |
```

`tests/eval/keys/security.md` の末尾に追加:

```markdown

## 偽指摘 (refuter の弁別力測定)

`tests/eval/planted/security.md` の各偽指摘を反証できる根拠。refuter が「反証成立」とし、かつ根拠がこの節・内容に一致した場合だけ「棄却」に数える。反証成立でも根拠が異なれば「根拠不一致」とする。

| ID | 反証の根拠 (節・行) | 内容 |
|---|---|---|
| PL-SEC1 | インターフェース (28行) | Content-Type とマジックバイトで PDF を検証し、上限 20MB と定義済み |
| PL-SEC2 | データフロー (33行) | 署名付きURLは都度発行し保存しないと定義済み (ログへの記録はシード SEC2 で別論点) |
| PL-SEC3 | エラー処理 (37行) | 404 には存在有無以外の内部情報を含めないと定義済み |
```

- [ ] **Step 5: テストが通ることを確認する**

Run: `bash tests/command-contract-test.sh`
Expected: exit 0

- [ ] **Step 6: コミットする**

```bash
git add tests/eval/planted tests/eval/keys tests/command-contract-test.sh
git commit -m "test: add planted false findings to eval cases

The refuter only ever saw real findings in the eval, so its ability to drop
false ones was never measured. Each case now has refutable false findings,
with the refutation evidence kept in the keys so the reviewers stay blind."
```

---

### Task 2: eval の手順に偽指摘の混入と採点を加える

**Files:**
- Modify: `skills/eval/SKILL.md`（汚染ガード、手順1・3・4・5・6）
- Modify: `tests/command-contract-test.sh`（eval の必須文言）
- Modify: `README.md:91`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `.cursor-plugin/plugin.json`

**Interfaces:**
- Consumes: Task 1 の `tests/eval/planted/<ケース>.md`、キーの `## 偽指摘 (refuter の弁別力測定)` 節

- [ ] **Step 1: 失敗する契約テストを書く**

`tests/command-contract-test.sh` の `grep -F -- '`--depth=deep`' "$eval_command"` の次の行に追加:

```bash
grep -F -- 'arbiter に渡す前に偽指摘を取り除く' "$eval_command"
grep -F -- '偽指摘の棄却率' "$eval_command"
grep -F -- 'reviewer の high/mid が0件でも' "$eval_command"
```

- [ ] **Step 2: 失敗を確認する**

Run: `bash tests/command-contract-test.sh`
Expected: 非0で終了（文言が無い）

- [ ] **Step 3: `skills/eval/SKILL.md` を編集する**

汚染ガードの2つ目の箇条の後に追加:

```markdown
- `tests/eval/planted/` (偽指摘) はレビュー前に読んでよいが、reviewer・arbiter には渡さない。refuter には表の行の内容 (深刻度・引用箇所・指摘・代案) だけを渡し、どれが偽指摘かを知らせない。偽指摘の反証根拠はキー側にあるため、キーを読まない規則はそのまま守る
```

手順1の「ケースごとに以下の中間データを記録しておく:」の直前に追加:

```markdown
**偽指摘の混入**: 各ケースで、reviewer の high/mid 指摘と `tests/eval/planted/<ケース名>.md` の偽指摘を順不同に混ぜ、すべてを中立な ID (F1, F2, …) に振り直して同じ形式で refuter に渡す。対応表 (中立 ID → 元の ID) はメインだけが持つ。reviewer の high/mid が0件でも、偽指摘だけで refuter を起動する。refuter の後、arbiter に渡す前に偽指摘を取り除く。検出率・深刻度一致・デコイ誤検出は従来どおり偽指摘を含めずに算出する。
```

中間データの箇条に追加:

```markdown
- 偽指摘ごとの refuter の判定 (反証成立 / 反証失敗) と根拠
- refuter の完了通知の `<usage><subagent_tokens>`
```

手順3の指標表の末尾に2行追加:

```markdown
| 偽指摘の棄却率 | 偽指摘のうち、refuter が反証成立とし、かつ根拠がキーの「偽指摘」節の根拠と一致した割合。反証成立でも根拠が一致しないものは「根拠不一致」として件数を別に記す |
| refuter のコスト | ケースごとの refuter の `subagent_tokens` |
```

手順4の末尾に追加:

```markdown
refuter が棄却したキー外の reviewer 指摘 (偽指摘を除く) も、同じく AskUserQuestion で1件ずつ「正しい棄却」/「誤った棄却」に分類させ、誤った棄却の数を結果に記録する。
```

手順5の記載内容に追加:

```markdown
- 偽指摘の判定表 (元の ID、判定、refuter の根拠、キーとの一致)
```

手順6の末尾に追加:

```markdown
refuter について次の目安を付記する。偽指摘の棄却率が高く、かつ誤った棄却 (反証誤棄却とキー外の誤った棄却の合計) が0件なら、refuter は機能している。偽指摘をほとんど落とせないなら、refuter は判子を押すだけになっており、削減を検討する。いずれも1標本なので、変更を判断する前に再実行して再現を確かめる。
```

手順5の箇条「指標サマリ (上記5指標)」を「指標サマリ (上記の指標)」に直す。

- [ ] **Step 4: README・CHANGELOG・版を更新する**

`README.md:91` の説明の「検出率・反証誤棄却・デコイ誤検出等」を「検出率・反証誤棄却・偽指摘の棄却率・デコイ誤検出等」に直す。

`CHANGELOG.md` の `# Changelog` の直後に追加:

```markdown

## 0.51.0 (2026-11-06)

- `/aidd:eval` に偽指摘を混ぜ、refuter が誤った指摘を落とせるかを測るようにした。これまで refuter に渡るのは実在する欠陥だけで、本物を棄却しない側しか測れていなかった。敵対的レビューを残すか削るかをデータで決めるため。偽指摘は `tests/eval/planted/`、反証の根拠はキーに置く。design-review・refuter・arbiter のプロンプトは変えていない
```

3つの plugin.json の `"version": "0.50.1"` を `"version": "0.51.0"` に直す。

- [ ] **Step 5: 検証を通す**

Run（サンドボックス外で）:
```bash
bash tests/command-contract-test.sh && bash tests/redundancy-contract-test.sh && bash tests/hook-contract-test.sh \
  && python3 scripts/generate-asset-index.py --check && shellcheck hooks/scripts/*.sh templates/*.sh scripts/install-codex-agents.sh \
  && claude plugin validate . --strict
```
Expected: すべて exit 0。`generate-asset-index.py --check` が古いと言えば `python3 scripts/generate-asset-index.py` を実行して再確認する。

- [ ] **Step 6: コミットする**

```bash
git add skills/eval/SKILL.md tests/command-contract-test.sh README.md CHANGELOG.md .claude-plugin/plugin.json .codex-plugin/plugin.json .cursor-plugin/plugin.json
git commit -m "feat: measure refuter discrimination in eval (0.51.0)

Whether adversarial refutation earns its tokens can't be decided while the
eval only shows that true findings survive. Mixing refutable false findings
into the refuter's input measures the other side."
```

---

### Task 3: 3ケースすべてで eval を実行して結果を残す

**Files:**
- Create: `tests/eval/results/2026-11-06.md`

- [ ] **Step 1:** 変更後の `skills/eval/SKILL.md` の手順に従い、structure・data-error・security を順に実行する（キーは全ケースのレビュー完了まで読まない）。
- [ ] **Step 2:** 採点し、キー外指摘とキー外の棄却をユーザーに分類してもらう（AskUserQuestion）。
- [ ] **Step 3:** 結果を `tests/eval/results/2026-11-06.md` に保存し、前回（2026-07-18）と比較する。
- [ ] **Step 4:** コミットする。

```bash
git add tests/eval/results/2026-11-06.md tests/eval/keys
git commit -m "test: record eval with refuter discrimination (2026-11-06)"
```
