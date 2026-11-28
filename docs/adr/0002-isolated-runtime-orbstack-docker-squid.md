# ADR-0002: 保証ロードマップの最初の隔離実行基盤を OrbStack の VM 内 Docker + squid サイドカーにする

## ステータス

accepted (所有者の決定、2026-11-28)

## 文脈

保証ロードマップ (`docs/superpowers/specs/2026-11-23-assurance-roadmap-design.md`) の S03〜S05 (#151、#153、#154) は、エージェントを動かす隔離環境の作成・破棄、外側での通信制限、資格情報の分離を参照構成として用意する。どれも基盤に依存するため、S02 (#150) で基盤・OS・CPU・ハーネス・認証方式・対応版を所有者が選ぶまで、後続の実装は止める決まりになっている。

全環境に対応する新しい runtime は保守範囲が大きいので作らない。隣接リポジトリの aidd-autopilot は、作業ごとの Docker コンテナと squid サイドカーによる既定拒否の通信制限を、すでに macOS + OrbStack で使っている。比較と実測は `docs/assurance/runtime-selection.md` と `docs/assurance/runtime-spike.md` にある。

## 決定

所有者 (ユーザー) が 2026-11-28 に次を選んだ。

- OS / CPU: macOS、arm64
- 隔離基盤: OrbStack の Linux VM 上で、作業ごとに Docker コンテナを1つ起動し、終了後に消す
- 通信: runner を `--internal` ネットワークに置き、許可ドメインだけ通す squid サイドカー経由にする。aidd-autopilot の構成を流用する
- ハーネス: Claude Code
- 認証方式: aidd-autopilot が対応する方式を使う。モデルは `claude setup-token` の OAuth トークンまたは API キー (設定 `anthropic_auth_mode`)、GitHub は対象リポジトリだけの fine-grained PAT。値はこの ADR に書かない
- 費用: 新しい有料契約を結ばない
- 用途: 非本番の PoC。本番環境・本番データ・顧客データに使わない

対応版は実測した組み合わせに限る: macOS 26.7.3、OrbStack 2.2.5、Docker Engine 29.8.2 (linux/arm64)、squid 5.7、Claude Code 2.1.207 (aidd-autopilot の Dockerfile の固定版)。別の版で使うときは `runtime-spike.md` の手順を再実行して結果を残す。

## 検討した代替案

### 作業ごとの VM (Lima・Tart など)

- 概要: タスクごとに VM を作り、終了後に消す
- 利点: カーネルが作業ごとに分かれる。コンテナの root と VM の root が同じという問題が無い
- 欠点: 起動・更新・イメージ管理の手間が大きい。通信制限と資格情報の渡し方を新たに作る必要がある。このマシンでは測っていない
- 不採用理由: 既存の仕組みを流用できず、新しい runtime を作ることに近づく。この構成で足りないと #149 の主張で判明したときの差し替え候補として残す

### 管理された sandbox (Claude Code の OS sandbox、クラウドの sandbox サービス)

- 概要: Claude Code の Seatbelt sandbox (aidd の `docs/guides/local-permissions.md`) か、事業者の sandbox を使う
- 利点: OS sandbox は追加の基盤が要らない。クラウドは運用を事業者に任せられる
- 欠点: OS sandbox は同じ macOS ユーザーのプロセスで、廃棄の単位と資源上限が無い。クラウドは有料契約が要る
- 不採用理由: OS sandbox は通常利用の手順として残し、強い保証を求める構成には使わない。クラウドは有料契約なしの条件に合わない

### Docker Desktop

- 概要: macOS 上の VM 内 Docker。選んだ構成と同じ型
- 利点: 広く使われている
- 欠点: このマシンではデーモンに接続できず測れなかった。利用条件は確かめていない
- 不採用理由: 同じ型の OrbStack がすでに動いていて実測できた

### rootless Docker・普通の Docker (Linux ホスト)

- 概要: Linux ホスト上で dockerd を一般ユーザーまたは root で動かす
- 利点: rootless はコンテナの root がホストの一般ユーザーに対応する
- 欠点: Linux ホストが要る。このマシン (macOS) では測れない
- 不採用理由: 所有者が選んだ OS は macOS

## 影響

- S03 (#151)、S04 (#153)、S05 (#154) は、この構成を前提に実装へ進める。別の OS・基盤に広げるときは新しい ADR を書く
- 実測で見つかった不足は aidd-autopilot 側の変更として扱う (aidd の Issue に抱えない)。とくに、ビルドされたままの squid サイドカーが `/dev/stdout` を開けずに起動直後に終了すること、秘密を環境変数で渡すと `docker inspect` から平文で読めること、ネットワークとプロキシを全タスクで共有していること
- コンテナの root は VM の root と同じ uid で、userns の再割り当ては無い。コンテナから VM に抜けた場合に macOS の何が見えるかは未確認のまま残る。#149 の主張では、この構成を「macOS ホストを守る」保証の根拠にしない
- 認証方式のうち、いまの設定がどちらかは資格情報ファイルを読まない規則のため確かめていない。所有者が確認する
- OrbStack の利用条件 (費用) は確かめていない。所有者が確認する
- #149 の主張IDへの対応付けは #149 のマージ後に行う
