# 受け入れ基準: 架空の経費精算 API

**これは架空のサンプルである。** 原要件は [requirements.md](requirements.md)、説明は [受け入れ基準と重要性質の検証](../../../docs/assurance/acceptance.md)。

- 対応する主張: `AC-SPEC-001` ([保証条件と責任分担](../../../docs/assurance/contract.md))
- 基準の所有者: 経理部長 (架空)。この文書・[api.py](api.py)・[acceptance_test.py](acceptance_test.py) の変更は所有者の承認を要する。承認した内容の digest は [approved.sha256](approved.sha256)
- 書き方: 各行は Given-When-Then (reqd の `requirements-notation` の記法) で、期待値は「由来」列の原要件・所有者の判断から導いた。実装 (`impl_*.py`) から写した値は無い

## API

基準が前提にする外から見える振る舞い。型と例外は [api.py](api.py) にある。

| 操作 | 結果 |
|---|---|
| `submit(actor, amount)` | 申請 ID。状態は `submitted` |
| `get(actor, id)` | `{"id", "org_id", "owner", "amount", "status"}` |
| `approve(actor, id)` | 状態を `approved` にする |
| `pay(actor, id, key)` | `{"expense_id", "amount", "transfer_id"}`。状態を `paid` にする。送金先 (gateway) の `transfer` を呼ぶ |
| `payouts()` | 支払いの記録の一覧 |

試験は送金先を偽物に差し替え、`transfer` が成功した回数と金額を実装の外で数える。二重支払いの判定はこの数で行い、実装自身の記録 (`payouts()`) だけを信じない。

## 基準

種類: 例 = 具体例、境界 = 境界値、性質 = 乱数で作った操作列で不変条件を確かめる、障害 = 送金先の失敗を注入する。

| ID | 由来 | 種類 | Given / When / Then (期待値) | ASVS 5.0 |
|---|---|---|---|---|
| AT-FLOW-01 | R-1, R-2, R-4 | 例 | Given 組織1の社員 m1・承認者 a1・経理 c1 / When m1 が 5000 円を申請し、a1 が承認し、c1 が鍵 k1 で支払う / Then 状態は `submitted`→`approved`→`paid`、支払いの金額は 5000、送金は 5000 円が1回 | 2.3.1 |
| AT-FLOW-02 | R-4 | 例 | Given 未承認の申請 / When 経理が支払う / Then `Invalid`、送金は0回、状態は `submitted` のまま | 2.3.1 |
| AT-AMT-01 | R-1, D-2 | 境界 | When 金額 1 と 1000000 で申請する / Then 受け付ける。When 0・-1・1000001・1.5・"100"・True で申請する / Then `Invalid` | 2.2.1, 2.1.3 |
| AT-AUTHZ-01 | R-3, D-1 | 例 | Given 組織1の申請 / When 組織2の社員・承認者・経理が `get` する / Then どれも `NotFound` で、存在しない ID への `get` と同じ例外 | 8.2.2, 8.4.1 |
| AT-AUTHZ-02 | R-3, D-1 | 例 | Given 組織1の社員 m1 の申請 / When 同じ組織の社員 m2 が `get` する / Then `NotFound` | 8.2.2 |
| AT-AUTHZ-03 | R-2, D-1 | 例 | Given 組織1の申請 / When 組織2の承認者が承認する / Then `NotFound`、状態は `submitted` のまま | 8.2.2, 8.4.1 |
| AT-AUTHZ-04 | R-2 | 例 | When 承認者が自分の申請を承認する、社員が自分の申請を承認する / Then どちらも `Forbidden`、状態は `submitted` のまま | 8.2.1, 2.3.5 |
| AT-AUTHZ-05 | R-4, D-5 | 例 | Given 組織1の承認済みの申請 / When 組織2の経理が支払う / Then `NotFound`。When 組織1の承認者 (経理でない) が支払う / Then `Forbidden`。どちらも送金は0回 | 8.2.1, 8.4.1 |
| AT-AUTHZ-P | R-2, R-3, D-1, D-5 | 性質 | 2組織・各組織の社員2人・承認者・経理で、乱数で作った申請・閲覧・承認・支払いの操作列 (固定の seed) / Then 申請と別の組織の利用者の操作は必ず `NotFound` で、状態も送金も変えない | 8.2.2, 8.4.1 |
| AT-PAY-01 | R-4 | 例 | Given 承認済みの申請 / When 経理が同じ鍵 k1 で2回支払う / Then 2回とも同じ支払い (金額・transfer_id) を返し、送金は1回 | 2.3.4 |
| AT-PAY-02 | R-4, D-4 | 例 | Given 鍵 k1 で支払い済みの申請 / When 別の鍵 k2 で支払う / Then 1回目の支払いを返し、送金は1回のまま | 2.3.4 |
| AT-PAY-03 | D-3 | 例 | Given 申請 E1 を鍵 k1 で支払い済み、承認済みの申請 E2 / When E2 を鍵 k1 で支払う / Then `Conflict`、E2 は `approved` のまま、送金は1回のまま | 2.3.4 |
| AT-PAY-P | R-4, R-5, D-4 | 性質 | 承認済みの申請に、乱数で選んだ鍵 (再送・新しい鍵) で支払いを繰り返し、送金先を乱数で失敗させる (固定の seed) / Then 各申請の成功した送金は最大1回、`paid` の申請はちょうど1回、`payouts()` は成功した送金と一致する | 2.3.3, 2.3.4 |
| AT-FAULT-01 | R-5 | 障害 | Given 承認済みの申請と、次の1回だけ失敗する送金先 / When 支払う / Then `GatewayError`、状態は `approved`、`payouts()` は空。When 同じ鍵でやり直す / Then 支払われ、成功した送金は1回 | 2.3.3 |

## 主張しないこと

- [requirements.md](requirements.md) の対象外 (X-1〜X-5)。特に、認証 (X-1) と複数プロセスからの同時実行 (X-4)
- 基準に書いていない振る舞い。たとえば上の表に無い例外の種類や、`get` が返す項目の順序
- 性質 (`-P`) の行は、固定した seed で作った有限個の操作列で不変条件が破れなかったことを示す。すべての操作列で成り立つことの証明ではない
