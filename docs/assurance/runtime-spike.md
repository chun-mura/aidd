# 隔離実行基盤の PoC 記録 (S02 / #150)

このファイルは、[runtime-selection.md](runtime-selection.md) の比較のうち「実測した」と書いた行の根拠である。架空のデータだけを使い、実際の認証情報・顧客データ・本番環境には触れていない。実モデルは動かしていない (使用額 $0)。

## 測った環境 (2026-11-28)

| 項目 | 値 |
|---|---|
| ホスト | macOS 26.7.3 (Darwin 25.6.0)、arm64 |
| VM と Docker | OrbStack 2.2.5、Docker Engine 29.8.2 (linux/arm64)、VM のカーネル 7.2.12-orbstack、cgroup v2、seccomp は既定プロファイル、userns の再割り当ては無し |
| 使ったイメージ | `alpine:latest` (`sha256:1991bd78…`、arm64)。squid は aidd-autopilot がビルドした `aidd-autopilot-proxy:latest` (`sha256:fc27b719…`、2026-08-01 ビルド)。中の `entrypoint.sh` と `generate-squid-conf.sh` は aidd-autopilot main (`cf660fd`) と同じハッシュであることを確かめた。HTTPS を試すクライアントは手元にあった `node:22` (amd64。Rosetta で動く) の `curl` |
| 作ったもの | コンテナ・ネットワーク・ボリュームは名前を `s02-poc-` で始め、最後に消した (5 で 0 件を確認)。イメージは作っていない |

手順はスクリプト1本にまとめ、`bash poc.sh > poc-output.txt` で実行した。スクリプトと出力は末尾の付録にそのまま載せた (作業ディレクトリの絶対パスだけ `<poc>` に置き換えた)。

## 結果の要約

「許可」は操作が通ったこと、「拒否」は操作が失敗したことを表す。

| # | 確かめたこと | 結果 | 出力の根拠 |
|---|---|---|---|
| 1-1 | コンテナのカーネルは macOS ではなく OrbStack の Linux VM のもの | 実測: `uname -r` が `7.2.12-orbstack…` | 付録 1 |
| 1-2 | マウントしなければホストの `/Users` と docker.sock は見えない | 拒否: どちらも `No such file or directory` | 付録 1 |
| 1-3 | ホストの環境変数は `-e` で渡さない限り入らない | 拒否: 0 件 | 付録 1 |
| 1-4 | 値を書かない `-e NAME` で渡した値は、コンテナ内と **`docker inspect` の `.Config.Env` に平文で残る** (argv には出ない) | 許可 (=秘密が Docker API から読める) | 付録 1 |
| 1-5 | コンテナの root は VM の root と同じ uid (userns 無し) | 実測: `uid_map` が `0 0 4294967295`、`id -u` が 0 | 付録 1 |
| 1-6 | Docker API を使える者はホストのパスを mount できる。`:ro` なら書けない | 許可 (読み取り)、拒否 (書き込み) | 付録 1 |
| 2-1 | 既定の bridge からは外に出られる | 許可 | 付録 2 |
| 2-2 | `--internal` のネットワークからは、名前解決・IP 直打ち (1.1.1.1)・クラウドの metadata (169.254.169.254) のどれも届かない | 拒否 (`bad address` / `Network unreachable`) | 付録 2 |
| 2-3 | OrbStack では既定の bridge から `host.docker.internal` (=ホスト) が引ける。`--internal` からは引けない | bridge: 許可、internal: 拒否 | 付録 2 |
| 2-4 | **aidd-autopilot の squid サイドカーは、ビルドされたままでは起動直後に終了する** (`FATAL: Cannot open '/dev/stdout' for writing`。squid が `proxy` ユーザーに降格した後に `/dev/stdout` を開けない) | 起動失敗 (Exited 1) | 付録 2b |
| 2-5 | 同じイメージ・同じ生成規則で access log だけファイルに変えると (PoC 用の回避)、許可した `example.com` は 443 で通り、ほかのドメイン・ホスト (`host.docker.internal`)・IP (1.1.1.1、169.254.169.254)・443 以外のポートは 403。プロキシを通さない直接の通信は名前解決で失敗する | 許可 1 件、拒否 6 件 | 付録 2c |
| 2-6 | IP 直打ちの HTTP (169.254.169.254) は、squid が逆引きを待つため 403 が返るまで約 38 秒かかる | 拒否 (遅い) | 付録 2c |
| 3-1 | `--read-only` で root ファイルシステムに書けない。`--tmpfs /tmp` は書ける | 拒否 / 許可 | 付録 3 |
| 3-2 | `--cap-drop ALL` で CapEff が 0 になり、root でも `chown` できない (既定では通る) | 拒否 | 付録 3 |
| 3-3 | `--security-opt no-new-privileges` で `NoNewPrivs: 1` (既定は 0) | 実測 | 付録 3 |
| 3-4 | `--pids-limit 32` で fork が `Resource temporarily unavailable` で止まる | 拒否 | 付録 3 |
| 3-5 | `--memory 64m --memory-swap 64m` で 200MB を確保しようとすると OOM kill (exit 137、`OOMKilled=true`) | 拒否 | 付録 3 |
| 3-6 | `--cpus 0.5` が cgroup の `cpu.max` に `50000 100000` として入る (負荷をかけた測定はしていない) | 設定値のみ実測 | 付録 3 |
| 3-7 | `--user 65534:65534` で `/etc` に書けない | 拒否 | 付録 3 |
| 4-1 | コンテナを消すと、その中で書いたファイルは次のコンテナに残らない | 状態は残らない | 付録 4 |
| 4-2 | 名前付きボリュームはコンテナを消しても残る。ボリュームを消すまで次の実行が読める | 状態が残る | 付録 4 |

## このマシンで測れなかったもの (未確認)

推測で埋めない。比較表では「未確認」と書いた。

- **普通の Docker (Linux ホストで直接動く dockerd)**: このマシンは macOS なので、VM の緩衝が無い構成を測れない。コンテナの root がホストの root と同じ uid になる点は 1-5 と同じになるはずだが、ホストのカーネルを直接共有するため影響の範囲が違う。測っていない。
- **rootless Docker**: Linux 専用。OrbStack の Docker を rootless で動かす設定があるかも確かめていない。
- **VM (Lima など、作業ごとの VM)**: `limactl` 2.1.2 は入っているがインスタンスは無い。VM イメージの取得が要るため、この PoC では作っていない。
- **Docker Desktop**: `desktop-linux` という docker context は残っているが、デーモンに接続できなかった (`Cannot connect to the Docker daemon`)。`/Applications` にもアプリは無い。測っていない。
- **管理された sandbox (クラウドのサービス)**: 有料契約・ホスティングが要るため対象外。測っていない。
- **gVisor (runsc)**: OrbStack に入っていない。測っていない。
- **IPv6・DNS rebinding・リダイレクト・許可ドメインへの持ち出し**: S04 (#153) の範囲。ここでは測っていない。
- **ディスク容量と実行時間の上限**: `--storage-opt` が OrbStack で効くか、時間上限 (aidd-autopilot はホストの watcher が `max_wall_clock_minutes` で kill) は測っていない。S03 (#151) の範囲。
- **aidd-autopilot の実際のタスク実行**: 2-4 の起動失敗が実タスクでどう見えるか (runner が通信できずに止まるか) は、実タスクを流していないので未確認。
- **OrbStack の VM が macOS の `/Users` を共有している範囲**: VM 内から macOS のファイルがどこまで見えるかは測っていない (1-6 は Docker API 経由の mount で、VM 自体の共有ではない)。

## 再実行のしかた

付録のスクリプトを任意の作業ディレクトリに `poc.sh` として置き、`bash poc.sh` を実行する。macOS の Claude Code の sandbox の中からは docker.sock に届かないため、sandbox の外で実行した。所要は約3分 (2-6 の待ちを含む)。終了時に `s02-poc-` で始まるコンテナ・ネットワーク・ボリュームを消す。

## 付録 A: スクリプト

````bash
#!/bin/bash
# S02 (#150) PoC: measure what a per-task container on OrbStack allows and denies.
# Fictional data only. Every object is prefixed s02-poc- and removed at the end.
set -u
W="$(cd "$(dirname "$0")" && pwd)/work"
IMG=alpine:latest
PROXY_IMG=aidd-autopilot-proxy:latest
CLIENT="--platform linux/amd64 node:22"
NET=s02-poc-internal

run() {
  printf '\n$ %s\n' "$*"
  bash -c "$*" 2>&1 | sed 's/^/  /'
  printf '  [exit %s]\n' "${PIPESTATUS[0]}"
}

cleanup() {
  docker rm -f s02-poc-proxy s02-poc-persist s02-poc-oom s02-poc-env >/dev/null 2>&1
  docker network rm "$NET" >/dev/null 2>&1
  docker volume rm s02-poc-vol >/dev/null 2>&1
}
trap cleanup EXIT
cleanup

rm -rf "$W"; mkdir -p "$W/in"
printf 'fictional input for S02 PoC\n' > "$W/in/dummy.txt"

echo "## 0. environment"
run "docker version --format '{{.Server.Version}} {{.Server.Os}}/{{.Server.Arch}}'"
run "docker info --format '{{.OperatingSystem}} kernel={{.KernelVersion}} security={{.SecurityOptions}} cgroup={{.CgroupVersion}}'"
run "uname -sr"
run "docker image inspect $IMG $PROXY_IMG node:22 --format '{{.Id}} {{.Architecture}}'"

echo "## 1. host sharing"
run "docker run --rm $IMG uname -r"
run "docker run --rm $IMG sh -c 'ls -d /Users /Users/* 2>&1; ls -l /var/run/docker.sock 2>&1'"
run "FAKE_HOST_VAR=dummy-value docker run --rm $IMG sh -c 'env | grep -c FAKE_HOST_VAR'"
run "FAKE_PASSED_VAR=fictional-value docker run --name s02-poc-env -e FAKE_PASSED_VAR $IMG sh -c 'echo in-container=\$FAKE_PASSED_VAR' && docker inspect s02-poc-env --format '{{range .Config.Env}}{{println .}}{{end}}' | grep FAKE_PASSED_VAR; docker inspect s02-poc-env --format 'Args={{.Args}}'; docker rm s02-poc-env >/dev/null"
run "docker run --rm $IMG cat /proc/self/uid_map"
run "docker run --rm $IMG id -u"
run "docker run --rm -v '$W/in:/in:ro' $IMG sh -c 'cat /in/dummy.txt; echo x > /in/new.txt'"
run "ls '$W/in'"

echo "## 2. network"
run "docker run --rm $IMG wget -q -T 5 --spider http://example.com && echo reachable"
run "docker network create --internal $NET >/dev/null && docker network inspect $NET --format 'internal={{.Internal}}'"
run "docker run --rm --network $NET $IMG wget -q -T 5 --spider http://example.com"
run "docker run --rm --network $NET $IMG wget -q -T 5 --spider http://1.1.1.1"
run "docker run --rm --network $NET $IMG wget -q -T 5 --spider http://169.254.169.254/"
run "docker run --rm --network $NET $IMG nslookup host.docker.internal"
run "docker run --rm $IMG nslookup host.docker.internal"
echo "### 2b. squid sidecar as built (unchanged image and entrypoint)"
run "docker run -d --name s02-poc-proxy --security-opt no-new-privileges -e AP_EGRESS_DOMAINS=example.com $PROXY_IMG >/dev/null; sleep 3; docker inspect s02-poc-proxy --format 'Status={{.State.Status}} ExitCode={{.State.ExitCode}}'"
run "docker run --rm --entrypoint bash -e AP_EGRESS_DOMAINS=example.com $PROXY_IMG -c '/opt/aidd-autopilot/generate-squid-conf.sh \"\$AP_EGRESS_DOMAINS\" > /etc/squid/squid.conf; squid -N -d1 -f /etc/squid/squid.conf 2>&1 | grep -A2 FATAL'"
docker rm -f s02-poc-proxy >/dev/null 2>&1
echo "### 2c. same image and generated rules, access log moved to a file (PoC-only workaround)"
run "docker run -d --name s02-poc-proxy --security-opt no-new-privileges -e AP_EGRESS_DOMAINS=example.com --entrypoint bash $PROXY_IMG -c '/opt/aidd-autopilot/generate-squid-conf.sh \"\$AP_EGRESS_DOMAINS\" | sed s#stdio:/dev/stdout#stdio:/var/log/squid/access.log# > /etc/squid/squid.conf && exec squid -N -f /etc/squid/squid.conf' >/dev/null && docker network connect $NET s02-poc-proxy && echo proxy-up"
P="http://s02-poc-proxy:3128"
C="docker run --rm --network $NET $CLIENT curl -sS -o /dev/null -w %{http_code} --max-time 10"
for i in 1 2 3 4 5 6 7 8 9 10; do
  docker run --rm --network "$NET" $CLIENT curl -s -o /dev/null --max-time 2 -x "$P" http://example.com && break
  sleep 1
done
run "$C -x $P https://example.com"
run "$C -x $P https://example.org"
run "$C -x $P http://host.docker.internal/"
run "$C -x $P https://1.1.1.1/"
run "time $C --max-time 60 -x $P http://169.254.169.254/"
run "$C -x $P https://example.com:8443/"
run "$C https://example.com"
run "docker exec s02-poc-proxy cat /var/log/squid/access.log | awk '{print \$4, \$6, \$7}'"

echo "## 3. hardening flags"
run "docker run --rm $IMG sh -c 'touch /probe && echo writable-rootfs'"
run "docker run --rm --read-only $IMG sh -c 'touch /probe'"
run "docker run --rm --read-only --tmpfs /tmp:size=16m $IMG sh -c 'touch /tmp/probe && echo tmpfs-ok'"
run "docker run --rm $IMG sh -c 'grep CapEff /proc/self/status; touch /f && chown 1234 /f && echo chown-ok'"
run "docker run --rm --cap-drop ALL $IMG sh -c 'grep CapEff /proc/self/status; touch /f && chown 1234 /f'"
run "docker run --rm $IMG grep NoNewPrivs /proc/self/status"
run "docker run --rm --security-opt no-new-privileges $IMG grep NoNewPrivs /proc/self/status"
run "docker run --rm --pids-limit 32 $IMG sh -c 'cat /sys/fs/cgroup/pids.max; for i in \$(seq 100); do sleep 3 & done; echo not-reached'"
run "docker run --name s02-poc-oom --memory 64m --memory-swap 64m $IMG sh -c 'cat /sys/fs/cgroup/memory.max; x=\$(head -c 200000000 /dev/zero | tr \"\\\\0\" a); echo survived'"
run "docker inspect s02-poc-oom --format 'OOMKilled={{.State.OOMKilled}} ExitCode={{.State.ExitCode}}'"
run "docker run --rm --cpus 0.5 $IMG cat /sys/fs/cgroup/cpu.max"
run "docker run --rm --user 65534:65534 $IMG sh -c 'id -u; touch /etc/probe'"

echo "## 4. disposal"
run "docker run --name s02-poc-persist $IMG sh -c 'echo fictional-state > /state.txt' && docker rm s02-poc-persist"
run "docker run --rm $IMG cat /state.txt"
run "docker volume create s02-poc-vol >/dev/null && docker run --rm -v s02-poc-vol:/v $IMG sh -c 'echo kept > /v/f' && docker run --rm -v s02-poc-vol:/v $IMG cat /v/f"
run "docker volume rm s02-poc-vol && docker volume ls -q | grep -c s02-poc || true"

echo "## 5. cleanup"
cleanup
trap - EXIT
run "docker ps -a --format '{{.Names}}' | grep -c s02-poc || true"
run "docker network ls --format '{{.Name}}' | grep -c s02-poc || true"
rm -rf "$W"
````

## 付録 B: 出力

付録の節番号は出力の `## N.` の見出しと対応する。

````text
## 0. environment

$ docker version --format '{{.Server.Version}} {{.Server.Os}}/{{.Server.Arch}}'
  29.8.2 linux/arm64
  [exit 0]

$ docker info --format '{{.OperatingSystem}} kernel={{.KernelVersion}} security={{.SecurityOptions}} cgroup={{.CgroupVersion}}'
  OrbStack kernel=7.2.12-orbstack-00394-gbecdd6130068 security=[name=seccomp,profile=builtin name=cgroupns] cgroup=2
  [exit 0]

$ uname -sr
  Darwin 25.6.0
  [exit 0]

$ docker image inspect alpine:latest aidd-autopilot-proxy:latest node:22 --format '{{.Id}} {{.Architecture}}'
  sha256:1991bd789d7184290c3cce84fd6af068b8b745e9bddf178661ce7f5ecf68135c arm64
  sha256:fc27b7199a7a71bc0e24af676864f37936b79ad96aab74ef3b6bc987e3021e4e arm64
  sha256:eefceac94552a7e7e9da532feb53139a8630e3934b862662ce1d7cb877772c86 amd64
  [exit 0]
## 1. host sharing

$ docker run --rm alpine:latest uname -r
  7.2.12-orbstack-00394-gbecdd6130068
  [exit 0]

$ docker run --rm alpine:latest sh -c 'ls -d /Users /Users/* 2>&1; ls -l /var/run/docker.sock 2>&1'
  ls: /Users: No such file or directory
  ls: /Users/*: No such file or directory
  ls: /var/run/docker.sock: No such file or directory
  [exit 1]

$ FAKE_HOST_VAR=dummy-value docker run --rm alpine:latest sh -c 'env | grep -c FAKE_HOST_VAR'
  0
  [exit 1]

$ FAKE_PASSED_VAR=fictional-value docker run --name s02-poc-env -e FAKE_PASSED_VAR alpine:latest sh -c 'echo in-container=$FAKE_PASSED_VAR' && docker inspect s02-poc-env --format '{{range .Config.Env}}{{println .}}{{end}}' | grep FAKE_PASSED_VAR; docker inspect s02-poc-env --format 'Args={{.Args}}'; docker rm s02-poc-env >/dev/null
  in-container=fictional-value
  FAKE_PASSED_VAR=fictional-value
  Args=[-c echo in-container=$FAKE_PASSED_VAR]
  [exit 0]

$ docker run --rm alpine:latest cat /proc/self/uid_map
           0          0 4294967295
  [exit 0]

$ docker run --rm alpine:latest id -u
  0
  [exit 0]

$ docker run --rm -v '<poc>/work/in:/in:ro' alpine:latest sh -c 'cat /in/dummy.txt; echo x > /in/new.txt'
  fictional input for S02 PoC
  sh: can't create /in/new.txt: Read-only file system
  [exit 1]

$ ls '<poc>/work/in'
  dummy.txt
  [exit 0]
## 2. network

$ docker run --rm alpine:latest wget -q -T 5 --spider http://example.com && echo reachable
  reachable
  [exit 0]

$ docker network create --internal s02-poc-internal >/dev/null && docker network inspect s02-poc-internal --format 'internal={{.Internal}}'
  internal=true
  [exit 0]

$ docker run --rm --network s02-poc-internal alpine:latest wget -q -T 5 --spider http://example.com
  wget: bad address 'example.com'
  [exit 1]

$ docker run --rm --network s02-poc-internal alpine:latest wget -q -T 5 --spider http://1.1.1.1
  wget: can't connect to remote host (1.1.1.1): Network unreachable
  [exit 1]

$ docker run --rm --network s02-poc-internal alpine:latest wget -q -T 5 --spider http://169.254.169.254/
  wget: can't connect to remote host (169.254.169.254): Network unreachable
  [exit 1]

$ docker run --rm --network s02-poc-internal alpine:latest nslookup host.docker.internal
  Server:		127.0.0.11
  Address:	127.0.0.11:53
  
  ** server can't find host.docker.internal: SERVFAIL
  
  ** server can't find host.docker.internal: SERVFAIL
  
  [exit 1]

$ docker run --rm alpine:latest nslookup host.docker.internal
  Server:		0.250.250.200
  Address:	0.250.250.200:53
  
  Non-authoritative answer:
  
  Non-authoritative answer:
  Name:	host.docker.internal
  Address: 0.250.250.254
  
  [exit 0]
### 2b. squid sidecar as built (unchanged image and entrypoint)

$ docker run -d --name s02-poc-proxy --security-opt no-new-privileges -e AP_EGRESS_DOMAINS=example.com aidd-autopilot-proxy:latest >/dev/null; sleep 3; docker inspect s02-poc-proxy --format 'Status={{.State.Status}} ExitCode={{.State.ExitCode}}'
  Status=exited ExitCode=1
  [exit 0]

$ docker run --rm --entrypoint bash -e AP_EGRESS_DOMAINS=example.com aidd-autopilot-proxy:latest -c '/opt/aidd-autopilot/generate-squid-conf.sh "$AP_EGRESS_DOMAINS" > /etc/squid/squid.conf; squid -N -d1 -f /etc/squid/squid.conf 2>&1 | grep -A2 FATAL'
  2026/11/28 07:34:48| FATAL: Cannot open '/dev/stdout' for writing.
  	The parent directory must be writeable by the
  	user 'proxy', which is the cache_effective_user
  [exit 0]
### 2c. same image and generated rules, access log moved to a file (PoC-only workaround)

$ docker run -d --name s02-poc-proxy --security-opt no-new-privileges -e AP_EGRESS_DOMAINS=example.com --entrypoint bash aidd-autopilot-proxy:latest -c '/opt/aidd-autopilot/generate-squid-conf.sh "$AP_EGRESS_DOMAINS" | sed s#stdio:/dev/stdout#stdio:/var/log/squid/access.log# > /etc/squid/squid.conf && exec squid -N -f /etc/squid/squid.conf' >/dev/null && docker network connect s02-poc-internal s02-poc-proxy && echo proxy-up
  proxy-up
  [exit 0]

$ docker run --rm --network s02-poc-internal --platform linux/amd64 node:22 curl -sS -o /dev/null -w %{http_code} --max-time 10 -x http://s02-poc-proxy:3128 https://example.com
  200  [exit 0]

$ docker run --rm --network s02-poc-internal --platform linux/amd64 node:22 curl -sS -o /dev/null -w %{http_code} --max-time 10 -x http://s02-poc-proxy:3128 https://example.org
  curl: (56) CONNECT tunnel failed, response 403
  000  [exit 56]

$ docker run --rm --network s02-poc-internal --platform linux/amd64 node:22 curl -sS -o /dev/null -w %{http_code} --max-time 10 -x http://s02-poc-proxy:3128 http://host.docker.internal/
  403  [exit 0]

$ docker run --rm --network s02-poc-internal --platform linux/amd64 node:22 curl -sS -o /dev/null -w %{http_code} --max-time 10 -x http://s02-poc-proxy:3128 https://1.1.1.1/
  curl: (56) CONNECT tunnel failed, response 403
  000  [exit 56]

$ time docker run --rm --network s02-poc-internal --platform linux/amd64 node:22 curl -sS -o /dev/null -w %{http_code} --max-time 10 --max-time 60 -x http://s02-poc-proxy:3128 http://169.254.169.254/
  403
  real	0m38.672s
  user	0m0.018s
  sys	0m0.011s
  [exit 0]

$ docker run --rm --network s02-poc-internal --platform linux/amd64 node:22 curl -sS -o /dev/null -w %{http_code} --max-time 10 -x http://s02-poc-proxy:3128 https://example.com:8443/
  curl: (56) CONNECT tunnel failed, response 403
  000  [exit 56]

$ docker run --rm --network s02-poc-internal --platform linux/amd64 node:22 curl -sS -o /dev/null -w %{http_code} --max-time 10 https://example.com
  curl: (6) Could not resolve host: example.com
  000  [exit 6]

$ docker exec s02-poc-proxy cat /var/log/squid/access.log | awk '{print $4, $6, $7}'
  TCP_MISS/200 GET http://example.com/
  TCP_TUNNEL/200 CONNECT example.com:443
  TCP_DENIED/403 CONNECT example.org:443
  TCP_DENIED/403 GET http://host.docker.internal/
  TCP_DENIED/403 CONNECT 1.1.1.1:443
  TCP_DENIED/403 GET http://169.254.169.254/
  TCP_DENIED/403 CONNECT example.com:8443
  [exit 0]
## 3. hardening flags

$ docker run --rm alpine:latest sh -c 'touch /probe && echo writable-rootfs'
  writable-rootfs
  [exit 0]

$ docker run --rm --read-only alpine:latest sh -c 'touch /probe'
  touch: /probe: Read-only file system
  [exit 1]

$ docker run --rm --read-only --tmpfs /tmp:size=16m alpine:latest sh -c 'touch /tmp/probe && echo tmpfs-ok'
  tmpfs-ok
  [exit 0]

$ docker run --rm alpine:latest sh -c 'grep CapEff /proc/self/status; touch /f && chown 1234 /f && echo chown-ok'
  CapEff:	00000000a80425fb
  chown-ok
  [exit 0]

$ docker run --rm --cap-drop ALL alpine:latest sh -c 'grep CapEff /proc/self/status; touch /f && chown 1234 /f'
  CapEff:	0000000000000000
  chown: /f: Operation not permitted
  [exit 1]

$ docker run --rm alpine:latest grep NoNewPrivs /proc/self/status
  NoNewPrivs:	0
  [exit 0]

$ docker run --rm --security-opt no-new-privileges alpine:latest grep NoNewPrivs /proc/self/status
  NoNewPrivs:	1
  [exit 0]

$ docker run --rm --pids-limit 32 alpine:latest sh -c 'cat /sys/fs/cgroup/pids.max; for i in $(seq 100); do sleep 3 & done; echo not-reached'
  32
  sh: can't fork: Resource temporarily unavailable
  [exit 2]

$ docker run --name s02-poc-oom --memory 64m --memory-swap 64m alpine:latest sh -c 'cat /sys/fs/cgroup/memory.max; x=$(head -c 200000000 /dev/zero | tr "\\0" a); echo survived'
  67108864
  [exit 137]

$ docker inspect s02-poc-oom --format 'OOMKilled={{.State.OOMKilled}} ExitCode={{.State.ExitCode}}'
  OOMKilled=true ExitCode=137
  [exit 0]

$ docker run --rm --cpus 0.5 alpine:latest cat /sys/fs/cgroup/cpu.max
  50000 100000
  [exit 0]

$ docker run --rm --user 65534:65534 alpine:latest sh -c 'id -u; touch /etc/probe'
  65534
  touch: /etc/probe: Permission denied
  [exit 1]
## 4. disposal

$ docker run --name s02-poc-persist alpine:latest sh -c 'echo fictional-state > /state.txt' && docker rm s02-poc-persist
  s02-poc-persist
  [exit 0]

$ docker run --rm alpine:latest cat /state.txt
  cat: can't open '/state.txt': No such file or directory
  [exit 1]

$ docker volume create s02-poc-vol >/dev/null && docker run --rm -v s02-poc-vol:/v alpine:latest sh -c 'echo kept > /v/f' && docker run --rm -v s02-poc-vol:/v alpine:latest cat /v/f
  kept
  [exit 0]

$ docker volume rm s02-poc-vol && docker volume ls -q | grep -c s02-poc || true
  s02-poc-vol
  0
  [exit 0]
## 5. cleanup

$ docker ps -a --format '{{.Names}}' | grep -c s02-poc || true
  0
  [exit 0]

$ docker network ls --format '{{.Name}}' | grep -c s02-poc || true
  0
  [exit 0]
````
