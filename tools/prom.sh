#!/usr/bin/env bash
# Fetch the pinned Prometheus once, then serve a stripped snapshot on :19090.
#
#   tools/prom.sh /path/to/stripped/<name>
#
# That endpoint is the student's whole world.
set -euo pipefail

PROM_VERSION="${PROM_VERSION:-3.14.0}"
PORT="${PORT:-19090}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE="${HERE}/.prometheus"

[[ $# -eq 1 ]] || { echo "usage: $0 <stripped-snapshot-dir>" >&2; exit 1; }
SNAPSHOT="$1"
[[ -d "$SNAPSHOT" ]] || { echo "no such directory: $SNAPSHOT" >&2; exit 1; }

case "$(uname -s)/$(uname -m)" in
  Darwin/arm64) PLATFORM=darwin-arm64 ;;
  Linux/x86_64) PLATFORM=linux-amd64 ;;
  *) echo "unsupported platform $(uname -s)/$(uname -m); only darwin/arm64 and linux/amd64 are pinned" >&2; exit 1 ;;
esac

BIN="${CACHE}/prometheus-${PROM_VERSION}.${PLATFORM}/prometheus"
if [[ ! -x "$BIN" ]]; then
  echo "==> fetching Prometheus ${PROM_VERSION} for ${PLATFORM}"
  mkdir -p "$CACHE"
  TARBALL="prometheus-${PROM_VERSION}.${PLATFORM}.tar.gz"
  curl -fsSL -o "${CACHE}/${TARBALL}" \
    "https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/${TARBALL}"
  tar xzf "${CACHE}/${TARBALL}" -C "$CACHE"
  rm -f "${CACHE}/${TARBALL}"
fi

# Prometheus will not start without a config file, even serving a static TSDB.
CFG="${CACHE}/empty.yml"
printf 'global: {}\n' > "$CFG"

# The snapshot sits in a tsdb/ subdirectory when written by cmd/strip.
DATA="$SNAPSHOT"
[[ -d "${SNAPSHOT}/tsdb" ]] && DATA="${SNAPSHOT}/tsdb"

[[ -f "${SNAPSHOT}/span.txt" ]] && echo "==> snapshot span: $(cat "${SNAPSHOT}/span.txt")"

echo "==> serving ${DATA} on http://127.0.0.1:${PORT}"
exec "$BIN" \
  --config.file="$CFG" \
  --storage.tsdb.path="$DATA" \
  --storage.tsdb.retention.time=10y \
  --web.listen-address="127.0.0.1:${PORT}"
