# コンテナと ubuntu-24.04 で Codex の read-only サンドボックスが起動するかの実測 (#193)

autonomous-review は異種レビューを `codex exec --sandbox read-only --skip-git-repo-check -C <snapshot> -o <file> < /dev/null` で行う (`skills/autonomous-review/SKILL.md` のレビュー・ループ 2)。この呼び出しが、Docker の既定の seccomp・非 root のコンテナと GitHub Actions の ubuntu-24.04 ランナーで成り立つかを測った。モデルの認証は使っていない。サンドボックスは `codex sandbox -P :read-only` で直接動かし、`codex exec` の振る舞いは、コンテナ内の `127.0.0.1` に置いた Responses API の代役 (下の「モデルの代役」) に向けて確かめた。実モデルの費用は $0。

## 条件

| 項目 | 値 |
|---|---|
| 日時 | 2026-11-28 |
| Codex | `@openai/codex@0.163.0` (npm。Linux では同梱の `codex-linux-<arch>` と同梱の bwrap を使う。PATH に bwrap は無い) |
| 環境1 | arm64 macOS + OrbStack (Docker 29.8.2、カーネル `7.2.12-orbstack`、aarch64)。イメージ `node:22-bookworm-slim` に codex を入れ、`USER node` (uid 1000)。`--network none`。AppArmor なし |
| 環境2 | GitHub Actions `ubuntu-24.04` (イメージ 20261122.23.1、Ubuntu 24.04.5、カーネル `7.0.0-1018-aws`、x86_64、Docker 28.0.4)。ランナー上で直接 (uid 1001 `runner`) と、環境1と同じイメージのコンテナ。workflow の権限は `contents: read` だけ、secrets は使っていない。一時ブランチ `tmp/codex-sandbox-probe` (push で起動、run 46121598786・46121742837・46121852124) は結果を取ったあと remote・local とも削除した |
| AppArmor (環境2) | `kernel.apparmor_restrict_unprivileged_userns=1`、`unprivileged_userns_clone=1`。`/etc/apparmor.d` に bwrap 用のプロファイルは無い |
| CODEX_HOME | 実行ごとに空の一時ディレクトリ。資格情報は無い |

### プローブ

`codex sandbox -P <profile> -C <dir> -- <cmd>` は、0.163.0 で権限プロファイルの指定 (`-P`) が必須になっている (無いと exit 2 `required arguments were not provided: --permission-profile`)。組み込みのプロファイル名は `:read-only`・`:workspace`・`:danger-full-access`。`$HOME` 下の一時ディレクトリ (スナップショットの代わり、`a.txt` に `hello`) で、次の4つを実行した。

1. `cat a.txt` (cwd の中の読み取り)
2. `sh -c 'echo x > b.txt'` (cwd の中への書き込み)
3. `sh -c 'echo y > /tmp/outside.txt'` (cwd の外への書き込み)
4. `sh -c 'cat /etc/hostname'` (cwd の外の読み取り)

### モデルの代役

`CODEX_HOME/config.toml` に `model_provider = "mock"` (`base_url = "http://127.0.0.1:8099/v1"`、`wire_api = "responses"`) を書き、コンテナ内で動く数十行の node のサーバーに向けた。1回目の応答で `exec_command` に `cat a.txt` を実行させ、2回目の応答ではツールの結果を記録したうえで、中身に関係なく `{"verdict":"approved","findings":[]}` を返す。外部への通信も資格情報も使わない。実モデルがツールの失敗をどう扱うかは測っていない (未確認)。

## 結果: `codex sandbox -P :read-only`

| 環境 | コンテナ設定 | 1 読み取り | 2・3 書き込み | 4 cwd の外の読み取り | 失敗のメッセージ |
|---|---|---|---|---|---|
| macOS ホスト (Seatbelt、参考) | なし | 通る (exit 0) | 2 は拒否 (`Operation not permitted`、exit 1)。3 は未測定 | 未測定 | |
| 環境1 | 既定の seccomp、非 root | 失敗 (exit 1) | 失敗 (exit 1、ファイルは作られない) | 失敗 | `bwrap: No permissions to create a new namespace, likely because the kernel does not allow non-privileged user namespaces.` |
| 環境1 | 既定の seccomp、root (`--user 0`) | 失敗 (exit 1) | 失敗 | 失敗 | 同上 |
| 環境1 | `seccomp=unconfined`、非 root | 通る | 拒否 (`Read-only file system`、exit 2) | 通る | |
| 環境1 | 既定の seccomp に名前空間の syscall を足したもの (下)、`no-new-privileges`、非 root | 通る | 拒否 (`Read-only file system`) | 通る | |
| 環境2 ホスト | (ランナーそのもの) | 失敗 (exit 1) | 失敗 | 失敗 | `bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted` |
| 環境2 ホスト | ディストリの `bubblewrap` 0.9.0 を PATH に入れる | 失敗 | 失敗 | 失敗 | 同上 |
| 環境2 ホスト | `sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0` | 通る | 拒否 (`Read-only file system`) | 通る | |
| 環境2 コンテナ | 既定の seccomp、非 root | 失敗 | 失敗 | 失敗 | `bwrap: No permissions to create a new namespace, ...` |
| 環境2 コンテナ | 名前空間の syscall を足した seccomp、`no-new-privileges` | 失敗 | 失敗 | 失敗 | `bwrap: Failed to make / slave: Permission denied` (Docker の `docker-default` AppArmor プロファイルが mount を拒否) |
| 環境2 コンテナ | 上に加えて `apparmor=unconfined` | 失敗 | 失敗 | 失敗 | `bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted` (ホストの userns 制限) |

「名前空間の syscall を足した seccomp」は、moby v28.0.4 の `profiles/seccomp/default.json` に、`clone`・`mount`・`pivot_root`・`setns`・`umount2`・`unshare` を条件なしで許す規則を1つ足したもの。既定の profile ではこれらは `CAP_SYS_ADMIN` を持つ場合だけ許され (`clone` は名前空間のフラグを引数で拒否)、非 root にも root にも効く。

読み取れること:

- **Docker の既定の seccomp では、root でも非 root でも起動しない**。原因は seccomp (unconfined にすると起動する)。
- **ubuntu-24.04 では、コンテナでなくても起動しない**。原因は AppArmor の非特権 userns 制限 (sysctl を0にすると起動する)。ディストリの bwrap を PATH に置いても変わらない (bwrap 用の AppArmor プロファイルが無い)。openai/codex#15057 の報告と同じ。
- **OrbStack (AppArmor なし) では、seccomp に名前空間の syscall を足すだけで、`no-new-privileges` のまま起動し、read-only が効く**。ubuntu-24.04 の Docker では、それに加えて AppArmor (コンテナのプロファイルとホストの userns 制限の両方) を緩めないと起動しない。
- 起動した場合、cwd の外の読み取りは止まらない (`/etc/hostname` を読めた)。SKILL.md が `residual_risks` に書かせている「read-only サンドボックスは cwd の外の絶対パスの読み取りまでは防がない」と一致する。

## 結果: `codex exec` (モデルの代役)

| 環境 | コンテナ設定 | `codex exec` の終了コード | `-o` のファイル | ツール (`cat a.txt`) の結果 |
|---|---|---|---|---|
| 環境1 | 既定の seccomp、非 root | 0 | `{"verdict":"approved","findings":[]}` | `Process exited with code 1` / `bwrap: No permissions to create a new namespace, ...` |
| 環境1 | `seccomp=unconfined`、非 root (対照) | 0 | `{"verdict":"approved","findings":[]}` | `Process exited with code 0` / `hello` |
| 環境2 ホスト | (ランナーそのもの) | 0 | `{"verdict":"approved","findings":[]}` | `Process exited with code 1` / `bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted` |
| 環境2 コンテナ | 既定の seccomp、非 root | 0 | `{"verdict":"approved","findings":[]}` | `Process exited with code 1` / `bwrap: No permissions to create a new namespace, ...` |

- サンドボックスが起動しない場合でも、`codex exec` は終了せず、bwrap の失敗をツールの結果としてモデルに返し、モデルの最終応答で **exit 0** で終わる。起動しない場合と起動する場合 (対照) で、終了コードも `-o` のファイルも同じになった。
- stderr には `exec` の行に ` exited 1 in 0ms:` と bwrap のメッセージが出る (`--json` を付けない既定の表示)。`warning: Codex could not find bubblewrap on PATH. ... Codex will use the bundled bubblewrap in the meantime.` は起動する場合にも出る。
- **SKILL.md の現在の判定では、これを見分けられない**。起動失敗の検出は「`-o` のファイルが 3 のJSON契約どおりにパースできた場合だけを成功とする」(レビュー・ループ 2「起動失敗の検出」)。ファイルが無い・空の場合 (「exit 0 と空出力」) は失敗にできるが、サンドボックスの外の原因でツールがすべて失敗し、モデルがそれでも契約どおりの JSON を返した場合は成功に数える。実モデルが同じ状況で `approved` を返すかは測っていない (未確認) が、モデルの振る舞いに頼らない判定にする必要がある。変更案は ADR 0003 の「影響」に書いた。

## 再現

プローブ (`probe.sh`・`probe-exec.sh`・`mock-responses.js`・`Dockerfile`・seccomp の差分を作る `make-userns-seccomp.py`・workflow) はリポジトリに残していない (一時ブランチとともに削除した)。手順は上の「プローブ」「モデルの代役」のとおりで、主な呼び出しは次のとおり。

```bash
docker run --rm --network none [--security-opt no-new-privileges] [--security-opt seccomp=<profile>] \
  [--security-opt apparmor=unconfined] codex-sandbox-probe:0.163.0 bash /probe.sh
# probe.sh の中:
CODEX_HOME="$(mktemp -d)" codex sandbox -P :read-only -C "$SNAP" -- cat a.txt < /dev/null
# probe-exec.sh の中 (CODEX_HOME/config.toml でモデルの代役に向ける):
codex exec --sandbox read-only --skip-git-repo-check -C "$SNAP" -o "$OUT" '<prompt>' < /dev/null
```
