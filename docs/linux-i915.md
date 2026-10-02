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
`lib/sort.c`, `lib/rbtree.c`, `lib/find_bit.c`, `lib/hweight.c` and i915's
`i915_memcpy.c`. The last file is a WC memory-copy component, not GPU
initialization or command submission. Importing
the complete i915 source tree is not evidence that the driver runs.

## Implemented APIs

- Linux integer types, error pointers, overflow helpers and compiler macros.
- Linux list/tree/sort APIs using the actual upstream headers and algorithms.
- 32/64-bit, `atomic_long`, raw and conditional atomic operations and memory
  barriers. Linux's generated API wrappers and compiler helpers stay upstream;
  the architecture primitives use compiler atomics. Compatibility C uses
  `-fwrapv`, as required by Linux's signed-overflow convention.
- Upstream `refcount_t` and ordinary `kref_get`/`kref_put`, including saturation,
  final-release ordering, spinlock release helpers and
  `refcount_dec_and_mutex_lock`.
- Spinlocks and raw spinlocks, nested IRQ save/restore and scheduler preemption
  guards. Lock spinning continues to answer Vinix's TLB shootdowns. IRQ flags belong to
  the caller, not to shared lock storage.
  Failed IRQ-save trylocks restore both IRQ and preemption state.
- Ordinary sleepable mutexes use a raw lock only to protect their wait list;
  contending tasks block in the native scheduler. Direct FIFO handoff prevents
  new arrivals from stealing ownership. Interruptible/killable acquisition
  removes cancelled stack waiters before returning `-EINTR`; an assigned
  handoff wins a concurrent signal. Static/dynamic initialization, trylock,
  ownership checks and `atomic_dec_and_mutex_lock` are implemented.
  Recursive acquisition and unlocking another task's mutex fail explicitly.
  Wound/wait mutexes, optimistic spinning, I/O accounting and devres are pending.
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
  Freezer states, I/O waits, CPU-placement wake hints, pollfree/RCU
  lifetime handling and lockdep validation remain unimplemented. Regular queue
  wake traversal currently holds the lock for the whole walk; it does not
  implement Linux's optional bookmark batching. Unsupported out-of-line APIs
  remain unresolved rather than reporting fictitious success.
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
  native TLB shootdowns. High-resolution timers,
  `usleep_range`, realtime/TAI/suspend clock offsets and I/O waits
  remain unimplemented.
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
  queue fails explicitly. CPU-bound queues, other system queues and RCU work,
  CPU placement, priority, reclaim rescuers, freezer support and attribute
  changes remain pending. Unsupported allocation flags/modes return `NULL`;
  explicit CPU queueing returns false with a warning. This first backend
  covers i915's ordinary ordered queues, while its unordered and high-priority
  flip queues still need implementations.
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
  affinity pools and attribute changes remain pending. CPU-bound allocation
  (`flags=0`), explicit CPU placement, reclaim rescuers, priority and freezer
  support remain unsupported. i915's default CPU-bound unordered queue and
  high-priority flip queue therefore still cannot be allocated.
- Unmodified `delayed_work` and its static/stack initialization macros use
  the timer backend and ordered/concurrent unbound queues. `queue_delayed_work`,
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
  and flushing. Explicit CPU placement remains unsupported.
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
  initial-namespace PID/TGID queries, a bounded name and a read-only snapshot
  of `PF_EXITING`. Construction copies the program name; clone inherits its
  running parent's name. Queries reflect `PR_SET_NAME`, with the copied
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
  boundaries. Other out-of-line bitmap operations remain unresolved.
- Linux byte-order and unaligned-access helpers, using the upstream generic
  implementations without Linux's instruction-patching machinery.
- `memchr`, `memchr_inv`, `strnlen`, `strscpy`, `strscpy_pad`, `kstrdup`,
  `kstrndup` and `kmemdup_nul`. Bounded string operations use byte accesses
  and do not read into an adjacent unmapped page. String duplication returns
  a `kfree`-owned allocation and propagates overflow/OOM failure.
- `kmalloc`, `kzalloc`, `kcalloc`, `kmalloc_array`, `kmemdup`, `krealloc`,
  `ksize` and `kfree`, including zero-size pointers, overflow/OOM handling
  and Linux allocation alignment. The initial backend uses contiguous
  physical pages, including for small allocations; it favors correctness
  over memory efficiency.
- Non-reclaiming allocation for `GFP_ATOMIC`, `GFP_NOWAIT`, `GFP_NOFS`,
  `GFP_NOIO` and callers with IRQs/preemption disabled. Only unrestricted
  sleepable allocations invoke Vinix's existing reclaimers. Zone-constrained,
  `__GFP_NOFAIL` and memory-cgroup-accounted allocations are not supported.
- A read-only target identity check against the unmodified Tiger Lake PCI
  table. This does not register an i915 device or change GPU registers.
- Boolean static branches without text patching; CPUID feature words 0 and 4.
- Kernel FPU borrowing that saves/restores the running thread's existing
  XSAVE/FXSAVE storage while preemption is disabled. The upstream i915 WC-copy
  component uses it for SSE4.1 copies; other CPU-feature words fail explicitly.

The compatibility build is opt-in, x86-64 only:

```sh
LINUXKPI=1 PROD=false ./build-amd64.sh --no-userland --no-iso
```

For a direct kernel build, pass `LINUXKPI=1` to `make -C kernel`; cross
compilation on macOS also needs the compiler/linker settings used by
`build-amd64.sh`. An out-of-tree build can set `LINUXKPI_SOURCE_DIR` to the
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

The host tests use ASan and UBSan. They exercise allocation failure and
preservation of the original buffer after failed `krealloc`, zero-fill,
alignment, list stability, red-black tree invariants, concurrent atomic/lock
operations and nested IRQ restoration. Refcount tests cover overflow/underflow
saturation, concurrent final release, and acquire/release publication.
Source-import tests cover modification, manifest tampering and archive path
traversal.
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
exit with status 1. The current result is **1/269** translation units passing.
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
3. Remaining lock/wait variants (including wound/wait mutexes and I/O waits),
   CPU-bound/priority/freezable/reclaim workqueues, remaining system queues,
   RCU work, remaining timer modes,
   high-resolution timers and RCU lifetime
   rules.
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
