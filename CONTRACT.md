# Contract

What every power model tool in this project reads, writes and exports.
Language is free. These shapes are not.

## Functionality
Your tool must support two modes, offline and online.

In the online mode, you act as a Prometheus metrics provider (see below), reading live data to produce your model output.

In the offline mode, you are provided with a link to a Prometheus snapshot with a timeframe (where measurements are available). You apply your model and produce an output of predictions per time interval.

To derive a prediction, you need to gather some signals, for this we require you support reading from Prometheus.


| Flag | Detail | 
| ---  | ---    |
| --mode | `online`,`offline`, default `online` |
| --prometheus | url to a Prometheus instance | 
| --node | `str` node selector relevant to filter signal data |
| --step | `int` in seconds, describing the step rate or tick rate of your tool, default `10` |
| --cpu-model | `str` a reference to the CPU model you model for | 
| --machine-type | `str` a reference to the machine type you run on, indicating a split of CPU resources |
| --range | `RFC3339..RFC3339` timeframe (relevant only in offline) |

All flags can also be set using environment variables with the `POWERMODEL_` prefix. E.g., `POWERMODEL_CPU_MODEL="Intel(R) Xeon(R) Silver 4114 CPU @ 2.20GHz"` to set the CPU model.

## Offline Mode
An offline run must produce a `predictions.csv` which provides readings from `--range Start..End` 
Start-Time till the End-Time at the step frequency `--step`.

The csv file should look like this:

```csv
ts,node,zone,pred_node_w,pred_active_w,groupname,pred_pod_w
```

| column | meaning |
|---|---|
| `ts` | unix seconds, on the step grid |
| `node` | the node modelled, the `node` label of the snapshot |
| `zone` | `package`, `dram`, … as Kepler names them; `host` when scored against Scaphandre |
| `pred_node_w` | estimated node watts in that zone |
| `pred_active_w` | the part attributable to work: `pred_node_w × cpu_usage_ratio` |
| `groupname` | your group's fixed tag. |
| `pred_pod_w` | (Optional) JSON object, `namespace/pod` → watts in that zone |

One row per zone per step. The first step of a window has no previous
sample and is not written.

Scoring compares against truth recorded on a fixed grid (10 s unless the
snapshot says otherwise). `--step` must be a multiple of it, and `--range`
must start on that grid; `span.txt`'s start does. Other files are rejected.

## Online Mode

You provide a `/metrics` endpoint, compatible with a Prometheus exporter.

This must report two types:

```txt
    powermodel_node_watts{node_name,zone,groupname}
    powermodel_pod_watts{node_name,zone,groupname,pod_namespace,pod_name}
```

Gauges, in watts. `groupname` is your group's fixed tag.

## Signals

Prometheus stands in as the signal abstraction during this project.

Normally you would read `/proc`, `/sys` and cgroupfs, but that is difficult to snapshot and replay, therefore for simplification we use Prometheus instead, and configure it such that all typical signals that are available in `/proc`, `/sys`, cgroupfs and Kubernetes are available to you there.

However, Prometheus has capabilities beyond these special filesystems, i.e., historical views, windowing, aggregation. As these would not be available normally, refrain from relying on them.

As with any distributed system, make sure you check all assumptions you make about the signal data.
There are things that may not be true, e.g., that data is always available, that data is complete, that time is the same across nodes.

## Honour code

Snapshots and servers will have ground truth data embedded, but your model must not read it.
The task here is for you to find reasonable ways to predict power usage. When you do feature modelling, make sure you remove these features by hand if necessary.
