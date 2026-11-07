---
status: draft
---

# 会員ポイント台帳サービス 設計書

規模: 新規サービス1つの追加と既存2サービス (注文サービス・会員サービス) の改修のため詳細形式

## 背景と目的

自社ECサイトの会員ポイントは、現在 `members` テーブルの `point_balance` 列1つで管理している。注文サービスが付与・利用のたびにこの列を直接加減算し、会員サービスがこの列を読んでマイページに表示している。この方式には次の問題がある。

- 履歴が残らない。会員から「ポイントが減っている」と問い合わせを受けても、いつ何で増減したかを説明できない。CS 担当は注文履歴から手計算で再構成しており、1件あたり平均40分かかっている
- 有効期限を管理できない。会員規約には有効期限の定めがあるが、実際には失効させておらず、未失効ポイントが引当金として積み上がっている。経理から是正を求められている
- 返品時のポイント回収が手作業で、回収漏れが月に数十件発生している

会員規約の改定 (2027年4月施行) に合わせ、ポイントの増減をすべて台帳として記録する専用サービスを作る。これにより、履歴の説明、有効期限による自動失効、返品時の自動回収を実現する。

### 目標

- CS の履歴調査を1件あたり5分以内にする (管理画面で台帳を見るだけで説明できる状態)
- 改定後の規約どおりにポイントを失効させる
- 返品時の回収漏れを0件にする

### 前提

- 会員数は約120万、そのうち月に1回以上購入する会員は約18万
- 注文数はピーク時 1,500件/時、通常時 300件/時
- 1ポイント = 1円。ポイントは購入時の支払いにのみ使える

## スコープ / やらないこと

- やる
  - ポイント台帳サービス (`point-ledger`) の新設: 付与・利用・取消・失効・手動調整の記録と残高の提供
  - 注文サービスの改修: 購入時のポイント利用、配送完了・返品・キャンセルのイベント発行
  - 会員サービスの改修: マイページでの残高・履歴・失効予定の表示
  - CS 管理画面への「ポイント台帳」「手動調整」画面の追加
  - 既存 `members.point_balance` からの残高移行
  - 失効予定の通知メール
- やらない
  - キャンペーンによる倍率付与 (2027年度下期に別途検討)
  - 他社ポイントとの交換
  - 実店舗 (POS) でのポイント利用。現状 EC 専用のため
  - 返品ポリシーの変更。返品は既存どおり注文単位のみ (部分返品は不可) とし、受付は「配送完了日から14日以内」で、それを過ぎた返品は受け付けない

## 用語

| 用語 | 意味 |
|---|---|
| 付与 (grant) | 購入に応じてポイントを会員に与えること。購入による付与は1注文につき1件 |
| 仮付与 | 配送完了から返品受付期間が終わるまでの付与の状態。マイページには表示するが、利用はできない |
| 確定 | 返品受付期間を過ぎ、返品による取消が起きなくなった付与の状態 |
| 利用 (redeem) | 購入時にポイントを支払いに充てること |
| 引き当て | 1回の利用で、どの付与から何ポイントを消費したかを決めること |
| 失効 (expire) | 有効期限を過ぎた確定ポイントを残高から除くこと |
| 台帳 (ledger) | ポイントの増減を1行1イベントで記録する追記専用の表 |
| 手動調整 | CS 担当が問い合わせ対応・補償のために行う加算・減算 |

## 構成と責務

| コンポーネント | 責務 |
|---|---|
| `PointLedgerService` | 台帳への記録と残高の更新を行う唯一のコンポーネント。付与・確定・利用・取消・失効・調整のすべての書き込みはここを通る |
| `PointApi` | 注文サービス・会員サービス向けの内部 API。`PointLedgerService` を呼ぶ |
| `PointAdminApi` | CS 管理画面向けの API。手動調整と台帳の参照を提供する |
| `OrderEventConsumer` | 注文サービスが発行するイベント (配送完了・返品・キャンセル) を購読し、付与・取消・利用の返還を `PointLedgerService` に依頼する |
| `GrantConfirmJob` | 確定予定日を迎えた仮付与を確定にする日次ジョブ |
| `ExpireJob` | 有効期限を過ぎた確定ポイントを失効させる日次ジョブ |
| `ExpiryNoticeJob` | 失効予定の通知メールを会員サービスに依頼する日次ジョブ |
| `BalanceReconcileJob` | 台帳から残高を再計算し、残高テーブルとの差分を検出・修正する日次ジョブ |

`point-ledger` は既存の Kubernetes クラスタに独立した Deployment として配置し、専用の PostgreSQL データベース (`point_db`) を持つ。注文サービス・会員サービスは `point_db` に直接接続せず、必ず `PointApi` を経由する。日次ジョブは同じイメージを使う CronJob として動かし、タイムゾーンは `Asia/Tokyo` を指定する。

`PointAdminApi` は社内ネットワーク (管理画面と同じ VPN 内) からのみ到達できるイングレスに載せ、既存の社内 SSO で認証する。手動調整は SSO 上で `point_admin` ロールを持つ担当者だけが実行でき、実行者の社員 ID を台帳の `operator_id` に記録する。台帳の参照は `cs_member` ロール以上で可能とする。

### 既存サービスの改修範囲

- 注文サービス: 注文確定時の `members.point_balance` の減算を `POST /v1/redemptions` の呼び出しに置き換える。配送完了時の加算処理を削除し、代わりに `order.delivered` を発行する。返品・キャンセル時の手作業手順を廃止し、`order.returned`・`order.cancelled` を発行する
- 会員サービス: マイページの残高表示を `members.point_balance` から `GET /v1/members/{member_id}/balance` に切り替え、履歴タブを追加する。失効予定メールの送信 API (`POST /internal/mail/point-expiry`) を追加する

## インターフェース

### PointApi (内部 API)

すべてのエンドポイントはクラスタ内のサービスメッシュ経由でのみ到達でき、呼び出し元サービスの mTLS 証明書で認証する。呼び出しを許可するサービスは、注文サービスと会員サービスだけとする。

#### `GET /v1/members/{member_id}/balance`

会員の残高を返す。マイページと注文画面で使う。

```json
{
  "member_id": "m_0001",
  "confirmed_balance": 1200,
  "pending_balance": 300,
  "next_expiry": { "date": "2027-06-30", "points": 400 }
}
```

- `confirmed_balance`: 利用できるポイント
- `pending_balance`: 仮付与中のポイント。表示のみで、利用はできない
- `next_expiry`: 次に失効するポイントとその日付。失効予定が無ければ `null`
- 会員が存在しない場合は 404。台帳に行が無い会員は、すべて0で 200 を返す

#### `POST /v1/redemptions`

注文確定時にポイントを利用する。注文サービスが呼ぶ。

リクエストヘッダ `Idempotency-Key` (注文サービスが利用要求ごとに発行する UUID) を必須とする。同じキーの再送には初回と同じレスポンスを返し、台帳には二度書かない。キーと初回レスポンスは `redemption_requests` テーブルに保存する。

```json
{ "member_id": "m_0001", "order_id": "o_9001", "points": 500, "item_amount": 8000 }
```

- 200: `{ "redemption_id": "r_1", "points": 500, "confirmed_balance_after": 700 }`
- 409 `insufficient_balance`: 利用可能な残高が要求ポイントに足りない
- 422 `invalid_points`: `points` が1未満、または `item_amount` (送料を除く商品代金) を超える
- 400: `Idempotency-Key` が無い、または UUID 形式でない

#### `POST /v1/redemptions/{redemption_id}/cancel`

注文キャンセル時に、利用したポイントを返還する。返還したポイントは、引き当てた元の付与に戻り、その付与の有効期限を引き継ぐ。同じ `redemption_id` への2回目以降の呼び出しは何もせず 200 を返す。

- 200: `{ "redemption_id": "r_1", "returned_points": 500 }`
- 404: `redemption_id` が存在しない

#### `GET /v1/members/{member_id}/history?cursor=...`

台帳の行を新しい順に50件ずつ返す。マイページの履歴表示に使う。

```json
{
  "items": [
    { "type": "redeem", "points": -500, "order_id": "o_9001", "created_at": "2027-05-01T10:12:00+09:00" },
    { "type": "grant", "points": 80, "order_id": "o_8800", "created_at": "2027-04-20T09:00:00+09:00" }
  ],
  "next_cursor": "eyJpZCI6MTIzfQ"
}
```

`type` は台帳の `entry_type` をそのまま返す。ただし `confirm` 行 (増減0) は会員向けの履歴には含めない。

### PointAdminApi

#### `POST /admin/v1/adjustments`

```json
{ "member_id": "m_0001", "points": -300, "reason_code": "CS_CORRECTION", "note": "問い合わせ #123 の誤付与分" }
```

- `points` は正負どちらも可。0 は 422
- `reason_code` は `CS_CORRECTION` (誤りの訂正) / `COMPENSATION` (補償) / `OTHER` のいずれか。`OTHER` の場合は `note` を必須とする
- 負の値で `confirmed_balance` が足りない場合は 409 を返す
- 加算した調整ポイントは作成時から確定とし、有効期限は通常の付与と同じ規則で決まる

#### `GET /admin/v1/members/{member_id}/ledger`

台帳の全行を古い順に返す。会員向けの履歴と違い、`confirm` 行と `operator_id`・`reason_code`・`note` を含む。

### 注文サービスが発行するイベント

| イベント | 発行タイミング | 主な項目 |
|---|---|---|
| `order.delivered` | 配送業者から配送完了の通知を受けたとき | order_id, member_id, item_amount (送料・ポイント利用分を除く商品代金), delivered_at |
| `order.returned` | 返品を受け付けたとき | order_id, member_id, returned_at |
| `order.cancelled` | 出荷前に注文がキャンセルされたとき | order_id, member_id, redemption_id (ポイント利用が無い注文では null) |

イベントは既存のメッセージブローカーで配信する。配信は少なくとも1回 (重複あり) で、同じ注文のイベント間の順序は保証される。

## データフロー

### テーブル定義 (`point_db`)

`point_grants`: 付与1件ごとの行。残量と有効期限を持つ。

| 列 | 型 | 説明 |
|---|---|---|
| grant_id | uuid PK | |
| member_id | text NOT NULL | |
| order_id | text NULL | 購入による付与なら注文 ID。手動調整・移行なら NULL |
| grant_kind | text NOT NULL | `purchase` / `adjustment` / `migration` |
| points | integer NOT NULL | 付与したポイント数 |
| remaining | integer NOT NULL | まだ利用・失効していない残量 |
| status | text NOT NULL | `pending` / `confirmed` / `cancelled` / `exhausted` / `expired` |
| confirm_at | date NULL | 確定予定日 (仮付与のときのみ) |
| expires_at | date NULL | 有効期限 (この日の終わりまで利用可)。確定時に設定する |
| created_at | timestamptz NOT NULL | |

一意制約は `UNIQUE (order_id, grant_kind)` とする (order_id が NULL の行は対象外)。

`point_ledger`: 追記専用。UPDATE・DELETE しない。

| 列 | 型 | 説明 |
|---|---|---|
| ledger_id | bigserial PK | |
| member_id | text NOT NULL | |
| entry_type | text NOT NULL | `grant` / `confirm` / `redeem` / `redeem_cancel` / `grant_cancel` / `expire` / `adjust` / `migrate` |
| points | integer NOT NULL | 残高への増減 (符号付き) |
| grant_id | uuid NULL | 関係する付与 |
| redemption_id | uuid NULL | 関係する利用 |
| order_id | text NULL | 関係する注文 |
| operator_id | text NULL | 手動調整の実行者の社員 ID |
| reason_code | text NULL | 手動調整の理由区分 |
| note | text NULL | 手動調整のメモ |
| created_at | timestamptz NOT NULL | |

`point_redemptions`: 利用1件ごとの行。

| 列 | 型 | 説明 |
|---|---|---|
| redemption_id | uuid PK | |
| member_id | text NOT NULL | |
| order_id | text NOT NULL | INDEX (一意ではない。決定事項 D6) |
| points | integer NOT NULL | |
| status | text NOT NULL | `active` / `cancelled` |
| created_at | timestamptz NOT NULL | |

`point_redemption_allocations`: 利用1件がどの付与から何ポイントを引き当てたか。主キーは `(redemption_id, grant_id)`、列は `points integer NOT NULL`。

`point_balances`: 会員ごとの残高。台帳から導出できる値のキャッシュ (決定事項 D1)。

| 列 | 型 | 説明 |
|---|---|---|
| member_id | text PK | |
| confirmed_balance | integer NOT NULL | |
| pending_balance | integer NOT NULL | |
| updated_at | timestamptz NOT NULL | |

`redemption_requests`: 利用要求の冪等性のための表。列は `idempotency_key uuid PK`、`response_status integer`、`response_body jsonb`、`created_at timestamptz`。

### 付与の状態遷移

| 現在の状態 | 契機 | 次の状態 | 利用可否 |
|---|---|---|---|
| (なし) | `order.delivered` を受信 | `pending` | 利用不可 |
| `pending` | `GrantConfirmJob` が `confirm_at` の到来を検出 | `confirmed` | 利用可 |
| `pending` | `order.returned` を受信 | `cancelled` | 利用不可 |
| `confirmed` | 利用で `remaining` が0になる | `exhausted` | — |
| `exhausted` | 利用の返還で `remaining` が戻る | `confirmed` | 利用可 |
| `confirmed` | `ExpireJob` が期限切れを検出 | `expired` | 利用不可 |

手動調整の加算と移行による付与は、作成時から `confirmed` とする。`cancelled`・`expired` は終端で、ここから他の状態には戻らない。

### `point_balances` の持ち主

`point_balances` を書き換えるのは `PointLedgerService` だけとする。台帳への追記と同じトランザクションで加減算し、他のコンポーネントや手作業による更新は行わない。

`BalanceReconcileJob` は毎日 03:00 に、会員ごとに台帳から `confirmed_balance` と `pending_balance` を再計算する。`point_balances` と食い違う会員があれば台帳側の値で上書きし、差分を WARN ログとメトリクス `point_balance_drift_members` に出す。

### 付与の流れ

1. `OrderEventConsumer` が `order.delivered` を受信する
2. 付与ポイントを `floor(item_amount × 0.01)` で計算する (決定事項 D3)。0 ポイントなら何もせず ack する
3. `PointLedgerService` が1トランザクションで、`point_grants` に `pending` の行を INSERT し (`confirm_at` = 配送完了日 + 15日。決定事項 D4)、`point_ledger` に `grant` を追記し、`point_balances.pending_balance` を加算する
4. 同じ注文のイベントが再配信された場合は、`INSERT ... ON CONFLICT (order_id, grant_kind) DO NOTHING` で何もせず、残高も変えずに ack する

### 確定の流れ

`GrantConfirmJob` は毎日 01:00 に `status = 'pending' AND confirm_at <= 当日` の付与を対象にし、1件ずつ次を1トランザクションで行う。

- `status` を `confirmed` にし、`expires_at` = 確定日 + 365日 を設定する
- `point_ledger` に `confirm` (points = 0) を追記する
- `point_balances` の `pending_balance` から `remaining` を減算し、`confirmed_balance` に加算する

### 利用の流れ

1. 注文サービスが注文確定時に `POST /v1/redemptions` を呼ぶ
2. `PointLedgerService` は `Idempotency-Key` で `redemption_requests` を引き、あれば保存済みのレスポンスをそのまま返す
3. `point_balances` の会員行を `SELECT ... FOR UPDATE` でロックし、`confirmed_balance + pending_balance` が要求ポイント以上かを確認する。不足なら 409 を返す
4. 引き当て対象の付与を `status IN ('confirmed', 'pending')` かつ `expires_at` が当日以降 (または NULL) のものから選び、`expires_at` の早い順 (`expires_at` が NULL の仮付与は最後) に `remaining` を減らす。`remaining` が0になった確定付与は `exhausted` にする。結果を `point_redemption_allocations` に記録する
5. `point_redemptions` に行を作り、`point_ledger` に `redeem` を追記し、引き当てた分を `point_balances` から減算する
6. `redemption_requests` にキーとレスポンスを保存してコミットする

2〜6 は1つのトランザクションで行う。同じキーの同時リクエストは、6 の主キー制約で後着側がロールバックされ、後着側は保存済みのレスポンスを読み直して返す。

### 利用の返還の流れ

1. `OrderEventConsumer` が `order.cancelled` を受信し、`redemption_id` が null でなければ返還を行う (`POST /v1/redemptions/{redemption_id}/cancel` と同じ処理)
2. `point_redemptions.status` が `cancelled` なら何もしない
3. `point_redemption_allocations` を見て、引き当てた付与ごとに `remaining` を戻す。`exhausted` だった付与は `confirmed` に戻す
4. `point_ledger` に `redeem_cancel` を追記し、`point_balances` に加算して、`point_redemptions.status` を `cancelled` にする

### 失効の流れ

`ExpireJob` は毎日 00:30 に、`status = 'confirmed' AND expires_at < 当日` の付与を対象にする。会員ごとに1トランザクションで次を行う。

- 対象付与の `remaining` を0にして `status` を `expired` にする
- `point_ledger` に `expire` (points = -remaining) を追記する
- `point_balances.confirmed_balance` から減算する

00:00〜00:30 の間は、期限切れの付与が `confirmed_balance` に含まれたままになる。利用の流れの 4 で期限切れの付与は引き当て対象から除くため、この間に失効済みのポイントが使われることはない (残高が足りているように見えて 409 になる場合があるが、許容する)。

`ExpiryNoticeJob` は毎日 10:00 に、`expires_at` がちょうど30日後になる `confirmed` の付与を会員ごとに合算し、会員サービスの `POST /internal/mail/point-expiry` に失効日とポイント数を渡す (決定事項 D7)。

### 既存残高の移行

リリース時に1回だけ移行スクリプトを実行する。

1. 注文サービスへの書き込みを止めるため、サイトをメンテナンス画面に切り替える (想定30分。深夜帯に実施)
2. `members.point_balance` が1以上の全会員について、`grant_kind = 'migration'`、`status = 'confirmed'`、`expires_at` = 移行日 + 365日 の付与を作成し、台帳に `migrate` を追記し、`point_balances` を作る
3. 移行した会員数と合計ポイントを、`members` 側の集計と突き合わせる。一致しなければ移行を中止し、`point_db` を空に戻してメンテナンスを解除する
4. 一致を確認したら、マイグレーション `drop_members_point_balance` で `members.point_balance` 列を削除する (決定事項 D5)
5. 新バージョンの注文サービス・会員サービスをデプロイし、動作確認の後にメンテナンスを解除する

## エラー処理

### 付与・取消 (`OrderEventConsumer`)

- `point_db` への書き込みに失敗した場合は ack せず、ブローカーの再配信に任せる (最大10回、指数バックオフ)。10回失敗したメッセージはデッドレターキューに移し、メトリクス `point_dlq_messages` で検知する
- 再配信による重複は、付与の一意制約 (付与の流れの 4)、返品時の状態チェック、返還時の `point_redemptions.status` のチェックで吸収する
- `order.returned` で対象の付与が `pending` の場合: `cancelled` にし、`remaining` 分を `pending_balance` から減算し、台帳に `grant_cancel` を追記する。仮付与は利用できないため、取消時に利用済みの分を考慮する必要はない
- `order.returned` で対象の付与が `cancelled` の場合: 再配信とみなして何もせず ack する
- `order.returned` で対象の付与が `confirmed` 以降の場合: 確定は配送完了から15日後であり、14日を過ぎた返品は受け付けないため、このイベントは発生しない。万一受信した場合は ERROR ログを出して ack し、CS が個別に対応する
- 対象の会員が退会済みの場合: 付与せずに ack し、INFO ログを出す

### 利用 (`POST /v1/redemptions`)

- 残高不足 (409): 注文サービスは利用ポイントを0にした確認画面を会員に表示し、再確認を求める
- `point_db` への書き込み失敗: 注文の確定を止めないよう、200 と要求どおりのポイント数を返し、要求を `redemption_retry` キューに積んで、後から非同期で台帳に記録する
- タイムアウト: 注文サービス側の `PointApi` 呼び出しのタイムアウトは3秒とする。タイムアウトした場合、注文サービスは注文を「ポイント処理待ち」で保留し、自身のアウトボックスから同じ `Idempotency-Key` で再送する。再送は指数バックオフ (初回1分、上限6時間間隔) で最大72時間続け、それでも成功しなければ注文をキャンセルして会員にメールで知らせる
- 422: 注文サービスの不具合として ERROR ログを出し、注文は確定させない

### 利用の返還

- 戻し先の付与が既に `expired` の場合: その付与の `remaining` を戻したうえで、戻した分を即時に失効させ、台帳に `redeem_cancel` と `expire` を続けて追記する。有効期限を引き継ぐ規則 (インターフェース) に従う
- `redemption_id` が存在しない場合: ERROR ログを出して ack する

### 日次ジョブ

- `GrantConfirmJob`・`ExpireJob` が途中で失敗した場合: 処理済みの付与・会員はコミット済みのため、そのまま残す。ジョブは失敗として終了し、運用の手順で再実行する
- `ExpiryNoticeJob` のメール送信 API が失敗した場合: 3回リトライし、それでも失敗した会員は WARN ログに出す。通知は会員規約上の義務ではないため、翌日以降の再送はしない
- `BalanceReconcileJob` が途中で失敗した場合: 翌日の実行で同じ処理が行われるため、再実行しない

## 運用

### デプロイとロールバック

- `point-ledger` は新規 Deployment のため、初回リリースは移行手順 (データフロー「既存残高の移行」) と同じメンテナンス枠で行う
- 注文サービス・会員サービスのロールバック: 前バージョンのコンテナイメージを再デプロイする。DB マイグレーションは戻さない (`point_db` の新規テーブルは前バージョンからは参照されないため、残しておいて害はない)
- `point-ledger` 自体のロールバック: 前バージョンのイメージに戻す。台帳は追記専用のため、戻したバージョンでもそのまま読める

### 監視

| メトリクス | 閾値 | 通知先 |
|---|---|---|
| `PointApi` の 5xx 率 | 5分間で1%超 | オンコール |
| `POST /v1/redemptions` の p99 レイテンシ | 1秒超 | オンコール |
| `point_dlq_messages` | 1件以上 | オンコール |
| `point_balance_drift_members` | 1以上 | ポイント運用チャンネル |
| 各日次ジョブの最終成功時刻 | 26時間以上前 | オンコール |
| `redemption_retry` キューの滞留件数 | 100件超 | オンコール |

### 日次ジョブの再実行

- `ExpireJob`・`GrantConfirmJob` が失敗した場合、オンコールは原因を取り除いた後、同日中に手動で再実行する。いずれも対象条件に状態 (`pending`・`confirmed`) を含むため、処理済みの行が二重に処理されることはない
- `BalanceReconcileJob` は再実行しない

### データの保持

- `point_ledger`・`point_grants`・`point_redemptions`・`point_redemption_allocations`: 削除しない (会計監査のため10年保持)
- `redemption_requests`: テーブルの肥大化を防ぐため、作成から24時間を過ぎた行を毎日 04:00 のクリーンアップジョブで削除する

### CS 対応手順

- 会員から履歴の問い合わせを受けた場合、CS 担当は管理画面の「ポイント台帳」画面 (`GET /admin/v1/members/{member_id}/ledger`) で確認し、増減の理由を説明する
- 誤付与・付与漏れの訂正と補償は「手動調整」画面 (`POST /admin/v1/adjustments`) で行い、`reason_code` を必ず選ぶ
- 調査の結果、会員の残高に誤りがあると判明した場合、CS 担当は管理画面の「残高編集」画面から `point_balances.confirmed_balance` を正しい値に直接書き換え、書き換え前後の値を問い合わせチケットに記録する

### 権限

- `point_db` への直接接続は、`point-ledger` のサービスアカウントと DBA の緊急用アカウントだけに許可する
- 管理画面の各画面の利用権限は、構成と責務に記載したロールに従う

## 決定事項

| ID | 決定 | 理由 | 検討した代案 |
|---|---|---|---|
| D1 | 台帳は追記専用とし、残高は `point_balances` にキャッシュする | 履歴の説明責任と残高参照の速さを両立する | 毎回台帳を集計する (会員あたりの行数が増えると遅くなるため不採用) |
| D2 | ポイントの有効期限は「最後にポイントを獲得した日から1年」とする。付与が確定するたびに、その会員が保有する確定ポイント全体の有効期限が、その確定日から1年後まで延長される | 会員規約の改定案 (第12条) として法務・マーケティングと合意済み。継続して購入する会員のポイントを失効させない | 年度末に一律失効 (年度末に問い合わせが集中するため不採用) |
| D3 | 付与率は送料とポイント利用分を除く商品代金の1%、小数点以下は切り捨てる | 現行の付与ルールを変えない | 支払総額の1% (ポイント利用分にも付与され、規約と合わないため不採用) |
| D4 | 仮付与の確定は配送完了日の15日後 (返品受付期間14日の翌日) とする | 確定後に返品が起きないようにし、確定済みポイントの回収処理を不要にする | 出荷日起点 (配送遅延時に返品期間中に確定してしまうため不採用) |
| D5 | 旧列 `members.point_balance` は移行が完了したら同じリリースで削除する | 旧列を残すと、誤って参照・更新するコードが残り、残高の二重管理になる | 半年残して参照を監視する (二重管理の期間が長いため不採用) |
| D6 | 利用の冪等性は `Idempotency-Key` で保証し、`point_redemptions.order_id` に一意制約は付けない | 1注文で利用を返還した後、同じ注文の支払方法変更で再び利用するケースがある | `order_id` の一意制約 (上記ケースに対応できないため不採用) |
| D7 | 失効予定の通知は失効日の30日前に1回だけ送る | 通知回数を増やすと配信停止が増えるとマーケティングから要望があった | 30日前と7日前の2回 |
| D8 | 日付はすべて JST の日付として扱い、日次ジョブも JST で動かす | 会員に見せる期限日と、ジョブの判定日を一致させる | UTC で保持して表示時に変換 (日付の境界がずれるため不採用) |
