#!/usr/bin/env bash
# Snapshot a cluster's Prometheus and stream the snapshot to a local tarball.
#
#   tools/capture.sh <kube-context> <out.tar.gz> [namespace=monitoring]
#
# Serve the result with:
#   mkdir snap && tar xzf <out.tar.gz> -C snap && tools/prom.sh snap/<name>
#
# Needs the admin API (power-kind enables it). The snapshot is deleted from
# the pod however this script exits: a forgotten one fills the TSDB volume.
set -euo pipefail

[[ $# -ge 2 && $# -le 3 ]] || { echo "usage: $0 <kube-context> <out.tar.gz> [namespace=monitoring]" >&2; exit 1; }
CTX="$1" OUT="$2" NS="${3:-monitoring}"

k() { kubectl --context "$CTX" -n "$NS" "$@"; }

POD="$(k get pod -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}')"
[[ -n "$POD" ]] || { echo "no pod labelled app.kubernetes.io/name=prometheus in $CTX/$NS" >&2; exit 1; }
ex() { k exec "$POD" -c prometheus -- "$@"; }

RESP="$(ex wget -qO- --post-data='' http://localhost:9090/api/v1/admin/tsdb/snapshot)"
NAME="$(sed -n 's/.*"name":"\([^"]*\)".*/\1/p' <<<"$RESP")"
[[ -n "$NAME" ]] || { echo "snapshot failed: $RESP" >&2; exit 1; }
trap 'ex rm -rf "/prometheus/snapshots/$NAME" || echo "WARNING: remove /prometheus/snapshots/$NAME in $POD by hand" >&2' EXIT

echo "==> streaming snapshot $NAME from $POD"
if ! ex tar czf - -C /prometheus/snapshots "$NAME" >"$OUT"; then
  rm -f "$OUT"
  echo "tar failed; nothing written" >&2
  exit 1
fi
echo "==> wrote $OUT; serve with: mkdir snap && tar xzf $OUT -C snap && $(dirname "$0")/prom.sh snap/$NAME"
