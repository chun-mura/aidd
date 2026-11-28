# 開発用の権限と公開の権限を分ける参照構成 (S05 #154)

[README に戻る](../../README.md) / [保証条件と責任分担](contract.md) / [隔離実行と通信境界](runtime-boundary.md) / [公開ゲート](release-gate.md)

## いつ使うか

[最初の対応構成](contract.md#明示選択の保証構成の例-最初の対応構成) (`poc-orbstack-arm64`) で、意図しない資格情報を引き継がないこと (AC-PRIV-006) と、開発用の権限では公開・管理操作ができず、期限切れのときに広い権限へ切り替わらないこと (AC-PRIV-007) の証拠を探すとき。

ロードマップと #154 は、置き場所を `docs/assurance/credentials.md` としていた。その名前はサンドボックスの読み取り拒否パターン (`*credential*`) に当たり、aidd の書き込みガードが作成を止める (作っても他のセッションから読めなくなる)。そのため、所有者の判断でこの名前にした。

## この文書が宣言しないこと

- 証拠の所在と限界を示すだけで、どの主張も判定しない。すべての主張は `未検証` である。判定は開発の実行と分けた判定者が行い、所有者が承認する ([採用の条件](contract.md#採用の条件))
- GitHub 側の権限 (ruleset・fine-grained PAT の範囲・branch protection) は実測していない。#230 で、所有者の承認を待っている
- 新しい secret broker は作らない。GitHub の fine-grained PAT と、モデルの OAuth token または API キーという既存の仕組みだけを使う

## 1. 参照構成の所在

実装は aidd-autopilot の `chun-mura/aidd-autopilot#8` (#7 の上に積む、コミット `8469893` 以降) にある。所在の一覧は [runtime-boundary.md の §1](runtime-boundary.md#1-参照構成の所在) と同じ。資格情報に関わるのは次のファイル。

| 役割 | 所在 (aidd-autopilot) |
|---|---|
| 段階ごとの受け渡し・引数の検査 | `packages/platform-docker/src/staged-runner.ts` |
| stdin の1行 JSON (封筒) の読み取り | `packages/runner/src/stdin-envelope.ts` |
| 公開 (push) | `packages/runner/src/publish.ts`、`packages/runner/src/publish-cli.ts` |
| 期限と承認の gate | `apps/controller/src/config.ts`、`apps/controller/src/main.ts` |

## 2. 資格情報の流れ

| 資格情報 | 渡す先 | 渡し方 | 渡さない先 |
|---|---|---|---|
| controller token (Issue・PR の操作、ruleset の読み取り) | host の controller だけ | controller のメモリ | どのコンテナにも渡さない |
| runner token (作業ブランチへの push) | publish 段階だけ | `docker run -i` の stdin に1行の JSON | seed・deps・agent・ingest |
| model token | agent 段階の claude の子プロセスだけ | stdin で受け取り、その子プロセスの env にだけ置く | seed・deps・ingest・publish |

- 秘密は引数・コンテナの env・label・image・成果物・ログに置かない。値を書かない `-e NAME` でも `docker inspect` の `.Config.Env` に平文で残ると実測したため、この方式にした ([runtime-spike.md](runtime-spike.md) 1-4 と同じ結果)
- ホストの home・`~/.ssh`・docker.sock・`SSH_AUTH_SOCK` はどの段階にも mount しない。controller の環境変数は段階に引き継がない (段階には決めた変数だけを渡す)

## 3. 開発用の権限でできないこと (AC-PRIV-007)

- agent 段階 (モデルが動く段階) には GitHub の token が無い。push・merge・release・設定の変更は、資格情報が無いのでできない
- publish 段階は、モデルを動かさず、決まったコマンドだけを実行する。push できるのは、request の branch (`aidd/` で始まる) への1つの refspec `<tip>:refs/heads/<branch>` だけ。force・`+`・tag・mirror・main は拒否する
- push の宛先は `https://github.com/<owner>/<repo>.git` に固定する。token を守るのは、この固定した remote と、publish 段階の通信の許可先 (`github.com`・`api.github.com`) である。git の extra header を origin に限って付けても、守りにはならない。最初の redirect の後も、git は同じ header を送り続けるため
- merge・release・本番の変更・ruleset の変更を GitHub が拒否することは、PAT の範囲と ruleset で決まる。これは #230 で実測するまで `未確認` である

### 期限切れ・失効・付与の失敗

- config に `runner_github_token_expires_at` を必須で持たせる。controller の gate は、期限切れの場合と、期限までの残りが 1回の run の時間 + 1時間を下回る場合に、dispatch しない
- publish も、受け取った期限を確かめ、切れていれば止める
- どの場合も、別の token (controller token や環境変数の `GH_TOKEN`) には切り替えない。run は blocked で止まり、人が確かめる

## 4. 依存の取得・build script・モデルの認証

- 依存の取得は deps 段階だけで行う。この段階に秘密は無い。lockfile があるときだけ `npm ci --ignore-scripts` を実行し、install script は動かさない。通信は依存レジストリだけに許す
- agent 段階で動く build script・試験 (モデルの指示で動くもの) には、GitHub の token が無い。ただし model token は claude の子プロセスの env にあり、モデルのプロセス (Bash ツールなど) から読める
- モデルの認証には、OAuth token か API キーの1つが要る。利用額の上限は `--max-budget-usd` と run の予算で掛ける。権限を絞ったキーを使う

## 5. 証拠 (試験と記録)

| 主張 | 試験 (aidd-autopilot) | 種類 |
|---|---|---|
| AC-PRIV-006 | `tests/docker/host-exposure.test.ts`: 架空の秘密を host の env・`SSH_AUTH_SOCK`・model token に置き、どの段階の `docker inspect` (Env・Args・Labels・Mounts)・ログ・`limits.json`・成果物にも出ないこと。deps 段階に秘密が無く、agent 段階に GitHub の token が無いこと。bind mount がこの run の準備ディレクトリだけで、home ではないこと | 実際の Docker |
| AC-PRIV-006 | `packages/runner/test/stdin-envelope.test.ts`、`publish-cli.test.ts`: 値がエラー文・argv・stdout・stderr に出ないこと | 単体 |
| AC-PRIV-007 | `tests/docker/publish.test.ts`: 正しい branch だけを push し、main・tag・別の branch・force を拒否すること。期限切れで止まり、別の token に切り替えないこと。proxy を通る HTTPS の remote まで届くこと | 実際の Docker (remote はローカルの bare repo と `example.com`) |
| AC-PRIV-007 | `apps/controller/test/main.test.ts`: 期限の gate | 単体 |

実行の記録は [aidd-autopilot の検証記録](https://github.com/chun-mura/aidd-autopilot/blob/8469893/docs/verification/2026-11-28-assurance-boundary-docker.md) にある。

## 6. 未確認と残るリスク

- `未確認`: GitHub 側で merge・release・ruleset の変更が拒否されること (#230)、PAT の範囲、実際の claude CLI (試験は偽の claude)
- 残るリスク: model token はモデルのプロセスから読める。許可先の `api.anthropic.com` へ持ち出せる。publish 段階の token は push の間だけ git のプロセスにある
- 結合検証 (攻撃と故障のケース) は #159 (S10) で行う
