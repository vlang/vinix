# G13 firmware statistics

```sh
v run tests/agx-stats/run.v --asahi-linux PATH
```

`PATH` is the packaged Linux-Aurora checkout. The runner reads each
`StatsMsg` variant's field offsets from its `fw/channels.rs`, a repr(C, u32)
enum whose `U64` is packed, and the line order of `agx_stats` and `gpu_memory`
from its `sysfs.c`. It writes them into a generated oracle and builds the
production `kernel/gpu/agx/gpu/stats.v` against it under
address/undefined-behavior sanitizers, with a stand-in manager whose heaps
report fixed sizes.

The checks feed firmware-layout messages through the decoder: utilization
windows over whole seconds, a single tick, a value above 100 and a timestamp
that goes back; power state, average power and temperature; an unknown tag;
and two completed jobs. They then compare both files' text, names and values.
`AGX_STATS_SOURCE` selects another `stats.v`, for negative controls.
