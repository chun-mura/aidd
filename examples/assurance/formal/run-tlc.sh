#!/usr/bin/env bash
# Run the pinned TLC model checker on one spec, with a local Java or a pinned Java image in Docker.
#
# Usage: run-tlc.sh <dir> <Module.tla> <Config.cfg>
#   <dir> holds the module, the config and every module they extend. TLC writes its
#   state files under <dir>/states. The exit code is TLC's (0: no error,
#   11: deadlock, 12: safety violation, other: setup or parse error).
#
# Environment:
#   AIDD_FORMAL_JAVA   auto (default) | local | docker
#   AIDD_FORMAL_CACHE  where the verified jar is kept
#                      (default: ${XDG_CACHE_HOME:-$HOME/.cache}/aidd-formal)
set -euo pipefail

# Tool pins. Changing any of them is a re-verification trigger (formal-methods.md).
TLA2TOOLS_VERSION="v1.7.4"
TLA2TOOLS_URL="https://github.com/tlaplus/tlaplus/releases/download/${TLA2TOOLS_VERSION}/tla2tools.jar"
TLA2TOOLS_SHA256="936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88"
JAVA_IMAGE="eclipse-temurin@sha256:d77e090ae1f6970c047b443c6f0a6c1358b0426d44432bb5a7753408cd43de0d"

if [ "$#" -ne 3 ]; then
  echo "usage: $0 <dir> <Module.tla> <Config.cfg>" >&2
  exit 2
fi
dir=$(cd "$1" && pwd)
module=$2
config=$3

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

cache=${AIDD_FORMAL_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/aidd-formal}
jar="$cache/$TLA2TOOLS_VERSION/tla2tools.jar"
if [ ! -f "$jar" ]; then
  mkdir -p "$(dirname "$jar")"
  curl -fsSL -o "$jar.part" "$TLA2TOOLS_URL"
  mv "$jar.part" "$jar"
fi
actual=$(sha256_of "$jar")
if [ "$actual" != "$TLA2TOOLS_SHA256" ]; then
  echo "run-tlc: sha256 of $jar is $actual, expected $TLA2TOOLS_SHA256; not running it" >&2
  exit 3
fi

mode=${AIDD_FORMAL_JAVA:-auto}
if [ "$mode" = auto ]; then
  if java -version >/dev/null 2>&1; then mode=local; else mode=docker; fi
fi

tlc_args=(-config "$config" -workers 1 -cleanup -metadir states "$module")
case "$mode" in
  local)
    cd "$dir"
    exec java -XX:+UseParallelGC -cp "$jar" tlc2.TLC "${tlc_args[@]}"
    ;;
  docker)
    exec docker run --rm --network none --user "$(id -u):$(id -g)" \
      -v "$dir:/work" -v "$jar:/tools/tla2tools.jar:ro" -w /work \
      "$JAVA_IMAGE" \
      java -XX:+UseParallelGC -cp /tools/tla2tools.jar tlc2.TLC "${tlc_args[@]}"
    ;;
  *)
    echo "run-tlc: AIDD_FORMAL_JAVA must be auto, local or docker (got $mode)" >&2
    exit 2
    ;;
esac
