# G13 firmware statistics and GPU memory in sysfs

The packaged Asahi driver registers two files on the GPU's platform device on
G13: `agx_stats`, built from the firmware's statistics messages, and
`gpu_memory`, the device's GPU memory totals. Monitoring tools reach them as
`/sys/class/drm/card*/device/`. Vinix drained the statistics ring and dropped
every message. It now keeps what Asahi keeps and publishes both files.

## The statistics

The event worker decodes each message as Asahi's `StatsChannel::poll` does.
Every field follows the four-byte tag directly, because the firmware's 64-bit
fields are unaligned. Only the values the export shows are kept:

- `Utilization` gives `util1` to `util4`. Its timestamps, in 24 MHz base-clock
  ticks, also give `busy_ns`: each window's length scaled by the busiest
  value, capped at 100. Whole seconds and the tick remainder are converted
  separately, as in Asahi, so the arithmetic cannot overflow. A timestamp that
  goes back adds nothing and becomes the new base.
- `PowerState` gives `pstate`, `AvgPower` gives `power_mw`, and `Temperature`
  gives `temperature_raw` and `temperature_scale`.
- `jobs` counts submissions that reached the firmware once all their commands
  have retired, failed ones included.

Asahi warns for each message with an unknown tag; Vinix counts them instead.
[Asahi decoder](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/channel.rs#L633-L722),
[file format](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/sysfs.c#L53-L118)

```
busy_ns 2875000041
jobs 2
pstate 5
power_mw 1234
util1 100
...
```

## The memory totals

`gpu_memory` prints Asahi's six lines. `user_committed` is the size of the live
user objects, each counted once against the client that created it, as
`fdinfo` counts them ([fdinfo](m1-agx-fdinfo.md)). Vinix allocates an object's
backing when it creates it, so `user_resident` equals `user_committed`.
`kernel_resident` is the live allocations of the driver's firmware heaps;
Asahi counts the kernel GEM objects that back them, so its figure includes
heap space not yet handed out. G13 has no limits, so `limit`, `client_limit`
and `refused` are 0, as Asahi prints them there.

## Where they are

Linux names the GPU's platform device after its device-tree node,
`gpu@206400000` on M1: `/sys/devices/platform/soc/206400000.gpu`. Vinix
builds the same name from the ASC register base, whichever device tree it
booted with, and publishes both files there once the DRM device is registered.
(The first version used the SGX base, which would have made it
`204000000.gpu`.) They are removed before the GPU is stopped; removal waits for
any read still running. `/sys/class/drm/card*/device` leads there
([DRM sysfs](m1-agx-drm-sysfs.md)).

## Validation

- `tests/agx-stats` takes each message's field offsets from the pinned Rust
  declaration and both files' line order from the pinned `sysfs.c`, then runs
  the production decoder under ASan/UBSan. It checks every kept value,
  busy-time integration over whole seconds, a single tick, a capped value and
  a timestamp that goes back, the job count, unknown tags and both files' text.
  Mutants that read `pstate` one word early, drop the cap, or swap two lines
  fail it.
- A first version added to `busy_ns` with a compare-and-swap whose argument
  form the stubs and kernel interpret differently; the host test hung in it. The
  event worker is the only writer, so it now stores the sum directly.
- An independent lifetime review found one use-after-free: a fatal error's
  shutdown retires the timestamp heap's table holding only `mgr.lock`, which
  the `gpu_memory` read did not take. The read now sums the heaps under
  `mgr.lock`. The files stay published after such a shutdown, reading the
  last values; the manager is never freed.
- The G13 failure, file-close, async, CPU-cache, `gem-private`, native-error,
  `drm-wire` and `drm-syncobj-wait` suites pass, as do 79 G13 contract test files
  and 122 pinned reference checks. Both `PROD` kernels build, the allocation
  scan is unchanged, and the AArch64 kernel boots in QEMU. The guests have no
  AGX device, so the files were not read on a running GPU.

Evidence is under
`/Users/alex/.local/state/vinix/omarchy-m1-agx-stats-20261119/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `47724253f2364b984bae013d110ad200791a749d9de57535b2e3cf141a2f3a96` |
| `bundle.tar.gz` inventory | `658f121ef7f1bc6b6348a90c4d34ea3939afc0237a448720175d9fad73d0f6c3` |
