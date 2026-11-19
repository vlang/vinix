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

## Raw statistics in debugfs

Linux-Aurora also keeps every statistics message as the firmware sent it, and
exports that in debugfs as `asahi_stats`
([stats_raw.rs](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/stats_raw.rs)).
Vinix now does the same. Each of the ten kinds the driver decodes keeps a
sample count, the monotonic time of its last sample and that sample's words.
`messages` counts every message with a known tag, including the undecoded
ones; a tag past the last is not counted, as in Asahi. Nothing is scaled or
derived. The text is Asahi's `asahi_stats_v1` format, and a kind never
received shows `count=0` with no values:

```
asahi_stats_v1
device=206400000.gpu
now_ns=100000
messages count=3
power count=0
...
utilization count=1 captured_ns=107 timestamp=21474836481 util1=327682 util2=327683 util3=327684 util4=327685
...
temperature count=1 captured_ns=114 raw_value=720998 scale=720999 tmin=721000 tmax=721001
...
```

The snapshot is kept under its own short lock, as Asahi keeps it under a
spinlock, and a read copies it out before formatting it.

Linux's DRM core gives every device a debugfs directory named after its
parent device, with a link to it per minor. On M1 that is
`/sys/kernel/debug/dri/206400000.gpu`, reached as `dri/0` and `dri/128`,
since the GPU is `card0` there. Vinix has no debugfs filesystem, so the DRM
core now publishes that directory
in /sys at the path Linux mounts debugfs on. Drivers add files to it with
`drm.debugfs_add_file()`, Linux's `drm_debugfs_add_file()`
([DRM sysfs](m1-agx-drm-sysfs.md#drm-debugfs)). The AGX driver adds
`asahi_stats` once the DRM device is registered, as Asahi does. Only root may
read it, as only root may enter debugfs on Linux; anyone may list the
directories. Unregistering the DRM device removes it before the GPU is
stopped, and removal waits for any read still running.

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

### Validation of `asahi_stats`

- `tests/agx-stats` compiles the reference's own code with rustc as its
  oracle: `StatsMsg` from `fw/channels.rs`, `RawStatsSnapshot` and
  `format_snapshot` from `stats_raw.rs`, and `record_raw` from `channel.rs`.
  Two phases of messages go through it and through Vinix's decoder. Every
  field has its own value, and Vinix's copies carry junk in the pads and
  undecoded words. The phases include undecoded tags, a tag past the last and a
  repeated kind. Vinix's text must match the oracle's byte for byte. Mutants
  that read `power` or `sensor_id` from a pad, swap `util1` and `util2`, or
  count a tag past the last fail it.
- `tests/drm-sysfs` checks the debugfs directory, its links, a root-only file
  read through either link and removal at unregister, and that a parentless
  device and a second device with a taken name get no directory. Mutants with
  a wrong link target, no removal, a world-readable file or a shared directory
  fail it. In QEMU, on both architectures, the parentless devices have no
  debugfs entry.
- An independent lifetime review found no bug. It confirmed the following:
  - every new allocation is freed exactly once;
  - unregistering waits for reads of files in the removed directory, through
    either link, before the GPU is stopped;
  - the snapshot lock is only ever taken inside the manager lock, never the
    other way round;
  - nothing in the generated C moves to the heap.

  It raised two hazards that no caller can reach. First, adding a file is not
  synchronized with unregistering; the doc comment now requires callers to add
  first, as the AGX driver does during registration. Second, two devices whose
  parents share a name would have shared a directory; the second now gets none,
  as Linux refuses the name.
- The G13 failure suite needed its fixture adapted: a stub for the new
  registration step and a fixed sample time. With that, it passes, as do the
  async, file-close, context-retire, heap-cancel, heap-pressure, `drm-wire` and
  `drm-fdinfo` suites, 79 G13 contract test files and 122 pinned reference
  checks. Both `PROD` kernels build, and the allocation scan is unchanged at
  419 findings. Both kernels boot in QEMU, and Omarchy's Mesa still runs
  there. The file was not read on a running GPU; QEMU has no AGX device.

Evidence for `asahi_stats` is under
`/Users/alex/.local/state/vinix/omarchy-m1-asahi-stats-20261119/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `3d7ee81a657d7cca8a359f625a208729a76b49bf6652d5da1ff162ed15d9f7dc` |
| `bundle.tar.gz` inventory | `ed0dd492c60e3adc2384fc55e14e875c0e0f45fb13e359a90cc747c0058ecb59` |
| AArch64 kernel | `f9e974d5d3a1c2bc5d2eaff9a5efabfd367124fc2b4ba96aaf10b755ae596c18` |
