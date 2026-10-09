# Resource groups

Vinix's `cgroup2` filesystem enforces hierarchical memory, CPU, disk I/O and
task limits on AArch64 and x86_64. A process inherits membership at creation;
writing its PID, or `0` for the caller, to `cgroup.procs` moves its whole workload.
Membership, task reservations and creator-owned kernel reservations move together.
Failed admission returns `EAGAIN` and preserves the old membership and charges.
A move within a full common parent needs no temporary extra quota.

| Control | Enforcement and accounting |
| --- | --- |
| `pids.max` | Atomic admission counts threads, including concurrent clones and `CLONE_INTO_CGROUP`, through every ancestor. `pids.current`, `pids.peak` and `pids.events` expose usage and denials. Exec transfers its task reservation, so it succeeds at the ceiling. Exit releases the task reservation. |
| `memory.max` | Committed anonymous memory plus the kernel reservations described in [kernel resources](kernel-resources.md). Kernel admission fails with `ENOMEM`; anonymous excess selects the largest process, or the whole group with `memory.oom.group=1`, for `SIGKILL`. Lowering the limit checks existing usage immediately. |
| `memory.high` | Anonymous commitment above the threshold records a high event and adds a 10 ms delay at the next safe userspace boundary. It does not kill the workload. |
| `memory.swap.max` | Limits logical nonresident anonymous backing, including compressed pages and encrypted disk swap. Each backing is charged once to its origin and ancestors, even after fork. The last mapping reference releases quota independently of temporary fault or worker pins. `0` prevents new pageout backing; already paged data remains valid. |
| `cpu.max` | Scheduler quota and period, in microseconds, apply through every ancestor. Exhausted groups wait until the next period. `cpu.stat` reports actual user/system CPU time, periods and throttling. Killing or exiting a throttled task remains possible. |
| `io.max` | Per physical device `major:minor`, `rbps`, `wbps`, `riops` and `wiops` share virtual service clocks across parallel issuers and ancestors. `max` removes a particular rate. `io.stat` reports actual device bytes and completed transfers. |

`memory.current` is logical committed anonymous usage plus conservative kernel
capacity reservations, rather than RSS. `memory.stat` separates `anon`, `kernel`
and `anon_paged`; `memory.peak` records their total peak. Pageout and `PROT_NONE`
preserve anonymous charges. Resident COW frames and shared aliases divide their
charge among owners; nonresident fork backings use mapping references rather
than transient worker references. Migration includes the committed anonymous
workload in destination admission. Counts and publication share the process
table lock with membership changes. A busy page map retains its previous count.

Anonymous limits are checked every 16 newly committed pages. This permits
bounded fault-batch overshoot, plus concurrent in-flight work; it is not a
preallocation guarantee for every anonymous page. Maintenance refreshes counts
once per second, allowing recovery after unmap without reading a controller
file. Exec/exit invalidate old address-space charges. Exited thread stacks cease
to consume the workload's group quota, while their physical reservations remain
in the global creator budget until the scheduler can free them. Surviving IPC,
file and shared-mapping objects retain their creator reservations.

Disk rates pace completed I/O at syscall/fault return and after background
writeback batches. Device, filesystem and VM locks are released before waiting.
The first operation or batch can therefore burst; this is not a pre-dispatch
block queue. Cache hits consume no disk quota. Dirty cache pages retain their
original dirtier's controller and split writeback runs at changes of origin.
Changing a child's limit cannot cancel a parent's outstanding service debt.
An independent maintenance worker keeps cleanup and notifications running while
writeback is throttled. Native VirtIO, ATA, AHCI, NVMe and Apple ANS transfers
use physical device identities; native hardware paths beyond QEMU were built
but not exercised by these tests.

`resource.pressure` is a Vinix extension on each nonroot group. Open it read-only
and use `poll` or `epoll` with `POLLIN`/`POLLPRI`. An initial snapshot is ready;
subsequent configuration changes, pressure level transitions and quota events
make it ready again. Reading at offset zero acknowledges that generation and
returns a fixed snapshot with usage, limits and event counters. Independent
opens acknowledge independently; `dup` and fork share the open description.
Maintenance delivers notifications about once per second. There are 128
system-wide subscription slots; exhaustion returns `ENOSPC`, and closing the
last description makes its slot reusable. This interface does not implement
Linux PSI stall-time averages or trigger syntax.

Configuration writes are limited to 4096 bytes and checked for numeric overflow,
unknown I/O fields and duplicate keys. Disk accounting has 32 device records per
group. Hierarchies have an absolute depth limit of 64; `cgroup.max.depth` and
`cgroup.max.descendants` impose tighter limits. `cgroup.stat` counts live
descendants. Retirement prevents late task admission through an old directory
descriptor, and failed directory publication rolls back the live hierarchy
count. Removing a group releases its descendant slot.

The existing directory, namespace and controller objects retain mount lifetime,
including after `rmdir`; they remain charged to their creator budget. Repeated
directory creation is bounded by that budget, but does not regain metadata
quota through removal. Text replacement keeps its reservation throughout the
five-second reader grace period. Full controller-object reclamation remains
part of the kernel lifetime work. File cache ownership, memory protection
(`memory.min`/`low`), CPU/I/O weights and cpuset placement are not enforced by
this change. Legacy files for those controls retain their existing readback
behavior. A zero anonymous memory limit uses the existing one-byte sentinel.

See [acceptance tests](../tests/resource-groups/README.md).
