# ADR-0003: コンテナ内で Codex の read-only サンドボックスが起動しない場合も human_required のままにする

## ステータス

proposed

## 文脈

`/aidd:autonomous-review` は異種レビューを `codex exec --sandbox read-only --skip-git-repo-check -C <snapshot> -o <file> < /dev/null` で行い、失敗・タイムアウトは `human_required` にし、同じモデルの自己レビューへ黙ってフォールバックしない (`skills/autonomous-review/SKILL.md` のレビュー・ループ 2)。非対話のホストが使い捨てのコンテナでこの skill を動かす構成 (#192、#193) では、Codex の Linux のサンドボックス (bwrap による名前空間と seccomp) が起動しないことがあり、Codex 公式はその場合コンテナを境界にして `danger-full-access` で動かすよう案内している。このままではコンテナで動くホストは `auto_merge_eligible` に届かない。

Codex 0.163.0 で実測した (`tests/eval/results/2026-11-28-codex-sandbox-container.md`)。

- Docker の既定の seccomp では、root でも非 root でも bwrap が名前空間を作れず起動しない (arm64 OrbStack、GitHub Actions ubuntu-24.04 の Docker とも)
- ubuntu-24.04 では、コンテナでなくても AppArmor の非特権 userns 制限 (`kernel.apparmor_restrict_unprivileged_userns=1`) で起動しない
- OrbStack (AppArmor なし) では、Docker の既定の seccomp に名前空間の syscall (`clone`・`mount`・`pivot_root`・`setns`・`umount2`・`unshare`) を足すだけで、`no-new-privileges`・非 root のまま起動し、cwd の中も外も書き込みは拒否された。ubuntu-24.04 の Docker では、さらにコンテナの AppArmor プロファイルとホストの userns 制限を緩めないと起動しない
- 起動しない場合でも `codex exec` は exit 0 で終わり、bwrap の失敗はツールの結果としてモデルに返るだけで、モデルが契約どおりの JSON (`approved`、指摘0件) を返せば `-o` のファイルはそれになる (モデルの代役での測定)。現在の SKILL.md の起動失敗の検出 (`-o` のファイルが JSON 契約どおりにパースできれば成功) は「exit 0 と空の出力」は失敗にできるが、この場合を成功に数える

隔離基盤は #150 でユーザーが「arm64 macOS + OrbStack 上の作業ごとの Docker コンテナ + squid サイドカー (aidd-autopilot の構成を流用)」に決めており、その参照構成は #151 で作る (`docs/assurance/runtime-*.md` と ADR 0002 は別の作業が書いている)。aidd-autopilot の現行のコンテナは `--security-opt no-new-privileges`、既定の seccomp、非 root で、`GH_TOKEN` と Anthropic の資格情報を環境変数で渡し、リポジトリ (`.git` を含む) をコンテナの中に持つ。

## 決定

aidd の既定の挙動を変えない。Codex のサンドボックスが起動しない環境では、異種レビューは成立せず `human_required` のままとする (選択肢 (a))。ホストの宣言で Codex のサンドボックスを外す選択肢 (b) は採らない。

コンテナで `auto_merge_eligible` に届かせたいホストには、aidd を変えずに、Codex の read-only サンドボックスが起動する環境を用意する方法 (選択肢 (c)) を案内する。採用基盤 (OrbStack) では、Docker の既定の seccomp に名前空間の syscall を足したプロファイルを、レビューを動かすコンテナに付ける。これはコンテナの中でカーネルの user namespace を使えるようにする緩和であり、どの syscall を足したか・何を緩めたかを #151 の参照構成の判断記録に残すのは #151 の側とする。

あわせて、サンドボックスが起動しないことを、モデルの応答ではなく決定的な事前確認で検出するよう `skills/autonomous-review/SKILL.md` を直す (下の「影響」)。この変更は #134 が同じファイルの適格条件を書き換えた後に行う。

## 検討した代替案

### (a) human_required のまま (現状)

- 概要: サンドボックスが起動しなければ異種レビューは成立しないので、`human_required` で人に渡す
- 利点: 既定の挙動 (read-only、失敗は `human_required`、同一モデルへの黙ったフォールバック禁止) を変えない。aidd が検証できない前提に依存しない
- 欠点: Docker の既定の設定と ubuntu-24.04 の標準のランナーでは、`--reviewer codex` の run は常に `human_required` になる
- 採用理由: 欠点はホストの設定 ((c)) で解消でき、aidd が安全性の前提を引き受けずに済む

### (b) ホストがコンテナを境界と宣言した明示選択のときだけ Codex のサンドボックスを外す

- 概要: ホストが「コンテナが境界である」と宣言したとき (フラグや環境変数) に限り、`codex exec --sandbox danger-full-access` で起動する。前提条件は「スナップショット以外に資格情報・`.git`・ホームが無い」こと
- 利点: Codex 公式の案内どおりで、seccomp や AppArmor を緩めずにコンテナで異種レビューが成立する
- 欠点:
  - 前提条件を同じコンテナでは満たせない。Codex 自身がモデルに接続する資格情報 (`CODEX_HOME/auth.json` か API キー) を必要とし、`danger-full-access` ではモデルが実行するシェルからそれを読める。`codex exec` はモデルの API への通信を要するので、通信も閉じられない。aidd-autopilot の構成では、同じコンテナに `GH_TOKEN`・Anthropic の資格情報・リポジトリの `.git` もある
  - 満たすには、レビューごとに、スナップショットと Codex の資格情報だけを持ち、通信をモデルの API だけに絞った別のコンテナが要る。これはホスト側の隔離の仕組みであり、aidd の中からは宣言が正しいかを検証できない (資格情報が無いことは、在るものを列挙するようには確かめられない)
  - レビュー担当はプロンプトに差分 (信頼できない入力) を受け取るので、差分に書かれた指示でシェルを動かされうる。read-only の制限が外れると、その被害の上限がコンテナの設定だけで決まる
- 不採用理由: 前提条件を aidd が検証できず、宣言を誤ったホストでは資格情報の漏えいと書き込みを許す。(c) で同じ目的 (コンテナでの異種レビュー) を、サンドボックスを外さずに達成できる
- 見直す条件: (c) が使えない基盤 (seccomp・AppArmor を緩められない、または user namespace をカーネルが提供しない) を採用し、かつホストがレビュー専用のコンテナ (スナップショットと Codex の資格情報だけ、通信はモデルの API だけ) を用意できる場合に、別の ADR で扱う

### (c) Codex の read-only サンドボックスが起動する環境をホストが用意する

- 概要: aidd は変えない。ホストが、レビューを動かすコンテナに名前空間の syscall を許す seccomp プロファイルを付ける (ubuntu の Docker では AppArmor も)、またはサンドボックスが起動する場所 (macOS のホストなど) で `codex exec` を動かす
- 利点: read-only が効いたまま異種レビューが成立する。OrbStack では `no-new-privileges`・非 root を保ったまま、seccomp に syscall を足すだけで済んだ
- 欠点: コンテナの中で user namespace を作れるようにするので、カーネルの攻撃面が広がる。ubuntu-24.04 の Docker では、さらに AppArmor の制限を外す必要がある
- 位置づけ: aidd の選択肢ではなくホストの設定。採用基盤での具体的な設定と緩和の評価は #151 が持つ

## 影響

- 既定の挙動 (read-only、失敗は `human_required`、同一モデルへの黙ったフォールバック禁止) は変わらない
- #150 の採用基盤 (OrbStack) で `--reviewer codex` を使うには、#151 の参照構成が、レビューを動かすコンテナの seccomp に名前空間の syscall を足す必要がある。足さなければ `human_required` になる (安全側)。Codex を動かすなら、その資格情報をコンテナに渡すことと、squid の許可先にモデルの API を足すことも #151・#153 の判断になる
- `skills/autonomous-review/SKILL.md` の判定には、モデルの応答に頼らない検出が要る。変更案 (#134 のマージ後に別の変更で入れる):
  - レビュー・ループ 2 の `--reviewer codex` の「起動前の確認」に、ラウンドごとの `codex exec` の前の事前確認を足す。リポジトリの外の空の一時ディレクトリに乱数を書いたファイルを置き、`codex sandbox -P :read-only -C <dir> -- cat <file> < /dev/null` が exit 0 でその乱数だけを出力すること、`codex sandbox -P :read-only -C <dir> -- sh -c ': > <dir>/w' < /dev/null` が 0 以外で終わり `<dir>/w` が作られていないことを確かめる (Bash ツールの `timeout` は 10000ms)。どちらかが通らない・オプションが無い版の codex では `codex exec` を起動せず `human_required` (`human_required_reason` は `review_incomplete`) とし、stderr を理由に記録する
  - 「起動失敗の検出」の「codex はサンドボックス内で起動に失敗しても exit 0 で空の応答を返すことがある」を、「exit 0 で終わり、ツールの失敗を受けたモデルが契約どおりの JSON を返すこともある。`-o` のファイルの形だけでは起動の成否を判断できない」に改める
  - 事前確認は、その時点でサンドボックスが起動することを示すだけで、`codex exec` の中の各コマンドの成否は示さない。この点は `residual_risks` に書く
