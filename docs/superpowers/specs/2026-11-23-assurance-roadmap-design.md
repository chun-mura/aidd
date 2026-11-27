# aiddの保証条件と外部保護基盤の導入ロードマップ

調査日: 2026-11-23。起票時main: a98d6a0fa105fbef4544a9effeecae6c3af58bf5。これは実装設計の承認ではなくIssue分割案。

## 目的と境界

無条件の完全安全を宣言せず、条件付きの主張・証拠・責任・失効を扱う。通常利用を維持し、強い保証の参照構成は明示選択。aiddは手順/接続/報告を担い、隔離と権限制御は既存基盤、公開強制はCI/サービス、業務上の妥当性は導入先が持つ。

同種モデル独立レビューの条件と#129の入力・文脈分離方針は維持。OS隔離を通常evalへ一律追加しない。一般hookのfail-openや#122の非ブロック警告を一律変更しない。独自runtime/prover/secret brokerは作らない。

## 調査結果と選択肢

指示とAIレビューの増加だけでは、権限境界・仕様正当性・公開物の同一性を保証できない。Dockerは環境管理、VMはOS境界、外部CIは独立検証を担うが、共有設定・秘密・通信経路が前提を崩す。形式検証は明示した性質と前提に限定される。

全環境対応の新runtimeは保守範囲が大きいため採らず、既存基盤1構成の参照例から始める。VM/VM内Docker/管理sandboxの最終選択はS02で実測と所有者確認の後に行う。OS/CPU/ハーネス/費用/ホスト共有の選択を先取りしない。有償契約・実環境変更・本番公開は今回の起票の範囲外。

## 分割方針

各Issueは独立マージ可能な文書/参照設定/試験を縦切りで含む。主要変更は概ね5ファイル以内（ディレクトリ記載は配置案、実際の数を実装前に確認）。規模超過は追加分割する。README/CHANGELOG/manifest/生成物の必要な更新は各PRに含む。親Issueは指定されていないため無し。

### S01 安全性・正しさの保証条件と責任分担を定義する

範囲: 保証対象・前提・対象外・信頼する構成要素・責任者・失効条件を定義する。通常利用は維持し、強い保証を求める明示選択の構成を別扱いにする。『完全安全』『全入力で正しい』とは宣言しない。

配置案: `docs/assurance/contract.md`、`templates/assurance-claims.md.template`、`README.md`

完了条件:
- 手順遵守・権限制限・仕様適合を別の主張IDとして管理し、前提/対象版/証拠/限界/責任者を持つ
- 未検証・不適合・適合・対象外と期限付き例外を区別し、重大な禁止事項を例外で黙って緩めない
- aidd、実行基盤、CI、導入先の業務責任者の責務を割り当てる
- 採用条件は所有者の承認を要し、サンプル記入を一般的な保証宣言として扱わない

先行マージ: 独立

根拠: [NIST SP 800-160: 保証・設計原則](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-160v1r1.pdf)、[NIST SSDF](https://csrc.nist.gov/pubs/sp/800/218/final)。[seL4: 証明の前提と限界](https://sel4.systems/Verification/assumptions.html)

### S02 隔離実行基盤の候補を比較し、最初の対応構成を決める

範囲: VM/VM内Docker/管理された既存sandboxを比較し、1つのOS・CPU構成・ハーネスに絞った非本番PoCと判断記録を作る。新規の汎用runtimeは作らない。採用先・ホスティング・有償契約・予算はユーザー確認事項とし、このIssueの起票は導入許可ではない。 既存aidd-autopilotの隔離/egress/資格/運用を最初に棚卸しし、再利用・不足と変更所有repoを明確にする。隣接repoの実装変更はこのaidd Issueへ抱えず、必要なら選定結果から所有repoへ別途起票する。

配置案: `docs/assurance/runtime-selection.md`、`docs/assurance/runtime-spike.md`、`docs/adr/（承認後に採番）`

完了条件:
- ホスト共有、管理API、通信、秘密、資源上限、更新、廃棄、互換性、費用と運用担当を同じ観点で比較する
- 架空データのみのPoCで許可/拒否操作を実測し、普通のDocker・rootless・VM・Docker Desktopの違いを記録する
- OS/CPU/ハーネス/認証方式と対応版を所有者が選び、未選択なら後続の実装は停止する
- 後続の各参照構成を5主要ファイル程度に収められるか見積もり、超える場合は実装前に追加分割する

先行マージ: S01

根拠: [Docker Engine security](https://docs.docker.com/engine/security/)、[Docker DesktopのVMと共有](https://docs.docker.com/faqs/platform/)。[Docker rootless](https://docs.docker.com/engine/security/rootless/)。[gVisor Security Model](https://gvisor.dev/docs/architecture_guide/security/)

### S03 採用基盤で作業ごとの隔離環境を作成・破棄する参照構成を用意する

範囲: S02で選んだ既存基盤1種類の設定と利用例だけを用意する。ソースの固定コピーを渡し、セッション別の作業領域・キャッシュ・一時状態・資源上限・終了後廃棄を実装する。ホストhome/鍵/daemon socket/管理APIを共有しない。

配置案: `examples/assurance/runtime/（採用基盤の設定）`、`examples/assurance/runtime/README.md`、`tests/assurance/runtime-lifecycle-test.*`

完了条件:
- 正常終了・異常終了・タイムアウト後に実行を停止し、環境を廃棄できる
- 並行する2実行が作業領域とキャッシュを変更できず、前実行の状態を継承しない
- CPU/メモリ/ディスク/時間上限と実効設定を記録し、管理側の制御をエージェントが変更できない
- 成果物をホストへ渡す前にパス逸脱/リンク/自動実行ファイルを扱う境界を定め、ホストで生成コードを自動実行しない
- 成果物の取り込み・展開・解析を隔離された領域で行い、総量/展開後容量/ファイル数/処理時間を制限する。上限超過・不正形式・解析不能ではホストへの取り込みを拒否する

先行マージ: S02

根拠: [Docker Engine security](https://docs.docker.com/engine/security/)、[Docker DesktopのVMと共有](https://docs.docker.com/faqs/platform/)。[SLSA Build requirements](https://slsa.dev/spec/v1.2/build-requirements)

### S04 隔離環境の通信を外側で制限し、経路ごとの拒否を検証する

範囲: 採用基盤の外側で既定拒否の通信制御を行う。モデル接続・依存取得・ツール通信を分類し、必要な宛先とデータだけを許可する。shell以外のMCP/ブラウザ/connectorを含め、外側で制御できない経路は無効化または保証対象外とする。

配置案: `examples/assurance/network/（外側の通信設定）`、`examples/assurance/network/README.md`、`tests/assurance/network-boundary-test.*`

完了条件:
- 直接IP/IPv6/DNS/redirect/ローカル・私設網/クラウドmetadata/代理経路の禁止ケースを無害な試験先で拒否する
- 依存取得は承認した段階と経路に限定し、エージェント段階に広い通信を残さない
- モデルAPIへ送るコード等も外部送信として扱い、データ分類・利用承認を記録する
- 許可ドメインへの漏えいはドメイン制限だけでは防げないと明記し、許可先/操作/データの残存リスクを保証条件へ戻す

先行マージ: S03

根拠: [gVisor Security Model](https://gvisor.dev/docs/architecture_guide/security/)。[NIST SP 800-160: 保証・設計原則](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-160v1r1.pdf)、[NIST SSDF](https://csrc.nist.gov/pubs/sp/800/218/final)

### S05 開発用資格情報と公開権限を分離する参照構成を用意する

範囲: 実装時は無資格情報を基本に、必要時だけ対象repo/操作/期限を限定した権限を付与する。公開・本番DB・署名・保護ルール変更はエージェントから分離する。既存IAM/secret機構を利用し、新規secret brokerを作らない。

配置案: `docs/assurance/credentials.md`、`examples/assurance/credentials/（採用サービスの最小設定）`、`tests/assurance/credentials-boundary-test.*`

完了条件:
- ホスト保存認証/SSH agent/cloud metadata/環境変数/ログ経由の意図しない継承を架空の秘密で試験する
- 開発権限でrelease/merge/本番変更/管理設定変更が拒否され、正規の開発操作は通る
- 期限切れ・失効・付与失敗では必要な操作を停止し、広い権限へフォールバックしない
- 依存インストールやbuild scriptへ秘密を渡す経路、モデル認証の必要権限と残る限界を説明する

先行マージ: S02

根拠: [NIST SP 800-160: 保証・設計原則](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-160v1r1.pdf)、[NIST SSDF](https://csrc.nist.gov/pubs/sp/800/218/final)。[Docker Engine security](https://docs.docker.com/engine/security/)、[Docker DesktopのVMと共有](https://docs.docker.com/faqs/platform/)

### S06 原要件から独立した受け入れ基準と重要性質の検証例を用意する

範囲: reqd/stddを再実装せず、原要件と業務責任者の確認に基づく受け入れ基準の保護・実行例を提供する。#124は対応の報告、本Issueは実装と独立した正解基準の成立を扱う。Web/APIには適用ASVS項目を選ぶ。

配置案: `docs/assurance/acceptance.md`、`examples/assurance/acceptance/（架空アプリの基準と試験）`、`tests/assurance/acceptance-test.*`

完了条件:
- 認可越境・二重実行・正常業務例を架空アプリで定義し、誤実装と正実装を識別する
- 実装から期待値を転記せず、原要件/期待値/対象外/所有者の判断を追える
- 性質ベース/境界/障害試験の適用理由を示し、試験合格と全入力の証明を区別する
- 受け入れ基準変更の承認者を実装者から分離する導入手順を示し、業務妥当性をAIだけで確定しない

先行マージ: S01

根拠: [OWASP ASVS 5.0 検証方針](https://github.com/OWASP/ASVS/blob/v5.0.0/5.0/en/0x04-Assessment_and_Certification.md)。[NIST SP 800-160: 保証・設計原則](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-160v1r1.pdf)、[NIST SSDF](https://csrc.nist.gov/pubs/sp/800/218/final)

### S07 必須検証の未実行・改変・迂回を防ぐ公開ゲートの参照構成を用意する

範囲: 導入先用の明示選択のGitHub/CI参照設定を用意する。信頼する設定と受け入れ基準を変更対象PRのコードから分離し、必須検査の実実行・対象SHA・結果を集約する。aidd自身や利用先GitHub設定はこのIssueの実装だけで変更しない。#122の非ブロック警告は維持する。

配置案: `examples/assurance/github/verification-gate.yml`、`examples/assurance/github/ruleset.json`、`docs/assurance/release-gate.md`、`tests/assurance/release-gate-test.*`

完了条件:
- 失敗/未実行/skipped/neutral/timeout/cancel/証跡なし/古いSHAを必須検査の成功として扱わない
- PRからworkflowや基準を書き換えて合格条件を消す攻撃を、保護された検証元と設定変更承認で防ぐ
- 期待するcheck提供元・管理者を含むbypass制限・最新変更承認・base更新/merge queueの設定と実測を示す
- 信頼しないPRコードを特権イベントで実行せず、workflow権限を最小化する
- 管理者権限の契約上の前提を明記し、実repoでの適用は所有者の承認後とする

先行マージ: S01、S06

根拠: [GitHub protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)。[GitHub status checks: skippedの扱い](https://docs.github.com/en/pull-requests/reference/status-checks)。[NIST SP 800-160: 保証・設計原則](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-160v1r1.pdf)、[NIST SSDF](https://csrc.nist.gov/pubs/sp/800/218/final)

### S08 検証証跡と配布物を改ざん検出可能な形で結び付ける

範囲: 既存attestation/provenance機構を用い、要件版・source SHA・実際の検証・成果物digest・実行基盤・承認を結ぶ。#122のローカル証跡と異なり、信頼するCIが観測/生成して配布側で検証する。独自署名方式やログ基盤は作らない。

配置案: `docs/assurance/evidence.md`、`examples/assurance/github/provenance.yml`、`examples/assurance/evidence/（検証ポリシー）`、`tests/assurance/evidence-test.*`

完了条件:
- 検証対象digestと配布digestが一致しない、署名元/環境/入力が違う、古い証拠の再利用なら配布を拒否する
- エージェントとPRのbuild stepが証跡の署名権限や検証条件を変更できない
- 必要な証拠をartifactに関連付け、秘密/プロンプト本文は保存せず保持期間・アクセス権を定める
- SLSA準拠レベルは基盤の要件を実測して示し、署名があるだけでL3や機能正当性を宣言しない

先行マージ: S07

根拠: [SLSA Build requirements](https://slsa.dev/spec/v1.2/build-requirements)。[GitHub protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)

### S09 重要な状態遷移の形式検証を小さな例で試し、適用条件を定める

範囲: 小さな架空の承認/公開状態機械の1性質で、既存のモデル検査または証明ツールを選択して試す。一般アプリ全体の証明や新規proverは対象外。導入先の重要性質へ適用する判断基準を作る。

配置案: `docs/assurance/formal-methods.md`、`examples/assurance/formal/（モデル・反例・実行設定）`、`tests/assurance/formal-test.*`

完了条件:
- 前提・不変条件・状態範囲・並行/障害モデル・ツール版を明示し、欠陥版で反例を得る
- 正しいモデルで対象性質を確認し、有限範囲の探索と無制限の数学的証明を混同しない
- モデルと実装の対応を検査する例と未証明部分を示し、モデル検査だけで実装全体の正しさを宣言しない
- 実装/設定/前提が変わったときに再検証する条件を定める

先行マージ: S01、S06

根拠: [seL4: 証明の前提と限界](https://sel4.systems/Verification/assumptions.html)。[NIST SP 800-160: 保証・設計原則](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-160v1r1.pdf)、[NIST SSDF](https://csrc.nist.gov/pubs/sp/800/218/final)

### S10 隔離境界と公開ゲートを攻撃・故障ケースで結合検証する

範囲: 既存基盤の実境界に対し、架空データと使い捨て環境でプロンプト注入・並行実行・状態破損・強制終了・証拠改変を試す。#129/#133のモデル品質評価を置き換えず、禁止操作が実行されなかった外側の証拠を集める。

配置案: `tests/assurance/boundary-cases/（固定fixture）`、`tests/assurance/boundary-suite.*`、`docs/assurance/boundary-results.md`

完了条件:
- README/ツール出力に悪意ある指示を置いても禁止操作を拒否し、正常な操作を許可する対照例を持つ
- symlink/path逸脱/共有cache汚染/秘密持出し/管理API/ゲート迂回/成果物差替え/中断を無害に試験する
- モデルが攻撃操作を試さなかった場合を境界防御成功とせず、直接の決定的probeとAI経路を区別する
- 実ハーネス/基盤の版と範囲を固定し、未実行は未確認として適合判定を出さない
- 小容量で安全に打ち切れる圧縮爆弾・大量ファイル・不正形式のfixtureで、取り込み側の上限と拒否を確認する

先行マージ: S03、S04、S05、S07、S08

根拠: [gVisor Security Model](https://gvisor.dev/docs/architecture_guide/security/)。[NIST SP 800-160: 保証・設計原則](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-160v1r1.pdf)、[NIST SSDF](https://csrc.nist.gov/pubs/sp/800/218/final)。[SLSA Build requirements](https://slsa.dev/spec/v1.2/build-requirements)

### S11 保証条件の失効・更新・緊急停止と復旧の運用手順を用意する

範囲: 採用基盤の更新・脆弱性対応、証拠の有効期間、保証失効と再検証、緊急停止/資格失効/成果物回収・rollbackを定める。自動更新サービス・新規監視基盤は作らない。開発環境破棄と利用先のDB復元を混同しない。

配置案: `docs/assurance/operations.md`、`examples/assurance/operations/（演習設定）`、`tests/assurance/recovery-test.*`

完了条件:
- OS/runtime/harness/model/policy/依存/受け入れ条件の変更ごとに再検証の範囲と責任者を定める
- 使い捨て環境で進行中の実行停止と資格失効を演習し、無効な証拠で公開が再開しない
- rollback先digestの検証と、利用先が別途担うデータ復旧・復元試験・復旧目標を記録する
- 監査記録の秘密除外/閲覧権/保持期間/削除と例外の期限を定める

先行マージ: S03、S05、S08

根拠: [NIST SP 800-160: 保証・設計原則](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-160v1r1.pdf)、[NIST SSDF](https://csrc.nist.gov/pubs/sp/800/218/final)。[SLSA Build requirements](https://slsa.dev/spec/v1.2/build-requirements)

### S12 対応構成の適合判定と導入から公開までの受け入れ実証を整える

範囲: #123のdoctor結果を利用し、明示選択の保証構成の適合/不適合/未確認/対象外を報告する。#124の要件対応とS01の主張IDを引用して証拠をまとめる。導入先を模した使い捨てrepoで公開ゲートまで通す。通常doctorを一律ブロック化せず、本番公開や実repo設定変更は行わない。

配置案: `skills/doctor/SKILL.md`、`docs/assurance/adoption.md`、`examples/assurance/qualification-report.md`、`tests/assurance/qualification-test.*`、`tests/command-contract-test.sh`

完了条件:
- 正常系は同じdigestの成果物と検証済み証跡を得て、必須項目不足・期限切れ・禁止構成なら適合を出さない
- 評価者を開発実行と分離し、fixtureだけの成功を実VM/実CIの成功として報告しない
- モデル・OS・基盤・ハーネス・policyの対応版と主張ごとの限界、利用先の承認責任を明記する
- 形式検証のサンプル成功を利用先の業務ロジック証明へ転用しない
- 有料環境/管理権限が必要な実証は承認を得て実施し、できなければ未確認のまま残す

先行マージ: S10、S11、S09、#123、#124

根拠: [NIST SP 800-160: 保証・設計原則](https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-160v1r1.pdf)、[NIST SSDF](https://csrc.nist.gov/pubs/sp/800/218/final)。[OWASP ASVS 5.0 検証方針](https://github.com/OWASP/ASVS/blob/v5.0.0/5.0/en/0x04-Assessment_and_Certification.md)。[GitHub protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)

## 既存作業との境界と進行規律

#117-#134を再起票しない。特に#122はローカル証跡の警告、#123はhook診断、#124は要件対応の報告、#129はモデル評価入力の分離、#133は公開前停止のモデル評価。本計画は管理された外部境界と公開経路の参照構成を扱う。#97/#84/#115の既存sandbox方針も維持する。

既存実装セッションへメッセージ送信や割込みを行わない。実装時は最新mainと各PRの変更を確認し、共通ファイルを触るIssueを直列化する。ADR番号・バージョンは調整し、実環境適用は所有者の承認を得る。必須依存だけblocked byとし、単なる編集競合は依存にしない。

## 起票結果と読み直し

12件作成済み。全件のタイトル・本文・ラベル・親なしを読み直して一致。2026-11-24にユーザーの続行承認を受け、残り17組を登録。全12件の依存23組をAPIで読み直し、計画と過不足なく一致。未登録の依存なし。

| 単位 | Issue | 親 | blocked by（実測） | 未登録の依存 | 照合 |
|---|---|---|---|---|---|
| S01 | [#149](https://github.com/chun-mura/aidd/issues/149) | なし | なし | なし | 一致 |
| S02 | [#150](https://github.com/chun-mura/aidd/issues/150) | なし | #149 | なし | 一致 |
| S03 | [#151](https://github.com/chun-mura/aidd/issues/151) | なし | #150 | なし | 一致 |
| S04 | [#153](https://github.com/chun-mura/aidd/issues/153) | なし | #151 | なし | 一致 |
| S05 | [#154](https://github.com/chun-mura/aidd/issues/154) | なし | #150 | なし | 一致 |
| S06 | [#155](https://github.com/chun-mura/aidd/issues/155) | なし | #149 | なし | 一致 |
| S07 | [#156](https://github.com/chun-mura/aidd/issues/156) | なし | #149、#155 | なし | 一致 |
| S08 | [#157](https://github.com/chun-mura/aidd/issues/157) | なし | #156 | なし | 一致 |
| S09 | [#158](https://github.com/chun-mura/aidd/issues/158) | なし | #149、#155 | なし | 一致 |
| S10 | [#159](https://github.com/chun-mura/aidd/issues/159) | なし | #151、#153、#154、#156、#157 | なし | 一致 |
| S11 | [#160](https://github.com/chun-mura/aidd/issues/160) | なし | #151、#154、#157 | なし | 一致 |
| S12 | [#161](https://github.com/chun-mura/aidd/issues/161) | なし | #123、#124、#158、#159、#160 | なし | 一致 |

経緯: 前回は自動承認レビュー拒否により登録を停止。2026-11-24の明示的な続行承認後、番号・数値IDと既存依存を再確認し、未登録17組のみ登録した。登録失敗・未確認・食い違いなし。

新規作成しなかった単位なし。重複候補は既存本文まで確認して作業境界を区別し、新規12件の範囲に既存#122/#123/#124/#129/#133を複製しない。S02は既存aidd-autopilotも棚卸しし、他repoの実装変更は別途扱う。

設計レビュー: 構造・データ/エラー・実用性とセキュリティを実施。成果物取り込みの資源枯渇midを反証確認後に修正し、差分再確認でhigh/blocking midなし。実装・実環境設定・契約・コミット/pushはしていない。

