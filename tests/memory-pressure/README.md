# Global memory pressure and proactive clean-cache reclaim

The maintenance worker samples physical free memory once a second. The low
watermark is 1/32 of usable memory, bounded to 16–128 MiB and at most 1/8
of tiny machines' RAM. The critical watermark is 1/4 of low; recovery to normal
requires 1.5 times low. Below low, each pass reclaims at most 4 MiB of clean
backing-cache data. The existing five-second writeback pass makes successfully
written dirty pages eligible on later passes. This is a soft reserve; allocation
can still consume it. Anonymous pages and live file mappings are not evicted.

Read `/proc/vmpressure` for normal/warning/critical state, transition generation,
free/total bytes, watermarks, reclaim runs, dropped-cache physical-page
equivalents, and failed PMM bitmap scans. `allocation_failures` counts failed
scans before retry as well as terminal failures. `reclaimed_pages` counts cache
data in physical-page units; packed objects may share a frame, so the immediate
change to MemFree need not equal it. Reclaim does not discard dirty/in-flight data.

Each open subscribes independently with initial `POLLIN`/`EPOLLIN`. Reading at
offset zero takes a stable snapshot and acknowledges the current transition;
partial reads and EOF belong to that snapshot. After poll reports a transition,
`lseek(fd, 0, SEEK_SET)` then read. Dup/fork share an open description's snapshot
and consumption. Transitions coalesce while unread. There are 64 subscription
slots, with `ENOSPC` at the limit; close returns the slot. O_PATH does not subscribe.
Subscriptions and their buffers/interface boxes use static bounded storage.
Reading an old snapshot at a nonzero offset, including EOF, does not acknowledge
a new transition; readiness remains set until a read at offset zero.

Run host tests of the unchanged production policy and subscription resource:

```sh
V=/path/to/v sh tests/memory-pressure/run.sh
```

These substitute physical-memory snapshots, synchronization, atomic operations,
and event delivery. They exercise threshold recovery, separate reads, stable
partial reads, delayed acknowledged events, subscription limits and slot reuse.
`guest.c` exercises real procfs opens, poll, epoll, descriptor sharing and slot
reuse on either architecture through `tests/kernel-gaps/run.py`.
It also faults in anonymous memory while leaving a bounded kernel reserve,
checks warning/critical readiness and a background reclaim attempt, then unmaps
the allocation and verifies the normal recovery notification.

This is partial VM3/VM4 coverage: there is no anonymous page-out/compressor/swap,
essential-operation hard reserve, global OOM recovery, PSI stall-time sampling,
per-cgroup pressure attribution or dirty mapped-file reclaim in this change.

## Checkpoint validation (2026-10-02)

Both architecture builds and the host pressure/pagecache tests passed. The
AArch64 and x86_64 1 GiB guests passed live pressure/recovery notifications, a
reclaim attempt, poll/epoll consumption, dup sharing, subscription exhaustion and
reuse. The x86_64 serial verdict arrived late in its boot and passed within the
240-second test limit.

`desktop-perf/run.py --scenarios=ops,churn,cache --rounds=1 --mem=2048` completed
with `build-support/init-aarch64/initramfs.tar`. The larger default desktop
image stalled in firmware, so that attempt is not validation. Writing/reading
32 MiB through EXT2 used 22 MiB more RAM and reported 16 MiB cached. Existing
retention remains substantial: 300 true/sleep/curl/awk runs retained respectively
1840/1952/2816/2016 KiB; proc_read/proc_list/readdir measured approximately
674/30722/327170 bytes per operation. These are measurements of this checkout,
not a matched before/after demonstration or a claim of flat kernel allocations.

The allocation-site audit reported 363 arm64 and 255 amd64 sites, with many
pre-existing allowance mismatches under the installed V (and an amd64 reporting
compiler error). It did not pass. Only the two reviewed mount-lifetime pressure
source allocations were added to allowed.txt; subscription opens do not allocate
objects or interface boxes. The unrelated allowance baseline was preserved.
