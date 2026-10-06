# Linux i915 compatibility layer

**Status: initial kernel API support, not a working Intel graphics driver.**
Vinix does not yet compile, link or bind the complete Linux i915 driver.
The existing firmware framebuffer remains the display backend.

The initial hardware target is the Tiger Lake-LP GT2 GPU in the Core
i5-1135G7. The current PCI filter accepts only `8086:9a49`, with a display
class matching Linux's own Tiger Lake table. Confirm the actual device with
`lspci -nn -s 00:02.0`; CPU model information alone is not a PCI identity.

## Unmodified upstream sources

`kernel/linuxkpi/upstream.json` pins Linux **6.6.157**, its kernel.org archive
SHA256, and a separately pinned manifest of every imported file. Fetch with:

```sh
python3 kernel/linuxkpi/upstream.py fetch
python3 kernel/linuxkpi/upstream.py verify
```

The complete upstream `drivers/gpu/drm/i915` directory, Linux headers and
selected library sources are imported below
`third_party/linux-i915/linux-6.6.157`. The source archive and generated tree
are excluded from Git. Compatibility changes belong in
`kernel/linuxkpi/include` or Vinix's native backend; do not patch the driver.
Verification rejects changed, added, missing or symlinked source files, and
rejects a rewritten manifest. Original copyright notices, `COPYING` and
`LICENSES` are retained. Unrelated netfilter headers are excluded because
their case-distinct filenames cannot coexist on default macOS filesystems.

The current build compiles and links unmodified Linux `lib/list_sort.c`,
`lib/sort.c`, `lib/rbtree.c`, `lib/find_bit.c`, `lib/hweight.c`,
`lib/ctype.c`, `lib/siphash.c` and i915's `i915_config.c`, `display/intel_qp_tables.c` and
`i915_memcpy.c`. These supply timeout policy, DSC lookup tables and a WC
memory-copy component; they do not initialize the GPU or submit commands. Importing
the complete i915 source tree is not evidence that the driver runs.

## Implemented APIs

- Linux integer types, error pointers, overflow helpers and compiler macros.
  Original Linux `log2.h` and `minmax.h` supply power-of-two, logarithm,
  rounding and clamp operations. Native headers preserve the transitive
  includes required by the unchanged DRM color LUT helpers.
- Unsigned 32-bit Linux kernel `dev_t` preserves the original 12-bit major,
  20-bit minor and old/new/huge/SYSV encodings through unchanged `kdev_t.h`.
  Hosted tests keep libc's device type, stat layout and mknod prototype separate.
  Native 64-bit Stat fields and device registration still need an explicit
  encoding and namespace bridge.
- Unchanged i915 timeout policy uses the pinned 10,000 ms Kconfig default:
  context zero returns zero; nonzero 64-bit contexts return 10,001 ticks at
  native HZ=1000. Unchanged DSC QP lookups cover 8/10/12-bpc 4:4:4 and 4:2:0
  tables. Callers must supply valid indices. Fence execution, reservation
  ownership and actual display compression remain unresolved.
- Linux list/tree/sort APIs using the actual upstream headers and algorithms.
- 32/64-bit, `atomic_long`, raw and conditional atomic operations and memory
  barriers. Linux's generated API wrappers and compiler helpers stay upstream;
  the architecture primitives use compiler atomics. Compatibility C uses
  `-fwrapv`, as required by Linux's signed-overflow convention.
  Native, hosted and audit translation units force-include the unchanged
  `compiler_types.h` after `kconfig.h`, matching the pinned Kbuild contract.
  A separate first-header probe checks the original DRM atomic declarations.
- Upstream `refcount_t` and ordinary `kref_get`/`kref_put`, including saturation,
  final-release ordering, spinlock release helpers and
  `refcount_dec_and_mutex_lock`.
- Ordinary process and IRQ-off `printk`, `vprintk`, `vprintk_emit` and deferred
  capture use a fixed 64-record ring with 1,024 bytes per record. Producers
  synchronously copy borrowed arguments into owned bytes, allocate nothing,
  and never write the console or wake tasks. A permanent pthread drains records
  outside the ring lock and polls every 10 ms while idle. Full rings discard
  the oldest queued record and count drops; an in-flight record stays live
  until its sink returns. Flush snapshots wait through the captured ordinal,
  including overwritten entries, without waiting for later submissions.
  Log levels, prefix removal, truncation and trailing-newline metadata are
  retained. Unknown-caller continuations remain separate records. NMI capture,
  panic-console bypass, per-caller continuation merging, device/facility
  metadata, rate limiting and the broader console machinery remain pending.
- Native Linux `snprintf`, `vsnprintf`, `scnprintf`, `vscnprintf`, `sprintf`
  and `vsprintf` implement the inventoried i915 formatting subset outside the
  unchanged import. Integer/string padding, precision and return conventions
  follow the pinned source, including Linux-specific boundary rules. Resource,
  physical/DMA address, bitmap, byte-array, FourCC, error-pointer and nested
  `%pV` conversions copy borrowed bytes synchronously. Default pointer hashes
  use the unchanged SipHash implementation and a securely seeded immutable
  key; before readiness they emit Linux's pointer-value placeholder. Native
  RNG publication uses acquire/release atomics, and readiness/output share
  its generator lock. Symbols use the real address fallback with KALLSYMS
  disabled; pointer restriction policy is zero. Unsupported pointer extensions
  emit a bounded diagnostic and stop. Invalid `%n` never fetches or writes its
  argument. Complete `lib/vsprintf.c` dependency closure remains pending.
- `WARN`, `WARN_ON`, `WARN_ONCE` and `WARN_ON_ONCE` preserve Boolean returns
  and evaluate conditions once; false conditions suppress formatting and
  argument evaluation. Concurrent once-callers elect one capture per callsite.
  Warning and refcount diagnostic frontends record sticky `TAINT_WARN` before
  asynchronous output; `add_taint`, `test_taint` and `get_taint` cover the 19
  original taint bits with atomic updates. Stack traces, panic policy, taint
  reporting strings and lockdep remain unresolved. Existing native refcount
  diagnostics still report each invalid operation rather than using upstream
  per-kind once suppression.
- Spinlocks and raw spinlocks, nested IRQ save/restore and scheduler preemption
  guards. Lock spinning continues to answer Vinix's TLB shootdowns. IRQ flags belong to
  the caller, not to shared lock storage.
  Failed IRQ-save trylocks restore both IRQ and preemption state.
- Unmodified Linux `seqlock.h` supplies plain, spinlock-associated and
  mutex-associated sequence counters, seqlocks and two-copy latch counters.
  Readers retry inconsistent scalar snapshots; writers use real native locks
  and preemption guards. The native `cpu_relax` hint services TLB shootdowns.
  Plain counters require caller serialization and nonpreemptible writers;
  mutex-associated counters preserve upstream automatic preemption exclusion.
  Sequence counters do not retain pointers or provide a reclamation grace
  period. BH exclusion and NMI entry remain unresolved, and their declarations
  do not supply runtime implementations. Lockdep and PREEMPT_RT remain disabled.
- Ordinary sleepable mutexes use a raw lock only to protect their wait list;
  contending tasks block in the native scheduler. Direct FIFO handoff prevents
  new arrivals from stealing ownership. Interruptible/killable acquisition
  removes cancelled stack waiters before returning `-EINTR`; an assigned
  handoff wins a concurrent signal. Static/dynamic initialization, trylock,
  ownership checks and `atomic_dec_and_mutex_lock` are implemented.
  `mutex_lock_io` prepares native I/O intent around the ordinary lock and
  restores the caller's previous intent after acquisition; `_nested` preserves
  the upstream non-lockdep annotation alias. Only actual sleeping scheduler
  transitions charge a CPU, and FIFO handoff retires the original CPU's count
  even when the task resumes elsewhere. The public I/O mutex remains
  uninterruptible; independently prepared interruptible scopes can cancel.
  Recursive acquisition and unlocking another task's mutex fail explicitly.
  Optimistic spinning and devres are pending.
- Unmodified Linux `ww_mutex.h` uses native Wait-Die and Wound-Wait locking.
  Transaction stamps order contexts across multiple objects, including wrap;
  contending transactions return `-EDEADLK` when they must drop their locks.
  Slow retry preserves the original stamp after backoff. First-lock waiters
  neither die nor wound an owner; wounded owners wake from waits on another
  object. Same-context blocking acquisition returns `-EALREADY` without changing
  the owned count; contended trylock returns zero. Context-free callers retain
  their queue order alongside stamped transactions. Interruptible cancellation
  detaches its stack waiter, and an assigned ownership handoff wins concurrent
  cancellation. Context counts and wounds use atomics across independent locks.
  Lock, wait, trylock and unlock allocate nothing. Context/task/lock storage
  must remain alive through every owned lock and waiter; release through the
  WW API and finish all users before destruction. RT priority inheritance,
  optimistic spinning and debug lock validation remain pending. i915/TTM's
  eventual unchanged reservation core uses Wait-Die; this primitive does not
  provide the remaining dma-resv/fence implementation.
- Unmodified Linux SRCU headers and public layouts use native two-bank
  per-CPU reader counters and full grace periods. Readers may sleep, nest and
  migrate; counter sums include every CPU. Static domains preserve readers
  that entered before lazy updater initialization. Dynamic initialization
  rolls back usage/per-CPU allocation failures. A private boot queue advances
  grace periods in persistent nonblocking phases, releasing its active slot
  while readers remain, independently of callback dispatch. Callbacks run in
  FIFO order with preemption disabled and interrupts enabled; they may requeue
  or free their own detached object. Polling cookies require a full period
  beginning after their snapshot. Normal/expedited synchronization supplies
  that period; expedited has no separate native latency guarantee. Callback
  barriers capture their submission boundary before serializing waiters and
  include callbacks still executing. Cleanup requires stopped readers,
  producers and API users, then joins GP/timer/callback activity before freeing
  either allocation. There is no allocation per reader or callback. Ordinary
  RCU, NMI-safe SRCU, down/up context-independent SRCU and CPU hotplug remain
  unresolved; SRCU does not provide ordinary RCU's implicit read regions.
- Unmodified Linux `wait.h`, `swait.h` and `completion.h` use native-backed
  queues and task wakeups. Ordinary wait queues preserve nonexclusive,
  exclusive and priority order, wake quotas, callback keys and automatic
  removal. Simple waits use FIFO entries and drop their lock between wakes
  in `swake_up_all`. Completions support pre-issued tokens, single/all wakeups,
  saturation, try-wait and interruptible/killable waits, including timeouts.
  Waiters live on the sleeping task's stack; finish/cancellation takes the
  queue lock before returning, including after a producer removed the entry.
  Callers must keep the enclosing object alive until every waiter and producer
  has returned. Reinitialization requires quiescent users.
  Freezer states, CPU-placement wake hints, pollfree/RCU
  lifetime handling and lockdep validation remain unimplemented. Regular queue
  wake traversal currently holds the lock for the whole walk; it does not
  implement Linux's optional bookmark batching. Unsupported out-of-line APIs
  remain unresolved rather than reporting fictitious success.
- Unmodified Linux `wait_bit.h` uses a permanent native hashed wait table.
  Bit waits preserve complete address/index keys, including multiword indices,
  and bit-lock waits preserve exclusive wake quotas and atomic acquisition.
  Action errors and interruptible/killable signals retain the upstream return
  values; acquiring a now-free lock bit wins a concurrent action error.
  Timed waits capture one absolute jiffies boundary, so spurious wakes do not
  extend it. Variable-event macros use keyed native queues and never dereference
  the address passed to `wake_up_var`; the condition must use live storage.
  Ordinary waiters on a bit bucket can wait for a bit to become set, as i915
  display reset does. Typed bit waiters still require the bit to clear.
  Wait/wake paths allocate nothing and IRQ-off wakes are supported. Records
  remain on the waiter stack; finish/removal synchronizes with bucket traversal
  before returning. Keep bit/condition storage alive through every waiter and
  stop producers before releasing it. I/O actions use the native accounting
  described below; freezer and special task states remain unsupported.
- `io_schedule_prepare`, `io_schedule_finish`, `io_schedule` and
  `io_schedule_timeout` preserve nested per-task I/O intent. Intent alone never
  counts a runnable task: the native run-queue lock admits a reservation only
  after actual removal and accepted-signal filtering. Successful enqueue ends
  it before runnable publication; duplicate or failed/full enqueue cannot
  subtract it twice or lose it. Permanent dead-task removal also retires it.
  `nr_iowait_cpu` and `nr_iowait` report these actual blocked tasks across boot
  CPUs. A sleeping task retains its blocking CPU for accounting even if its
  affinity changes and it resumes elsewhere. The total reads each CPU in turn,
  without promising a simultaneous global snapshot. Original bit-I/O actions
  retain signal/error results and absolute deadlines. These paths allocate
  nothing; intent fits the existing 64-byte task view, the native CPU token
  occupies existing Thread padding and fixed counters have boot lifetime.
  `CONFIG_BLOCK` and `CONFIG_TASK_DELAY_ACCT` remain disabled: this supplies no
  block-plug service, per-task delay statistics or CPU idle-time accounting.
  Freezer/special task states and CPU hotplug remain unresolved.
- Unmodified Linux `jiffies.h`, `ktime.h`, `time64.h`, `timekeeping.h` and
  `delay.h` use native monotonic/raw clock reads and fixed `HZ=1000` conversion
  helpers. Linux's own `timeconst.bc` generated the conversion constants.
  The HPET counter (or calibrated TSC fallback) supplies timestamps and the
  clock-resolution query; the PIT tick advances `jiffies` and expires sleeps.
  Raw and monotonic clocks currently agree because no NTP discipline exists.
  Coarse timestamps use the last tick; deadline wake granularity is 1 ms.
  `schedule_timeout` and its interruptible/uninterruptible/killable/idle
  wrappers return remaining ticks after early wakes and zero after expiry.
  `MAX_SCHEDULE_TIMEOUT` has no deadline. Each finite deadline lives on the
  caller's stack; both expiry and cancellation detach it under the same raw
  lock before the caller can return. Ordinary/simple queue timeout macros
  and timed completions use this backend, including signal cancellation and
  successful completion at expiry returning at least one tick.
  `msleep` retries early wakes, `msleep_interruptible` returns remaining
  milliseconds, and `udelay`/`ndelay` poll the real counter while answering
  native TLB shootdowns. `usleep_range_state` and the unchanged ordinary/idle
  wrappers preserve one absolute monotonic minimum through every early wake,
  including accepted pending signals. They return in TASK_RUNNING and allocate
  nothing. The PIT wakes at its first 1 ms tick at or after the minimum, choosing
  zero optional slack; dispatch can overrun the upper bound. These are sleeping
  minimum-duration waits, without a high-resolution timer service. Invalid
  reversed ranges, unsupported task states and ranges outside the signed
  ktime horizon fail explicitly. High-resolution timers and realtime/TAI/suspend
  clock offsets remain unimplemented. The range check deliberately rejects
  malformed DSI firmware delays whose upstream u32 `delay + 10` wraps;
  equivalence to unchecked invalid-input arithmetic is not claimed.
- Unmodified Linux `timer.h` and its `timer_list` layout support static,
  dynamic and stack initialization, pending queries, `add_timer`, `mod_timer`,
  pending-only modification, deadline reduction and jiffy rounding. The PIT
  promotes expired timers into a ready queue and wakes one native kernel
  worker. Callbacks run with preemption disabled and cannot sleep; ordinary
  callbacks permit interrupts, while `TIMER_IRQSAFE` callbacks disable them.
  Rearming at or before the current jiffy waits for a subsequent tick.
  A timer never overlaps its own callback, including after rearming.
  Deletion has asynchronous, try-synchronous and synchronous forms;
  shutdown also prevents future rearming until explicit reinitialization.
  Synchronous calls wait for the running callback before returning. Callers
  must stop external producers before freeing their object and must not hold
  locks needed by its callback. Blocking deletion from the same callback fails
  explicitly. A callback may free its own detached timer; dispatch keeps a
  separate stack record and never dereferences that timer after the callback.
  Timer entries and running records require no per-arm allocation. The worker
  and its retained task reference have boot lifetime and are created before
  measuring repeated operations. `TIMER_PINNED`, `TIMER_DEFERRABLE`,
  `add_timer_on`, CPU hotplug, NOHZ placement and Linux softirq accounting
  remain pending. Unsupported initialization flags fail explicitly.
  All callbacks currently share one worker, so timer throughput and placement
  differ from Linux's per-CPU timer wheels.
- Unmodified Linux `workqueue.h`, `work_struct`, static/stack initialization
  and explicit `alloc_ordered_workqueue(..., 0)` queues. Each queue owns one
  native worker; FIFO callbacks can sleep, requeue themselves or free their
  detached work item. A running item cannot overlap itself after migration
  to another ordered queue. Enqueueing and waiting need no extra allocation.
  `queue_work`, nonblocking/synchronous cancellation, `work_busy`,
  `current_work`, work/queue flushing, draining and destruction have native
  implementations. Stack flush markers preserve the queueing boundary;
  flushing a queued item also retains an earlier running instance when
  cancellation removes the queued copy. Synchronous cancellation suppresses
  self-requeueing until the running callback ends. Drain/destruction allow
  callback chaining and wait for the queue to empty; destruction then joins
  its worker and releases its retained task before freeing the queue.
  Callers must stop external producers and concurrent API users before
  freeing a work item or destroying its queue, keep the queue alive throughout
  cancellation/flushing, and avoid holding locks needed by its callbacks.
  Waiting for the current callback or flushing/draining its own ordered
  queue fails explicitly. RCU work, reclaim rescuers, freezer support and
  attribute changes remain pending. Unsupported allocation flags/modes return
  `NULL`.
  Explicit `_on` requests accept valid boot CPU IDs; invalid IDs return false
  with a warning. Ordered queues remain unbound regardless of that request.
- Concurrent `alloc_workqueue(..., WQ_UNBOUND, max_active)` queues and
  `system_unbound_wq` use a native worker pool that grows on demand. A separate
  manager allocates and creates workers with interrupts enabled; enqueueing
  remains allocation-free and usable with interrupts disabled. Limits from
  1 to 512 are supported, with Linux's default of 256 when zero is requested.
  Workers remain in their queue until destruction, which joins the manager
  before reclaiming every published worker and retained task. The system queue
  has boot lifetime. Independent sleeping callbacks can run concurrently, but
  a work item never overlaps itself, including migration between queues.
  A blocked migrated item does not prevent independent items from running.
  Each queue flush places its own stack marker at the call's queueing boundary;
  running records carry the generation determined by their position relative
  to those markers. Overlapping flushes exclude later work even when an older
  queued item starts after a later callback. Item and queue flush markers do
  not consume worker slots. Item flushing from a different callback on the
  same concurrent queue is supported when the active limit permits progress.
  This backend uses one affinity domain for the current target; NUMA/cache
  affinity pools and attribute changes remain pending. Reclaim rescuers and
  freezer support remain unsupported.
- CPU-bound `alloc_workqueue(..., 0, max_active)` queues use aligned metadata
  per boot CPU and lazily created workers that bind before publishing readiness.
  Default queueing captures the producer CPU with IRQ/preemption protection;
  `_on` variants route to valid CPUs. Same-item requeue on its running public
  queue preserves the execution CPU, including requests from another CPU.
  Sleeping callbacks retain their per-CPU active slots. Normal bound queues
  share one runnable-concurrency domain per CPU; high-priority queues share a
  separate domain. Scheduler notifications account actual blocking switches,
  resume and wake-before-switch races; ordinary yields/preemption keep workers
  runnable. Only idle workers/managers receive pool wakeups, so callback waits
  remain controlled by their own conditions. The public queue has one pending
  list/generation across all CPU pools, preserving atomic whole-queue flush
  boundaries. Bound support currently requires at most 64 boot-online CPUs;
  hotplug and CPU masks beyond the native 64-bit mask are unsupported.
- `WQ_HIGHPRI` works for bound, unbound and ordered queues with a per-thread
  ordinary nice override of -20. It uses the native scheduler's existing nice
  weighting (twice the normal quantum at -20), without changing the shared
  kernel process or selecting a real-time policy. The existing scheduler cap
  when real-time policies are in use still applies. `system_wq`,
  `system_highpri_wq` and `system_unbound_wq` initialize together at boot; partial
  initialization releases every worker and publishes none of the system pointers.
  Required i915 default/unordered and high-priority queue allocations now work,
  while their GPU, memory and device dependencies remain incomplete. Workers
  remain privately owned by each queue and retain its peak count until teardown;
  Linux's cross-queue worker sharing/idle retirement is not implemented.
- Native pthread creation has fallible stack/FPU/Thread construction on both
  architectures, returns `EAGAIN` and leaves the output handle untouched on
  failure. Every partial allocation is freed before publication. Checked large
  native heap allocations may fail on fragmentation rather than retain newly
  created shared page tables; ordinary heap allocation keeps its existing mapped
  fallback. Unrelated boot kernel-thread creation retains its existing API.
- Unmodified `delayed_work` and its static/stack initialization macros use
  the timer backend and ordered/unbound/bound queues. `queue_delayed_work`,
  `mod_delayed_work`, asynchronous/synchronous cancellation and
  `flush_delayed_work` support immediate execution, deadline extension or
  reduction, queue migration, sleeping callbacks and self-rearming.
  Pending timer reservations use the work item's existing list/data fields;
  arming needs no extra allocation. IRQ-off modification/cancellation drops
  the work lock before retrying an in-flight timer transfer. Synchronous
  cancellation suppresses rearming and waits for both timer transfer and
  work execution. Delayed flushing forces the captured timer into execution,
  while preserving a later self-rearm. Queue flushing/draining excludes
  unexpired timers; owners must cancel all delayed work before destroying
  its queue. Timer transfer and work dispatch both permit a detached work
  callback to free its enclosing object. External producers must have stopped
  before freeing the object; its queue must remain alive through cancellation
  and flushing. Bound delayed work retains its selected CPU through timer
  transfer, including explicit `_on` placement.
- Static `DEFINE_PER_CPU` variables preserve their initializers and alignment
  in a separate copy for every boot CPU. Dynamic `alloc_percpu`,
  `alloc_percpu_gfp` and `free_percpu` use zeroed, aligned slots, with checked
  overflow and allocation failure. Pointer translation supports struct fields
  and uses Vinix CPU IDs; Linux pointers never access Vinix's GS segment.
  Linux's generic `this_cpu` accessors and `get_cpu_ptr`/`get_cpu_var` retain
  their IRQ/preemption protection. Callers must stop all readers before
  `free_percpu`; CPU hotplug and Linux early-boot per-CPU machinery are pending.
- Ordinary `preempt_disable`/`preempt_enable`, nested counts, `preemptible`,
  no-reschedule release and deferred rescheduling. `preempt_count` currently
  reports scheduler pins only. Linux IRQ/NMI/softirq context accounting and
  `in_interrupt`/`in_atomic` are not implemented.
- A `current` task view embedded in the native x86 Thread, with
  initial-namespace PID/TGID queries, a bounded name and task-owned flags.
  Refresh preserves every Linux-owned bit, including unchanged vtime helper
  `PF_VCPU` transitions. Native exit atomically adds sticky `PF_EXITING` before
  release-publication of `TASK_DEAD`, including a wake that discovers death
  during native queue admission. A stale non-exiting view cannot clear it.
  Construction starts flags clear and copies the program name; clone inherits
  its running parent's name with clear flags. Queries reflect `PR_SET_NAME`, with the copied
  initial name as fallback, without borrowing mutable process-name storage.
  Native unnumbered kernel threads currently report PID/TGID 0.
  Each x86 Thread reserves a 64-byte view buffer; it needs no allocation.
- `get_task_struct` and `put_task_struct` retain the native Thread across
  exit. Reference counts detect unmatched releases and saturate on overflow
  rather than wrapping to zero. An intrusive deferred-reap list has no fixed
  corpse limit; the final release collects eligible exited threads even when
  no further thread exits. Native pthread join/detach use these same pins;
  x86 kernel threads record both owned stacks for reclamation after switching
  away. The existing arm64 reaper still reserves the most recent corpse per
  CPU until that CPU's next exit, because its idle path can use that stack.
- `set_current_state`, `__set_current_state`, `schedule`, `wake_up_process`
  and `wake_up_state` support running, interruptible, uninterruptible,
  killable and idle wait states. State publication has the required full
  barrier, and a per-task lock serializes queue removal with Linux wakeups.
  Native signals are checked after removal to avoid lost wakeups. Ordinary
  signals cannot finish uninterruptible/idle waits or killable waits; their
  native enqueue makes the task sleep again. Special parked/stopped/frozen
  states and Linux scheduler internals remain unimplemented.
- `signal_pending` and `fatal_signal_pending` query native pending/masked
  signals and forced thread exit. `need_resched` reports deferred native
  preemption. `cond_resched` voluntarily enters the actual scheduler when
  IRQs are enabled and no preemption pin is held; otherwise it returns 0.
  `get_cpu`/`put_cpu` and CPU-ID queries use native CPU IDs and scheduler pins.
- Atomic bit operations, including acquire/release bit locking, using Linux's
  generic implementation and the native atomic backend. Unmodified Linux
  bitmap headers, bit searches and population counts work across word
  boundaries. Native multiword bitmap equality, subset/intersection, Boolean
  operations, replacement, population counts, range set/clear, shifts and
  32-bit array conversion preserve tail and in-place alias semantics. Checked
  bitmap allocation/free supports the native allocation domain (node 0 or
  `NUMA_NO_NODE`); invalid nodes and unsupported GFP modes fail. Parsing,
  devres/user-buffer, remapping and region bitmap APIs remain unresolved.
- Linux byte-order and unaligned-access helpers, using the upstream generic
  implementations without Linux's instruction-patching machinery.
- `memchr`, `memchr_inv`, `strnlen`, `strscpy`, `strscpy_pad`, `kstrdup`,
  `kstrndup` and `kmemdup_nul`. Bounded string operations use byte accesses
  and do not read into an adjacent unmapped page. String duplication returns
  a `kfree`-owned allocation and propagates overflow/OOM failure.
- Original Linux `sysfs_streq`, `match_string`, `__sysfs_match_string` and
  `strreplace` algorithms use borrowed strings synchronously without allocation.
  Matching is case-sensitive, returns the first match and stops at the first
  NULL entry; sysfs matching accepts a trailing newline at the first mismatch.
  Replacement scans through inserted NULs until the original terminator and
  returns the caller's original pointer. The unchanged display CRC parser uses
  exact matching. PMU replacement is used on discrete GPUs; Tiger Lake's PMU
  name takes the integrated-GPU branch. Sysfs and display CRC services remain
  unresolved.
- Kernel-string `kstrtoull`, `kstrtoll`, long/int and 8/16-bit conversions,
  their unchanged 32/64-bit aliases and `kstrtobool` preserve the pinned Linux
  algorithms outside the import. The original character-class table is linked.
  Numeric parsing accepts base zero or 2 through 16, an allowed sign and one
  trailing newline; syntax/range failures leave the destination unchanged.
  Boolean parsing retains Linux's first-token rules, including ignored suffixes.
  Borrowed strings are consumed synchronously without allocation, IRQ changes
  or preemption changes. The unchanged kernel header supplies their declarations.
  Real callers include PCI force-probe tokens and GT engine/power settings;
  the device/settings lifecycles remain unresolved. The eleven `_from_user`
  wrappers copy the pinned bounded input into stack buffers before parsing.
  Any uncopied byte returns `-EFAULT` without changing the result, even after
  an earlier NUL. Integer buffers preserve the sign/base-two/newline limits;
  Boolean input is capped at three bytes.
- Ordinary `raw_copy_{from,to}_user`, `__copy_{from,to}_user`,
  `_copy_{from,to}_user` and public `copy_{from,to}_user` use the real native
  pagemap walk and return the exact uncopied suffix. Raw and double-underscore
  copies leave that suffix untouched; public from-user copies zero it.
  `access_ok` checks the numerical user half without implying page access.
  Callsite object bounds and the Linux `INT_MAX` limit reject a public copy
  before changing bytes. Existing native Boolean and remote-copy policies
  retain their behavior. Faulting copies require ordinary task context with
  enabled IRQs and preemption, and use the current syscall's owned pagemap.
  The existing range-source pins and fresh identity checks protect backing
  acquisition. Scalar, atomic/pagefault-disabled, unsafe-scope and noncached
  APIs, dynamic hardened-usercopy checks and x86 LAM remain unresolved.
- `strchr`, `strpbrk`, `strsep`, `skip_spaces`, `strim` and the original
  `strstrip` alias consume borrowed strings synchronously. Search results and
  tokens point into the caller's storage; splitting preserves empty tokens and
  only replaces delimiters. Trimming uses the original Linux character-class
  table and changes the first trailing whitespace byte. The local trimming
  loop avoids forming a pointer before the buffer on all-whitespace input,
  while preserving its return pointer and complete byte mutations. Upstream
  remains unchanged. These APIs allocate nothing and preserve IRQ/preemption
  state. Real consumers include the force-probe and mitigation token parsers;
  their device/module-parameter lifecycles remain unresolved.
- `kmalloc`, `kzalloc`, `kcalloc`, `kmalloc_array`, `kmemdup`, `krealloc`,
  `ksize` and `kfree`, including zero-size pointers, overflow/OOM handling
  and Linux allocation alignment. The initial backend uses contiguous
  physical pages, including for small allocations; it favors correctness
  over memory efficiency.
- Plain `kmem_cache_create`, `KMEM_CACHE`, allocation/zero-allocation, free,
  shrink, size query and destruction use reusable packed native page slabs.
  Flags zero and `SLAB_HWCACHE_ALIGN` are supported; RCU, reclaim-accounted,
  zone-constrained and other nonzero cache flags fail creation. Slot metadata
  stays outside payloads. Constructors run once per fresh slot before slab
  publication, outside the cache lock and in the allocating caller's context;
  reuse preserves object contents unless zero-allocation clears them.
  Allocation/free support IRQ-off callers without changing their IRQ or
  preemption state, and share kmalloc's checked GFP/reclaim policy. Empty slabs
  remain reusable until explicit shrink or destruction. Shrink may overlap
  alloc/free; it detaches only empty slabs under the lock and releases pages
  afterward. Create/shrink/destroy require sleepable context. Owners must stop
  every API user and free every live object before destruction. RCU-safe caches,
  native per-CPU caches, reclaim accounting and NUMA placement remain pending.
- Non-reclaiming allocation for `GFP_ATOMIC`, `GFP_NOWAIT`, `GFP_NOFS`,
  `GFP_NOIO` and callers with IRQs/preemption disabled. Only unrestricted
  sleepable allocations invoke Vinix's existing reclaimers. Zone-constrained,
  `__GFP_NOFAIL` and memory-cgroup-accounted allocations are not supported.
- A read-only target identity check against the unmodified Tiger Lake PCI
  table. This does not register an i915 device or change GPU registers.
- Native PCI configuration reads, writes and COMMAND updates share one
  IRQ-safe transport lock across ordinary device users and uACPI callbacks.
  Domain zero, valid BDF coordinates and aligned 1/2/4-byte registers are
  checked before I/O; full 64-bit offsets cannot truncate into valid registers.
  Failed reads leave the borrowed result untouched. Missing functions retain
  the hardware's successful all-ones reads. x86 uses actual CF8/CFC subword
  ports within 256 bytes; ARM uses a boot-immutable, Device-nGnRnE ECAM window
  within 4096 bytes, with checked bus and physical/virtual bounds. ARM preserves
  every DAIF mask and completes unlock publication before waking waiters.
  COMMAND updates read/conditionally write sixteen bits in one transaction,
  preserving adjacent STATUS RW1C flags. Existing ATA, e1000 and xHCI command
  writes use the proper width. Transactions allocate nothing and never sleep,
  log or map memory while holding the transport lock. Linux `pci_dev`/bus
  publication, references, registration/removal and resource ownership remain
  unresolved; this transport does not provide them. BAR sizing still needs
  exclusive ownership and safe device quiescence. NMI/FIQ recursion, nonzero
  segments, nonzero-origin ARM apertures and x86 extended ECAM remain pending.
- Boolean static branches without text patching; CPUID feature words 0 and 4.
- Kernel FPU borrowing that saves/restores the running thread's existing
  XSAVE/FXSAVE storage while preemption is disabled. The upstream i915 WC-copy
  component uses it for SSE4.1 copies; other CPU-feature words fail explicitly.

The compatibility build is opt-in, x86-64 only:

```sh
LINUXKPI=1 PROD=false ./scripts/build-amd64.sh --no-userland --no-iso
```

For a direct kernel build, pass `LINUXKPI=1` to `make -C kernel`; cross
compilation on macOS also needs the compiler/linker settings used by
`scripts/build-amd64.sh`. An out-of-tree build can set `LINUXKPI_SOURCE_DIR` to the
absolute imported source directory. The default and arm64 builds do not
enable the compatibility runtime. Enabling it currently runs self-tests and
reports the target GPU as **not bound**, because i915 compatibility is
incomplete.

## Verification

```sh
tests/linuxkpi/run.sh
python3 kernel/linuxkpi/audit.py
python3 tests/linuxkpi/run_vm.py \
    --kernel build-amd64-kernel/bin/vinix \
    --state-dir /tmp/vinix-linuxkpi-guest
python3 tests/linuxkpi/run_vm.py \
    --kernel build-amd64-kernel/bin/vinix \
    --cpu max,hypervisor=off --state-dir /tmp/vinix-linuxkpi-guest-sse
```

PCI transport validation uses 18 frozen kernel paths at isolated baseline
`71426a7e`, enabled ELF SHA256
`9f76e1954c9188dcffae9035ee1f097d0957ae0947febc49c8371ae05d7ad475`.
The complete strict ASan/UBSan runtime, unchanged import and standalone-header
suite passed at `/tmp/vinix-linuxkpi-pci-config-host-final.log`. The added
standalone `tests/pci-config/run.sh` exercises the actual portable C core under
both GNU99 and GNU11. Controlled host contention holds a CF8 address/data pair
while a second device tries to enter; fixed register vectors cover full
256/4096-byte bounds, real subword lanes, unchanged error outputs and concurrent
COMMAND updates against a STATUS RW1C model. Core allocation attempts stay zero.
Host interrupt/pin state is a model, not native architecture evidence.

Four CPU-bound native actors each perform 896 identity/class reads of two
actual devices, mixing ordinary and IRQ-off calls with nested preemption pins
and allocation disabled. They check typed results, invalid-only writes, caller
state and CPU identity after sleeping. All sixteen real worker constructor
failure cases cover four stages after zero through three successful actors.
Cleanup joins every started actor, checks DEAD/deadline state while retained,
waits for the entire cohort to leave its stacks, releases task pins and waits
for actual deferred frees. Three warmups precede a measured fourth batch with
exact physical-page recovery. The normal four-CPU guest passed all 33 markers
and Linux-ABI PID1 at `/tmp/vinix-linuxkpi-pci-config-vm/serial.log`; default x86
startup passed without LinuxKPI markers. Enabled/default x86 and default ARM
builds passed. Independent source, fixture and saved generated-C reviews cover
ABI widths, stack result storage, actual port/MMIO instructions and lifetimes.

The first SSE guest passed the PCI/page checks but later failed the unchanged
bound self-free watchdog: 15/16 completions at 509 ticks, then 16/16 during the
cleanup wait in that tick. Its failure remains
`/tmp/vinix-linuxkpi-pci-config-sse-vm/serial.log`. Callback review found complete
progress and safe cleanup; it does not explain the delayed completion. A second
same-ELF SSE guest again passed PCI/page checks, then observed 14/16 at 520 ticks
and 16/16 at 534 ticks in the same bound test. The pre-PCI enabled ELF from
`71426a7e` also reproduced that watchdog under identical guest settings:
14/16 at 534 ticks, then 16/16 in that tick. Its private harness removes only the
unavailable new PCI marker; provenance and the failing baseline log are saved
at `/tmp/vinix-linuxkpi-pci-baseline-harness-provenance.json` and
`/tmp/vinix-linuxkpi-pci-baseline-sse-vm/serial.log`. No callback deadline was
changed, and neither feature SSE run is a full-suite pass.

The default ARM guest passed with the fixture absent. A separate ARM kernel
built with `PCI_CONFIG_TEST=1` passed actual ECAM 1/2/4-byte reads, invalid
offsets and all eight independent D/A/F mask combinations while IRQs remained
masked. Full DAIF state survives every transaction and the original state is
restored before return. Both ARM guests reached their raw Linux-ABI PID1;
logs are `/tmp/vinix-linuxkpi-pci-config-arm-{default,test}-vm/serial.log`.
The approved harness owns its disk, firmware-variable copy and QEMU process;
a synthetic late-panic regression also verifies its final log drain. The
fixture is opt-in, and four configured QEMU CPUs do not establish ARM SMP:
these context vectors run on the controller CPU. Exact sources, artifact
hashes, failure logs and independent approvals are recorded in
`/tmp/vinix-linuxkpi-pci-config-final-validation.json`.

The official allocation gate initially differed after another session rebuilt
the shared V compiler. Repeated baseline and final feature scans with the same
compiler both retain **428 sites, 191 groups and 160 existing failure groups**;
no counts or groups were added by the feature. Both exit 1, and the x86 scan
retains existing V errors. The initial 411-site reports and their provenance
remain recorded in `/tmp/vinix-linuxkpi-pci-allocation-comparison.json`.
This is a scoped comparison, not a global allocation pass or GPU validation.

String-token validation used four frozen kernel paths at isolated baseline
`ce4606b3`, enabled ELF SHA256
`8c32940b5f6a4bd707a52a2f3073055ebe5e529190812a2f13a6585f09c0ad8e`.
The complete strict ASan/UBSan runtime, import and standalone-header suite
passed at `/tmp/vinix-linuxkpi-string-tokens-host.log`. Fixed vectors check
borrowed pointer/cursor positions, empty and repeated delimiters, complete
buffer mutations, all 256 byte classifications, read-only inputs and guarded
mutable buffers. Calls preserve IRQ/preemption/CPU state and page counts with
allocation disabled. The host-only aliases exercise the actual implementations
without interposing on sanitizer/libc internals; native names stay unchanged.
Separate actual-backend tests passed 7,542,446 comparisons with the pinned
algorithms, including the equivalent bounded trimming traversal.

Fresh enabled/default x86 and disabled ARM builds passed. The final rebuild
including the host-only header aliases produced identical saved ELF/generated-C
hashes. Normal/SSE four-CPU guests passed at
`/tmp/vinix-linuxkpi-string-tokens-{vm,sse-vm}/serial.log`. The native fixture
runs 200 times in the exact physical-page measurement; default startup passed
without LinuxKPI markers. Independent source, host/native fixture and generated-C
review covers the borrowed lifetimes and genuine `strchr` link dependency.
Exact evidence is `/tmp/vinix-linuxkpi-string-tokens-final-validation.json`.
These checks do not register a PCI device or initialize a GPU.

Kernel-string parser validation used five frozen kernel paths at isolated
baseline `7735509f`, enabled ELF SHA256
`cf90f5defc1003984b0c261c85debd4b08d6831884c80c43428fa168e782b996`.
The complete strict ASan/UBSan runtime, import and standalone-header suite
passed at `/tmp/vinix-linuxkpi-kstrtox-host-final.log`. Fixed vectors cover
all supported bases and signed/unsigned widths, boundary values, invalid
syntax, overflow precedence, unchanged error outputs, permissive Boolean
suffixes and inaccessible adjacent pages. IRQ-off calls with nested preemption
pins and allocation disabled preserve caller state. Separate comparison with
the pinned algorithms passed 16,653 comparisons. All 15 substantive parser
functions were independently compared with the pinned source.

Fresh enabled/default x86 and disabled ARM builds passed. Normal/SSE four-CPU
guests passed at `/tmp/vinix-linuxkpi-kstrtox-{vm,sse-vm}/serial.log`, including
56 native conversion checks per iteration in the existing 200-iteration exact
physical-page measurement. Default Linux-ABI startup passed with no LinuxKPI
markers. Independent source and generated-C review found no new allocations or
retained input/result pointers. Exact evidence is
`/tmp/vinix-linuxkpi-kstrtox-final-validation.json`. The full syntax audit still
passes 3/269 units at that milestone; GPU/device operation remains unresolved.

Ordinary user-copy validation used isolated x86 and ARM worktrees at
`bea41f8e`, a frozen compiler, and only this feature's recorded overlay.
The production V copy/parser host tests passed 6,440 assertions each under
GNU99/GNU11 with ASan/UBSan and no allocator imports. The complete host runtime,
unchanged-import tests and actual native page-source host tests also passed.
Enabled x86, default x86 and default ARM builds passed; both default guests
completed Linux-ABI startup. The exact final enabled ELF
`4534a060ef59c7865d9c5e4188ff6e188fcfa48a772e8ede0ef324d4388a9eeb`
passed the full normal native suite. New copy tests exercise real page holes,
read-only/PROT_NONE pages, demand faults and COW; three warmups plus a measured
batch return every physical page and live heap class to baseline. Independent
source and final generated-C reviews found no retained borrows or hidden
allocations. Earlier normal/SSE and clean-baseline runs exceeded the outer
180-second limit; the final normal run used 600 seconds without changing any
runtime callback deadline. SSE copy measurements also passed, while its full
final suite check remains pending. The paired allocation gate has 414 sites,
192 groups and 158 pre-existing failing groups, with no added groups; this is
not a global allocation pass. The full i915 audit remains 3/269. Evidence uses
the `/tmp/vinix-linuxkpi-uaccess-oct06-` prefix, including source/provenance,
allocation comparison, independent reviews and preserved failed guest logs.

Minimum-duration sleep validation used five frozen kernel paths at isolated
baseline `53f41b30`, enabled ELF SHA256
`354139c5a2fe25d532aa9e5ec9f84343a19a7f3b2ffac3abd32a082dde56e723`.
The complete strict ASan/UBSan host/import/header suite passed at
`/tmp/vinix-linuxkpi-usleep-host-final.log`, including seven subprocess boundary
checks. Deterministic tests cover sub-tick and zero minima, eight early wakes
through one captured expiry, accepted/ignored signals, expiry before arm/park
and independent concurrent deadlines. Six invalid-input probes require an
explicit BUG with no live deadline or page; the exact valid signed-clock
boundary succeeds. These tests are part of the repeatable host runner.

Native tests use four actual CPU-bound workers with ordinary, idle,
interruptible, killable and RUNNING waits. They check minimum duration, state,
CPU identity and caller context with allocations disabled. A longer controlled
case observes accepted early wakes and ignored-signal repark while waking past
the original boundary. All four constructor failure stages are tested after
zero, one, two and three successful workers. Every started worker is joined,
its deadlines inspected while retained, and all off-stack handoffs precede
final task releases and actual-free quiescence. Three warmups precede a fourth
batch with exact physical-page recovery. Source and generated C have independent
lifetime approval. Enabled/default x86 and disabled ARM builds and default
Linux-ABI startup passed.

The first normal guest passed the new sleep/page checks but later failed an
unchanged unbound self-free timeout at 502 ticks with 3/8 callbacks observed.
That failing log remains `/tmp/vinix-linuxkpi-usleep-vm/serial.log`. A fresh
normal guest using the identical ELF passed the full suite at
`/tmp/vinix-linuxkpi-usleep-normal-diagnostic-vm/serial.log`; the full SSE guest
also passed at `/tmp/vinix-linuxkpi-usleep-sse-vm/serial.log`. This rerun does not
repair or explain the intermittent unbound timeout. Equal-baseline allocation
gates both retain 429 sites, 192 groups and 161 existing failures, with no added
counts or groups; enabled scans also retain their pre-existing V errors.
Exact evidence is `/tmp/vinix-linuxkpi-usleep-final-validation.json`.
The 1 ms wake granularity still affects short hardware polling latency;
these compatibility tests establish no i915 hardware operation.

String-helper validation used three frozen kernel paths on isolated baseline
`92c24841`, with enabled ELF SHA256
`2d976d406a63e4795716521e59fdd3357f9ba42e4018c8fc05062a61fff6c193`.
The complete strict ASan/UBSan host, import and standalone-header suite passed
at `/tmp/vinix-linuxkpi-string-helpers-host.log`. Fixed vectors cover newline
edge cases, duplicate and NULL entries, zero/SIZE_MAX counts, guarded borrowed
strings and arrays, inserted NULs and inaccessible adjacent pages. Calls with
allocation disabled, interrupts disabled and nested preemption pins preserve
their caller's state. Independent comparison against extracted pinned
algorithms also passed. Fresh enabled/default x86 and disabled ARM builds
passed. Normal/SSE four-CPU guests passed at
`/tmp/vinix-linuxkpi-string-helpers-{vm,sse-vm}/serial.log`; the native fixture
runs 200 times inside the existing exact physical-page measurement. Independent
source and generated-C review covers these allocation-free operations and the
literal V diagnostic. This does not establish sysfs, CRC or GPU operation.
Exact source and validation scope is saved in
`/tmp/vinix-linuxkpi-string-helpers-final-validation.json`.

Policy/helper validation used nine frozen kernel paths on isolated baseline
`3d92a08b`, with enabled ELF SHA256
`0208f9ab0f90194c35850220b53a760b6455d30ebd7ad7659a299597f4af0a82`.
Strict ASan/UBSan runtime, import and standalone-header tests passed at
`/tmp/vinix-linuxkpi-i915-policy-host-complete.log`. Fixed device-number
goldens include every legacy identifier and independent bit permutations;
48 literal DSC goldens and all 3,240 valid min/max pairs exercise the linked
original tables. The existing native allocation loop repeats the pure helper
fixture 200 times and returns exactly to its physical-page baseline.
Fresh enabled/default x86 and disabled ARM builds passed. Full normal/SSE
guests passed at `/tmp/vinix-linuxkpi-i915-policy-normal-diagnostic-vm/serial.log`
and `/tmp/vinix-linuxkpi-i915-policy-sse-vm/serial.log`; default startup also
passed. Independent generated-C review found no hidden allocation in the new
V call and no policy code in the disabled ARM build.

The initial normal guest passed the new 200-iteration helper measurement but
failed an existing timed-wait baseline equality with 1,029 more free pages.
Review identified a gap between TASK_DEAD publication and final scheduler
reaping: the 50 ms stable-count heuristic can still include one dying thread.
The unchanged-ELF rerun is diagnostic evidence, not a repair of that fixture.
Exact source/build/guest scope is saved in
`/tmp/vinix-linuxkpi-i915-policy-final-validation.json`. No full driver or
hardware claim follows from these helper results.

The timed-wait fixture now joins every worker and observes each retained
thread's off-stack deferred-reaper handoff before releasing any final pin.
A scalar counter, updated under the existing list lock, keeps detached nodes
visible through their actual free; the fixture then waits for an empty list
and zero frees in flight. It never reads a released thread. The shared
one-second monotonic retirement bound starts after all joins, including DEAD
publication, readiness and final frees; operation timeouts and exact page
equality remain unchanged. This establishes retirement of known timed-wait
workers, not global heap quiescence or the arm64 most-recent-corpse policy.

The retirement fix and I/O mutex tests share the seven-path frozen overlay
at `b52104ef`, enabled ELF SHA256
`7ce625f4b7ff4b54c2dd39604274c0b596b18ad75992ef85ee8aed029a69105d`.
Fresh full normal/SSE guests passed at
`/tmp/vinix-linuxkpi-mutex-io-retirement-{vm,sse-vm}/serial.log`.
Enabled/default x86 and disabled ARM builds passed. Independent source and
both-architecture generated-C reviews found no new hidden allocation.
Equal-source official allocation gates both retain 440 sites, 193 groups
and 162 existing failures, adding no sites or groups. Supplementary enabled
V scans still fail on existing import/interface errors; successful native
build C supplies the guarded-path review. This is scoped evidence, not a
global allocation pass. Details are saved in
`/tmp/vinix-linuxkpi-mutex-reap-allocation-comparison.json`.

The I/O mutex host suite passed strict ASan/UBSan and import/header checks at
`/tmp/vinix-linuxkpi-mutex-io-host.log`. It covers nested intent, mixed FIFO
waiters, middle-waiter cancellation, disallowed-signal repark, cross-CPU count
retirement and ownership-before-signal handoff with allocation failures armed.
Native tests exercise the actual scheduler, routed handoff and all four
constructor failure stages after zero, one or two queued workers. Gates open,
the controller unlocks and every started worker joins before stack mutex
destruction, including unexpectedly successful constructors. Three warmups
and the measured fourth batch return exactly to baseline. Default guest
startup also passed. Independent lifetime reviewers approved the wrapper and
every new cleanup path. Exact evidence is
`/tmp/vinix-linuxkpi-mutex-io-retirement-final-validation.json`.
No direct `mutex_lock_io` caller exists in the current imported i915, DRM
headers or libraries; this implements a real compatibility API without
claiming driver execution or a new syntax-audit pass.

Logging validation used the frozen 17-path overlay on isolated baseline
`a34c2473`, with enabled ELF SHA256
`318b1939b75b5d2111ea2a306d646c054775d788e086f49dd493615eacb8810b`.
Fresh normal and SSE4.1 four-CPU guests passed, including checked preboot worker
construction, real held scheduler/console lock capture, borrowed-byte lifetime,
four concurrent producers, overflow, in-flight retirement and flush snapshots.
After three warmups, the measured fourth batch returned exactly to its physical
page baseline; the permanent logger was started before measurement. Logs are
`/tmp/vinix-linuxkpi-printk-complete-{vm,sse-vm}/serial.log`. The first candidate
guest stopped at an older timed-wait fixture's global-empty assertion: the new
permanent worker legitimately sleeps on that list. The fixture now checks each
joined, retained task's own records before its final release, with failure
reason diagnostics and unchanged timeouts. No timer backend behavior changed.

The complete strict ASan/UBSan host runtime, import and standalone-header suite
passed at `/tmp/vinix-linuxkpi-printk-host-final.log`. Formatting goldens cover
Linux boundary rules, pointer forms, key publication and nested argument
ownership; warning tests cover suppression, concurrent once winners and all
19 sticky taints, including a first-event refcount warning. Fresh enabled x86,
default x86 and disabled ARM builds passed; default four-CPU Linux-ABI startup
also passed. Independent formatter/ring/fixture and final time/taint lifetime
reviews approved. Frozen generated C on both architectures has no new hidden
allocation in logging bridges or synchronized RNG readers. The equal-source
allocation gate remains **440 sites, 193 groups and 162 existing failures**
on both baseline and feature, with no new allocation counts or failure groups.
Its earlier 16-path scope is preserved separately; the final native time and
taint changes are C-only and leave those V paths unchanged. These results do
not establish a global kernel leak pass or GPU operation.

The host tests use ASan and UBSan. They exercise allocation failure and
preservation of the original buffer after failed `krealloc`, zero-fill,
alignment, list stability, red-black tree invariants, concurrent atomic/lock
operations and nested IRQ restoration. Refcount tests cover overflow/underflow
saturation, concurrent final release, and acquire/release publication.
Source-import tests cover modification, manifest tampering and archive path
traversal.
Cache tests exercise descriptor/name/refill OOM rollback, private constructor
publication, constructor-once reuse, explicit/GFP alignment and payload sizes
from one byte through multiple pages. Four host allocators race explicit shrink
under ASan/UBSan; IRQ-off and preemption-pinned refills preserve caller context
and avoid reclaim. Four native CPU-bound workers allocate/free while the
controller shrinks. After three warmups, the measured fourth complete batch
restores the exact physical-page baseline. Fresh normal and SSE4.1 enabled
four-CPU guests passed using ELF SHA256
`f5fefb21858cc7d80dd8aa3ef06c203da6c7d84cd4d46b20ea602ca69a8ed93e`;
logs are `/tmp/vinix-linuxkpi-cache-{vm,sse-vm}/serial.log`. Fresh default x86
and disabled ARM builds also passed, with default Linux-ABI guest startup.
Independent backend/fixture lifetime and generated-C reviews approved. The
fresh equal-source allocation gate at `e29bcc4d` has identical baseline/feature
results: 416 sites, 184 groups and 155 existing failures; both exit 1. This
feature adds no gate failure and does not establish a whole-kernel leak pass.

Separate host executables include `kernel.h` and `drm_color_mgmt.h` first,
checking header dependencies independently of the runtime's other includes.
They verify integer boundaries, single argument evaluation, LUT half-step
rounding/clamping and every full-precision u16 LUT value under ASan/UBSan.
Bitmap tests compare searches against a scalar reference for every size from
0 to 256 bits, including set operations and word boundaries. Four threads
exercise shared-word atomic updates and bit-lock publication. String tests
place source/destination buffers against protected pages, check truncation
and zero padding, and verify allocation failure and release. Unaligned
byte-order tests check both values and encoded bytes. Raw-lock tests include
failed trylocks and nested IRQ state restoration.
Per-CPU tests run four CPU-labelled workers, check static initializers and
independent updates, and exercise interior-field translation, scalar widths,
compare/exchange, nested preemption and IRQ restoration. Dynamic allocation
tests cover alignments from 1 to 4096 bytes, overflow, OOM, zero-fill and release.
The static template is copied as a complete linker section; host template
globals omit ASan redzones so that alignment padding is readable. Allocated
CPU copies and runtime accesses remain instrumented.
Task tests run four workers with independent native task models, retain
identity through simulated CPU migration, and check name truncation, padding,
renaming and child inheritance. The initial name's source buffer is overwritten
after construction to verify that the view owns its copy. They also cover
masked SIGTERM, SIGKILL, forced exit and scheduling guards.
One thousand host wait/wake iterations cover wakes before removal, after
removal and at the point of sleeping, including state-mask matching and
disallowed native signal enqueues. The enabled four-CPU guest runs four
batches of 70 exited workers, alternating early/blocked wakes and join/detach,
while retaining their task views. It checks reference saturation, ignored
SIGTERM wakeups, dead-task wake rejection and release of every worker's native
stacks, FPU buffer and Thread. After warming the native allocator, physical
free pages return to the baseline.
Task-flag tests run unchanged disabled-accounting vtime guest helpers through
repeated current/name refreshes and yields, then verify fresh child flags and
terminal exit preservation. Controlled host races cover stale non-exiting
views and death between a waker's alive check and queue admission, with page
allocation disabled. Native current tests preserve pre-existing flags, and
70 retained exited workers keep their guest/sentinel bits through acquired
DEAD and final release. Normal/SSE guests pass using ELF SHA256
`e51ffd67cdaf20a418be7a7936027f3e0998e59cf01dc64d2dc21db7336383e7`
at `/tmp/vinix-linuxkpi-taskflags-{vm,sse-vm}/serial.log`, including exact page
recovery. Fresh enabled/default x86 and disabled ARM builds pass. Standalone
first-header probes verify original ktime declarations through sched and
current through ww_mutex. This supplies task flag behavior, without enabling
virtual CPU time accounting or claiming IRQ/BH packed preemption counts.

Sequence-counter fixtures check static/dynamic initialization, odd/even retry,
unsigned wrap, invalidation/barriers, writer lock/preemption ownership, nested
IRQ restoration and exclusive fallback readers. Two serialized writers and
two readers check scalar pairs through plain, spinlock-associated,
mutex-associated, seqlock and latch modes. Ordinary odd writers never sleep;
latch writers yield only while readers use the other copy. Started native
workers are joined before shared stack storage retires, including partial
construction failure. Host ASan/UBSan and strict native GNU99/GNU11 probes pass.
Fresh enabled/default x86 and disabled ARM builds pass. Normal/SSE four-CPU
guests pass all markers, including exact page recovery after three warmups and
a measured fourth sequence-counter batch, using ELF SHA256
`567317e40cc29069338c1d320020d375f5cbc4b33d974061aa2b45e0cb3afbf3`.
Logs are `/tmp/vinix-linuxkpi-seqcount-final-{vm,sse-vm}/serial.log`.
Independent lifetime/generated-C reviews approved. The equal-source allocation
gate at `d63e5c74` reports identical 439 sites, 193 groups and 164 existing
failures for baseline and feature; it remains a whole-kernel failure.

Two initial guests failed the older SRCU fixture before reaching these tests.
Failure-only diagnostics passed in both a committed-baseline control and a
sequence-counter build. Review identified a scheduling hazard: a callback
could pin the waiter's CPU before the waiter could migrate itself. The fixture
now routes its retained waiter away before publishing callback entry, then
checks real placement and grace-period/barrier progress. Final normal/SSE runs
pass with the original 500-tick deadlines. The initial failures had no stage
trace, so this is not proof that they had the same cause. The harness also
drains one second of panic diagnostics before terminating its own guest.

Four host workers exercise 4,000 contended mutex acquisitions, including a
yield inside each critical section. Controlled queues check FIFO handoff,
middle/tail cancellation, ignored ordinary signals in killable waits and
final-reference helpers. Wait tests cover priority callbacks, exclusive
quotas, callback removal/stop/key behavior, early and parked wakeups, signal
cleanup, condition-vs-signal ordering and completion saturation/reinitialization.
The four-CPU guest also runs four batches of four concurrent synchronization
workers. They yield while holding a mutex, block on ordinary/simple queues,
publish data through wakeups and consume completion tokens before a latched
all-wake. Every worker's retained task is released after exit; after allocator
warmup, the final batch restores the physical free-page count.

Timed-wait host tests use a controlled clock for 240 expiry/early-wake/signal
cases across tasks, ordinary/simple queues and completions. Additional cases
force expiry immediately after deadline publication and before task removal,
check completion tokens/signals at expiry, killable signal filtering,
zero/infinite timeouts and interrupted/retried `msleep`. Advancing the clock
after each waiter returns checks for stale stack pointers under ASan. Numeric
tests cover rounding, saturation, tick wrap comparisons, negative time64
values and nanosecond overflow. The enabled guest runs four batches of four
timed-wait workers, each repeating task/queue/completion expiry and signal
checks eight times. Every deadline list is empty after the batch and the
measured physical free-page count returns to its warmed baseline.

Timer host tests check pre-expiry/promoted cancellation, return values,
shutdown and reinitialization, static/stack timers, same-jiffy self-rearming,
IRQ/preemption balance and non-overlapping callbacks. Controlled callbacks
on another host thread hold execution while a synchronous deleter waits;
tests cover asynchronous deletion/shutdown and running callbacks that rearm.
Two hundred callbacks free their own heap object under ASan, with every page
returned. Four producers perform 2,000 shared-timer modification/cancellation
cycles while another thread advances ticks and dispatches callbacks. Rounding
checks cover four CPU skews and 2,000 offsets each. Native four-CPU tests run
four batches of four workers, each using 12 stack timers that rearm four times,
alternating ordinary and IRQSAFE callbacks. Synchronous shutdown precedes
stack exit; after warmup, the measured batch returns every physical page.

Workqueue host tests cover FIFO execution with a sleeping callback, duplicate
queueing, pending cancellation, callback chaining, and flush boundaries that
exclude later submissions. Controlled running callbacks test synchronous
cancellation suppressing self-requeueing, migration without overlap, and
flushing a canceled queued instance while an older callback still runs.
Two hundred callbacks free their own work item under ASan; four producers
perform 4,000 shared-item enqueue/cancel cycles across two queues. Fifty
queue creation/destruction cycles verify worker exit and retained-page counts;
unsupported modes and allocation failure are checked too. Four-CPU native
tests run four batches of four ordered workers, checking FIFO cancellation,
sleeping callbacks, eight-instance chains, self-freeing callbacks and complete
queue/worker teardown. The measured batch restores its physical-page baseline.
Native thread-test baselines require 50 ms of stable free pages while yielding
and reaping warmup workers, with a one-second bound. The measured batch still
must return exactly to that baseline; a mismatch prints both byte counts.

Delayed-work host tests cover pre-expiry/promoted cancellation, deadline
changes, immediate execution, migration, static initialization and IRQ-state
balance. Controlled timer transfers force atomic modification/cancellation
and synchronous cancellation/flushing to retry while the transfer is running.
Sleeping callbacks check cancellation suppressing rearm and flush boundaries
preserving a later timer. Four producers perform 2,000 shared-item
enqueue/modify/cancel cycles across two ordered queues while ticks advance;
callbacks assert that execution never overlaps. Two hundred callbacks free
their enclosing delayed-work object under ASan, with every page returned.
The native four-CPU guest runs four batches of four ordered workers, checking
timed self-rearm, sleeping callbacks, forced execution, IRQ-off deadline
changes/cancellation and 32 self-freeing objects per batch. After worker
teardown and timer dispatch retirement, the measured batch restores the
physical-page baseline.

Concurrent unbound host tests check active limits of one, two and four,
independent callbacks passing a blocked migrated item, nested item flushing,
snapshot flushing with later sleeping callbacks, and 20 overlapping queue
flushers. A held old queued copy starts after a later callback to verify
generation assignment. A controlled manager-publication gate forces queue
destruction while a new worker exists but has not joined the published list;
teardown waits for the manager and releases that worker too. Tests also run
shared delayed-work producer races, synchronous cancellation, 200 self-free
callbacks, and system-queue initialization, failure, reuse and release.
The native four-CPU guest runs four batches using active limits of two/four
and eight simultaneously blocked system-queue callbacks. It checks real
sleeping/rearming callbacks, nested item flushes and 24 self-free objects per
batch. System-queue workers are warmed to a fixed eight-worker peak before
the measured batch; temporary queues release every worker and native page.

Bound host tests cover per-CPU active limits, busy-versus-sleep scheduling across
queue owners, separate high-priority domains, same-item migration, delayed CPU
routing, overlapping whole-queue snapshots, cancellation, 200 self-freeing
callbacks, constructor/manager failures and boot-system rollback. The manager
publication gate identifies its CPU so an earlier lazy worker cannot trap the
wrong publication. Native tests also force preemption between task dequeue and
its explicit park, validate real CPU identity after sleep/yield, reject invalid
or atomic-context affinity/nice changes, and test isolated worker nice weights.
They inject failure at every native stack/FPU/Thread construction stage and
verify pthread handles, successful recovery, queue rollback and page recovery.
Three warmed batches precede each measured fourth batch. These measurements
cover the new feature; existing broader kernel allocation failures remain
outside this support claim.

Bitmap host tests compare against an independent per-bit oracle over widths
0 through 8193, with dirty tail bits, operand aliases, exact-sized 32-bit arrays,
zero-width NULL inputs and allocation failures. Oversized-shift checks cover
the implemented `__bitmap_*` functions; the unchanged upstream single-word
inline wrappers retain their original behavior. The native kernel repeats
multiword operations, conversion and allocation/free 200 times and checks
exact page recovery.

Bit/variable-wait host tests check complete keys across colliding words,
indices and variable sentinels, ordinary SET-bit waits, exclusive quotas,
wake-before-sleep, action errors and signal/atomic-acquisition races. Repeated
bit and variable cancellations reuse stack addresses with allocation disabled.
Real deadline tests include early and spurious wakes; isolated injected
jiffies values verify wrap arithmetic without overflowing the host clock.
Variable tests check condition-at-expiry, signal return values and opaque keys
at inaccessible or unmapped addresses. Native tests use actual parked tasks,
IRQ-off keyed wakes, exclusive lock ownership, display-reset SET wakes,
killable filtering, retired variable keys and 256 repeated action/deadline
cases per batch. After three warmups, a fourth batch releases all temporary
threads and restores the exact physical-page count in normal/SSE guests.

I/O host tests cover nested intent, runnable/zero/infinite/pending-signal paths,
multiple blocked CPUs, duplicate and cross-CPU wakes, finite expiry/early/signal
returns, bit waits and exclusive bit-lock handoff/cancellation. Controlled
full-queue failures retain the reservation until a successful wake, and signals
between removal and admission cannot count an already runnable task. Repeated
tests run with page allocation disabled. Native tests use actual CPU-bound
sleepers, forced preemption before explicit park, ignored signals, sleeping
affinity migration, real timed/bit waits and counted pthread exit. Three warmup
batches precede a measured fourth; every temporary worker is joined and released
and the physical-page count returns exactly to its baseline.

Wound/wait host tests exercise two/three-object Wait-Die cycles, cross-object
Wound-Wait wakeups, queued older transactions, original-stamp slow retry,
first-lock exclusions and stamp wraparound. They check interspersed context-free
waiters, signal/wound versus handoff races, unrelated nested classes and 400
reused stack-wait cycles with allocation deliberately disabled. Native tests
exercise actual blocked tasks, backoff/slow retry, both algorithms, signal
cancellation, context-free ownership and 256 repeated count/trylock cases per
batch. After three warmups, the fourth batch releases every temporary thread
and restores the exact physical-page count.

SRCU host tests exercise nested/migrated readers, both bank phases, full-period
polling boundaries, static first use and dynamic initialization rollback.
They check independent grace-period progress while a callback is gated,
20 overlapping callback barriers, late submissions, 200 self-free callbacks,
self-requeue, concurrent pointer reclamation and repeated dynamic teardown.
With a private active limit of two, reader-blocked domains do not starve an
unrelated domain; all 256 system-unbound active slots may wait for SRCU without
blocking its private service. Bootstrap OOM/retry/idempotence and domain
teardown return every host page and worker. Native tests use sleeping readers
that migrate between CPUs, actual barrier task parking, a new full period
while its old callback remains pinned, FIFO self-free callbacks, bound-worker
synchronization and caller-local OOM injection. Three batches warm the private
queue's two-worker peak; the measured fourth batch must restore the exact
physical-page baseline.

An enabled kernel runs the allocator/list/sort/tree/IRQ-lock tests 200 times
and verifies that the physical free-page count returns to its initial value.
The same repeated test also checks raw locks, bit searches, byte-order helpers,
bounded strings and static/dynamic per-CPU isolation across all four CPUs,
including allocated-string and dynamic-slot release. The static per-CPU pool
has boot lifetime and is initialized before the free-page baseline is taken.
Every iteration also checks current-task identity across a real voluntary
scheduler yield, and rejects yields inside a CPU pin or IRQ-off section.
It checks uncontended mutexes, wake-before-sleep queue removal, completion
tokens and clock/conversion helpers without allocating waiter objects.
It then holds preemption disabled with IRQs enabled until a real scheduler
interrupt defers a context switch, checks that no-reschedule release preserves
pending scheduling work with IRQs disabled, and services it on IRQ restoration.
The WC-copy test checks FPU register/MXCSR
preservation, buffer alignment and aligned/unaligned copies. Upstream i915
disables acceleration when CPUID reports a hypervisor; the second TCG guest
disables that CPUID flag to exercise the actual SSE4.1 path. This is a CPU
memory-copy test, not a test against GPU WC-mapped memory.
The QEMU test requires all kernel test markers and a static Linux-ABI PID 1
marker on COM1. Use a kernel built with
`PROD=false` for serial diagnostics. The test creates its own guest and disk
image; its state directory must not already exist. `--no-linuxkpi` checks a
default kernel's Linux-ABI startup and verifies that the API layer is disabled.
The WC test also exposed and verified a fix to the initial x86 kernel-thread
stack: entry now reserves a return-address word to satisfy SysV alignment.

`audit.py` obtains the driver translation-unit list from the original Linux
Kbuild Makefile, with ACPI and fbdev enabled and optional self-tests/GVT off.
It attempts every translation unit and writes complete compiler diagnostics
to `build/linuxkpi/i915-audit.json`. An incomplete API layer makes this command
exit with status 1. The current result is **3/269** translation units passing.
The policy/helper audit is recorded separately at
`/tmp/vinix-linuxkpi-i915-policy-final-audit.json`; `i915_memcpy.c`,
`i915_config.c` and `display/intel_qp_tables.c` pass syntax. Logging/WARN/taint,
device-number types, integer limits and native CPU spin-hint visibility
blockers are cleared. Leading first errors now include missing
`generated/bounds.h`, `asm/early_ioremap.h`, ordinary RCU pointer APIs
and `call_single_data_t`. These are syntax
paths, not a complete runtime dependency inventory.
Even a successful syntax audit would still require actual
object linking, unresolved-symbol checks and runtime/hardware testing.

## Remaining driver integration

The complete i915 build still fails. Ordinary per-CPU storage and scheduler
pins, current-task identity, ordinary blocking task states/wakeups and retained
task references now have native implementations. Namespace-relative
PID queries, SMP dispatch, interrupt-context accounting and page-table types
still need a bridge. No `mm` field or dummy address space is exposed.
Borrowed `current` must not be used after exit; callers retaining a view use
`get_task_struct` before surrendering its running/owned lifetime and release
it with `put_task_struct`.
The next work includes these interfaces and substantial
runtime subsystems:

1. Linux device/PCI registration and removal, configuration access and devres.
2. MMIO mapping with correct cache attributes, DMA/scatter-gather APIs,
   page/shmem management, GPU address spaces and TTM/GEM memory management.
3. Remaining lock/wait variants,
   freezable/reclaim workqueues, remaining system queues, RCU work, remaining
   timer modes, high-resolution timers and RCU lifetime rules.
4. Linux IRQ registration, interrupt synchronization and safe GPU reset paths.
5. C DRM core integration, device nodes, file ownership, ioctl/mmap handling,
   DMA fences, sync objects and dma-buf lifetime handling. The existing V DRM
   interfaces are not the internal Linux C DRM API.
6. Firmware loading, ACPI OpRegion, power management and display/KMS services.
7. Build/link all original i915 objects with that layer, filter PCI binding
   to the confirmed target and boot on the physical Tiger Lake machine.
8. Validate command submission, framebuffer/display handoff, GPU resets,
   repeated process teardown and Alpine Mesa/libdrm compatibility on hardware.

QEMU's standard VGA adapter cannot validate an Intel driver. Physical Tiger
Lake hardware, or a properly isolated passthrough setup, is required for that
final validation. GPU support must stay marked incomplete until those checks
pass.

References: [Linux 6.6 stable sources](https://cdn.kernel.org/pub/linux/kernel/v6.x/),
[Linux kernel versus userspace interfaces](https://docs.kernel.org/process/stable-api-nonsense.html),
[i915 documentation](https://docs.kernel.org/gpu/i915.html).
