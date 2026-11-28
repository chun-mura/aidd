# 公開ゲートの参照構成 (release gate)

[README に戻る](../../README.md) / 主張の体系: [保証条件と責任分担](contract.md) / 受け入れ基準: [acceptance.md](acceptance.md) / 例: [`examples/assurance/github/`](../../examples/assurance/github/)

## いつ使うか

明示選択の保証構成で、主張 `AC-PROC-001` (必須検査が公開する SHA で実際に実行されて成功している) と `AC-PRIV-008` (PR のコードから必須検査の定義・受け入れ基準・ruleset を書き換えて合格条件を消せない) の証拠を作るとき。具体的には次の場面で読む。

- 導入先の GitHub リポジトリで、必須検査の未実行・改変・迂回を CI 側で止める構成を決めるとき
- [acceptance.md](acceptance.md) の受け入れ基準を、実装を変える PR から守る経路 (導入手順6) を作るとき
- 「CI が通った」を報告するときに、何が成功として数えられ、何が数えられないかを確かめるとき

通常の aidd の利用はこの文書の対象外で、何も変わらない。PR を作る前の非ブロックの警告 (#122、`tool-reminder.sh` のレビュー証跡の警告) はそのまま残す。この文書は導入先が明示的に選ぶ CI 側の強制を扱う。aidd 自身の `.github/` と GitHub の設定は、この参照構成では変えない。

## 主張との対応

| 主張ID ([contract.md](contract.md)) | この参照構成が示すこと | 主張の判定に足りないもの |
|---|---|---|
| `AC-PROC-001` | 必須検査の結果を数える規則 ([判定の規則](#判定の規則))。失敗・未実行・skipped・neutral・timeout・cancel・証跡なし・古い SHA を成功と数えないことを、架空の check run の fixture で決定的に試験した | 導入先の実リポジトリで、ruleset と workflow が実際にその通りに効くことの実測 ([所有者の承認後に実測する](#所有者の承認後に実測する)) |
| `AC-PRIV-008` | 検証の定義・判定・基準を PR のコードから分ける配置 ([信頼の分け方](#信頼の分け方))、bypass を空にした ruleset、最新の push の承認、提供元の app の固定、workflow の最小権限 | 同上。管理者が ruleset 自体を変えられることは [管理者権限の前提](#管理者権限の前提) として残る |
| `AC-SPEC-001` (参照のみ) | 受け入れ試験を、保護されたブランチ側の基準で、変更側の実装に対して実行する | 基準の内容の妥当性は [acceptance.md](acceptance.md) と所有者が扱う |

aidd はどの構成のこれらの主張も `適合` と判定しない。試験と静的な検査はこのセッション (エージェント) が作って実行したもので、判定者を分ける要件 ([証拠の要件](contract.md#証拠の要件)) を満たさない。

## 構成

| ファイル | 役割 |
|---|---|
| [`verification-gate.yml`](../../examples/assurance/github/verification-gate.yml) | 検証の workflow。`verify` job (`aidd-verify`) が変更側の実装に受け入れ試験をかけ、`gate` job (`aidd-release-gate`) が check run と検証の報告を判定する |
| [`gate.py`](../../examples/assurance/github/gate.py) | 判定スクリプト。check run の JSON と検証の報告を読み、成功と数えてよいかを決める (Python 標準ライブラリのみ) |
| [`gate-policy.json`](../../examples/assurance/github/gate-policy.json) | 必須の check の名前・提供元の app id・同じ workflow run に限るか、報告を必須にするか |
| [`ruleset.json`](../../examples/assurance/github/ruleset.json) | 既定ブランチの ruleset (REST API `POST /repos/{owner}/{repo}/rulesets` の body の形)。上の workflow を必須にし、bypass を空にする |
| [`tests/assurance/release-gate-test.sh`](../../tests/assurance/release-gate-test.sh) | fixture による判定の試験と、workflow・ruleset・policy の静的な検査 |

## 信頼の分け方

PR が書き換えられるものの中に、合格条件を置かない。

| もの | どこから読むか | 誰が変えられるか |
|---|---|---|
| workflow (`verification-gate.yml`)・`gate.py`・`gate-policy.json` | 保護された別の **policy リポジトリ** の、固定したコミット (`POLICY_REPO`・`POLICY_SHA`)。ruleset の `workflows` ルール (required workflow) がこのファイルを必須にする | policy リポジトリの所有者だけ。変更はそのリポジトリの ruleset と承認を通る |
| 受け入れ基準 (`CRITERIA_DIR` の `criteria.md`・`acceptance_test.py`・`api.py`・`approved.sha256` など) | 対象リポジトリの、PR の **base** のコミット (`BASE_SHA`)。PR の head からは読まない | 基準のパスへの変更は `required_reviewers` で所有者のチームの承認が要る。base に入るのはマージの後だけ |
| 実装 (`IMPL_DIR`) | PR の head (`TARGET_SHA`) | PR の作成者 (エージェントを含む)。信頼しない |

この分け方で、次の書き換えは合格条件を消せない。

| PR がすること | 止める仕組み |
|---|---|
| 対象リポジトリの workflow を書き換える・消す | required workflow は policy リポジトリの固定コミットから動く。対象リポジトリの `.github/**` の変更には所有者のチームの承認が要る (`required_reviewers`) |
| 同じ job 名 (`aidd-verify`) で常に成功する workflow を足す | 提供元の app (GitHub Actions、`integration_id` 15368) は同じなので ruleset だけでは区別できない。`gate.py` が `aidd-verify` を自分と同じ workflow run (check suite) のものに限る (`same_run`)。workflow の追加自体も `.github/**` の承認に当たる |
| 別の GitHub App から同名の check を成功させる | ruleset の `integration_id` と `gate.py` の `app_id` で提供元を固定する |
| 受け入れ基準や `approved.sha256` を書き換える | 基準は base から読む。PR 側の変更は試験に使われない。マージには基準のパスの承認が要る |
| `gate.py` を書き換える | `gate.py` は policy リポジトリから読む |
| 承認の後にコミットを積む | `require_last_push_approval` と `dismiss_stale_reviews_on_push` で、最新の push に別の人の承認が要る |
| 古いコミットの成功を使い回す | check run を対象 SHA で取り、報告の `target_sha` を照合する。`strict_required_status_checks_policy` と merge queue で、base の更新後の組み合わせで検証し直す |

## 判定の規則

`gate.py` は、必須の check ごとに次の順で判定し、1つでも当てはまれば全体を失敗にする。理由はコードで出力する (fixture の試験はこのコードを過不足なく照合する)。

| 状況 | 理由のコード |
|---|---|
| その名前の check run が無い (未実行) | `missing-check:<名前>` |
| 別の SHA の結果しか無い (古い SHA) | `stale-sha:<名前>` |
| 期待する提供元 (app id) 以外の結果しか無い | `untrusted-app:<名前>` |
| 別の workflow run の結果しか無い (`same_run` のとき) | `other-run:<名前>` |
| 最新の run が完了していない (queued・in_progress など) | `not-completed:<名前>:<status>` |
| 最新の run の結論が `success` でない (failure・skipped・neutral・timed_out・cancelled・action_required・stale・startup_failure・結論なし) | `not-success:<名前>:<conclusion>` |
| 検証の報告が無い (証跡なし) | `missing-report` |
| 報告の形が違う・成功した基準が1つも無い | `report-invalid` |
| 報告の対象 SHA が違う | `report-sha-mismatch` |
| 報告の基準の digest が、base の `approved.sha256` と違う | `report-criteria-mismatch` |
| 報告に失敗した基準がある | `report-failed` |
| 入力を読めない (SHA が完全でない、JSON が壊れている、`--suite-id` が無い) | `invalid-input:<説明>` |

同じ名前・同じ提供元・同じ run の中で再実行があれば、最も新しい run (id、次に開始時刻) で判定する。GitHub が check を最新の run で数えるのに合わせた。開始時刻を先にしないのは、待機中の再実行には開始時刻が無く、古い成功が勝ってしまうからである。

**skipped を数えない理由**: GitHub は、必須の check が skipped で終わると、それを成功として扱う ([GitHub status checks](https://docs.github.com/en/pull-requests/reference/status-checks))。job の `if:` で `verify` が飛ばされると ruleset は通ってしまうので、`gate` は `if: ${{ always() }}` で必ず動き、`verify` の skipped を失敗と数える。workflow のトリガーに `paths` の絞り込みを付けない (必須の check が始まらないと待ち続け、job が飛ばされると通る)。

## ruleset の設定

[`ruleset.json`](../../examples/assurance/github/ruleset.json) の各ルールと、その理由。

| ルール | 設定 | 理由 |
|---|---|---|
| `bypass_actors` | 空 | ruleset を迂回できる主体を置かない。管理者・エージェントの token の持ち主・GitHub App を入れない |
| `deletion`・`non_fast_forward` | 有効 | 既定ブランチの削除と force 更新を止める ([local-permissions.md](../guides/local-permissions.md) の手順3と同じ) |
| `pull_request` | 承認1以上、code owner の承認、`require_last_push_approval`、`dismiss_stale_reviews_on_push`、スレッドの解決、`required_reviewers` (`.github/**`・`assurance/**` に所有者のチーム) | 最新の push に別の人の承認を要し、workflow と基準の変更に所有者の承認を要する |
| `required_status_checks` | `aidd-verify` と `aidd-release-gate`、どちらも `integration_id: 15368` (GitHub Actions)、`strict_required_status_checks_policy: true` | 提供元を固定し、base が進んだら最新の base で検証し直させる |
| `workflows` | policy リポジトリの `.github/workflows/verification-gate.yml` を、`repository_id`・`ref`・`sha` で固定 | 検証の定義を PR から書き換えられない場所に置く |
| `merge_queue` | `ALLGREEN`、`SQUASH`、応答待ち30分 | 他の PR と合わせた結果 (merge group) で検証してからマージする。workflow は `merge_group` でも動く |

### 置き換えるもの

例の値は架空で、そのままでは動かない (動かないように 0 にしてある)。所有者が適用するときに置き換える。

| 場所 | 項目 | 置き換える値 |
|---|---|---|
| `verification-gate.yml` | `POLICY_REPO`・`POLICY_SHA` | policy リポジトリの名前と、所有者が承認したコミットの完全な SHA |
| `verification-gate.yml` | `CRITERIA_DIR`・`IMPL_DIR`・`IMPL` | 対象リポジトリの基準のディレクトリ、実装のディレクトリ、`module:factory` |
| `ruleset.json` | `workflows[].repository_id`・`sha` | policy リポジトリの数値の id と、上と同じコミット |
| `ruleset.json` | `required_reviewers[].reviewer.id`・`file_patterns` | 所有者のチームの id、`CRITERIA_DIR` に合わせたパス |

### organization が無い場合

ruleset の `workflows` ルールと `required_reviewers` (チーム) は organization を前提にしている。利用できるプランと所有者の種類は GitHub の「About rulesets」で確かめる (このリポジトリでは未確認)。個人のリポジトリで使えないときは、workflow を対象リポジトリの `.github/workflows/` に置き、`POLICY_REPO` を対象リポジトリ自身、`POLICY_SHA` を `BASE_SHA` にし、`.github/CODEOWNERS` で `.github/**` と基準のパスの持ち主を所有者にして `require_code_owner_review` で守る。ただし、1人で開発するリポジトリでは承認者を実装者と分けられない (自分の PR は自分で承認できない) ので、その構成では `AC-PRIV-008` を `適合` にできない。

## workflow の権限

- トリガーは `pull_request` と `merge_group` だけ。`pull_request_target`・`workflow_run`・`issue_comment` のような、書き込みの token や secrets を持つイベントで PR のコードを動かさない
- workflow 全体は `permissions: {}`。`verify` は `contents: read` だけ、`gate` は `contents`・`checks`・`actions` の読み取りだけ。どの job も書き込みの権限を持たない
- secrets を参照しない。同じリポジトリのブランチからの PR では `pull_request` でも secrets が渡るので、参照しないことで渡さない
- `actions/checkout` は `persist-credentials: false` にし、token を `.git/config` に残さない。使う action はすべて完全なコミット SHA に固定する
- PR のタイトル・本文・ブランチ名などを `${{ }}` で `run:` に展開しない (script injection)。値は環境変数で渡す
- PR のコードを動かすのは `verify` だけ。`gate` は PR のコードを checkout しない

## 管理者権限の前提

この参照構成は、次を正しいと仮定する。崩れたら `AC-PROC-001`・`AC-PRIV-008` は失効する ([失効条件](contract.md#失効条件))。

- policy リポジトリと対象リポジトリの管理者 (organization の owner・リポジトリの admin) は、ruleset・required workflow・CODEOWNERS を変えられる。bypass を空にしても、管理者が ruleset を無効にすること自体は止められない。管理者は信頼する構成要素で、エージェントや実装者に管理者権限を渡さない
- ruleset の変更は所有者の承認を要する設定変更として扱い、変更の記録 (organization の audit log など) を所有者が確かめる
- エージェントに渡す token は、対象リポジトリへの書き込みまでで、管理 (Administration) の権限を持たない ([local-permissions.md](../guides/local-permissions.md) の手順2)
- GitHub (Actions・ruleset・check run の API) を信頼する。GitHub の不具合や侵害は主張の外にある

## 確かめた範囲

`bash tests/assurance/release-gate-test.sh` (CI の `contract-tests` で ubuntu と macOS の両方) が次を確かめる。どれも fixture と静的な検査で、実際の GitHub では動かしていない。

1. `gate.py` の判定: 架空の check run と報告の27通り (上の表の各状況、同じ名前の偽の成功が本物の失敗と並ぶ場合、再実行で成功・失敗が入れ替わる場合、成功の後の再実行が待機中の場合) で、判定・終了コード・理由のコードが期待と一致する。読めない入力が `invalid-input` で失敗になる
2. workflow の静的な検査: 標準ライブラリだけの小さな YAML の解析 (例が使う構文だけを読み、それ以外は失敗にする) で、トリガー・権限・SHA の固定・`persist-credentials`・secrets の参照・script injection・`paths` の絞り込み・`gate` の `if: always()` を確かめる
3. 静的な検査の識別力: 特権トリガー・書き込みの権限・タグでの参照・token の保持・secrets・PR のタイトルの展開・`paths`・広い既定の権限、の8つの改変をそれぞれ検出する
4. ruleset・workflow・policy の対応: ruleset の項目名が REST API の body の形に合うこと (使うルールの範囲だけ)、bypass が空であること、必須の check の名前が workflow の job 名と一致し、すべて app id 15368 に固定されていること、プレースホルダが残っていること
5. `actionlint` があれば実行する (CI の runner と手元には入っていないので、通常は飛ばす。無くても上の検査は成り立つ)

## 所有者の承認後に実測する

次は実際の GitHub でしか確かめられず、新しいリポジトリの作成や設定の変更を伴うので、**この issue では行っていない (未確認)**。所有者が承認した検証用のリポジトリ (架空のデータだけを置く) で行い、結果を [contract.md の記録項目](contract.md#主張の記録項目) の証拠に書く。

| 実測すること | 確かめ方 |
|---|---|
| ruleset が受け付けられ、ルールが効く | `gh api -X POST repos/<owner>/<repo>/rulesets --input ruleset.json` (値を置き換えたもの) が成功し、`GET` で同じ内容が返る |
| skipped・失敗・未実行の必須 check でマージできない | `verify` を飛ばす・落とす・動かさない PR を作り、マージボタンと `gh pr merge` が拒否されることを見る |
| 同じ job 名の偽の workflow を足しても通らない | 常に成功する `aidd-verify` を持つ workflow を足した PR で、`gate` が `other-run` で落ち、`.github/**` の承認が要求されることを見る |
| PR から基準を変えても試験に使われない | 基準を緩めた PR で、試験が base の基準で動き、基準のパスに所有者の承認が要求されることを見る |
| 承認の後の push で承認が外れる | 承認の後にコミットを足し、再承認なしでマージできないことを見る |
| bypass が無い | 管理者のアカウントでもマージボタンに bypass の選択肢が出ないことを見る (管理者が ruleset を無効にできることは前提として残る) |
| merge queue で base の更新後に検証される | 2つの PR を queue に入れ、`merge_group` で `aidd-verify`・`aidd-release-gate` が動き、片方の失敗で他方がマージされないことを見る |
| `same_run` の判定が再実行で崩れない | 失敗した `verify` を再実行したとき、新しい check run が同じ check suite に入り、`gate` が最新の結果で判定することを見る (GitHub の挙動として未確認) |
| required workflow から policy リポジトリを読める | `POLICY_REPO` が private のとき、対象リポジトリの `github.token` で checkout できるか (policy リポジトリの Actions のアクセス設定) を見る |

## 限界

- **実行時の改ざんは防がない。** 受け入れ試験は実装と同じプロセスで動くので、悪意のある実装は試験の関数や報告を実行時に書き換えられる。この構成が防ぐのは「PR がファイルとして基準・workflow・判定を書き換えること」で、実行時の攻撃には実行環境の隔離 (#151) とレビューが要る
- **報告は署名されていない。** 検証の報告は、PR のコードを動かした job が書く。改ざんを検出できる形で配布物と結び付けるのは #157 (`AC-PROC-002`) の範囲である
- `gate.py` が数えるのは `gate-policy.json` に書いた check だけ。他の workflow の check は ruleset の `required_status_checks` に直接足す (`gate` の時点で終わっていないと `not-completed` で落ちるため)
- GitHub の ruleset・required workflow・merge queue の挙動は、公開の文書と REST API の body の形に合わせて書いたもので、実測していない ([所有者の承認後に実測する](#所有者の承認後に実測する))
