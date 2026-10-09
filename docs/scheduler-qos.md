# Scheduler scalability, PI and workload hints

Runnable threads use intrusive CPU queues with independent locks. Enqueue and
removal update a thread's links in constant time, without allocating a queue node
or searching 512 slots. Ordinary selection starts at its home queue, periodically
checks remote queues, and rotates selected tasks for fairness. Ranked selection
compares occupied queues using configured or inherited urgency and absolute
SCHED_DEADLINE deadlines. Stealing takes a thread's scheduling lock before
releasing the queue lock; final retirement drains dispatch ownership before
freeing that storage. Affinity, NUMA preference, cgroup bandwidth, RT throttling
and deadline runtime limits still apply.

Queues cover 256 logical CPUs. User task admission remains bounded by resource
reservations, RLIMIT_NPROC and cgroup pids.max. The separate user-thread object
limit is 4096; the global 2–512 MiB reservation budget and per-owner half-budget
remain mandatory. X86 task and page-fault stacks each reserve 256 KiB with guard
pages, replacing their former 2 MiB size. CPU interrupt/idle stacks retain their
separate sizing. ARM task stacks remain 64 KiB.

The general slab heap has up to eight static CPU shards. Boot allocations retain
the original slab owner. Every free follows its allocation header, including
cross-CPU frees, so migration adds no magazine or deferred-object allocation.
/proc/slabinfo aggregates all shards by size class. Pressure trimming includes
both boot slabs and every shard's bounded empty spare page. The optional XNU
zone allocator retains its existing cache policy.

Private PI futexes support FUTEX_LOCK_PI, LOCK_PI2, TRYLOCK_PI and UNLOCK_PI.
A private key is the address-space identity plus virtual address, including
CLONE_VM processes. Pageable words resolve COW/page-in before taking the PI
lock. A concurrent pageout preserves the wait queue and retries resolution
outside that lock. Retry exhaustion reports EAGAIN; invalid mappings report
EFAULT, corrupt swap backing reports EIO, and page-in allocation failures retain
ENOMEM. Retirement retries conservatively
and eventually detaches waiters on a terminal error or repeated exhaustion.

Donation follows wait chains, detects cycles, and recomputes from configured
priorities when a waiter times out, is interrupted, changes policy, or receives
ownership. The highest-ranked waiter receives the user word before its event
fires; equal ranks preserve arrival order. Each donation and contended owner
pins Thread storage. A closing flag prevents late admission during exit, forced
sibling retirement or exec. Cleanup uses the old map before detaching it, and
hands surviving waiters ownership with FUTEX_OWNER_DIED. Uncontended locks need
the application's robust-list registration for owner-death recovery. Robust
list traversal recognizes tagged PI entries.

Static admission limits are 256 contended words, 2048 donation edges and 64
chain links. Exhaustion returns EAGAIN, and a cycle returns EDEADLK. MAP_SHARED
PI words and SCHED_DEADLINE PI callers return ENOTSUP: shared backing-object
identity and full deadline-budget inheritance remain separate work. Donation
changes effective rank without overwriting configured policy or bypassing
resource-group/RT bandwidth limits.

Linux sched_attr accepts its original 48-byte form and the 56-byte utilization
extension. UTIL_CLAMP_MIN/MAX flags set hints in 0–1024 units; UINT32_MAX resets
that bound. Fork, clone, exec and ordinary sched_setscheduler preserve hints.
Placement balances queue occupancy against capacity, prefers cores meeting the
minimum, and biases capped work toward smaller cores. Busy preferred cores
allow fallback to another allowed core, so hints never defeat affinity or strand
work. Wake interrupts use the same preference as selection.

ARM reads capacity-dmips-mhz from CPU device-tree nodes and matches full MPIDR
affinity. Values normalize against the largest advertised capacity. Missing
firmware data and x86 use 1024; /sys/devices/system/cpu/cpuN/cpu_capacity exposes
the snapshot. This provides placement hints, without adding DVFS, energy-model
calibration or an adaptive recent-CPU-use policy. Ordinary nice still weights
timeslices.

Scheduler timers consult the earliest sleep, timerfd, POSIX wall-clock timer and
ITIMER_REAL deadline, subject to platform input/maintenance ceilings. Busy timer
locks yield a conservative retry within 1 ms, avoiding a scheduler wait behind
faulting usercopy. Arming or changing a deadline wakes CPU 0. Relative ordinary
nanosleeps use PR_SET_TIMERSLACK, inherited across fork/clone/exec; zero restores
50 microseconds. A sleep can merge onto an existing deadline within its allowed
slack, and never fires early. RT waits and absolute timers stay strict. Distant
wall-clock deadlines saturate rather than overflow.

This is bounded deadline-driven idle scheduling, not complete tickless operation.
X86 CPU 0 retains the PIT tick; polled devices retain their maintenance ceiling.
Native Apple scheduling still uses the existing SEV/timer fallback. Firmware
capacity selection is qualified with synthetic topology tests; QEMU does not
establish placement or power savings on physical heterogeneous machines.

Both architecture builds and four-CPU guests pass the 600-worker, concurrent
pageout, PI inversion/retirement and ABI fixtures. PI churn shows bounded first
cohort noise and no growth in the second cohort. Process, job-control, resource
pressure, paging and timer regressions pass on both architectures; ARM desktop
idle, app-launch and drag checks pass. Generated queue/donation/deadline scans
and PI retry/retirement helpers contain no implicit allocator calls. An
independent review approved the new ownership and retirement paths.

The general desktop measurements still show inherited mkdir and process-churn
retention. The allocation audit still fails on the same 170 allowance groups as
the preceding implementation, with no added group or allowlist expansion.
Those existing failures belong to the separate measured-retention roadmap item.
See [acceptance tests](../tests/scheduler-qos/README.md) for results and
measurement limits.
