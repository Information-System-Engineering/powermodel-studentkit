# examples/python

A minimal power model in one Python file, `powermodel.py`. It uses only the
standard library. The model is `predict()`. Everything around it reads
counters from Prometheus and writes the shapes in `CONTRACT.md`.

Needs Python 3.11+, plus Go 1.24 for scoring. The snapshots are described in
`snapshots/README.md`; below, `$SNAP` is the absolute path of an unpacked one
and `sut-02` its node.

## The loop

**1. Look at the data.** From the repo root, serve the snapshot and leave it
running:

```sh
tools/prom.sh $SNAP        # web UI on http://127.0.0.1:19090
```

The data is in the past, so use the Graph tab with a time range inside the
snapshot (`span.txt` for a stripped one). The raw training snapshot also has
the measured power, `kepler_node_cpu_watts`, so you can see which signals
move with it.

**2. Change the model.** `predict()` turns a CPU usage ratio into watts per
zone and splits them over pods. To use another signal, fetch it in `fetch()`
with a raw selector, filtered by node:

```python
query_range(a.prometheus, f'node_vmstat_pgfault{{node="{a.node}"}}', start, end, a.step)
```

Then take its delta between `ts - step` and `ts` in `at()`, the way
`usage_ratio()` does. Selectors are metric names with label matchers, no
`rate()` or `sum()`: the arithmetic lives in Python, as it would when
reading `/proc`.

**3. Score.** With the snapshot served, from `examples/python`:

```sh
set -a; . $SNAP/hw.env; set +a     # POWERMODEL_CPU_MODEL, POWERMODEL_MACHINE_TYPE
python3 powermodel.py --mode offline --node sut-02 --range "$(cat $SNAP/span.txt)"
go -C ../go tool score "$PWD/predictions.csv" --truth "$SNAP/truth.csv"
```

The score shows MAE, RMSE, MAPE and energy error per zone.

**4. Predict the held-out snapshot.** It has no truth, so run only the
`python3` line and hand in `predictions.csv`. Set `GROUP` at the top of the
file to your group's tag first.

**5. Deploy.** Without `--mode offline` the script serves
`powermodel_node_watts` and `powermodel_pod_watts` on `:9270`.

```sh
docker build -t powermodel-python:dev examples/python      # from the repo root
```

On a [power-kind](../../power-kind) cluster:

```sh
kind load docker-image powermodel-python:dev --name power-kind
kubectl --context kind-power-kind apply -k examples/python/deploy/overlays/kind
curl -sG http://localhost:30090/api/v1/query --data-urlencode 'query=powermodel_node_watts'
```

kind proves that the deployment works, nothing more: its power is synthetic.
On bare metal, set the two hardware values in
`deploy/overlays/bare-metal/kustomization.yaml`, label the nodes to model
`role=sut`, and apply that overlay instead.

## Flags

The flags from `CONTRACT.md`, plus `--listen` (online, default `:9270`) and
`--out` (offline, default `predictions.csv`). Each can also be set as
`POWERMODEL_<FLAG>`.
