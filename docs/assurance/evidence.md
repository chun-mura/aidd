# 検証証跡と配布物の結び付け (evidence)

[README に戻る](../../README.md) / 主張の体系: [保証条件と責任分担](contract.md) / 公開ゲート: [release-gate.md](release-gate.md) / 例: [`examples/assurance/github/provenance.yml`](../../examples/assurance/github/provenance.yml)、[`examples/assurance/evidence/`](../../examples/assurance/evidence/)

## いつ使うか

明示選択の保証構成で、主張 `AC-PROC-002` (配布物の digest が検証した成果物の digest と一致し、要件の版・source SHA・実行した検証・実行基盤・承認を結ぶ証跡が、信頼する CI によって生成され、配布側で検証されている) と `AC-PRIV-009` (エージェントと PR の build step が、証跡の署名権限と検証条件を変更できない) の証拠を作るとき。具体的には次の場面で読む。

- 配布物 (release の asset など) を出す前に、「検証したものと配るものが同じか」を配布側で機械的に確かめたいとき
- 証跡に何を入れ、何を入れないか、どれだけ残し、誰が読めるかを決めるとき
- SLSA のレベルを名乗れるかを判断するとき

通常の aidd の利用はこの文書の対象外で、何も変わらない。#122 のローカル証跡 (`.aidd/autonomous-review/` のレビューの記録) は、エージェントの手元で書かれ署名されていないので、この文書の証跡とみなさない。この文書の証跡は、信頼する CI が観測して生成し、配布側が検証するものだけを指す。

独自の署名方式やログ基盤は作らない。GitHub の artifact attestation (`actions/attest-build-provenance`・`actions/attest`、Sigstore による署名) と、in-toto の statement、SLSA provenance・in-toto test-result の predicate をそのまま使い、配布側では `gh attestation verify` で署名を検証する。

## 主張との対応

| 主張ID ([contract.md](contract.md)) | この例が示すこと | 主張の判定に足りないもの |
|---|---|---|
| `AC-PROC-002` | 配布物の digest を主語にした provenance と test-result の2つの attestation を同じ workflow run で発行し、配布側で両者を結び付けて判定する規則 ([配布側の判定](#配布側の判定))。digest の不一致・署名元・環境・入力の違い・古い証拠の再利用を拒否することを、架空の検証結果の fixture で決定的に試験した | 実際に attestation を発行し `gh attestation verify` で検証することの実測 ([所有者の承認後に実測する](#所有者の承認後に実測する)) |
| `AC-PRIV-009` | 署名の権限 (`id-token: write`・`attestations: write`) を、プロジェクトのコードを動かさない job だけに渡す workflow と、検証条件 (`policy.json`) を配布側・policy リポジトリに置く配置 ([署名権限と検証条件を守る](#署名権限と検証条件を守る)) | 同上 |

aidd はどの構成のこれらの主張も `適合` と判定しない。試験と静的な検査はこのセッション (エージェント) が作って実行したもので、判定者を分ける要件 ([証拠の要件](contract.md#証拠の要件)) を満たさない。

## 何を何に結び付けるか

配布物の digest (SHA-256) を主語にして、次を結ぶ。

| 結ぶもの | どこに入るか | 配布側で照合するもの |
|---|---|---|
| 成果物の digest | 2つの attestation の `subject`、test-result の `configuration` | 配る手元のファイルから計算した digest |
| source SHA と ref | 署名証明書の `sourceRepositoryDigest`・`sourceRepositoryRef`・`sourceRepositoryURI` (GitHub の OIDC token から Fulcio が埋める。workflow が書き換えられない) | 配る版の commit と tag、`policy.json` の `source_repository`・`source_ref_pattern` |
| 実際に実行した検証 | in-toto test-result の predicate (`result`・`passedTests`・`failedTests`) | `PASSED` で、失敗が無く、成功した基準が1つ以上 |
| 要件の版 (受け入れ基準) | test-result の `configuration` の `approved.sha256` の digest。`approved.sha256` は原要件・基準・インタフェース・試験の digest を含む ([acceptance.md](acceptance.md)) | `policy.json` の `criteria_digest` |
| 実行基盤 | 証明書の `issuer`・`runnerEnvironment`・`buildSignerURI` (署名した workflow)・`buildSignerDigest` (その workflow の commit) | GitHub Actions の OIDC、GitHub hosted runner、policy リポジトリの `provenance.yml` の、所有者が承認した commit (`policy.json` の `signer_digest`) |
| 同じ実行であること | 証明書の `runInvocationURI` | 2つの attestation で一致すること |
| 承認 | attestation には入らない。source の commit が #156 の ruleset で守られた既定ブランチに含まれ、tag が [`tag-ruleset.json`](../../examples/assurance/github/tag-ruleset.json) で守られていることで間接に結ぶ | 承認の記録は [contract.md の記録項目](contract.md#主張の記録項目) に残す ([限界](#限界)) |

## 構成

[`provenance.yml`](../../examples/assurance/github/provenance.yml) は policy リポジトリに置く再利用 workflow (`workflow_call`) で、対象リポジトリの release の workflow から固定コミットで呼ぶ。呼ぶ側の例:

```yaml
on:
  push:
    tags: ['v*']
permissions: {}
jobs:
  provenance:
    permissions:
      contents: read
      id-token: write
      attestations: write
    uses: example-org/assurance-policy/.github/workflows/provenance.yml@<policy の commit SHA>
```

| job | 権限 | すること | しないこと |
|---|---|---|---|
| `build` | `contents: read` | release の commit を checkout し、配布物を再現可能に固める (`tar --sort=name --mtime=@0`・`gzip -n`)。digest を出力する | 署名しない (`id-token` が無い) |
| `verify` | `contents: read` | 配布物を取り出し、digest が `build` と同じか確かめ、承認済みの基準 (`sha256sum --check`) で受け入れ試験を実行し、test-result の predicate を書く。失敗したら job ごと失敗する | 署名しない |
| `attest` | `contents: read`・`id-token: write`・`attestations: write` | 配布物と test-result の digest を照合し直し、SLSA provenance と test-result の attestation を発行する。`build` と `verify` が成功したときだけ動く | プロジェクトのコードを checkout も実行もしない |

release の tag (`refs/tags/v*`) の作成・移動・削除は、tag を対象にした ruleset [`tag-ruleset.json`](../../examples/assurance/github/tag-ruleset.json) で禁じ、bypass に所有者のチーム (`actor_id` は置き換える) だけを置く。#156 の `ruleset.json` は既定ブランチだけを対象にしているので、tag は別の ruleset で守る。エージェントに渡す token の持ち主をこのチームに入れない。所有者が既定ブランチに無い commit に tag を付けても配らないように、配布側は commit が既定ブランチに含まれることを別に確かめる (下の手順)。

## 配布側の判定

配る前に、配布側 (所有者の手元か、公開を行う信頼する job) で3段階で確かめる。

1. **署名の検証 (`gh attestation verify`)**: 証明書の連鎖・透明性ログ・署名元を検証する。predicate の種類ごとに1回ずつ実行し、JSON を保存する。

   ```bash
   gh attestation verify dist/app.tar.gz --repo example-org/example-app \
     --signer-workflow example-org/assurance-policy/.github/workflows/provenance.yml \
     --signer-digest <policy リポジトリの承認した commit SHA> \
     --source-ref refs/tags/v1.2.3 --source-digest <release の commit SHA> \
     --deny-self-hosted-runners \
     --predicate-type https://slsa.dev/provenance/v1 --format json >provenance.json
   gh attestation verify dist/app.tar.gz --repo example-org/example-app \
     --signer-workflow example-org/assurance-policy/.github/workflows/provenance.yml \
     --signer-digest <policy リポジトリの承認した commit SHA> \
     --source-ref refs/tags/v1.2.3 --source-digest <release の commit SHA> \
     --deny-self-hosted-runners \
     --predicate-type https://in-toto.io/attestation/test-result/v0.1 --format json >test-result.json
   ```

2. **source の commit が既定ブランチにあることの確認**: tag は既定ブランチの外の commit にも付けられる。GitHub の compare API で、commit が既定ブランチの先端の祖先 (自分自身が merge base) であることを確かめる材料を取る。

   ```bash
   gh api repos/example-org/example-app/compare/main...<release の commit SHA> >compare.json
   ```

3. **結び付けの判定 ([`verify_evidence.py`](../../examples/assurance/evidence/verify_evidence.py))**: `gh` は attestation を1つずつ検証するので、2つが同じ実行・同じ入力から来たか、試験が通ったか、古くないかは別に確かめる。検証条件は [`policy.json`](../../examples/assurance/evidence/policy.json) に置く。例の `signer_digest` は 0 の並びで、[release-gate.md](release-gate.md#置き換えるもの) の `POLICY_SHA` と同じ、所有者が承認した policy リポジトリの commit に置き換える (`example-org` の名前も同様)。

   ```bash
   python3 verify_evidence.py --policy policy.json --artifact dist/app.tar.gz \
     --source-digest <release の commit SHA> --source-ref refs/tags/v1.2.3 \
     --default-branch-compare compare.json \
     --attestations provenance.json test-result.json
   ```

`verify_evidence.py` は署名を検証しない。`gh attestation verify` を通っていない JSON に使わない。同じ workflow run (`runInvocationURI`) の attestation の組ごとに判定し、どれか1組がすべての規則を通れば配布してよい。通らなければ最も新しい組の理由を出す。

| 拒否する状況 | 理由のコード |
|---|---|
| 配る手元のファイルの digest が attestation の主語と違う | `digest-mismatch:<provenance か test-result>` |
| 試験が別の build の成果物に対して行われた | `digest-mismatch:test-result`、`input-mismatch` |
| 署名した workflow が policy リポジトリの `provenance.yml` でない (対象リポジトリ自身の workflow など)、またはその commit が `signer_digest` でない (policy リポジトリの未承認のブランチなど。パスだけでは区別できない) | `signer-mismatch` |
| source の commit が既定ブランチに含まれない (compare の `status` が `behind`・`identical` でない、または merge base が commit 自身でない) | `not-on-default-branch` |
| OIDC の発行者が GitHub Actions でない | `issuer-mismatch` |
| self-hosted runner で作られた | `environment-mismatch` |
| source のリポジトリ・commit が配る版と違う (古い commit の証跡の再利用を含む) | `source-mismatch` |
| ref が配る tag と違う、または tag の形でない (ブランチから作った) | `ref-mismatch` |
| 試験の入力 (承認済みの基準の digest) が policy と違う | `input-mismatch` |
| 試験が `PASSED` でない、失敗がある、成功が1つも無い | `tests-not-passed` |
| provenance か test-result が無い (別の run の組み合わせを含む) | `missing-attestation:<種類>` |
| 透明性ログの時刻が無い | `missing-timestamp` |
| 最も古い署名時刻が `max_age_days` (例は30日) より古い、または最も新しい時刻が未来 | `stale-evidence` |
| test-result に決めた項目以外 (プロンプトなど)、ID の形でない試験名 (ログの断片など)、run の URL の形でない `url`、配布物と `approved.sha256` 以外の `configuration` の名前がある | `unexpected-content` |
| 実行の識別子が無い | `missing-run` |
| 入力を読めない | `invalid-input:<説明>` |

provenance を新しく発行し直しても、古い run の test-result とは組にならない (`runInvocationURI` が違う)。古い証拠を新しい配布物や新しい版に流用すると、digest か source で落ちる。同じ版の同じ配布物でも、`max_age_days` を過ぎた証拠では配らず、再検証させる ([失効条件](contract.md#失効条件) の「有効期限切れ」と同じ考え方。期限は導入先が決める)。

## 署名権限と検証条件を守る

`AC-PRIV-009` のために、署名する権限と、何を合格とするかの条件を、エージェントと PR の build step から届かない場所に置く。

| 守るもの | 置き場所と仕組み |
|---|---|
| 署名の権限 (`id-token: write`) | `attest` job だけが持つ。`attest` は checkout せず、プロジェクトのコードを動かさない。`build`・`verify` は読み取りの token だけで、OIDC token を取れない |
| 署名する workflow | policy リポジトリの `provenance.yml` を固定コミットで呼ぶ。配布側は `--signer-workflow` でこのファイルに、`--signer-digest` と `policy.json` の `signer_digest` で所有者が承認した commit に限る。対象リポジトリの workflow を書き換えても、policy リポジトリの別のブランチで書き換えた版を呼んでも、署名元が変わって `signer-mismatch` になる |
| 発行のきっかけ | release の tag の push だけで、PR のイベント (`pull_request` など) では動かない。PR のコードが release に入らないことは2つの前提に依存する: (1) tag の作成・移動を所有者のチームに限る ([`tag-ruleset.json`](../../examples/assurance/github/tag-ruleset.json))、(2) 既定ブランチへのマージは #156 のゲートを通る。(1) が崩れて未マージの commit に tag が付いても、配布側の compare の確認で `not-on-default-branch` になる |
| 検証条件 (`policy.json`) | 配布側 (所有者の手元か policy リポジトリ) に置き、変更は所有者の承認を要する設定変更として扱う。対象リポジトリには置かない |
| 長期の秘密 | 使わない。署名は実行ごとの短命の証明書 (Sigstore の keyless 署名) で、保存する鍵が無い |

## 保存しないもの・保持期間・アクセス権

| 証跡 | 中身 | 置き場所 | 保持期間 | 読める人 |
|---|---|---|---|---|
| attestation (provenance・test-result) | digest・source の commit と ref・workflow と run の識別子・試験の ID と結果 | GitHub の attestation API と Sigstore の透明性ログ | 公開リポジトリでは public-good の透明性ログに記録され、**消せないものとして扱う**。GitHub 側の削除の可否は未確認 | 公開リポジトリでは誰でも。private リポジトリの attestation は GitHub Enterprise Cloud が要る (無料・Pro・Team では公開リポジトリだけ) |
| 中間の artifact (`dist`・`test-result`) | 配布物と test-result の JSON | GitHub Actions の artifact | 7日 (`retention-days`) | リポジトリを読める人 |
| 配布側の判定結果 | `verify_evidence.py` の出力 | 導入先の記録 ([contract.md の記録項目](contract.md#主張の記録項目)) | 主張の有効期限まで (書いていなければ90日) | 所有者と判定者 |

- 証跡に秘密・プロンプトの本文・ログの本文・本番データ・顧客データを入れない。test-result は試験の ID と digest だけにし、`verify_evidence.py` は決めた項目以外を `unexpected-content` で拒否する。試験の出力 (`assert` の失敗の説明など) は attestation に入れない
- 公開リポジトリでは attestation が公開され消せないので、リポジトリ名・ブランチ名・tag 名・ファイル名にも漏らしたくない情報を入れない
- 最初の対応構成 (有料契約なし、[contract.md](contract.md#明示選択の保証構成の例-最初の対応構成)) では attestation を公開リポジトリでしか使えない。架空のデータだけを置く検証用の公開リポジトリで実測する
- 証跡を読む権限と、証跡を発行する権限 (`attestations: write`) は別に扱う。後者は `attest` job だけが持つ

## SLSA のレベル

**この例は SLSA のどのレベルも宣言しない。** 署名された provenance があることは、ビルドの改ざん耐性の一部を示すだけで、SLSA Build L3 や成果物の機能の正しさを示さない。

| SLSA v1.2 Build | 要件 (要約) | この例での状態 |
|---|---|---|
| L1 | provenance が存在する | 構成上は provenance を発行するが、実測していない (未検証) |
| L2 | hosted のビルド基盤が provenance を生成し署名する | GitHub hosted runner と artifact attestation の組み合わせで満たしうるが、実測していない (未検証) |
| L3 | ビルドの実行どうしが隔離され、署名の鍵などの秘密がユーザー定義のビルドの手順から届かない | GitHub は「再利用 workflow と artifact attestation で L3 に近づける」と説明している。この例は再利用 workflow と署名 job の分離をとるが、基盤の隔離と、`build` の手順が `attest` の署名に影響できないことは実測していない (未検証) |

レベルを名乗るには、導入先が [SLSA の Build requirements](https://slsa.dev/spec/v1.2/build-requirements) を項目ごとに実測し、[contract.md](contract.md) の主張の記録に証拠として書く。

## 確かめた範囲

`bash tests/assurance/evidence-test.sh` (CI の `contract-tests` で ubuntu と macOS の両方) が次を確かめる。どれも fixture と静的な検査で、実際の GitHub では attestation を発行も検証もしていない。

1. `verify_evidence.py` の判定: `gh attestation verify --format json` の出力の形に合わせた架空の検証結果の35通り (上の表の各状況、古い run と新しい run が並ぶ場合、古い run だけの場合、同じ run の test-result の片方だけが失敗の場合、policy リポジトリの別の ref で署名した場合、末尾に改行のある ref) で、判定・終了コード・理由のコードが期待と一致する。読めない入力 (compare の出力を含む6通り) は `invalid-input` で失敗になる
2. `provenance.yml` の静的な検査 ([release-gate.md](release-gate.md) と同じ小さな YAML の解析): トリガーが `workflow_call` だけ、書き込みの権限は `attest` の `id-token`・`attestations` だけ、署名の action は `attest` だけ、`attest` は checkout しない、`attest` は `build` と `verify` の成功を待つ、action の SHA 固定、`persist-credentials: false`
3. 静的な検査の識別力: `build` に `id-token` を渡す、`attest` で checkout する、試験の失敗でも `attest` を動かす (`if: always()`)、PR のトリガーを足す、`attest` に `contents: write` を渡す、の5つの改変をそれぞれ検出する
4. `tag-ruleset.json`: tag を対象にした有効な ruleset で、`refs/tags/v*` の作成・更新・削除・force 更新を禁じ、bypass がチームだけ (置き換える `actor_id` 0) であること。`policy.json` の `source_ref_pattern` がこの tag の形だけを通すこと
5. `policy.json` と workflow・受け入れ基準の対応: 配布物の名前、test-result の predicate の種類、`criteria_digest` が例の `approved.sha256` の digest と一致すること

fixture は `gh attestation verify --format json` の出力 (sigstore-go の検証結果の JSON) の項目名に合わせて書いたもので、実際の出力の形と一致するかは実測していない。

## 所有者の承認後に実測する

次は実際の GitHub での実行が要り、検証用の公開リポジトリの作成と設定の変更を伴うので、**この issue では行っていない (未確認)**。所有者が承認した検証用のリポジトリ (架空のデータだけを置く) で行い、結果を [contract.md の記録項目](contract.md#主張の記録項目) の証拠に書く。

| 実測すること | 確かめ方 |
|---|---|
| attestation が発行され、`gh attestation verify` が通る | tag を push し、上の2つのコマンドが成功することを見る |
| tag の ruleset が効く | `tag-ruleset.json` (値を置き換えたもの) を適用し、所有者のチーム以外 (エージェントの token を含む) が `v*` の tag を作成・移動・削除できないことを見る |
| compare の判定が既定ブランチの外の commit を拒否する | 未マージのブランチの commit に tag を付け (所有者が試験として行う)、`compare` の `status` が `ahead` か `diverged` になり `not-on-default-branch` で落ちることを見る |
| `buildSignerDigest` が policy リポジトリの commit になる | 固定コミットで呼んだときの証明書の `buildSignerDigest` と `buildSignerURI` の ref を見る |
| `gh` の出力の形が fixture と同じ | 実際の `--format json` の出力で `verify_evidence.py` が `pass` になることを見る。項目名が違えば fixture と script を直す |
| 配布物を1バイト変えると拒否される | 変えたファイルで `gh attestation verify` が失敗することを見る |
| 対象リポジトリの workflow で署名したものは拒否される | 同じ手順を対象リポジトリ側の workflow で発行し、`--signer-workflow` で失敗することを見る |
| 試験が失敗したら attestation が発行されない | 誤実装を release し、`attest` が動かず attestation が無いことを見る |
| `build` の手順が署名の権限を使えない | `build` で OIDC token の取得を試み、取れないことを見る (`ACTIONS_ID_TOKEN_REQUEST_URL` が無い) |
| 透明性ログの時刻と `runInvocationURI` の扱い | 再実行 (attempt 2) で `runInvocationURI` が変わること、時刻が `verifiedTimestamps` に入ることを見る |
| 保持とアクセス | 公開リポジトリの attestation が誰から見えるか、削除できるかを見る |
| SLSA の各要件 | [SLSA のレベル](#slsa-のレベル) の表の項目 |

## 限界

- **承認は attestation に入らない。** source の commit が守られた既定ブランチにあること・tag が守られていることは #156 の ruleset と `tag-ruleset.json` に依存し、承認者・承認日は attestation では確かめられない。導入先の記録で結ぶ
- **試験の実行時の改ざんは防がない。** `verify` は配布物のコードを試験と同じプロセスで動かす ([release-gate.md の限界](release-gate.md#限界) と同じ)。test-result は「信頼する workflow がこの結果を観測した」ことを示し、悪意のある実装が試験の実行を乗っ取らなかったことは示さない
- `verify_evidence.py` は署名を検証しない。`gh attestation verify` を飛ばすと、偽の JSON でも通る
- 再現可能な固め方 (`tar --sort=name` など) は GNU tar を前提にしている (ubuntu の runner)。配布物の再現性 (別の環境で同じ digest になること) は確かめていない
- 証跡の改ざんの検出は Sigstore と GitHub を信頼する構成要素として仮定している。その侵害は主張の外にある
