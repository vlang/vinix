# Linux i915 next-session handoff

Prepared 2026-10-02 for `/Users/alex/code/vinix`, on macOS ARM64 with zsh.
Committed implementation baseline: **`53e42f7e`** (including SRCU, wound/wait and keyed waits). Recheck HEAD and the worktree before
starting; other sessions use this checkout. The main status document is
[linux-i915.md](linux-i915.md).

## Copy this request into the next session

> Continue implementing the Linux kernel API compatibility layer in
> `/Users/alex/code/vinix` until the unchanged upstream Linux i915 driver works
> on my 11th Gen Intel Core i5-1135G7 / Tiger Lake machine. Read `AGENTS.md`,
> `docs/linux-i915.md` and `docs/linux-i915-handoff.md` first. Use lots of
> parallel agents across implementation, tests, subsystem research and
> independent lifetime review, within the available concurrency limit.
> Assign disjoint file ownership and coordinate shared integration centrally.
> Continue through the remaining synchronization, device, memory and DRM
> dependencies; bound and high-priority workqueues are already implemented. Keep upstream sources unchanged,
> implement real native semantics, measure retained allocations in isolated
> worktrees, test both architectures, and commit each completed change using
> only its own paths. Preserve other sessions' staged and unstaged edits.
> Do not report GPU support complete until full compile/link and real Tiger
> Lake hardware validation pass. Continue independently where hardware access
> or the exact PCI identity is still pending.

The user's earlier instruction was **“continue until complete.”** They then
requested this summary with many parallel agents. This handoff documents
continuation work; it does not declare the graphics implementation finished.

## What works and what does not

Vinix's Linux userspace ABI does not supply Linux's internal kernel driver
APIs. This project is building those APIs on Vinix, keeping the imported
driver intact. The compatibility runtime is opt-in with `LINUXKPI=1`, currently
x86-64 only. Default x86-64 and arm64 kernels leave it disabled.

**There is no working native i915 GPU driver yet.** The complete driver does
not compile, link or bind; the firmware framebuffer remains the display
backend. The latest full syntax audit passes **1/269** i915 translation units.
The already-linked `i915_memcpy.c` is a CPU WC-copy helper, not GPU bringup.
Unrelated OpenGothic/Venus/KekVM commits are not evidence of native i915 support.

Initial target: Tiger Lake-LP GT2. The current read-only PCI identity filter
is **`8086:9a49`**, still unconfirmed on the user's machine. The CPU model alone
does not establish the GPU PCI ID. A previous optional question remains
unanswered: obtain `lspci -nn -s 00:02.0` from that machine and identify a
Vinix hardware test setup or isolated GPU passthrough setup. QEMU VGA cannot
validate i915. Keep coding and testing the compatibility runtime while that
information is pending; final hardware completion depends on it.

Bound and high-priority queues are now implemented and committed. The earlier
final-ELF artifact gap was closed by fresh normal/SSE guest runs using the
handoff's rebuilt ELF. Ten distinct agents contributed in waves, within the
four-active-agent limit including root. SRCU is now committed and tested in
fresh normal/SSE guests. Native Wait-Die/Wound-Wait mutexes are also committed
and tested. Bit/variable waits are also committed and tested in fresh native
normal/SSE guests. Genuine scheduler I/O-wait accounting is the next feature;
inspect HEAD and owned diffs before assuming its implementation.

## Committed progress

| Commit | Completed runtime change |
| --- | --- |
| `53e42f7e` | Allocation-free keyed bit/variable waits, exclusive bit locks, absolute deadlines and stack cancellation |
| `a554fb3d` | Native stamped Wait-Die and Wound-Wait mutexes, backoff/slow retry and signal cancellation |
| `bfbb99a6` | Native SRCU readers, persistent grace periods, callbacks/barriers and teardown |
| `30ac90ae` | Timer self-test failure diagnostics and finite scheduler-tolerant watchdog |
| `06410c39` | Allocation gate rejects missing reports and checks both architectures even with populated objects |
| `19789348` | Native multiword bitmap operations, conversions and checked allocation |
| `da886cde` | CPU-bound and high-priority workqueues, default/high-priority system queues, affinity-aware wakeups and checked worker constructors |
| `de5db8a3` | Concurrent unbound workqueues, active limits, `system_unbound_wq`, manager/worker teardown |
| `5ca6734d` | Native delayed work, timer transfer, cancellation and flush semantics |
| `ef29dedd` | Native ordered workqueues and worker lifetimes |
| `c98871d1` | Native timer callbacks, deletion and shutdown |
| `8d7ef0a5` | Monotonic clocks, jiffies, delays and timed waits |
| `bbc5dfe9` | Sleeping mutexes, ordinary/simple wait queues and completions |
| `886b313d` | Linux task waits and safe native thread retention |

Earlier commits provide integer/compiler/error/overflow helpers; upstream
list/tree/sort algorithms; atomics, refcounts and krefs; memory barriers;
spin/raw locks with nested IRQ restoration and preemption pins; strings,
bitmaps and endian helpers; static/dynamic per-CPU storage; native `current`
and task queries; checked page-backed allocation; CPUID/FPU/WC-copy support;
and the read-only target identity check. See the status document for the
exact implemented subset and unsupported cases.

Ordinary mutex waiters and task/queue/completion timeout records live on
the waiting task's stack. Cancellation and expiry detach records under the
same lock before the stack frame returns. Task references retain native
Threads through exit, with deferred reclamation after switching off their
stacks. The arm64 reaper still keeps the most recent corpse per CPU until
the next exit on that CPU. Do not generalize x86 reclamation guarantees to it.

Clocks use HPET or calibrated TSC and PIT ticks at `HZ=1000`; raw and monotonic
agree without NTP discipline. High-resolution timers, realtime/TAI offsets,
`usleep_range`, Linux IRQ/NMI/softirq accounting and SMP dispatch remain pending.
The allocator uses contiguous physical pages even for small objects; limited
GFP semantics are enforced rather than pretending unsupported zones work.

## Upstream import contract

Pin: **Linux 6.6.157**, archive
`https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.6.157.tar.xz`.

```text
archive SHA256:
b74a43d0630809b7871cc906ac155e956cbc0b2e78a7451f5e6c8bfcb1208c30
manifest SHA256:
973e6873ba669336d7ec89cb5df6d4d30dd52e927a424213ee53fe868e2af26f
```

`kernel/linuxkpi/upstream.json` is authoritative. The ignored source tree is
`third_party/linux-i915/linux-6.6.157`; **7,668 files** were verified unchanged.
The archive is alongside it. Imported directories include i915, Linux headers,
libraries, x86 headers and licenses. Case-conflicting netfilter headers are
excluded for macOS. Verification rejects changed, added, missing or symlinked
files and manifest tampering. Keep overlays and native backends outside that
tree; do not patch the driver or fill dependencies with fake-success stubs.

Linked original files currently include `list_sort.c`, `sort.c`, `rbtree.c`,
`find_bit.c`, `hweight.c` and `i915_memcpy.c`. Additional exact-version kernel
reference sources were extracted outside the verified tree at
`/tmp/vinix-linuxkpi-runtime-reference/`, including workqueue/timer/wait/time
code. If that temporary directory disappears, read or extract the pinned
archive into another separate reference directory, never into the import.

## Runtime invariants to preserve

### Workqueues and worker ownership

- Original Linux `work_struct`, `delayed_work` layouts and initialization
  macros are used. Native per-CPU pool objects are aligned to 256 bytes so their pointers
  can be encoded in `work.data`; each pool retains its public queue owner. `PENDING|PWQ` means queued; `INACTIVE` also
  means a delayed timer reservation. Do not change upstream layouts.
- Explicit `alloc_ordered_workqueue(..., 0)` has one FIFO worker. Concurrent
  `alloc_workqueue(..., WQ_UNBOUND, max_active)` supports limits 1 through 512,
  with zero selecting 256. Unbound queues use one affinity domain; bound queues enforce limits per CPU.
- Unordered queues with `max_active > 1` have a manager that creates workers
  with interrupts enabled, outside `work_lock`. Ordered and single-active unbound
  queues need only one worker. Bound pools create workers lazily. Enqueue and delayed-arm paths allocate nothing
  and can run with interrupts disabled. Workers stay until destruction, so
  an unbound queue retains its peak worker count during its lifetime.
- Each `native_worker` owns a pthread, retained task and ready completion.
  Destruction drains, stops workers, removes the queue, **joins the manager
  before traversing its final worker list**, then joins/releases every worker.
  The manager can publish a just-created worker during destruction. Preserve
  this ordering and test partial construction/OOM rollback.
- `system_wq`, `system_highpri_wq` and `system_unbound_wq` are initialized
  together at boot, with all-or-nothing rollback. Warm their peak before
  measuring temporary retained allocations.
- A work item never overlaps itself, including migration across queues.
  A migrated pending item blocked by an old callback cannot prevent later
  independent work from running. Completion wakes workers on all queues.
- Callbacks may sleep, requeue or free their detached object. Dispatch uses
  a separate stack running record and **never dereferences the work item
  after its callback**. Keep pointer-only bookkeeping separate from object
  reads, including cancellation and marker completion.
- External producers and concurrent API users must stop before object/queue
  destruction. The queue stays alive throughout cancellation and flushing.
  Drain accepts chaining only from callbacks on that same owning queue.

### Flush snapshots and cancellation

- Flush markers are independent stack records in the pending list. They
  never execute callbacks and never consume active slots. Each queue flusher
  captures a generation at its call boundary, increments the queue generation,
  and waits for its marker plus every running item from that generation or
  earlier. Dispatch derives the running generation from pending-list position
  relative to live queue markers, even when old work starts after newer work.
- Concurrent workers skip markers and blocked migrated items. Each flusher
  removes its own marker under `work_lock` before its stack frame expires.
  Item flush markers capture the detached target's dispatch sequence under
  the same lock; an earlier running copy on another queue is waited separately.
- Do not serialize whole flush waits with a `flush_mutex`: that moves a
  later caller's snapshot and can include work submitted after it began.
  Do not use executable FIFO barriers on concurrent queues: they miss older
  running jobs and consume slots needed by dependencies. Both approaches
  were rejected. Host tests cover **20 overlapping flushers**.
- Synchronous cancellation links a stack guard before waiting, suppresses
  callback self-requeue, and detaches the guard under the lock before return.
  Waiting on one's own callback, or flushing/draining one's own queue of
  any type, fails explicitly. Nested item flush on a concurrent queue requires
  sufficient active capacity to make progress.
- `workqueue_struct` has unusually strong alignment. Iterate `all_queues`
  with `list_for_each` and apply `list_entry` only to actual entries. Casting
  its sentinel to a fake aligned queue via `list_for_each_entry` triggered
  UBSan; do not reintroduce it.

### Timers and delayed work

- Original `timer_list` macros/layout are retained. One permanent worker
  dispatches PIT-promoted timers. Callbacks cannot sleep and run with
  preemption disabled; IRQSAFE callbacks also disable interrupts. Per-CPU,
  pinned, deferrable, NOHZ and hotplug modes remain unsupported.
- Timers never overlap their own callbacks. Self-rearm and self-free are
  supported using separate stack running records; dispatch never reads a
  timer after calling it. Synchronous shutdown/deletion waits for execution,
  and callers must stop external producers before freeing the enclosing object.
  Shutdown prevents rearming until explicit reinitialization. Rearming at or
  before current jiffies waits for another tick. Synchronous deletion must
  avoid locks needed by the callback and requires enabled IRQs for ordinary
  timers; self synchronous deletion fails explicitly.
- Delayed reservations use the work item's existing list/data fields, with
  no allocation on arm. Lock order is **`work_lock` then `timer_lock`**.
  Timer dispatch drops `timer_lock` before transfer takes `work_lock`.
- In-flight timer-transfer retries release `work_lock` first, including
  IRQ-off modification and cancellation. Never call blocking timer deletion
  while holding the work lock. Synchronous delayed cancellation establishes
  its requeue guard before waiting for timer and work execution.
- `flush_delayed_work` promotes only its captured reservation and preserves
  a later self-rearm. A blocking timer delete after taking the flush snapshot
  can cancel that new reservation and strand its metadata; do not do this.
- Queue flush/drain ignores unexpired delayed reservations. Owners must
  cancel delayed work before destroying its queue; outstanding reservations
  trip an explicit failure. Timer transfer never accesses `dwork` after
  releasing `work_lock`, because a worker may already have freed it.
- A pointer-only timer running record can retire slightly after a promoted
  work callback finishes on another CPU. Native tests allow a bounded
  500-tick wait before asserting the timer-active count is zero.

### SRCU lifetime contracts

- Keep the original Linux `srcu_struct`, `srcu_usage`, `srcu_data` and static
  initializers. Static readers can enter before updater initialization; never
  reset their counters, replace their storage or reset `srcu_idx` lazily.
- Reader lock/unlock paths allocate nothing and pin only the counter update.
  Readers may sleep/migrate. Quiescence sums every CPU's unlock counts first,
  then a full barrier and lock counts; per-CPU subtraction is incorrect.
- A private boot unbound queue owns two independent embedded work items:
  `sup->work` is the delayed GP updater, CPU 0's `sdp->work` dispatches callbacks.
  Failed reader scans persist their phase, rearm one tick and return the active
  slot. A held callback cannot block independent GP/cookie progress. Sharing
  a saturated public/system queue would deadlock synchronous callers.
- GP cookies use Linux's two-bit sequence and full-period snapshot rules.
  Callback registration/ready/completed counts remain independent of GP
  completion. Pop/copy the next pointer and callback function before invoking;
  never read a head after its callback, which may free or requeue it.
- Barrier snapshots occur under the usage lock before taking the waiter mutex.
  Count a callback completed only after its function returns. Empty barriers
  do not request a GP; later submissions must not move earlier callers' boundaries.
- Owners stop readers/producers/API users before cleanup. Finish a full GP and
  callback barrier, synchronously cancel delayed GP activity, then flush/cancel
  callback work before freeing per-CPU data or usage. Static cleanup is forbidden.
- Ordinary RCU, NMI-safe and context-independent down/up SRCU remain unresolved.
  Do not treat explicit SRCU counters as ordinary RCU implicit read protection.

### Wound/wait lifetime contracts

- Preserve the original `ww_mutex.h` layouts and context stamps. The eventual
  dma-resv core owns `reservation_ww_class` and uses Wait-Die; do not synthesize
  its remaining fence/reservation runtime in this primitive backend.
- Every owner/list/context publication uses `base.wait_lock`. Stack waiters
  detach before returning, and handoff copies task/context before detaching,
  installs the new context/count/owner before wake, then never reads the record.
- Acquired counts and wounds use atomics because different locks can expose
  the same context. Context/task storage stays alive through every lock/wait.
  Use WW APIs for all accesses, including context-free users of that object.
- First-lock contexts neither die nor wound an owner. A free lock or assigned
  handoff wins cancellation/wounding; slow backoff retains its original stamp.
  Blocking same-context acquisition returns EALREADY; contended trylock is zero.

### Bit/variable wait lifetime contracts

- The static 256-bucket table has boot lifetime and serialized initialization;
  later initialization is idempotent and never resets active queues.
- Complete address/index keys distinguish collisions, multiword bit indices
  and the variable sentinel. Typed bit wakes read a live bit word only after
  matching. Variable hashing/matching never reads its opaque address.
- Display reset places ordinary entries directly on a bit bucket and wakes
  them when the bit becomes set. Do not globally suppress SET-bit dispatch.
- Stack records and producer keys stay synchronized by bucket traversal and
  native finish_wait, which always takes the queue lock before returning.
  Word and actual condition storage must remain alive through all users;
  a retired variable address may remain only as an opaque key.
- Absolute timeout boundaries do not move after spurious wakes. An available
  lock bit wins an action error/signal after cancellation, matching upstream.
- Wait/wake paths allocate nothing. I/O-wait actions remain unresolved until
  real scheduler accounting is integrated; there is no schedule alias stub.

### Ordinary RCU prerequisites

Explicit SRCU counters do not cover ordinary RCU's implicit IRQ-off, preemption
or BH read regions. Accurate context tracking requires real native interrupt
entry/exit, scheduler/idle paths that bypass the common exit, and softirq/BH
exclusion/dispatch. Current x86 NMI entry also needs paranoid GS and stack
handling: an NMI can arrive during ring-0 windows with user GS or a released
old Thread. A counter hook on the current ordinary thunk would be unsafe.
Do not resolve in_nmi/local_bh/ordinary RCU with constant or explicit-reader-only
stubs. Read-only next-step design is in
`/tmp/vinix-linuxkpi-context-design.md`, with pinned entry reference paths.

## Bound and high-priority contracts

- Bound support explicitly requires at most 64 online CPUs, matching native
  affinity masks. Default routing captures the calling CPU while pinned;
  explicit `_on` routing rejects invalid CPUs. Delayed reservations retain
  their selected CPU. Requeueing a running item on the same public queue
  preserves its original execution pool.
- Active callbacks stay counted while sleeping. Separate scheduler runnable
  accounting spans public queue owners on each CPU and priority domain.
  Sleep/wake transitions come from actual native scheduling boundaries.
- Public queue generations and pending lists cover every pool together, so a
  queue flush snapshots all CPUs under one lock. Per-pool sequential flushing
  would move the boundary and remains incorrect.
- Workers bind themselves before readiness publication. Affinity-aware idle
  wake selection and explicit target wakes prevent sleeping target CPUs from
  stranding work. Native checks verify placement after sleep and yield.
- `WQ_HIGHPRI` uses a per-thread nice override of -20 without changing the
  shared kernel process. Vinix's native linear nice weights increase its
  ordinary scheduling quantum; this is not Linux's exact CFS weighting.
- Checked constructors roll back stack, FPU and Thread allocations before
  publication. Partial manager/worker failure and destruction are tested.
- Hotplug, freezer/reclaim/rescuers, CPU-intensive/sysfs/attribute modes and
  RCU work remain unsupported. Additional system queues remain unresolved.

## Parallel-agent execution

There are four active slots including root. Use three workers continuously
and recycle completed tasks across implementation, host tests, native tests,
research and independent review. Ten distinct agents have contributed to the
current milestones; this does not mean ten were simultaneously active.

Root owns shared bridge/header/build/harness integration and commits.
Assign each backend and each new test file to one owner. Freeze ABI contracts
before dependent edits, and keep reviewers independent of implementation.
Every architecture build needs its own writable objects and compiler cache.
Do not commit fragments without functioning integration and actual tests.

### Later waves: subsystem teams

| Area | Good independent agent tasks | Integration dependency |
| --- | --- | --- |
| Synchronization | RCU/SRCU grace periods, wound/wait mutexes, context accounting, SMP calls | Scheduler/task and reclamation contracts |
| Devices | PCI/config/devres, firmware/ACPI, IRQ lifecycle | Native device and interrupt ownership |
| Memory | DMA/SG, page/shmem, MMIO cache attributes, GPU VM/TTM/GEM | Native paging, physical memory and lifetime contracts |
| DRM | C DRM core import/build closure, device/file/ioctl/mmap, fence/syncobj/dma-buf | Memory/device interfaces and userspace ABI |
| Validation | Audit/link inventory, host race tests, native leak measurement, hardware test plan | Tested exact source revision |

These are research and implementation streams, not permission to edit shared
headers simultaneously. Root should maintain one dependency inventory,
freeze small ABI contracts, allocate disjoint files, and rotate independent
reviewers through completed changes. Compile-only helpers cannot stand in for
runtime implementations. Keep working after each milestone toward the original
driver goal rather than stopping after a plan or an improved audit count.

## Files to read first

| Path | Purpose |
| --- | --- |
| `docs/linux-i915.md` | Truthful current support/limitations and tests |
| `kernel/c/linuxkpi_workqueue.c` | Ordered, delayed and concurrent unbound implementation plus native tests |
| `kernel/c/linuxkpi_{srcu,timer,time,sync,task,percpu}.c` | Native runtime backends |
| `kernel/linuxkpi/bridge_amd64.v` | Native V exports, initialization and measured guest tests |
| `kernel/linuxkpi/include/vinix/runtime.h` | Internal bridge declarations |
| `kernel/linuxkpi/include/linux/`, `include/asm/` | Compatibility overlays; many remaining headers stay upstream |
| `kernel/linuxkpi/upstream.py`, `upstream.json` | Import verification and exact pin |
| `kernel/linuxkpi/audit.py` | Kbuild-derived complete i915 syntax audit |
| `kernel/GNUmakefile` | Opt-in flags, verification and upstream objects |
| `tests/linuxkpi/run.sh`, `test.c`, `host_types.h`, `*_test.h` | ASan/UBSan host runtime models/tests |
| `tests/linuxkpi/run_vm.py`, `guest_init.c` | Four-CPU native kernel and Linux-ABI PID 1 verification |
| `kernel/sched/{sched_amd64,policy}.v`, `kernel/proc/{proc,proc_amd64,proc_arm64}.v` | Affinity, worker scheduling, task/process ownership |
| `kernel/lib/stubs/pthread.v`, `kernel/c/pthread.h` | Kernel worker creation/join |

Adding a C backend requires native LinuxKPI compiler flags/config dependencies
in `GNUmakefile` and host source-list integration in `run.sh`. Keep those shared
edits with root. Ordinary kernel C uses GNU99 and currently emits upstream
duplicate-typedef warnings; host/audit use GNU11. Do not hide compiler errors
or rewrite upstream headers to make a false success.

## Validation already completed

Fresh continuation checks cover these committed changes:

| Check | Result and artifact |
| --- | --- |
| Strict host runtime/import tests | Clean ASan/UBSan; `/tmp/vinix-linuxkpi-bound-host-gatefixed.log`, `/tmp/vinix-linuxkpi-bitmap-integrated-host.log` |
| Enabled x86 builds | Pass; `/tmp/vinix-linuxkpi-bound-x86-build-final.log`, `/tmp/vinix-linuxkpi-bitmap-x86-build.log` |
| Disabled arm64 builds | Pass; `/tmp/vinix-linuxkpi-bound-arm-build-final.log`, `/tmp/vinix-linuxkpi-bitmap-arm-build.log` |
| Default x86 build/guest | Pass; `/tmp/vinix-linuxkpi-bitmap-default-build.log`, `/tmp/vinix-linuxkpi-bitmap-default-vm/serial.log` |
| Four-CPU enabled normal/SSE guests | Pass; `/tmp/vinix-linuxkpi-bitmap-vm/serial.log`, `/tmp/vinix-linuxkpi-bitmap-sse-vm/serial.log` |
| Optional XNU allocator build/guest | Pass; `/tmp/vinix-linuxkpi-bound-xnu-build.log`, `/tmp/vinix-linuxkpi-bound-xnu-vm/serial.log` |
| Full i915 syntax audit | Expected exit 1, still **1/269** |
| Import verification | **7,668** unchanged pinned files |

The enabled bitmap ELF used by both normal/SSE guests is
`/tmp/vinix-linuxkpi-bitmap-enabled.elf`, SHA256
`69abc50a0752aee53a3a0e9594f0baa3573d74c6caab7f0fd108f98926d364e4`.
Both guest logs contain the bound/priority, worker-rollback and multiword
bitmap markers and exact per-feature physical-page recovery. The earlier
rebuilt unbound ELF also booted in fresh baseline normal/SSE guests at
`/tmp/vinix-linuxkpi-next-baseline-{vm,sse-vm}/serial.log`.

Independent reviews approved committed worker, scheduler, constructor,
bitmap, allocation-check and SRCU lifetimes. SRCU final strict host tests pass
in `/tmp/vinix-linuxkpi-srcu-host-final.log`; fresh enabled x86 and disabled ARM
builds pass in `/tmp/vinix-linuxkpi-srcu-{x86,arm}-build-tested.log`. Final normal
and SSE guests pass in `/tmp/vinix-linuxkpi-srcu-final-{vm,sse-vm}/serial.log`,
including the new SRCU marker and exact page recovery. Default x86 startup
passes in `/tmp/vinix-linuxkpi-srcu-default-vm/serial.log`. The final enabled ELF
is `/tmp/vinix-linuxkpi-srcu-enabled-final.elf`, SHA256
`7942f62276e324036df6e4f6655cd063271ade00ecf52faa62f14bafae16f824`.

Initial enabled SRCU guests intermittently failed the old timer self-test
watchdog before SRCU ran. Diagnostic records established timeout/incomplete
call count with no callback context/ordering violation, at 100–140 elapsed
ticks. The committed timer test now permits 500 ticks, retains every correctness
check and prints fixed-stack failure records after shutdown/join. Final guests
above use that exact source. Failed logs remain as evidence, including
`/tmp/vinix-linuxkpi-srcu-timer-diagnostic-sse-vm/serial.log`; do not count them
as successful boots.

Wound/wait strict host tests pass at `/tmp/vinix-linuxkpi-ww-host-final.log`.
Fresh x86 enabled, ARM disabled and x86 default builds pass at
`/tmp/vinix-linuxkpi-ww-{x86,arm,default}-build.log`. Four-CPU normal/SSE/default
guests pass at `/tmp/vinix-linuxkpi-ww-{vm,sse-vm,default-vm}/serial.log`; both
enabled guests include the wound/wait marker and exact page recovery.
The tested enabled ELF `/tmp/vinix-linuxkpi-ww-enabled.elf` has SHA256
`159a6a7c8d25acfac902aa401a1e505ec1caf44f9ebe84a965a5a8baa1e4c5fb`.
Independent backend/host/native lifetime reviews approved; generated measured
V code uses scalar locals and adds no hidden allocation. Its fresh allocation
gate `/tmp/vinix-linuxkpi-ww-alloc.log` matches every existing failure group;
comparison is `/tmp/vinix-linuxkpi-ww-alloc-comparison.json`. The syntax audit
still passes 1/269; complete driver linking and hardware remain pending.

Bit/variable-wait strict host tests pass at
`/tmp/vinix-linuxkpi-waitbit-host-review.log`. Fresh enabled x86, disabled ARM
and default x86 builds pass at `/tmp/vinix-linuxkpi-waitbit-{x86,arm,default}-build.log`.
Fresh normal/SSE/default guests pass at
`/tmp/vinix-linuxkpi-waitbit-{vm,sse-vm,default-vm}/serial.log`; both enabled
runs contain the new keyed-wait marker and exact page recovery. Both use
`/tmp/vinix-linuxkpi-waitbit-enabled.elf`, SHA256
`a7a244136d74992bcb6fbd69d68af085a93125e4ea3c9924dbbdfdeabebf6a19`.
Independent backend/host/native reviews approved. Fresh allocation results
match every baseline group at `/tmp/vinix-linuxkpi-waitbit-alloc-comparison.json`;
new generated V C contains only scalar measurement locals and direct calls
(`/tmp/vinix-linuxkpi-waitbit-generatedc-snippet.c`). The audit remains 1/269,
and import verification again checks all 7,668 unchanged files.

The corrected allocation gate reports the same baseline and feature results:
ARM **293 source files / 361 sites**, x86 **224 files / 253 sites**, combined
**425 unique sites / 182 file-kind groups / 155 pre-existing failures**.
Fresh and populated architecture object directories give identical results.
Missing make output and compiler reports now fail explicitly. Evidence:
`/tmp/vinix-linuxkpi-bound-alloc-fixed-{fresh,populated-arm,populated-x86}.log`.
The fresh SRCU overlay matches every count and failure group as well:
`/tmp/vinix-linuxkpi-srcu-alloc.log` and
`/tmp/vinix-linuxkpi-srcu-alloc-comparison.json`. Generated x86/ARM constructors
initialize the caller-local allocation-failure field to -1, and its successful
allocator bridge path adds no hidden V allocation. Do not change `allowed.txt`
to hide these baseline failures.

Broader required ARM ops/churn/cache and desktop idle/apps/drag workloads
completed without panic, then were repeated against the isolated SRCU-source
ARM build. Both repeat harnesses exited zero with their completion markers;
70 syscall reports matched the earlier retained-allocation measurements within
3 bytes per operation. Existing large readdir, proc listing/reads and program
churn allocations remain. Cache measurements also match the earlier run.
These guests use LinuxKPI disabled and one online CPU; they do not execute SRCU,
wound/wait or bit-wait code. The repeat boot disks contain the measured ELF
SHA256 `16343fd6ce1269aa2706fcda4e295cae0e51093d227df39ee4fbe5ec38af8d91`,
and source, generated C and ELF remained unchanged through both runs.

Repeat logs are `/tmp/vinix-linuxkpi-srcu-perf-ops-churn-cache.log` and
`/tmp/vinix-linuxkpi-srcu-perf-idle-apps-drag.log`; metadata and parsed retained
results are `/tmp/vinix-linuxkpi-srcu-perf-validation.json` and
`/tmp/vinix-linuxkpi-srcu-perf-retained-summary.json`. Desktop idle/apps/drag
physical usage was 65.4/150.3/108.8 MiB. Single samples, concurrent host load
and differing session binaries do not establish a causal performance change.
Earlier logs remain `/tmp/vinix-linuxkpi-bound-perf-ops-churn-cache-rerun.log`,
`/tmp/vinix-linuxkpi-bound-perf-idle-apps-drag.log` and
`/tmp/vinix-linuxkpi-bound-perf-retained-summary.json`. Do not claim the whole
kernel is leak-free; per-feature page recovery is a separate measured result.

## Repeatable commands and build isolation

From the repository root:

```sh
UBSAN_OPTIONS=halt_on_error=1 tests/linuxkpi/run.sh
python3 kernel/linuxkpi/upstream.py verify
python3 kernel/linuxkpi/audit.py --jobs 4
```

Create **separate fresh detached worktrees per architecture** at a known
committed baseline with `git worktree add --detach`. Copy only this feature's
uncommitted overlay if testing before commit. Touch copied sources after
`copy2`: preserved timestamps previously left stale `obj/blob.c` tests.
Do not share writable `obj`, `bin` or compiler runtime caches between builds.
Changing architectures in the same object directory is unsafe; the config
stamp does not rebuild every generic C object for an architecture change.

Symlink only ignored, read-only dependencies from the main checkout:

```text
kernel/cc-runtime
kernel/freestnd-c-hdrs
kernel/lwip-repository
kernel/uacpi-repository
kernel/c/flanterm
kernel/c/lwip
kernel/c/uacpi
kernel/c/nanoprintf.h
kernel/c/nanoprintf_orig.h
```

Do not run `get-deps` through shared dependency repository symlinks: it can
reset and clean those repositories. Pass compiler/tool settings as make
arguments as shown; makefile assignments may override environment settings.

**Copy**, rather than symlink, an architecture's compiled `cc-runtime-x86_64`
or `cc-runtime-aarch64` cache when reusing one. Do not symlink all of the
tracked `kernel/c` directory. Point LinuxKPI at the verified import separately.

```sh
make -C <x86-worktree>/kernel -j8 ARCH=x86_64 CC=clang \
  AR=/opt/homebrew/opt/llvm/bin/llvm-ar \
  LD_X86_64=/opt/homebrew/bin/ld.lld V=/Users/alex/code/v/v \
  LINUXKPI=1 \
  LINUXKPI_SOURCE_DIR=/Users/alex/code/vinix/third_party/linux-i915/linux-6.6.157 \
  PROD=false

make -C <arm-worktree>/kernel -j8 ARCH=aarch64 CC=clang \
  AR=/opt/homebrew/opt/llvm/bin/llvm-ar \
  LD_AARCH64=/opt/homebrew/bin/ld.lld V=/Users/alex/code/v/v \
  LINUXKPI=0 PROD=false
```

Replace angle-bracket placeholders before execution. For default x86, use
the x86 command with `LINUXKPI=0`. Switching enabled/default within one x86
worktree is supported, but save the enabled ELF first.

```sh
python3 tests/linuxkpi/run_vm.py --kernel <enabled.elf> \
  --state-dir /tmp/vinix-linuxkpi-next-vm
python3 tests/linuxkpi/run_vm.py --kernel <enabled.elf> \
  --state-dir /tmp/vinix-linuxkpi-next-sse-vm --cpu max,hypervisor=off
python3 tests/linuxkpi/run_vm.py --kernel <default.elf> \
  --state-dir /tmp/vinix-linuxkpi-next-default-vm --no-linuxkpi
```

Each state directory must be new. The harness owns its guest/disk, uses TCG,
four CPUs, q35 and 512 MB, and has a 90-second default timeout. Use `PROD=false`
for serial markers; do not kill other sessions' guests. The second enabled
run clears CPUID's hypervisor flag to exercise original i915 SSE4.1 code;
neither run tests actual GPU WC memory, rendering or display.

Existing temporary artifacts are convenient references, not clean worktrees:

- `/tmp/vinix-linuxkpi-unbound-worktree`: detached at `5ca6734d`, with final
  unbound sources copied/touched and currently enabled after the final rebuild.
- `/tmp/vinix-linuxkpi-unbound-arm-worktree`: detached at `5ca6734d`, arm64
  disabled build with the corresponding copied source.
- `/tmp/vinix-linuxkpi-unbound-enabled.elf`: kernel used by the recorded guest
  runs; the subsequent source change was host-test-only.
- `/tmp/vinix-linuxkpi-unbound-enabled-final.elf`: saved final-source rebuild.
- Earlier `*-delayed-*`, `*-workqueue-*` and `*-timer-*` worktrees contain older
  milestones. Start fresh for new changes; never infer exact source from their
  detached HEAD alone.

The earlier handoff's read-only verification found that both unbound worktrees' tracked
kernel sources match `de5db8a3`, although their detached HEADs are older and
three implementation files are locally modified. Their docs/test harnesses
are older. Use current root test scripts against an explicitly chosen kernel.

For kernel lifetime changes follow `AGENTS.md`: measure repeated operations,
inspect generated C for hidden V allocation, use allocation-site tracking when
needed, build both architectures, and obtain independent lifetime review
before committing. Broader syscall/desktop allocation checks are documented
there; preserve known baselines and clearly scope feature-specific evidence.

## Remaining path to completion

1. Remaining synchronization (ordinary RCU and I/O waits), SMP/context,
   additional system workqueues and timer interfaces.
2. Linux device/PCI registration/configuration/removal and devres ownership.
3. MMIO cache attributes, DMA/SG, page/shmem, GPU address spaces and TTM/GEM.
4. IRQ registration/synchronization and safe reset/recovery paths.
5. C DRM integration: device/file lifecycle, ioctl/mmap, fences, sync objects
   and dma-buf. Existing V DRM interfaces do not supply Linux C DRM internals.
6. Firmware, ACPI OpRegion, power management and display/KMS services.
7. Compile and link all required unchanged driver/core objects with no fake
   unresolved-symbol substitutes; bind only the confirmed target device.
8. Boot physical Tiger Lake or a suitable passthrough setup. Validate command
   submission, display handoff, reset, repeated process teardown and Alpine
   Mesa/libdrm operation. Measure memory and concurrency behavior under load.

Completion requires those hardware results, not a larger compatibility header
set or an improved syntax count. Keep status documentation explicit until then.

## Preserve the shared checkout

At handoff the LinuxKPI implementation was clean and committed. Other sessions
had staged/unstaged desktop/build-script changes, Disk Usage renames and image
assets, OBS/Xorg support edits, `kernel/event/event.v`, an arm64 syscall test,
Wine files, logs and untracked screenshots/scripts. This list is only a
snapshot: inspect current status before every edit or commit.

Never stage the entire repository or reset/stash/checkout someone else's
changes. Read each owned file's diff and commit only explicit owned paths
(`git commit -- <paths>`). Serialize commit operations across agents. No push
was requested for this work. The repository's desktop post-commit hook applies
to relevant app changes; this driver project does not authorize modifying or
publishing unrelated desktop work.
