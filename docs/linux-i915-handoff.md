# Linux i915 next-session handoff

Updated 2026-10-15 for `/Users/alex/code/vinix`, on macOS ARM64 with zsh.
Latest priority-worker build baseline: **`219a33d6f`**, with the two frozen native inputs described below. Recheck HEAD and the worktree before
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
backend. The latest full syntax audit passes **6/269** i915 translation units.
The already-linked `i915_memcpy.c` is a CPU WC-copy helper, not GPU bringup.
Unrelated OpenGothic/Venus/KekVM commits are not evidence of native i915 support.

Initial target: Tiger Lake-LP GT2. The current read-only PCI identity filter
is **`8086:9a49`**, still unconfirmed on the user's machine. The CPU model alone
does not establish the GPU PCI ID. A previous optional question remains
unanswered: obtain `lspci -nn -s 00:02.0` from that machine and identify a
Vinix hardware test setup or isolated GPU passthrough setup. QEMU VGA cannot
validate i915. Keep coding and testing the compatibility runtime while that
information is pending; final hardware completion depends on it.

Ordinary native SMP calls and interrupt-aware workqueue identity are now implemented and validated. Bound and high-priority queues are implemented and committed. The earlier
final-ELF artifact gap was closed by fresh normal/SSE guest runs using the
handoff's rebuilt ELF. Ten distinct agents contributed in waves, within the
four-active-agent limit including root. SRCU is now committed and tested in
fresh normal/SSE guests. Native Wait-Die/Wound-Wait mutexes are also committed
and tested. Bit/variable waits are also committed and tested in fresh native
normal/SSE guests. Genuine scheduler I/O-wait accounting is also committed.
Plain native object caches and the integer/DRM helper include fixes are also
committed and validated. The allocation harness now rejects incomplete
reports. Task-owned flags and original sequence counters are now committed
and validated. Owned printk records, the inventoried Linux formatting subset,
warning/taint capture and synchronized native RNG publication are also committed
and validated. Device-number types, unchanged i915 timeout/DSC policy helpers,
I/O mutex scopes, precise timed-worker retirement and allocation-free string
matching/replacement, minimum-duration sleeps, kernel-string number/Boolean
parsers and borrowed token/whitespace helpers are committed and validated.
Shared native PCI configuration transactions are committed and tested on
actual x86 CF8/CFC and ARM ECAM transports. Linux PCI device registration,
bus/device references and GPU binding remain unresolved. Ordinary user-copy
remaining counts, zero-tail semantics and bounded user-string parsers are now
implemented, together with ordinary scalar reads and checked serialized x86
transfers. Ordinary scalar stores, task-local fault-control nesting and resident-only
atomic copies are implemented and validated. Checked user-write scopes and
original page-table/UAPI type representations are committed. Resident
non-temporal user copies are also implemented and validated; complete normal/SSE
guests recover every measured page and live heap object. Actual GPU WC mapping
and kernel destination fixups remain pending. The current native
`RangePageSource` already pins backing storage
and rechecks mapping identity after unlocked acquisition; the earlier proposed
global fault-lease rewrite was not applied.

Ordinary RCU, deferred page-backed frees, native IRQ work and the DMA-fence
synchronization core are implemented and validated. The latest normal/SSE/
four-level guests pass 54 markers and 36 strict allocation equalities.
Fence containers, reservation ownership and unchanged i915 software fences are
implemented and validated. Original boot-CPU L1TF queries are also implemented
and validated, with native positive-MSR execution still pending. Task-owned migration pins now preserve CPU identity through sleep and yield; final validation is recorded below. Continue through the remaining task/MM, device,
memory and DRM services; complete i915 support is still pending.

## Committed progress

| Commit | Completed runtime change |
| --- | --- |
| `219a33d6f` | Task-owned migration pins across sleep/yield, post-lock eligibility and coherent affinity release snapshots |
| `6896a6ea9` | Original slab flag typedef ownership, with unchanged allocator semantics |
| `d7b24c4bf` | Original boot-CPU L1TF query policy and observed native CPU classification |
| `156ef022a` | Unchanged i915 software fences, real dependency graphs and DMA timeout ownership |
| `59b1e9ac5` | Native DMA reservation producers, usage tags, writer ownership, RCU iteration and collection lifetimes |
| `321bb4c63` | DMA-fence arrays/chains, actual IRQ union reuse and deferred container release |
| `c136b3209` | Native DMA-fence synchronization core, callbacks, waits and RCU release |
| `beb571021` | Real maskable IRQ work, lazy PIT delivery, concurrent callback synchronization and measured teardown |
| `a97f0490` | Genuine page-backed `kvfree` and deferred RCU free, original embedded/headless macros and measured complete actor teardown |
| `1d0f5b00` | Native ordinary RCU callback/cookie service, real IRQ-return grace periods, fixed CPU-domain guards and V-only validation tools |
| `b718a737` | Original SMP/CSD/header integration, genuine CPU accessor bindings and compiler provenance; remote dispatch remains pending |
| `4052200b` | Immutable actual boot-CPU MOVDIRI/MOVDIR64B capability intersection and measured caller-state-preserving queries |
| `909f6a4b` | Original x86 instruction-helper include closure, unchanged MOVDIR operands/opcodes and genuine unresolved privileged references |
| `079e3ccd` | Native bounded PCI/CardBus topology, permanent scalar boot publication and read-only capability validation |
| `d6d62bcc` | Actual original CSD records/initializer compiler tests; SMP runtime remains unresolved |
| `e2641335` | Actual maskable IRQ entry/exit ownership, scheduler handoff guards and measured complete actor lifetimes |
| `24afa95c` | Exact original Kbuild mmiowb wrapper; original disabled tracking macros, no fabricated barrier |
| `770ba039` | Exact pinned Kbuild-generated early-ioremap and kmap-size wrappers with genuine unresolved mapping references |
| `e393312a` | Resident non-temporal user copies, exact page prefixes, completion fences and measured mapping lifetimes |
| `0e35bb9a` | Generic checked user-access scopes and `unsafe_put_user` cleanup control flow |
| `376b5d66` | Genuine typed static-key extern declarations, preserving existing boolean branches |
| `a88dcea7` | Original page-table/UAPI type representations and five-level-capable compiler profile |
| `dd1df42f` | Task-owned fault controls, disabled page-in/COW policy and exact resident-only copies |
| `f1d5860b` | Actual pinned bounds compiler generation, input provenance and native Make dependencies |
| `15c21a91` | Faulting scalar stores, split-page prefixes, real COW, aligned coherence and measured complete worker lifetimes |
| `3a38ab99` | Per-invocation optional integer-policy audit adapters with current/older-metadata regression tests |
| `c3ab77ea` | Fault-zero scalar reads, aligned read coherence and checked serialized x86 page-copy transfers |
| `96f768b6` | Per-invocation real generated ABI adapters in full-driver audits and cleanup/error regression tests |
| `d0a65f59` | Exact pinned integer type limits, overflow/cast predicates and independent boundary tests |
| `bb37a234` | Original page-offset integer representation, checked on x86 and ARM |
| `a070633d` | Original checked typed-user-pointer conversion and strict evaluation/type tests |
| `5148f857` | Exact user-copy remaining counts, raw/zero-tail semantics, object bounds and bounded user-string parsers |
| `b9e2f45f` | Shared checked PCI transactions, subword I/O, atomic sixteen-bit COMMAND updates and full ARM DAIF preservation |
| `71426a7e` | Borrowed character search, empty-preserving tokens and bounded equivalent whitespace trimming |
| `ce4606b3` | Pinned kernel-string integer/Boolean parsing, range errors and output ownership |
| `7735509f` | Absolute-minimum range sleeps, early-wake/signal retries and full native rollback/retirement tests |
| `53f41b30` | Pinned borrowed string matching, sysfs newline equivalence and replacement |
| `92c24841` | I/O mutex scopes, actual blocked-CPU counts and nested intent restoration |
| `176549b4` | Joined timed-worker off-stack and actual deferred-free retirement before measurement |
| `3943191d` | Original i915 timeout/DSC policy helpers and Linux device encodings |
| `ea87f353` | Owned printk ring/drain worker, Linux formatting/SipHash, warning/taints, RNG publication and scoped timed-wait fixture |
| `26f77f05` | Original sequence counters, native lock/retry/latch tests, compiler include contract and SRCU fixture routing |
| `55294618` | Sticky task-owned flags and native exit publication |
| `ddd1d9f4` | Packed native object caches, constructor/reuse semantics, atomic allocation, shrink and teardown |
| `e29bcc4d` | Original integer helpers and standalone unchanged DRM color LUT dependencies/tests |
| `e4c5ffc4` | Complete allocation/desktop report coverage, completion and console-drain verification |
| `57a5cc18` | Native I/O intent scopes, blocked-CPU accounting, bit-I/O actions and wake/migration/exit cleanup |
| `41bd6faf` | Workqueue failure reasons and opt-in worker/keyed-wait traces, preserving callback deadlines |
| `a15be8d3` | Host keyed-wait collisions selected across arbitrary address layouts |
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
Linux IRQ/NMI/softirq accounting and SMP dispatch remain pending. Minimum-duration
range sleeps now use absolute monotonic deadlines and the existing 1 ms PIT;
high-resolution timers and real/TAI/suspend offsets remain pending.
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
`find_bit.c`, `hweight.c`, `siphash.c` and `i915_memcpy.c`. Additional exact-version kernel
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
- NMI-safe and context-independent down/up SRCU remain unresolved.
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
- Wait/wake paths allocate nothing. Bit-I/O actions use real native scheduler
  accounting and preserve absolute timeout/signal results.

### I/O-wait accounting contracts

- `in_iowait` is a nested intent token, initialized to zero and preserved by
  task-view refresh. A new/inherited task does not inherit its parent's intent.
- Admission follows actual dequeue and accepted-signal filtering under the
  task wait lock with IRQs off. The native queue lock checks intent, dead and
  runnable state again. Ordinary waits skip the extra accounting lock.
- An origin CPU + 1 token and fixed boot counters are owned by native queue
  transitions. End it only after a runnable slot is guaranteed, or on permanent
  dead removal. Duplicate/failed/full wake attempts must not lose or double
  subtract it. Migration debits the stored blocking origin.
- Native accounting never acquires a Linux task lock while holding its queue
  lock. The task-intent getter performs only an atomic load. No stack record,
  task reference or allocation is added on the repeated blocking path.
- The native token fills Thread padding without moving any existing field;
  task intent fits the existing 64-byte view. Reaping requires the token zero.
- `mutex_lock_io` wraps ordinary FIFO acquisition in nested native I/O intent;
  its public wait is uninterruptible and `_nested` preserves non-lockdep alias
  semantics. Only actual scheduler blocking charges a CPU. Block plugs, delay
  statistics, idle-time accounting and CPU hotplug remain unresolved.

### Minimum-duration sleep contracts

- `usleep_range_state` captures one absolute monotonic minimum, keeps it through
  accepted wakes and signals, and restores TASK_RUNNING on every valid return.
  RUNNING/interruptible/uninterruptible/killable/idle are the supported states.
- Absolute records carry a mode tag; designated legacy timeout initialization
  leaves that tag false and preserves jiffy-based expiry. The arm-time clock
  recheck and every removal happen under the same deadline lock before stack
  reuse or return. The PIT compares actual nanoseconds for absolute records.
- Optional slack is zero. The existing 1 ms PIT promotes at/after the minimum,
  and scheduling may exceed max. This supplies no hrtimer/hrtimeout service.
  Reversed or unrepresentable ranges and unsupported states/atomic contexts
  fail explicitly. Malformed DSI firmware u32 delay+10 wrap is outside the
  supported domain; unchecked invalid-input equivalence is not claimed.
- Native cleanup opens every gate and joins through any already-started
  uninterruptible sleep's natural expiry. It inspects only retained workers'
  records, observes all off-stack handoffs before any final put, and waits
  through actual deferred frees under one shared retirement bound.

### Ordinary RCU contracts

Explicit SRCU counters do not cover ordinary RCU's implicit IRQ-off, preemption
or BH read regions. Native x86 maskable entry/exit and scheduler handoffs now
have real CPU-owned accounting; the final validation below covers actual
nested interrupts and task returns. Ordinary nonpreemptible RCU now uses actual
outer maskable returns. Linux's full context encoding and softirq/BH
exclusion/dispatch remain pending. Current x86 NMI entry also needs paranoid GS and stack
handling: an NMI can arrive during ring-0 windows with user GS or a released
old Thread. A counter hook on the current ordinary thunk would be unsafe.
Do not resolve in_nmi/local_bh with constant or explicit-reader-only
stubs. Read-only next-step design is in
`/tmp/vinix-linuxkpi-context-design.md`, with pinned entry reference paths.

- Keep the IRQ hook behind the native active gate, which is published only
  after the boot owner warms generated module initialization and both worker
  owners are ready. AP interrupt entry must never run lazy V initialization.
- The ordinary THUNK closes maskable depth while CLI/kernel GS and the original
  frame remain installed. Its saved RFLAGS is at `160(%rsp)`. Acknowledge only
  saved IF=1, zero pins and zero remaining depth. Never substitute handler IF,
  another CPU's state, a CSD completion or an explicit SRCU counter.
- GP request publication, CPU-owned acknowledgement and GP completion have
  full ordering. Real IPIs include the calling CPU and are reissued while a
  genuine implicit reader remains. The hook takes no locks and allocates nothing.
- GP and callback pthread owners are permanent and independent of workqueue
  active limits. Failed construction joins and waits for actual off-stack
  retirement before final task release and owner free.
- Capture original callback next/function before invocation and never read the
  head afterward. Callbacks are serial, IRQ-enabled and pinned; they may free
  or requeue their object. Complete the ordinal only after callback return.
- Barriers snapshot the enqueue ordinal under the lock at their call boundary,
  then wait without moving that boundary. Public cookie polling retains the
  exact original signed/wrap comparison, including its old-cookie guard band.
- `kfree_rcu`/`kvfree_rcu`, completed-cookie shortcuts, PREEMPT_RCU, task/NMI/BH
  RCU, hotplug and NOHZ remain unresolved. Native operation has a fixed boot
  CPU domain. Host 256-CPU coverage does not establish native 256-CPU operation.

## Shared PCI transport and next user-copy prerequisite

- Every live ordinary PCI device accessor and uACPI callback uses the native
  C core and the same platform lock. The synchronous result is borrowed and
  untouched on error; widths/BDF/full 64-bit offsets are validated before I/O.
  Native statuses must not alias Linux PCIBIOS statuses or Linux error-output
  semantics. Original `pci_dev`/`pci_bus` and device-core closure are pending.
- x86 exposes only conventional 256-byte CF8/CFC registers and actual subword
  port I/O. ARM exposes 4096-byte registers only inside its immutable checked
  zero-origin segment-zero ECAM window. ARM saves full DAIF, masks only I and
  emits STLR0, DSB ISHST, SEV before restoring every mask. No NMI/FIQ recursion
  is supported. Lock holders never allocate, sleep, log or map memory.
- COMMAND read/conditional-write uses 16 bits in one lock hold; adjacent STATUS
  RW1C is preserved. Existing BAR probes still require exclusive ownership and
  quiescence; transport serialization alone does not make them safe for i915.
- Final 18-path kernel overlay is `/tmp/vinix-linuxkpi-pci-config-overlay.json`,
  private build baseline `71426a7e`. Full host strict GNU99/GNU11 ASan/UBSan,
  import and header suite passed. Normal x86 passed all 33 markers. Default x86,
  default ARM and opt-in ARM context guests reached actual Linux-ABI PID1.
  Enabled ELF SHA256 is
  `9f76e1954c9188dcffae9035ee1f097d0957ae0947febc49c8371ae05d7ad475`.
  Detailed immutable artifact/review/evidence manifest is
  `/tmp/vinix-linuxkpi-pci-config-final-validation.json`.
- Both feature SSE guests passed the new PCI exact-page checks, then failed
  the unchanged bound self-free 500-tick watchdog. Pre-PCI `71426a7e` ELF reproduced
  the same bound failure in identical guest settings. All 16 callbacks finish
  through safe cleanup, but delayed progress has no established cause. Do not
  claim these as full SSE passes or change the deadline to hide the failures.
  Preserved logs: `/tmp/vinix-linuxkpi-pci-config-sse-vm/serial.log`,
  `/tmp/vinix-linuxkpi-pci-config-sse-diagnostic-vm/serial.log` and
  `/tmp/vinix-linuxkpi-pci-baseline-sse-vm/serial.log`.
- Native x86 actors read two real devices 896 times each across four bound CPUs,
  with IRQ-off/nested-pin/OOM calls and all 16 actual constructor rollback cases.
  Three warmups precede exact measured page recovery. ARM `PCI_CONFIG_TEST=1`
  checks typed actual ECAM identity reads and all 8 independent D/A/F vectors
  with I masked. Its default build leaves the fixture absent. New isolated
  harness is `tests/pci-config/arm_vm.py`; four configured CPUs do not prove
  ARM SMP, since context vectors execute on the controller.
- The shared V compiler changed during allocation scans. Fresh repeated
  baseline and final feature scans under compiler SHA256
  `62e783b877abd3688ddd54806d73e5fd9c51b2a5b4fe9b5780369ffbf7bfa77e`
  both retain 428 sites, 191 groups and 160 existing failure groups and exit 1. The initial
  411-site reports and pre-existing x86 V errors remain preserved. This is no
  global allocation pass: `/tmp/vinix-linuxkpi-pci-allocation-comparison.json`.

Ordinary Linux user copies now use the native exact-remaining-count walk.
Existing Boolean/remote adapters preserve their policy. Raw and `__copy_*`
copies leave the uncopied tail alone; public from-user copies zero it after
range rejection or a partial copy. Public callsite object bounds and `INT_MAX`
checks reject copies without touching a destination. `access_ok` separately
checks numerical bounds, including NULL and zero-size boundaries. Eleven
bounded user-string parser wrappers use stack buffers and preserve results on
copy/syntax/range failure. Run `python3 tests/linuxkpi/uaccess_test.py` separately
from the shared runtime runner.

Native acquisition already uses `RangePageSource`: capture scalar metadata
under `pagemap.l`, retain handle/resource, acquire optional device-range ownership
outside that lock, and freshly recheck local identity/generation/global serial
before installing. Losers return through the retained source. Current syscall
unwind protects its pagemap through exec/exit; remote maps still need inspection
references. The earlier fault-lease proposal and vanished temporary artifacts
are not implementations or validation evidence.

Independent remaining VM work includes mapping publication without a universal
backing pin and DRM retain/release callbacks under `pagemap.l` that invert the
virtio file-lock order. Virtio command submission can also demand-fault while
holding the backing lock. Ordinary copies do not resolve those existing driver
lock cycles. Ordinary scalar stores, task-owned fault controls, resident-only
atomic copies and checked write scopes are now implemented. Resident non-temporal
user copies are implemented and validated in complete fresh normal/SSE guests.
Actual GPU WC mappings and hardware validation remain pending.

The 2026-10-06 user-copy validation is isolated at `bea41f8e` with recorded
feature hashes and a frozen compiler. Host copy/parser checks pass 6,440
assertions per C standard; complete runtime/import and actual native
page-source host checks pass. Enabled/default x86 and disabled ARM build,
and both default Linux-ABI guests pass. Exact final enabled ELF
`4534a060ef59c7865d9c5e4188ff6e188fcfa48a772e8ede0ef324d4388a9eeb`
passes the full normal and SSE suites; the new native copy batches recover all
pages and live heap objects. Preserve
the normal/SSE/clean-baseline 180-second timeout logs: the final normal run
passes with a 600-second outer harness limit, with runtime deadlines unchanged.
Paired default allocation reports contain 414 sites/192 groups and 158 existing
failures with no added groups. That milestone passed 3/269 syntax units. Logs,
source hashes and independent final generated-C reviews are under
`/tmp/vinix-linuxkpi-uaccess-oct06-*`; they are scoped evidence, not GPU bringup.

## Latest scalar and compiler-helper validation

`c3ab77ea` is committed. Ordinary `get_user`/`__get_user` preserve width,
signedness, single evaluation and fault-zero outputs. A single-page load is one
plain width-specific `MOV`; cross-page loads publish only after every checked
chunk succeeds and make no atomicity claim. Permission checks and width/count
selection precede a portable `CPUID` in the same assembly block as each load or
`REP MOVSB`. This adds per-access serialization cost; vendor/feature-based fence
selection and broader kernel speculation mitigation remain unresolved.

Strict production-core/header host checks pass 1,033 assertions per GNU99/GNU11
sanitizer build. Isolated enabled/default x86 and disabled ARM builds and both
default Linux-ABI guests pass. Final enabled ELF SHA256
`80b9288aaca113d487d90d286b0ae9d201b08ca5ac937298daca34dea9966f4a`
passes complete normal and SSE guest suites, about 700/973 seconds with a
1,200-second outer limit. Preserve the final 600-second timeout and earlier
cold-measurement diagnostics; runtime callback deadlines were not changed.

Three complete actor lifecycles warm before the fourth exact physical-page and
all-live-heap-class measurement. Resident fourth batches and the fully joined,
off-stack, actually reaped fourth lifecycle recover exactly in both guests.
The first complete lifecycle retains 8 KiB physical pages; both logs report it,
and subsequent lifecycles are flat. Its allocation sites are not established.
Independent reviewers inspect actual generated C, optimized object paths,
controller/actor stack lifetimes, stop acknowledgement and both thread pins.
Feature sources match the saved ELF's manifest. The private compiler binary
and recovered private runtime library avoid ongoing changes in the shared V
checkout; all 78 actual builtin inputs match previously captured hashes.
Exact checks, hashes and scope are in
`/tmp/vinix-linuxkpi-scalar-oct06-final-validation.json`, with library provenance
in `/tmp/vinix-linuxkpi-scalar-oct06-frozen-library-provenance.json`.
This does not establish a global allocation pass or LinuxKPI support on ARM.

Scalar stores are committed in `15c21a91`. Production-core/public-header checks
pass 26,260 strict ASan/UBSan assertions per GNU99/GNU11 build; unsupported
16-byte widths fail compilation. Actual generated code and optimized objects
receive two lifetime reviews, including fault resolution, map locking, actor
acknowledgement, joined/off-stack/reaped thread retirement and hidden allocation.
Isolated enabled/default x86 and disabled ARM builds and both default ABI boots
pass. The saved enabled ELF SHA256
`93e6a7c83a579f672204bb9e68ee4424af192d223bd7da372e86065d6b47e2f5`
passes complete normal and SSE suites, about 1,084/713 seconds with outer limits
of 1,200/1,800 seconds. Runtime callback deadlines remain unchanged.

Store fixtures cover real noncontiguous pages, protected split-page prefixes,
sparse demand mapping, actual fork/COW separation and concurrent aligned
2/4/8-byte writes. Three complete lifecycle warmups and resident warmups precede
strict fourth-batch page/all-live-heap-class measurements; both guests recover
exactly. The store fixture's first lifecycle is also flat after the preceding
scalar-read fixture; this does not explain that earlier fixture's cold 8 KiB
retention. Existing map/fork early-OOM rollback is outside this feature's scope.
Evidence: `/tmp/vinix-linuxkpi-scalar-store-oct06-final-validation.json`.
These builds use the recorded isolated baseline plus owned feature overlays,
not the concurrently changing shared HEAD; ARM remains LinuxKPI-disabled.

Typed user-pointer, original `pgoff_t` and pinned overflow/type predicates are
also committed (`a070633d`, `bb37a234`, `d0a65f59`). Strict host and independent
checks cover wrong types, single evaluation, both integer boundaries and
constant expressions. Pinned overflow macros retain their local-name collision
for an operand named `v`; `overflows_type` is not usable at file scope, whereas
`castable_to_type` preserves that constant-expression case. No Linux page runtime
is supplied by the page-offset representation.

Audit commits `96f768b6` and `3a38ab99` generate actual current ABI adapter headers privately
per run, uses them before other include directories and cleans up after all
compiler jobs. Invalid metadata rejects before compilation. Verified upstream
files remain 7,668 unchanged; the full result is **4/269**, expected exit 1:
`i915_memcpy.c`, `i915_config.c`, `display/intel_qp_tables.c` and
`i915_user_extensions.c`. The last unit is syntax-only and not linked. Exact
report at that milestone: `/tmp/vinix-linuxkpi-audit-generated-oct06-native.json`.
Bounds generation is now committed in `f1d5860b`: compile the exact pinned
`kernel/bounds.c` outside the verified import using the actual target, config
and generated adapters; record compiler/discovered-header hashes and command
stamps. `CONFIG_MMU=1` matches native paging. The five-level-capable type profile
is committed in `a88dcea7`, with original UAPI aliases and annotations rather
than duplicate typedefs. Linux page ownership, PFN/descriptor services and
runtime geometry globals remain unresolved. Latest frozen syntax report:
`/tmp/vinix-linuxkpi-smp-headers-oct06-enabled-proof/full-audit-report.json`, **4/269**,
expected exit 1. Original page-table types, static-key declarations and
instruction-header and original CSD closure clear prior first errors; 213 units first fail on
`rcu_read_lock`, followed by RCU pointer APIs and
`cpu_feature_enabled`. Full diagnostics contain no MOVDIR error. Original mmiowb tracking
macros are disabled under this configuration; a forced tracking configuration
still rejects the absent architecture barrier.

## Latest task-fault and compiler-scope validation

`dd1df42f` implements task-owned depth with exact compiler barriers, checked
overflow/underflow and original IRQ-state restoration. New tasks start at zero;
an actual worker sleeps and migrates while holding depth two. Native missing
page/COW resolution and kernel trap policy reject disabled scopes before
allocation. Resident accesses still work. Explicit inatomic copies always
reject missing/COW pages, preserve exact prefixes and never zero their tails.
Full Linux IRQ/NMI/BH encoding and exception-table recovery remain pending;
native maskable accounting is covered by the newer validation below.

The same enabled ELF SHA256
`22979f43e8511c33097d69ef8537781da96831814896390bedd8ccc675ea6ce2`
passes the complete normal rerun and SSE suite, about 1,173/961 seconds. The
first normal run passed fault-control measurements but failed a later I/O
fixture; preserve that failed report. Its cause remains unresolved. Three
full actor-lifecycle warmups precede exact fourth-batch physical/free-heap-class
recovery. Enabled/default x86 and disabled ARM builds and both default boots
pass. Host tests pass 433,858 depth assertions plus eight fatal cases and
9,200 copy assertions per GNU99/GNU11. Final actual generated C and optimized
objects received independent lifetime reviews. Evidence:
`/tmp/vinix-linuxkpi-pagefault-oct06-final-validation.json`.

Compiler milestones `a88dcea7`, `376b5d66` and `0e35bb9a` restore original
complete page/folio/descriptor and entry types, genuine UAPI aliases, typed
extern static keys and checked user-write scopes. Strict checks exercise both
include orders, sixteen unchanged scalar aliases on x86/ARM, separate key
definitions/consumer symbol closure, and 449,253 scope assertions per C
standard. Independent O0/O1/O2 scope objects preserve end compiler barriers
and error-label cleanup, without raw STAC/CLAC windows or extra imports.
Scalar access inherits the native ordinary/resident-only context contract;
unsafe reads and bulk-copy wrappers remain unresolved.

Saved compiler-profile ELF `065b36cb1af47879fb76b22e0a5f6b62a4a4b3035ee78503afce853fd8610f7d`
compiles/links. Its native V C and object match the passed fault-control kernel
byte-for-byte; no full guest boot is claimed for this separately linked ELF.
Aggregate evidence: `/tmp/vinix-linuxkpi-compiler-next-oct06-final-validation.json`.
These are scoped runtime/compiler results, not GPU bringup or a global allocation
pass. Upstream remains unchanged.

Resident non-temporal copies use actual aligned integer `MOVNTI` with cached
page/alignment edges, serializing source loads and `SFENCE` before every source
unlock. Exact resident prefixes leave later destination bytes untouched without
page-in/COW or context changes. The pinned x86 size/result ABI remains 32 bits.
Saved ELF `ebecc3ef0e7127f73cec652266dc00572e18eadf41cd88e1998c7c328e8ff783`
passes both complete four-CPU guests. The fourth complete map lifecycle recovers
exact physical bytes and all live heap classes after three warmups. Default x86
and disabled ARM builds/startup pass. Host GNU99/GNU11 checks each pass
25,299,139 sanitizer assertions; actual generated C, optimized object and linked
ELF receive independent lifetime/ordering review. Tests use ordinary RAM, not a
GPU aperture. Evidence: `/tmp/vinix-linuxkpi-nocache-oct06-final-validation.json`.

Generated x86 early-ioremap/kmap wrappers now forward to genuine headers
selected by the original Kbuild. Actual pinned wrapper generation, twelve
strict object probes and independent byte-identical replays pass. Real mapping
symbols remain unresolved. Enabled compiler-only integration links and retains
the passed nocache V C/object exactly; its separately linked ELF has no new
guest-boot claim. Evidence:
`/tmp/vinix-linuxkpi-asm-generated-headers-oct06-final-validation.json`.

## Native maskable IRQ validation and next context work

The frozen 28-path IRQ overlay passes full four-CPU normal and SSE guests using
the same saved ELF
`aaad1db6f60f17a4ea84ad98e457c5d2e7687a2b43ca36aa17777309300f3381`.
Real thunk nesting, scheduler self-IPIs and deferred switches, sleep/yield,
idle-target wakeup, pending-event preservation and actual userspace interrupts
pass. Each vector 32–255 closes its CPU-owned region before ordinary task return;
both scheduler handoffs close it before releasing the old task or changing GS.
Vectors 0–31 remain unchanged. Scheduler IST1 still requires IRQ exclusion;
accounting does not make reentry on an overwritten IST frame safe.

The actual native fixture joins every actor and observes its off-stack handoff
before releasing its last retention pin or resetting permanent ledger storage.
After three full lifecycle warmups, the measured fourth returns physical free
bytes from `348405760` to exactly `348405760` and restores every live heap class
in both guests. The first warmup retains 14 pages; do not describe the first
batch or global kernel allocation behavior as leak-free. Separate serial markers
prove user-CS entry and a later depth-zero task return, without identifying a
particular interrupted task or proving ordinary non-scheduler IRET return.

Strict GNU99/GNU11 IRQ host checks pass 280,732 sanitizer assertions each and
inspect all 256 real thunk routes, including the saved-CS frame offset. Updated
fault-control checks pass 494,347 assertions plus eight fatal cases per profile.
Default x86 and disabled ARM builds and Linux-ABI startup pass. Final generated
C, optimized objects, linked ELF, all frozen sources and fixture cleanup received
independent review. An earlier broad event-wait guard timed out on ARM; the
passing final version checks actual x86 maskable depth and restores ordinary
task wait behavior. Preserve that failed attempt and its passing diagnostic
variant instead of treating the failure as an architecture validation pass.

The final disabled ARM kernel also completes desktop harness scenarios
`ops,churn,cache,idle,apps,drag`. Its measurements include 16–32 KiB retained per
300-process churn batch and positive syscall allocations; this establishes no
global leak-free result. Clean `24afa95c` baseline and feature allocation scans
both exit 1 with 354 ARM sites, 293 x86 sites and identical 158 failing groups.
The initial allocation job never started because its worktree lacked the test
harness; the corrected failure record is preserved. Frozen sources, artifacts,
all result files and independent reviews are collected in
`/tmp/vinix-linuxkpi-irq-context-oct06-final-validation.json`.

Next, fix workqueue callback identity under real IRQ interruption: the current
task-only worker lookup must not grant an interrupt producer callback or drain
chaining privileges. That backend is currently owned by another session; do not
overwrite its ABI migration. Ordinary IRQ-off/pinned task callbacks must retain
their identity. NMI/BH tracking, full Linux context encoding and ordinary RCU
remain unresolved. SMP dispatch needs real IRQ-delivered callbacks and original
CSD lifetimes; a synchronous marker cannot stand in for completion of detached
asynchronous callbacks. Linux PCI/device/devres APIs and GPU binding remain
pending.

## Native bounded PCI topology

The native scanner now retains configured PCI/CardBus bridges, uses their actual
parent BDFs, checks bounded bus windows and frees all private observations before
publishing separate permanent device records. Absent functions no longer retain
allocated descriptors. Root bus numbers are explicitly supplied and borrowed
only during construction; current boot integration supplies domain-zero bus
zero. Host-function numbers and MCFG apertures do not establish additional
roots. Real firmware SEG/BBN/CRS root discovery remains pending, and uACPI
namespace initialization currently follows PCI publication. Do not claim general
multi-root discovery or solve that ordering by inventing firmware roots.

The graph uses nonmoving scalar records and a fixed bus bitmap, with no recursion
or dynamically growing worklist. Each checked transport transaction finishes
before an allocation. Every constructor error destroys the complete private
graph. Construction is for early boot or ordinary tasks; the fallible allocator
can reclaim, so this is no IRQ allocation guarantee. Readers must finish before
their uniquely owned snapshot is destroyed. Escaped native driver/uACPI device
pointers instead have boot lifetime; initialization is idempotent and supplies
no live replacement, hotplug or rescan API.

Conventional capability validation checks links, cycles, known MSI/MSI-X extents
and the MSI-X `low11+1` entry count before granting either capability. Malformed
chains keep the device but publish zero interrupt support. Unknown payload
extents and extended capabilities remain unresolved. There are no topology or
capability configuration writes, BAR probes, IRQ registration or Linux
`pci_dev`/`pci_bus` objects. Publication copies only scalars, frees the graph,
then creates permanent capability bitmaps. Raw descriptor OOM frees all prior
descriptors/vector/graph before failing; the vector and bitmap allocators retain
their existing fatal-OOM behavior.

Fresh isolated architecture builds at `e2641335` pass. The exact saved enabled
ELF `fee7d8617e9ab98e5810f6b84183a3481f3cb4494698fb9c523198b26b129687`
passes both complete four-CPU normal/SSE suites. Three complete warmups precede
the fourth rollback cycle with exact PMM bytes `420929536` before/after and all
live heap classes equal. Optional-fixture default x86 recovers `423432192` bytes;
actual ARM ECAM/config fixtures recover `960380928`. True default x86 and
disabled ARM builds/startup pass with the fixtures absent. Four configured ARM
CPUs are not proof of native ARM SMP.

`tests/pci-config/topology` runs the actual unchanged V algorithms and
transport core against private synchronous observers. GNU99/GNU11 each pass
7,150,771 sanitizer assertions, including every private allocation/transaction
failure, bounded relationships, capability errors, 200 full destruction cycles
and explicit reader join before destruction. Independent final native
generated-C/object/ELF lifetime review approves both architectures. Preserve the
earlier failed V name/clone/callback lowering attempts and the first guest's
missing-bootloader preparation error. Final callbacks use direct scalar native
calls and the boot vector transfers its unique backing store once.

The allocation gate still fails with 354 ARM sites, 293 x86 sites and 158 groups;
its sole delta exchanges the old scanner heap site for the permanent vector
initialization. The disabled ARM desktop harness completes all six scenarios,
including retained churn allocations up to 48 KiB per 300-process batch and
positive syscall allocations. This is scoped
snapshot recovery evidence, not global leak freedom or GPU support. Sources,
artifacts, results, failed attempts and independent review are collected in
`/tmp/vinix-linuxkpi-pci-topology-oct06-final-validation.json`.

## Original instruction headers and CPU feature work

The genuine x86 `processor.h` instruction dependency closure now exposes original
MOVDIR64B/`iosubmit_cmds512`, preserving full 64-byte memory operands, exact opcode
bytes and original alternative metadata. CR0/CR4 writers and alternative patching
remain genuine unresolved symbols in reference objects. Sixteen strict compiler
objects, four rejected incomplete-header probes, ten actual Make-profile objects
and independent same-hash replays pass. An isolated enabled `e2641335` plus only
the processor overlay compiles and links; its saved ELF has no new instruction
caller and no separate guest/instruction execution claim.

The full frozen audit remains 4/269 with expected exit 1 and the same source set.
All fifteen prior MOVDIR declaration blockers advance to genuine RCU,
`cpu_feature_enabled`, `ERR_CAST` or architecture-header dependencies. Full
diagnostics contain no remaining MOVDIR error. QEMU TCG does not expose either
direct-store bit on this host and rejects forced positive exposure. Compiler
closure is not positive instruction, device-portal or MMIO validation. Evidence:
`/tmp/vinix-linuxkpi-movdir64b-oct06-final-validation.json`.

Native runtime now samples only MOVDIRI/MOVDIR64B hardware bits on each actual
CPU before its online acknowledgement, then publishes one immutable boot-CPU
intersection before first compatibility users. Support covers exactly original
feature IDs 539/540; other leaf-seven ECX bits remain unsupported. Queries
preserve caller state and remain valid across migration. Hotplug, concurrent
initialization and policy replacement need a separate protocol. Existing
word-zero/four queries retain their legacy current-CPU scope.

Fresh isolated enabled/default x86 and disabled ARM builds pass at `079e3ccd`
plus only six CPU-feature native paths and the processor prerequisite committed
in `909f6a4b`. Complete normal/SSE suites use the same saved enabled ELF,
SHA256 `4dd8a5f11371b90f69387fb446f4f0d8b2c54dc2a8aaf8cc452ec2daf986635f`.
After three warmups, the fourth query batch preserves normal free bytes
`390782976 -> 390782976` and SSE `390787072 -> 390787072`, with every live
heap class equal. IRQ-on/off and nested preemption caller state also passes;
four initialized CPUs publish a valid zero intersection. Default x86 and
disabled ARM reach Linux-ABI PID 1 with LinuxKPI fixtures absent.

The final strict GNU99/GNU11 host test passes 1,116,514 ASan/UBSan assertions
per standard with unchanged generated bodies and genuine 64-bit native online
and V array-length representations. Independent host and actual native
source/C/object/ELF reviews approve ownership and publication. Earlier narrower
private host records are superseded. Eighteen compiler objects and two cold
original-header objects retain exact expected imports. No positive direct-store
instruction or device MMIO execution is established.

All six broader desktop scenarios complete on disabled ARM. Churn retains
16–48 KiB per 300-process batch and positive syscall allocations remain. The
allocation gate still fails with exactly the same 158 groups as its PCI
baseline. Do not claim global allocation success. Full evidence:
`/tmp/vinix-linuxkpi-directstore-policy-oct06-final-validation.json`.

Original CSD tests now preserve records and genuine unresolved dispatcher/mask
references. Production full-header integration now passes strict same-source
compiler and native link checks; real masks and IRQ dispatch still need
implementation.

The SMP overlay imports original Linux/x86 records and declarations, then
restores only CPU accessors to the real native function and `get_cpu` pin.
Exact original early declarations leave actual storage/maps unresolved. Genuine
x86 Kconfig selects the architecture frame helper; with FRAME_POINTER and
HARDENED_USERCOPY unset its original branch returns `NOT_STACK`, without Linux
stack validation. Existing `current_thread_info()` casting still does not match
the native task view; TIF/status accessors remain an unsupported runtime boundary.

Final maintained test `smp_header_test.py` passes 22 GNU99/GNU11/assembly objects
and six genuinely rejected missing-prerequisite cases. Original CSD/node/mask
and fourteen-callback `smp_ops` ABI words match, individual CPU query/pin/unpin
relocations are native, cold orders emit no symbols and original eight
dispatch/mask plus six early-map imports remain genuine. The unchanged CSD
initializer test passes 420,004 ASan/UBSan assertions per standard with actual
production full headers now compiling. Section dumps use separate outputs;
all 22 original object hashes and four derived copies are preserved and verified.
Initial stale pre-objcopy receipts are retained as superseded evidence.

Fresh isolated enabled/default x86 and disabled ARM builds at `909f6a4b` plus
only four header/config paths compile and link. Enabled ELF SHA256:
`f2e594e33c380e620d79c09b278d81109fec17827bf187763e02c13a0e9a570c`.
The existing raw native CPU accessor exists in its real header object but is
garbage-collected when unreferenced in this ELF. No new runtime algorithm or
guest execution claim follows from this header feature. Full audit remains
4/269; exactly seven CSD first errors advance to RCU (206 to 213). Masks,
early maps, `smp_ops`, hotplug and remote callback services remain pending.
Aggregate: `/tmp/vinix-linuxkpi-smp-headers-oct06-final-validation.json`.

Original Linux boot CPU masks now publish Vinix's validated compact logical
CPU set: possible, present, online and active contain every installed CPU;
dying is empty. The sole boot publisher clears/writes all four original words,
sets the genuine `nr_cpu_ids` and atomic online count, then release-publishes
readiness before compatibility consumers. Original full-width `cpu_all_bits`
and compressed `cpu_bit_bitmap` constants retain exact pinned bytes. No CPU
hotplug, disabled-firmware inventory, `total_cpus`, early-map or remote callback
runtime follows from these masks; bound worker affinity still has its 64-CPU
restriction.

Fresh 2026-10-07 isolated enabled/default x86 and disabled ARM builds pass at
`95234fa286b400561671ff68bcc3df45d026dd73` plus eleven exact CPU-mask overlay
paths. Default x86/ARM guests reach Linux-ABI PID 1 with LinuxKPI absent.
Enabled ELF SHA256:
`65038097451fcddbfd33a764ee59fa24942b5967e424f1d12fcf54678af5530a`.
Both fresh complete four-CPU normal/SSE guests pass all 42 required markers
and nineteen exact free-byte/heap equalities. The fourth mask batch in each
preserves `390762496 -> 390762496` bytes and every live heap class; IRQ state
and nested preemption pins remain intact. Runs complete in 275.47/271.42 seconds
at the unchanged 3,600-second outer allowance. Old 41-marker FPU kernels do not
validate this stage.

The maintained GNU99/GNU11 host runs each pass 15,810,213 ASan/UBSan assertions
across 17 cold processes, retaining 28 unchanged V bodies, fourteen native
object proofs and exact pinned readonly bytes. Numerical 65/255 coverage does
not boot those CPUs. Peer review confirms permanent borrowed storage, sole
boot publication and acquire/release readiness, with no new allocations/frees.

The data-only C file combines pinned Linux 6.6.157 constant definitions with
native typed storage declarations and has no functions or runtime imports.
Its maintained wrapper file, declaration headers and authored embedded C test
oracle/runner are first-party follow-up under the C-removal instruction, not
vendored implementations or migration credit.

The earlier `/tmp/vinix-linuxkpi-cpu-masks-oct06-final-validation.json` receipt
and its worktrees are absent. Its previous full native/host/desktop and baseline
claims are archived as unverified draft text. Fresh evidence is kept in
`/Users/alex/.cache/vinix-c-to-v/firstparty-only-20261006-011023/` as
`cpu-mask-oct07-final-validation.json`, with host, native and build receipts
beside it. Preserve the broader allocation and
host-suite baselines; fresh mask results do not establish their resolution.

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
| `kernel/linuxkpi/compatcore/workqueue.v`, `kernel/c/linuxkpi_workqueue_native_test.c` | Ordered, delayed, bound and unbound engine plus independent native tests |
| `kernel/linuxkpi/compatcore/{srcu,timer,time,sync,task,percpu}.v`, `kernel/c/linuxkpi_*_v_primitives.{c,h}` | Native V backends and narrow Linux header/ABI bindings |
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

Adding a native C binding requires LinuxKPI compiler flags/config dependencies
in `GNUmakefile` and host source-list integration in `run.sh`. Keep those shared
edits with root. Ordinary kernel C uses GNU99 and currently emits upstream
duplicate-typedef warnings; host/audit use GNU11. Do not hide compiler errors
or rewrite upstream headers to make a false success.

## Validation already completed

Token helpers used four frozen kernel paths at `ce4606b3`, enabled ELF
`8c32940b5f6a4bd707a52a2f3073055ebe5e529190812a2f13a6585f09c0ad8e`.
Strict full ASan/UBSan host/import/header tests, enabled/default x86 and disabled
ARM builds, full normal/SSE guests and default Linux-ABI startup passed. The
final source rebuild, including host-only aliases, produced identical ELF and
generated-C hashes. Native checks run 200 times with exact page recovery;
separate actual-backend tests passed 7,542,446 pinned-reference comparisons.
The local `strim` traversal avoids forming `s - 1` and preserves every observable
byte/pointer result. Source, host/native fixtures and generated C have independent
approval. Evidence: `/tmp/vinix-linuxkpi-string-tokens-final-validation.json`.
Fresh full syntax audit remains 3/269; imported files remain unchanged.

Kernel-string parsers used five frozen kernel paths at `7735509f`, enabled ELF
`cf90f5defc1003984b0c261c85debd4b08d6831884c80c43428fa168e782b996`.
The same host/build/normal/SSE/default checks passed, including 56 native
conversion checks per iteration inside the exact 200-iteration page measurement.
Independent source/fixture/generated-C review and 16,653 private comparisons
passed. Evidence: `/tmp/vinix-linuxkpi-kstrtox-final-validation.json`.
`_from_user` and native remaining-byte/zero-tail user-copy integration are pending.

The minimum-duration sleep feature used five frozen kernel paths at `53f41b30`,
enabled ELF SHA256
`354139c5a2fe25d532aa9e5ec9f84343a19a7f3b2ffac3abd32a082dde56e723`.
Full strict host/import/header checks include permanent boundary subprocesses;
enabled/default x86 and disabled ARM builds and default startup passed. Both
normal and SSE guests passed the new four-batch sleep test with exact page
recovery. The first normal guest later failed an unchanged unbound self-free
timeout (3/8 at 502 ticks); the full normal rerun on the identical ELF and the
full SSE run passed. Preserve that failure: it remains unexplained, and the
rerun does not repair it. Evidence is
`/tmp/vinix-linuxkpi-usleep-final-validation.json`. Equal-source allocation
gates at this newer baseline have 429 sites, 192 groups and 161 existing
failures on both sides, with no new counts/groups and no global pass.

The latest string-helper feature used a three-path frozen kernel overlay at
`92c24841`, enabled ELF SHA256
`2d976d406a63e4795716521e59fdd3357f9ba42e4018c8fc05062a61fff6c193`.
Strict full ASan/UBSan host/import/header checks, enabled/default x86 and disabled
ARM builds, full normal/SSE four-CPU guests and default Linux-ABI startup passed.
The 200-iteration native test returned exactly to its physical-page baseline.
Sources and generated C were independently reviewed; frozen evidence is
`/tmp/vinix-linuxkpi-string-helpers-final-validation.json`. Latest full audit
`/tmp/vinix-linuxkpi-string-helpers-i915-audit.json` remains expected exit 1,
**3/269**, with all 7,668 imported files unchanged.

Policy/helper validation and the separate timed-worker retirement fix are
recorded in `/tmp/vinix-linuxkpi-i915-policy-final-validation.json` and
`/tmp/vinix-linuxkpi-mutex-io-retirement-final-validation.json`. The first policy
guest passed the new helper page measurement but failed an older timed-wait
baseline with 1,029 more free pages; a rerun was diagnostic, not a fix. The
committed retirement fix now waits for all known joined workers' off-stack
handoffs before releasing any final pin, then observes actual deferred frees
under a shared one-second bound. The scope is known x86 workers, not global
heap quiescence or arm64 reclamation. I/O mutex and retirement normal/SSE
guests passed using enabled ELF SHA256
`7ce625f4b7ff4b54c2dd39604274c0b596b18ad75992ef85ee8aed029a69105d`.
Equal-baseline allocation gates retain 440 sites, 193 groups and 162 existing
failures with no new counts or groups; they are not global allocation passes.

Earlier bound/bitmap continuation checks cover these committed changes:

| Check | Result and artifact |
| --- | --- |
| Strict host runtime/import tests | Clean ASan/UBSan; `/tmp/vinix-linuxkpi-bound-host-gatefixed.log`, `/tmp/vinix-linuxkpi-bitmap-integrated-host.log` |
| Enabled x86 builds | Pass; `/tmp/vinix-linuxkpi-bound-x86-build-final.log`, `/tmp/vinix-linuxkpi-bitmap-x86-build.log` |
| Disabled arm64 builds | Pass; `/tmp/vinix-linuxkpi-bound-arm-build-final.log`, `/tmp/vinix-linuxkpi-bitmap-arm-build.log` |
| Default x86 build/guest | Pass; `/tmp/vinix-linuxkpi-bitmap-default-build.log`, `/tmp/vinix-linuxkpi-bitmap-default-vm/serial.log` |
| Four-CPU enabled normal/SSE guests | Pass; `/tmp/vinix-linuxkpi-bitmap-vm/serial.log`, `/tmp/vinix-linuxkpi-bitmap-sse-vm/serial.log` |
| Optional XNU allocator build/guest | Pass; `/tmp/vinix-linuxkpi-bound-xnu-build.log`, `/tmp/vinix-linuxkpi-bound-xnu-vm/serial.log` |
| Full i915 syntax audit at the bound/bitmap milestone | Expected exit 1, **1/269** at that revision |
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

I/O strict host tests pass at `/tmp/vinix-linuxkpi-iowait-host-final.log`.
Fresh enabled x86, disabled ARM and default x86 builds pass at
`/tmp/vinix-linuxkpi-iowait-x86-build-final-diagnostics.log`,
`/tmp/vinix-linuxkpi-iowait-arm-build-final-diagnostics.log` and
`/tmp/vinix-linuxkpi-iowait-default-build.log`. Fresh normal/SSE/default guests
pass at `/tmp/vinix-linuxkpi-iowait-{reviewed-vm,reviewed-sse-vm,default-vm}/serial.log`.
Both enabled guests include the I/O marker and exact page recovery, using
`/tmp/vinix-linuxkpi-iowait-enabled-reviewed.elf`, SHA256
`7ce6e10a50ecec9e3fcef56ef2d0ab3b1a60a6429e6b2e65e9c4c2e8518c9af6`.
These isolated builds start at `118047fd` plus the owned I/O/diagnostic overlay;
later unrelated kernel commits are not silently included in this evidence.

Initial I/O guest logs failed or timed out in earlier workqueue/worker tests
before I/O ran. Preserve `/tmp/vinix-linuxkpi-iowait-{vm,sse-vm,trace-sse-vm,final-vm,worker-trace-vm}/serial.log`
as failures. Diagnostics identified a bound self-free completion watchdog,
whose later completion did not change its failed result. The reviewed normal
run took about 120 seconds including ISO preparation. Final runs used the
harness's explicit `--timeout 300`; every 500-tick callback check remains intact.
An earlier identical-runtime ELF also passes both long-budget guests at
`/tmp/vinix-linuxkpi-iowait-long-{normal,sse}-vm/serial.log`. These checks do not
establish a cause for every preceding intermittent failure.

Independent I/O backend/host/native and diagnostic lifetime reviews approved.
Generated V code has no allocation/string-conversion markers in the nine new
scheduler/bridge/route functions or measured locals:
`/tmp/vinix-linuxkpi-iowait-generatedc-review.json`. Thread-layout comparison
keeps size 11,256, alignment 8 and every old offset unchanged; the new token is
at offset 140. The fresh allocation baseline after unrelated kernel changes
is **418 sites / 184 groups / 155 existing failures**, matched exactly by the
I/O overlay (`/tmp/vinix-linuxkpi-iowait-alloc-comparison.json`). The older
425-site result below describes earlier baselines. The I/O syntax audit still
passes 1/269, and import verification still checks all 7,668 unchanged files.

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

The newer isolated ARM I/O-disabled build also completed desktop idle/apps/drag
with DONE and no panic: `/tmp/vinix-linuxkpi-iowait-perf-idle-apps-drag.log`.
Physical usage was 65.5/146.3/104.6 MiB. Its initial ops/churn/cache harness
returned zero at its deadline with incomplete reports and no DONE; that is
**incomplete validation**, not a pass. A fresh retry completed with DONE,
exit zero and all 70 OPS, eight CHURN and two CACHE reports:
`/tmp/vinix-linuxkpi-iowait-perf-retry-ops-churn-cache.log`. The corrected
harness in `e4c5ffc4` independently replays the actual serial files and
accepts exactly 80 allocation reports and three desktop scenarios, with no
errors: `/tmp/vinix-linuxkpi-iowait-perf-retry-completed-verdict-replay.json`.
Its 19 regression tests also reject missing completion, missing/duplicate
reports, malformed measurements, fatal exits and incomplete console output.
The measured ARM ELF is `f449c95e7ef242a2b794b6f883e262ed84da18bdc4f1e54cb8c6cfc8d848ebf4`;
boot-disk identity and unchanged source/generated-C/ELF/desktop are recorded
in `/tmp/vinix-linuxkpi-iowait-perf-retry-analysis.json`. These workloads use
AArch64 with `LINUXKPI=0`, `LIMINE_MP=0` and CPU0 only; they do not execute
LinuxKPI I/O APIs. Existing proc/readdir and
program-churn retention remains. Seventy changed and 26 added kernel paths
separate this baseline from the older SRCU performance build, so differences
do not establish an I/O-induced regression or improvement.

The cache feature was tested in fresh detached worktrees at `e29bcc4d` plus
its eight-path kernel overlay, including the later native page-fill optimization
and ext2 commits. The enabled ELF SHA256 is
`f5fefb21858cc7d80dd8aa3ef06c203da6c7d84cd4d46b20ea602ca69a8ed93e`.
Fresh normal/SSE guests pass all markers, including exact page recovery after
three cache warmups and a measured fourth batch:
`/tmp/vinix-linuxkpi-cache-{vm,sse-vm}/serial.log`. Default x86 startup passes
at `/tmp/vinix-linuxkpi-cache-default-vm/serial.log`; enabled/default x86 and
ARM-disabled builds pass. Full final host ASan/UBSan and strict helper probes
pass at `/tmp/vinix-linuxkpi-cache-host-boundaries-final.log`.

Native caches retain empty backing slabs for reuse until explicit shrink or
quiescent destruction. Only flags zero and `SLAB_HWCACHE_ALIGN` are accepted;
RCU-safe, reclaim-accounted and other nonzero modes remain unsupported. This
is not the allocator needed by i915's three RCU/reclaim-dependent caches.
Backend and fixtures have independent lifetime approval; private generated-C
review finds no hidden allocation in the added measurement locals. The fresh
equal-source allocation gate baseline/feature logs are byte-identical:
416 sites / 184 groups / 155 existing failures, both gate exits 1, ARM V exit
0 and x86 V exit 1. Evidence is `/tmp/vinix-linuxkpi-cache-{alloc-comparison,
generatedc-review,independent-lifetime-review}.json`. The full unchanged i915
syntax audit still passes only 1/269; the include fixes expose later errors
rather than a working driver. `/tmp/vinix-linuxkpi-cache-audit.log` and
`/tmp/vinix-linuxkpi-cache-i915-audit.json` preserve the diagnostics.

## Latest task, sequence and logging validation

`55294618`, `26f77f05` and `ea87f353` are completed changes. Each passed strict
host sanitizer/import tests, independent lifetime review, isolated enabled
x86/default x86/disabled ARM builds, normal and SSE4.1 native guests, and scoped
page recovery. See the main status document for the earlier exact artifacts.

The logging ELF is `/tmp/vinix-linuxkpi-printk-final-enabled-17path.elf`, SHA256
`318b1939b75b5d2111ea2a306d646c054775d788e086f49dd493615eacb8810b`.
Normal/SSE logs are `/tmp/vinix-linuxkpi-printk-complete-{vm,sse-vm}/serial.log`;
both contain the required owned-printk marker and Linux-ABI startup success.
The measured fourth logging batch returns exactly to baseline after three
warmups. A permanent worker is initialized before measurement. Final disabled
ELFs are x86 `e99712632eda2763a927fdb78100719da54079c35bef07b4c42117348eb339ec`
and ARM `92561bd3df145cb06a1a54a2c86ac316109c6215617dbc823c3df8f196e4ac88`;
the rebuilt default ELF matches the tested default guest byte for byte.

Logging producers hold only the IRQ-saving ring lock after synchronous
formatting; they never allocate, wake tasks or write the console. The worker
copies each record to its stack and unlocks before RNG/sink/console/wait calls.
An in-flight record retires only after its sink returns. Dropping queued
entries must not advance that retirement floor. Sink argument storage remains
alive through paused/quiescent removal. Shutdown drains and joins before
clearing the retained task pointer and releasing it. The native worker calls
pthread_exit explicitly because kernel pthread entry has no return trampoline.
The RNG publishes its boot-lifetime object atomically after complete seeding;
secure readiness and output are checked under the same generator lock. No
new hidden allocations appear in those generated V C paths on either target.

The first logging guest failed an old timed-wait fixture that expected the
entire deadline list to be empty. The permanent logger's msleep(10) legitimately
uses that list. The fixture now inspects only each joined, retained worker's
records under the existing lock, before its last task release. A lingering
reference is fatal before releasing its lifetime. All original API durations
remain unchanged; final normal/SSE runs pass this check and every other marker.

The final full host log is `/tmp/vinix-linuxkpi-printk-host-final.log`. Source
freeze/build/guest evidence is `/tmp/vinix-linuxkpi-printk-final-validation.json`.
Independent formatter/ring/fixture, RNG and final time/taint reviews are saved
in matching `/tmp/vinix-linuxkpi-*-review.json` files. The equal-baseline V gate
has 440 sites, 193 groups and 162 existing failures on both sides; no new counts
or groups. Its original 16-path scope is immutable and the final two C-only
changes preserve all checked V paths. This remains a scoped feature result,
not a global allocation pass.

The logging-milestone audit `/tmp/vinix-linuxkpi-printk-i915-audit.json` passed 2/269:
`i915_memcpy.c` and `display/intel_qp_tables.c`. The latter is not yet linked at
that baseline; it is now linked and that subsequent result was 3/269. Remaining syntax paths include `generated/bounds.h`,
`dev_t`, `asm/early_ioremap.h`, RCU pointer APIs and `call_single_data_t`.
Logging does not provide NMI entry, panic bypass, device/facility records,
per-caller continuation merging, rate limiting or complete lib/vsprintf closure.
No full i915 object/link or hardware result exists.

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

1. Remaining synchronization/RCU interfaces and SMP/context,
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

## Latest continuation: native SMP and workqueue IRQ identity

The October 10 implementation adds the five original ordinary SMP call APIs
using genuine CSD records, allocation-free intrusive queues and a real permanent
maskable IPI vector. Generic calls require ordinary IRQ-on task context;
caller-owned async calls also support IRQ-off submission. Callbacks cannot block.
Preserve early async unlock: the CSD may be reused or freed before callback
return. Capture next/function/info before release and never read a detached node
again. Synchronous stack records remain live until their release acknowledgement.
A CSD unlock is not a callback-return or IRET acknowledgement.

Four-word CPU selection is captured before invoking conditions. Ring each newly
nonempty target immediately; deferring all IPIs until after conditions can
strand an earlier call when a later condition recursively reuses its sender
slot. Keep x2APIC's full LAPIC ID and MFENCE/LFENCE before its weakly ordered
WRMSR doorbell. Boot construction requires published masks and ordinary native
task context, and partial allocation failures must retain no pages. Boot owners
and the installed vector are permanent; no hotplug or reset support is implied.

`current_work` and draining-chain identity now reject actual maskable IRQ depth,
while ordinary IRQ-off and pinned callbacks keep their ownership. Keep scheduler
worker accounting separate from this ownership query. The actual native drain
fixture verifies a real interrupt borrowing a held worker, and a subsequent
ordinary callback chain. Native pthread entries must explicitly call
`pthread_exit`: the native scheduler does not supply POSIX's return trampoline.
The first new fixture omitted that exit and faulted at RIP zero; failed evidence
is preserved and the final corrected object/guests are independently reviewed.

Final normal/SSE guests use the same saved enabled ELF SHA256
`92588ce66dab0bb36262f55221a92679a66641959a85fafefbd1b1ddaae50041` and pass all
44 markers and 21 measured equalities. The SMP and IRQ/work fourth lifecycles
recover every page and live heap class after three warmups. Default x86 build
and Linux-ABI guest pass; ARM default build passes. Host SMP tests pass 72 cold
processes per each of two compiler snapshots, independently replayed, and the
ordered host suite passes 20 new drain/context regressions plus its old cases.
The broad host suite still stops at original signedness warnings in its overflow
probe. The official default allocation gate has identical baseline/feature
counts and 151 existing failures; do not claim a global allocation pass.
Desktop scenarios were not rerun because rebuilding the rejected cached ISO
requires 7.84 GB, exceeding available disk space. Exact durable evidence is under
`/Users/alex/.cache/vinix-linuxkpi/smp-oct10/`; use the current maintained scripts.

The next runtime dependency is ordinary RCU. Genuine Linux grace periods cover
all preemption-disabled and IRQ-disabled regions, including atomic callbacks
that never call `rcu_read_lock` (see `i915_pmu.c`). A synchronous IPI alone cannot
acknowledge an interrupted pinned region or an IRQ-enabled nested handler.
Design actual scheduler, outer pin-release and IRQ-return quiescent hooks with
full ordering and saved interrupted IF state; do not substitute explicit-reader
SRCU counters. Hooks must avoid recursive preemption accounting through ordinary
LinuxKPI locks. RCU callback barriers wait for captured callback invocation,
including detached callbacks, and callbacks may free their own heads. NMI/BH
accounting, mixed call-single queue kinds and CPU hotplug remain unresolved.

### Worker binding context correction

The following native fix rejects actual maskable IRQ depth in `worker_bind`
before affinity/NUMA publication, including handlers which temporarily enable
IF. Its final enabled ELF is
`1b4e997729f4f988a0d1c22f0fb450f6decbbdbf8e8acdc5fcb2a5fe98494ba1`.
Both complete normal/SSE guests pass 45 markers and 22 measured equalities;
the fourth IRQ-binding actor batch recovers all pages and live heap classes
after three warmups. An isolated old-predicate kernel fails the genuine native
fixture as expected. Default x86 and ARM builds pass. Final source/actual
generated-code and native lifetime review is separate from the failed initial
fixture, which called a CLI-only CPU accessor with IF enabled. Keep the final
capture-IF-then-CLI observation order and the post-IRET stack retirement rule.
Durable evidence: `smp-oct10/worker-irq-final-validation.json` under the cache
root above. The subsequent ordinary-RCU results are recorded below; earlier
compile-only artifacts remain insufficient runtime evidence.

## Latest continuation: ordinary RCU and V-only tooling

Validation now uses fresh worktrees at **`ebefd710`**, after refreshing 291
committed kernel paths from the older baseline. The saved enabled ELF is
`7d0625d34d71b79d4e52664ed5df59a66dcacd118155e04bd572e1d0661763ee`;
both exact-image normal/SSE guests pass **46** markers and **28** strict PMM
and live-heap equalities. The RCU fourth lifecycles recover all pages and
classes; genuine implicit pinned/IRQ-off readers, nested IRQ-enabled handlers,
actual saved-IF0 software interrupts, FIFO/self-free/requeue callbacks, callback
barrier snapshots and polling cookies are exercised. Default x86 build/guest
and ARM disabled build pass. Independent reviews cover final source, generated
C, objects, stack storage, worker references and actual off-stack retirement.

All implementation and validation tooling must now be V. Current commands:

```sh
build-support/run-v-tool.sh tests/linuxkpi/upstream_source.v verify
build-support/run-v-tool.sh tests/linuxkpi/rcu_callbacks.v --keep-directory /tmp/vinix-rcu-host-fresh
build-support/run-v-tool.sh tests/linuxkpi/run_vm.v --kernel /absolute/enabled.elf --state-dir /tmp/vinix-rcu-normal-fresh --timeout 3600
build-support/run-v-tool.sh tests/linuxkpi/run_vm.v --kernel /absolute/enabled.elf --state-dir /tmp/vinix-rcu-sse-fresh --timeout 3600 --cpu max,hypervisor=off
```

Replace the ELF path and use new state/proof directories. The new V fixture
entry is `tests/linuxkpi/compile_v_fixture.v`; Make invokes it directly through
the V launcher. Upstream verification, module/ABI/bounds/sampler generation
and the guest's initfixture/ISO/process supervision also use V. Historical
Python commands in this handoff are superseded; do not run their wrappers.
The broad host shell runner still contains Python dependencies, so invoke
the maintained V feature tools until that runner is migrated.

Native observers use fixed caller buffers. An actual private diagnostic traced
the former snapshot array request, 463 bytes, to a retained class-512 spare.
A separate scalar diagnostic accounted for its full 12 KiB PMM deficit with
one added page each in classes 48/192/768 and flat live counts during CPU
migration. Finite real scalar warmups now enumerate every boot CPU and use
a bound neighbor writer; original unbound warmups and every exact fourth
equality remain. Controller affinity/NUMA are restored after all child joins,
including partial failures. Do not replace this calibration with allocator
trimming, additional until-pass retries or relaxed equalities.

Committed suspend support can park CPUs offline. The compatibility profile
rejects actual deep/hibernation plans before side effects, including deep
platform rehearsal, then reuses its captured plan to prevent a setter race.
Idle sleep and device-only rehearsals remain available; default profiles
select at their old post-sync boundary. Both profiles pass 72 plan/mutation
cases and an independently replayed removed-guard control fails as expected.
Hotplug, deep sleep and hibernation need genuine domain lifecycle integration
before that restriction can be removed.

Boot restoration is separately guarded after the original named-device lookup,
0600 image/parent restrictions and `hib_device` publication, before loader
allocation or any image I/O/consumption/CPU parking. Keep that metadata path:
the initial pre-open guard lost unreadable named-image disk protection and was
rejected by review. Never use `refuse()` here; it erases the image header.
Both profiles pass 24 exact production metadata/protection cases, and private
removed-guard, destructive-refuse and pre-open controls each fail. The final
normal/SSE RCU fourth rows recover `381243392 -> 381243392` and every live
class. A private kernel removing only the saved-IF predicate fails the native
held-scope fixture with its deadline; mode/early-ACK attribution is a source
inference, not a direct log observation.

The unmodified official default allocation gate has identical baseline/feature
**394** sites, **199** groups and **166** existing failures. No global pass is
claimed. Later Ethernet/boot-log changes in the shared checkout are outside
this exact baseline's native result. Evidence remains under
`/Users/alex/.cache/vinix-linuxkpi/smp-oct10/rcu-oct12-*`, plus the feature-tool
and independent lifetime review subdirectories. Earlier failed versions and
private causal diagnostics remain separate from the final PASS artifacts.

The latest full i915 audit remains **4/269**, and GPU support remains incomplete.
Next dependencies include task/MM/vfork ownership and GFP scopes, the reviewed
integer/error/resource include closure, configured CPU feature policy,
devices/DMA/DRM and firmware. Never expose dummy `task->mm`, parent or vfork
completion fields: the native task view is 64 bytes and carries no such owner.
Physical Tiger Lake or suitable passthrough validation is still required.

## Latest scalar/error/resource closure

Exact original `umode_t`, `lower_32_bits`, `upper_32_bits`, pointer-only
`ERR_CAST` and the UAPI Kbuild `asm/resource.h` wrapper are implemented.
Ten strict GNU99/GNU11 sanitizer profiles and an independent V replay pass,
including both type-header orders, constant expressions/single evaluation,
error boundaries and a genuine UAPI-only compiler route. Actual native
`ERR_CAST` object code returns the pointer without calls or allocation.

Fresh helper worktrees are detached at **`1d0f5b00`**, with five production and
six test paths overlaid. Enabled/default x86 and default ARM builds pass.
Exact ELF `2c75b056fa5e9eb9da9f8e10598886b69e70cf28966d77e552b7772c6549059a`
passes normal/SSE guests, all 46 markers and all 28 strict existing lifetime
equalities. Independent ISO checks verify the kernel, PID 1 and image identity.
Evidence: `smp-oct10/scalar-helper-*` and
`scalar-helper-independent-review/review-result.json` under the cache root.

The latest complete V audit passes **5/269**; its isolated report is
`smp-oct10/scalar-audit-oct12/full/i915-audit.json`. The largest first-error
groups are `vfork_done` (224 files) and `cpu_feature_enabled` (34). These are
compiler diagnostics, not a complete dependency or runtime inventory.
One additional first error is a missing `KBUILD_MODNAME` audit flag, which is
an invocation defect rather than a missing kernel API. The maintained V audit
replacement must derive that metadata from original Kbuild.
CPU policy needs genuine configured masks and boot capability/active-mode queries.
Keep hardware SHSTK separate from configured USER_SHSTK, and use actual
CR4/page-table mode for LA57. Native task/MM/vfork ownership, resource-limit
enforcement and complete device/DMA/DRM services remain unresolved.

Run helper tests through V, with a new proof directory when keeping outputs:

```sh
build-support/run-v-tool.sh tests/linuxkpi/scalar_helpers.v --keep-dir /tmp/vinix-scalar-helpers-fresh
```

## Latest configured CPU policy and V full audit

Original `cpu_feature_enabled` and the 22-word mask selection are preserved.
Configured-disabled literals do not query a native capability; dynamic inputs
follow the original raw path and unsupported bits still fail explicitly.
Native SHSTK is the common hardware capability with XSAVES, XSAVE, FXSR and
FPU prerequisites, distinct from configured USER_SHSTK and CET state. LA57 is actual CR4 paging
mode, checked on every CPU against native geometry. Both are immutable boot
policies, with samples written before each online acknowledgement.

Fresh worktrees at **`86090210`** with six production paths build enabled/default
x86 and default ARM. Exact enabled ELF
`0d52878a83cdaf82a9ebd44751beef39fca725a72d9c9d6de381c012e92e1bea`
passes normal/SSE/four-level guests, all 46 markers and all 28 strict existing
lifetime equalities. Native query fourth batches recover `387440640` bytes in
normal five-level, `387444736` in SSE five-level and `387473408` in four-level,
with unchanged live counts.
Actual witnesses show LA57=1/geometry `1<<56` and LA57=0/geometry `1<<47`.
Native SHSTK is zero in QEMU; do not claim CET execution or positive native
SHSTK validation from host capability tests.

Independent actual C/object review confirms unchanged Local size (1,424 bytes)
and existing offsets, with new booleans in old padding. Successful constructor
and query paths allocate nothing; exceptional compiler bounds-check panic
formatting remains in the generated kernel object. Default x86 setup is
unchanged; ARM's entire generated C matches after substituting only isolated
assertion path prefixes.
Default Linux-ABI startup passes with compatibility symbols/markers excluded.

The corrected full prerequisite chain has six GNU99/GNU11 sanitizer profiles
and six freestanding object checks, including 513 cases executing the unchanged
native sampler block. Every missing prerequisite or leaf acknowledgement is
covered independently. Fixed-domain, publication, configured-mask and
concurrent-query checks pass. Earlier sampler and guest artifacts predate the
explicit FXSR/FPU checks; use the `v2` native/guest and sampler-prerequisites-v3
receipts for the final feature.

The new maintained V audit derives object metadata through pinned Kbuild,
uses private ABI/bounds outputs, records all diagnostics and source states,
joins every job, rejects source changes and atomically publishes complete
reports. Its correct final profile is **5/269**. First errors now include
225 task/MM/vfork units and 33 encryption-header units; the old module-name
invocation defect is fixed. Use a fresh state directory:

```sh
build-support/run-v-tool.sh tests/linuxkpi/audit_full.v --jobs 4 --keep-dir /tmp/vinix-i915-audit-fresh
```

Evidence is under `smp-oct10/cpu-policy-v2-*`,
`cpu-policy-independent-oct12/sampler-prerequisites-v3/`, `scalar-cpu-policy-*-native-v2/` and
`cpu-policy-v2-full-audit/`. Disk-full preparatory runs and
partial extraction/audit attempts remain labeled and unpublished; fresh
retries pass. Four older root-owned completed worktrees were removed, with
source patches and immutable proofs preserved; do not reuse their paths.
Seventeen older supervisor-control ISOs are `.gz` archives verified against
their original hashes in `archived-control-isos-oct12.json`.

Remaining work includes actual task/MM/vfork rendezvous and retained owners,
encryption/TSC include closure, Linux PCI/devres, DMA/pages/TTM/GEM, IRQs,
DRM/firmware/display and real Tiger Lake validation. GPU support is incomplete.

## Latest original encryption-header selection

CPU policy is committed as `69a4d10f`. The next configuration change selects
the original unconditional x86 `ARCH_HAS_MEM_ENCRYPT` header route, retaining
configured-disabled zero SME/SEV masks. AMD/X86 encryption and confidential
computing stay disabled. No native encryption or Linux page ownership is
implemented by this selection.

Twelve compiler controls and independent original page-mask probes pass.
Configured-encryption controls keep real unresolved external owners; a strict
link rejects their absence. Fresh native worktrees at `69a4d10f` with only
this configuration overlay build enabled/default x86 and default ARM.
Enabled ELF `25b5ea1fa5791569e2fa01474d911ef663d36fc17064f21b2d0afdfdf78e37ab`
boots normal/SSE guests with the existing allocation equalities preserved;
default Linux-ABI startup passes. The isolated full syntax audit remains
**5/269**, with all 33 encryption-mask first errors reaching actual aggregate
`pmd_t` atomic-exchange type checks. The largest group remains task/MM/vfork
ownership, 225 files.

Evidence: `smp-oct10/mem-encrypt-*`, `sme-*-native/`, `sme-guest-review/`
and `sme-isolated-full-audit/`. A shared-tree audit overlapped newly written
TSC files, rejected the changed source snapshot and published no coherent
result; use the isolated report. The completed CPU worktrees were removed
only after exact saved artifact/source checks; their runtime caches were
copied into the fresh architecture worktrees. Immutable v2 proofs remain.

Next compilation/runtime work includes aggregate exchange witnesses, raw TSC,
actual vfork rendezvous and task/MM/GFP scopes, then PCI/DMA/DRM/firmware.
Hardware validation remains required for driver completion.

## Latest native raw TSC increment

Encryption-header selection is committed as `cb9d07f2`. Raw `rdtsc` now has
a real V/native instruction bridge and the exact unsigned-long-long Linux
facade. The original `get_cycles` guard, MSR constants/UAPI/shared types and
both include orders are preserved. Ordered TSC, MSR operations and clock
synchronization remain unsupported.

Four strict host profiles and four native instruction object profiles pass.
Host observations cover 1,160 values per profile, every bit/complement,
single invocation and both original feature/configuration paths. Producer
flags and exact generated bodies are checked before execution. Earlier test
global-name and producer-metadata mismatches were rejected, not normalized.
Actual module export guards are separately reviewed and warmed at bootstrap;
do not assert whole export-thunk equality across different producers.

Fresh architecture worktrees at `cb9d07f2` with eleven production/tool overlays
build enabled/default x86 and default ARM. Enabled ELF
`95542475f713df3dfd57f40167f97d22141450a11a8d43d220fd7d113e99793e`
boots fresh normal/SSE/four-level states, each with 46 required markers and
28 strict existing allocation equalities. Repeated native raw/guarded queries
preserve IRQ/pin state and recover fourth-batch pages/live counts; normal/SSE
free bytes are `387420160`, four-level `387448832`. Default startup passes.

Use `raw-tsc-*-vm-retry/` for enabled guests and `raw-tsc-default-vm/` for the
default guest, with the exact `raw-tsc-*-native/proof.json` records. Initial
ISO construction/default V source staging hit disk exhaustion and establish
no guest success. Evidence and independent reviews stay under `smp-oct10/`.
The completed SME worktrees were retired only after exact saved artifact and
source checks; copied runtime caches remain private to each architecture.

That increment's coherent audit remained **5/269**, with 226 task/MM/vfork and
33 aggregate exchange first errors. The private generic exchange witness design
under `aggregate-exchange-design-oct12/` was not yet implemented at that snapshot;
the completed increment below preserves the required rejection, alignment and
separate scalar128 boundaries.
Actual vfork rendezvous still needs retained actor/process owners, non-last
actor exit and abort semantics; see `vfork-native-design-oct12/design.md`.
Neither a predicate nor dummy task fields completes MM/GFP ownership.

Continue through genuine device/DMA/DRM/firmware dependencies. Tiger Lake
identity and physical/passthrough validation are still pending; GPU support
remains incomplete.

## Latest typed aggregate exchange increment

Raw TSC is committed as `0a94db7c`. The V ABI generator now accepts naturally
aligned 1/2/4/8-byte records/unions through an unevaluated generic type witness.
Original Linux wrappers and the V exchange/CAS backend remain unchanged.
Operands are captured once; exact old/new bytes are retained. Const, floating,
array, packed, width3 and explicitly aligned16 aggregate controls fail genuine
compiler checks. Scalar128 controls retain prior helper imports only, without
execution or an expanded availability claim. No MM service is supplied.

Two sanitizer profiles each pass 792 cases, 16,000 concurrent token exchanges
and 16,000 successful CAS increments. Four genuine freestanding production
objects import only `memcpy`. One independent no-override replay and source/
lifetime review bind the repository generator, genuine original types and
all compiler dependencies.

Fresh native architecture worktrees at `0a94db7c` plus six exact integration
paths build enabled/default x86 and default ARM. Enabled ELF
`0fbde437f087f965aea860649857394c80e8ba0fa817fc5fa63d545740674e45`
boots normal/SSE/four-level guests, each with 46 markers and 28 strict allocation
equalities. The native fixture uses ten concrete original/record/union types
on the stack and original `xchg`/`cmpxchg` wrappers. Across four query cycles it
executes 120,000 calls with IRQs on/off and nested pins. Fourth-batch free bytes
return to `387395584` for normal/SSE and `387424256` for four-level; live heap
counts remain equal. Default Linux-ABI startup passes. Exact actual C/object
review distinguishes the allocation-free warmed module guard from standalone
exports. Completed raw-TSC worktrees were retired only after exact saved
artifact/source checks; private runtime cache copies remain available.

The isolated coherent audit remains **5/269**. Its 33 former aggregate first
errors now reach genuine `boot_cpu_has_bug` dependencies; 226 task/MM/vfork,
two timer and one each entry-stack, IRQ-header and nested-lock errors remain.
Use `aggregate-final-isolated-audit/` and the exact `aggregate-*-native/`,
`aggregate-guest-review/` and `aggregate-independent-review/` evidence.
Full link, Tiger Lake PCI identity and physical/passthrough validation remain
pending. Continue genuine CPU-bug policy and task/MM/GFP ownership work, then
device/DMA/DRM/firmware services. GPU support is incomplete.

## Latest nested IRQ-save spinlock increment

Typed aggregate exchange is committed as `41587f08`. Normal/raw nested
IRQ-save forms now preserve the original configured-disabled lockdep flags
type witness, subclass elision and native IRQ/pin restoration. Runtime logic
is a V leaf; structured ABI metadata generates the original compiler witness
and post-acquisition flags assignment. Ordinary IRQ-save ordering and non-IRQ
nested-class handling are outside this increment; configured lockdep remains
unsupported.

Two focused strict sanitizer profiles, an independent replay, 38 compiler
profiles and seven malformed-metadata controls pass. Twelve compiler cases
are accepted and 26 rejected. The actual leaf/module C and native objects are
reviewed, including allocation-free guards, stack locals and fixed arrays.
The broader host suite is not a fresh passing result.

Fresh architecture worktrees at `41587f08` plus five exact production/tool
overlays build enabled/default x86 and default ARM. Enabled ELF
`0d463db9277a7070002e271d8ede652c1fbcf96144d2f6def89371621c012d4d`
boots normal/SSE/four-level four-CPU guests, each with 46 required markers and
28 existing strict allocation equalities. The new nested fixture executes
1,600 cases/3,200 acquisitions inside the existing 200-runtime page-recovery
measurement, which retains no pages. Those 28 other rows do not measure a new
per-case heap counter. Default startup passes; actual default/ARM C and ELF
exclude compatibility fixture symbols.

Important build-isolation correction: the copied V executable alone did not
select the copied standard library. On this macOS driver, use all of:

```sh
export VEXE=/Users/alex/.cache/vinix-linuxkpi/smp-oct10/toolchain-native/v
export V_MACOS_V3_CALLER_VEXE=/Users/alex/.cache/vinix-linuxkpi/smp-oct10/toolchain-native/v
export V_MACOS_V3_CALLER_VEXE_PRESENT=1
export V_MACOS_V3_CALLER_VCHILD_PRESENT=0
```

These assignments must be present in the build environment. `V3CACHE` and
`VTMP` are architecture-private; `VCACHE` alone does not isolate this compiler.
The private transparent V launcher adds `-nocache -gc none` for host helpers
and forwards every original argument/status. Earlier failed compiler outputs
were archived before regeneration; no SDK/shared compiler source was edited
and no compiler errors were hidden. Authenticate the actual frozen SDK include
paths as well as the executable hash. Exact launch/source/object/ELF evidence
is in `nested-spin-build-profile.json`, `native-compiler-diagnosis-oct12/`,
`nested-spin-*-native/`, `nested-spin-guest-review/` and
`nested-spin-independent-oct12/` below `smp-oct10/`.
Earlier successful artifact records bound the compiler executable but did not
establish the copied standard-library root; the saved aggregate ARM C explicitly
names the live V library. Preserve those exact historical artifacts and qualify
their producer provenance rather than treating them as frozen-SDK evidence.

The isolated full audit remains **5/269**; the nested-lock first error advances
to `might_sleep_if`; the next increment below supplies that annotation.
Genuine CPU-bug policy, task/MM/GFP/vfork ownership, device/DMA/DRM/firmware and full link/hardware
validation remain. GPU support is incomplete.

## Latest conditional sleep annotation increment

Nested IRQ-save spinlocks are committed as `fe594a9c`. The next V leaf and
generated adapter implement `might_sleep_if`: one C scalar predicate evaluation,
no context query for false, and the existing native `might_sleep` invariant
for true. It does not reschedule. This native invariant is stronger than the
configured upstream disabled-debug no-op. File/line reach the bug ABI, but the
current native panic bridge discards those arguments and reports a generic
failure.

Focused GNU99/GNU11 ASan/UBSan tests and an independent cold replay pass 31
safe cases each, eight total fatal children, ten compiler controls and seven
malformed-metadata preservation controls. Thirteen false cases skip the query;
18 true cases query once. Twenty-four selected V bodies and four full-module
leaf/export/initialization bodies are byte-identical before execution. The
staged module does not initialize unrelated workqueue/CPU-mask globals.
Test/control runtime code is V; the C contract only supplies types, includes,
static assertions, symbol aliases and the complex-construction intrinsic.
Grouping is checked in generated source and through V branches, without a
handwritten unbraced-C or postincrement test claim.

Native worktrees are detached at `fe594a9c` with eight frozen native/tool
overlays. The fixture adds five safe annotation calls per measured runtime
iteration: 1,000 calls inside the existing 200-iteration page-recovery check.
Real IF-enabled depth-one/depth-two interrupt frames call the false adapter;
the observer verifies task pointer identity, CPU, IF, pins and nesting. Its
CPU-local snapshots mask IRQs, then restore IF before the adapter and final
sleep/fault queries. The first v3 normal/SSE boots failed because those
snapshots violated `cpulocal.current()`'s IRQ-off contract. Preserve those
failures; the fixed v4 source and regenerated artifacts supersede them.

Final enabled/default x86 and default ARM builds pass. Enabled ELF
`f55eabf3a0f120ff3a3cedcfee7ea734065dfd5ee4a42b69d50d67341bc7fc6f`
passes fresh normal/SSE/four-level guests with all 46 markers and 28 existing
strict allocation equalities. The new 1,000 runtime calls recover the measured
page baseline; the complete IRQ actor lifecycle also recovers pages and heap
counts after three warmups. Those observations are not a new per-call heap
counter. Default Linux-ABI startup passes. Actual default/ARM C and ELF exclude
the compatibility fixture. Independent review authenticates real native
C/object/ELF and extracted guest images as well as source-level lifetimes.
Use `conditional-sleep-build-profile-v4.json`, `conditional-sleep-*-native-v4/`,
`conditional-sleep-guest-review-v4/` and `conditional-sleep-independent-oct15/`
for final evidence, preserving the separate failed v3 states.

Native compiler executable `335214a9...` and its actual copied SDK are selected
together using the four macOS transport variables above. The older host compiler
cannot compile the current typed spawn header, so host helpers use a separately
copied newer compiler/SDK (`26b0f007...`). This is a snapshot of existing compiler
state, including recorded dirty sources, not a pristine compiler rebuild.
The private transparent V router selects native `-gc none` for explicit
`-os vinix` and host `-gc boehm` otherwise. Actual generated SDK paths are
authenticated. Use Boehm for host analysis/provenance loops: an earlier
whole-blob analysis with GC disabled exhausted memory and is not passing
evidence. Initial compiler-header, namespace and guest failures remain archived.
Do not strip compiler headers or include Linux headers in the generic kernel
blob; Linux C facade modules have their own configured include environment.

Latest executed coherent full audit:
`smp-oct10/conditional-sleep-final-isolated-audit-v2/i915-audit.json`, **6/269**.
V3/v4 native observer changes are outside the driver's audited inputs; separate
addenda check the complete guarded input set and regenerated headers. Only
11 units emitted dependency files, so this does not claim complete discovered
dependency graphs for all 269 units. The original software-fence object now
compiles, but eight genuine runtime services still prevent its full link:
`dma_fence_add_callback`, `dma_fence_release`, `dma_fence_signal`,
`dma_fence_wait_timeout`, both unlocked reservation iterator operations,
`irq_work_queue` and `kvfree_call_rcu`.

Read `smp-oct10/sw-fence-link-design-oct15/design.txt` before tackling those
lifetimes. IRQ work needs actual interrupt dispatch and post-callback BUSY
ownership; native ordinary workqueues cannot replace it. Current SMP dispatch
accepts CSD records only, and its local async-call path runs inline in task
context. `kvfree_call_rcu` must support genuine allocator ownership and grace
periods rather than casting an encoded offset to a callback. Current runtime
has no `kvfree`/`vfree` service, and cache slots differ from ordinary allocation
prefixes. Remaining task/MM/vfork, CPU-bug, timer, entry-stack and IRQ-header
dependencies also remain. Full driver link and Tiger Lake hardware validation
are still required; GPU support and the global allocation gate are incomplete.

Focused replay command:
`build-support/run-v-tool.sh tests/linuxkpi/conditional_sleep.v --keep-dir NEW`.
Use fresh private compiler caches and the actual SDK selection above. Evidence
is under `smp-oct10/conditional-sleep-*` and `conditional-host-probe-oct15/`.

## Latest scheduler and IRQ include increment

Conditional annotations are committed as `df3389b5`. The next change restores
the original timer, CPU-mask and completion includes lost by the native scheduler
facade, with completion after task/prototype publication to preserve recursion.
Raw-lock types regain the original unconditional `lockdep_types.h` include.
The new `asm/irq_regs.h` exactly matches the one-line wrapper produced by pinned
Kbuild and forwards to original generic getter/setter declarations. It does not
define `__irq_regs` or translate native interrupt frames. Linux kthread workers,
high-resolution timers and configured lockdep remain unsupported.

Four strict GNU99/GNU11 first-header controls and an independent replay pass
without diagnostics or object symbols. Actual generated-V reference objects
preserve genuine missing IRQ/kthread symbols; final strict links reject frame
storage. The maintained wrapper test now checks all four wrappers and original
IRQ accessor ABI types. Its broader run stopped on original `thread_info.h`'s
signedness warning. Six exact unchanged-baseline/candidate/include-order controls
reproduce the same sole diagnostic, so preserve this inherited failure and do
not claim a full profile pass. No original source or warning flag was changed.

The new full audit is `include-closure-final-isolated-audit/i915-audit.json`,
still **6/269**, with all 7,958 guarded inputs stable. Three previous first
errors move past the intended timer/header gaps. Remaining groups: 228 task/MM/
vfork, 33 CPU-bug policy, one entry-stack type and one original IRQ-number typedef.
Only 11 units emitted dependency files; failed units do not supply a complete
actual include graph. No new runtime or GPU operation follows from these imports.

Fresh architecture worktrees are detached at `df3389b5` with four exact
header/tool overlays, architecture-private runtime copies/caches and the
previously authenticated native/host compiler router. Enabled/default x86 and
default ARM compile/link pass. Evidence is under
`smp-oct10/include-closure-*`. Earlier conditional guest passes belong to their
saved conditional ELF; they are not boots of the new header-build artifacts.
Continue with the real IRQ-number type, original entry-stack records, CPU-bug
policy and task/MM ownership, then the remaining IRQ/RCU-free/DMA/device/DRM
services. Full compile/link and real Tiger Lake validation remain pending.

## Latest hardware IRQ number type increment

Scheduler/IRQ header dependencies are committed as `4abd5cc6`. The next repair
restores exactly `typedef unsigned long irq_hw_number_t` from pinned
`include/linux/types.h:171`. Its C identity differs from `unsigned long long`
even on LP64. Sixteen strict original/candidate GNU99/GNU11 metadata controls
cover x86-64/arm64 and both include orders; eight real absent-type baseline
controls reject. Independent replay authenticates the original header, full
range, unsignedness, size/alignment and clean symbol-free objects. This is a
type declaration, without a new record, allocation, owner or IRQ service.

The original GSC unit now reaches genuine vfork/MM dependencies. Linux IRQ
domains, frame storage, registration, native hardware dispatch and enabled ARM
LinuxKPI are still separate unfinished services. Evidence is under
`smp-oct10/irq-number-type-*`, with the exact one-header source freeze at
`4abd5cc6`. Previous feature logs and ELFs remain unchanged.

Enabled/default x86 and default ARM builds pass in fresh isolated worktrees.
Actual C/object/ELF and dependency review verifies type-header consumption and
unchanged runtime/guard/IRQ bodies; these ELFs have no new boot or allocation
claim. Latest full audit: `irq-number-type-final-isolated-audit/i915-audit.json`,
**6/269**, with all 7,958 guard inputs stable. Remaining groups are 229 genuine
task/MM/vfork, 33 CPU-bug and one entry-stack record error. Only 11 units emit
dependency files; retain that discovery limit. Hardware IRQ services, full
driver linkage and Tiger Lake validation remain pending.

## Latest native x86 UAPI compiler profile

The IRQ-number type is committed as `41f6da03`. Native LinuxKPI CPPFLAGS now
include the original `arch/x86/include/uapi` directory, matching the namespace
already used by the audit. Replaying the actual previous native imported-object
flags on entire unchanged `i915_sw_fence.c` failed at genuine `asm/auxvec.h` in
both GNU11 and GNU99. The genuine directory fixes that compile failure without
replacement headers, source changes, runtime stubs or diagnostic suppression.

The whole object keeps all ten configured public exports and 42 unresolved
imports. The saved native kernel supplies 33; remaining names are the same
eight genuine DMA-fence/reservation/IRQ-work/RCU-free services and
`round_jiffies_up`, whose real V implementation is present in generated native
C but removed from the kernel ELF when unused. No full-object link or native
GPU execution is claimed. Prior controls/classification are preserved under
`smp-oct10/sw-fence-current-closure-oct15-v2/`; new actual build-profile evidence
uses `smp-oct10/native-uapi-*`. All earlier feature artifacts remain unchanged.

All three builds pass from fresh worktrees at `41f6da03` plus only the frozen
Makefile overlay. Actual enabled object/bounds command rows contain the UAPI
directory; default/ARM rows omit it. Native artifacts and eleven unchanged
runtime bodies are authenticated, without a new boot/allocation claim.
`sw-fence-fixed-native-closure-oct15/final-receipt.json` binds the real fixed
compiler command, whole GNU11/GNU99 objects, 274 actual dependencies each,
four unsuppressed original warnings and the runtime-gap inventory. No extra
include path is appended by that fixed-command replay.

The addendum `native-uapi-audit-input-addendum-oct15/addendum.json` verifies
that GNUmakefile is outside the driver's audit inputs and that all 269 recorded
commands already contain the exact directory. All 7,958 guarded inputs and
regenerated ABI/bounds are unchanged. No new full audit was needed; the last
executed result remains **6/269**, with the same task/MM, CPU-bug and entry-stack
blockers. Full driver link, hardware PCI identity and real GPU validation remain
unfinished.

## Worker priority ownership and IRQ rejection (2026-10-15)

The priority setter now compares Process pointers and rejects a live maskable
IRQ frame before mutation even with IF enabled. Existing valid nice publication
and ordinary scheduling remain unchanged. The native worker IRQ test now checks
both binding and nice rejection with the same retained interrupted actor and
post-IRET acknowledgement; priority overrides/flag, base/effective timeslice and
migration pin are unchanged. It has 200 eligible actual callbacks per batch,
three warmups and one measured fourth, with exact pages/all live heap recovery.
No new allocation/reference is owned. The complete normal/SSE/four-level guests
pass all 54 markers/36 strict rows; default startup passes without LinuxKPI.

Frozen production2 at isolated baseline `219a33d6f` SHA256:
`b9defe84de05c744db24b09d9944ba447e1ebd744bd61459a2f00de511e9b979`.
Enabled/disabled x86 and disabled ARM builds pass. Final enabled ELF SHA256:
`3521ba24edfadecf91ec1564bf4d47b926509414b3dcf55c548299e24a10b690`;
default ELF SHA256:
`37b88d958948cc502e9323ca4369596572737ac94bf0a1ff66c2121fe713a279`.
The separate stddef header feature is excluded from these build overlays.

Maintained V `worker_priority.v` passes six strict GNU99/GNU11 O0/O1/O2
sanitizer profiles and six freestanding objects. Each run has 64,590 cases,
two separately derived historical controls and 763,350 assertions. Host CPU/
IRQ/task/store/scheduler leaves are explicit models; no native dispatch claim
comes from them. Manifest40 actual definitions/two production bodies binds
208 input snapshots and 77 artifacts. Result SHA256:
`e21e9030417515df8282afcd11472f33f3ac7be88e87c0d13895cca4271f2e4a`;
four-path manifest SHA256:
`5b6c82d4600940060e506a2b00e47640a7ded191a1abd1add1f8243a8dd07f57`;
independent host review SHA256:
`b68da465cacb94bdecc86bba0f4a0104dceb6db9162c42c2450c9b055eaa41a4`.
Independent production2 source/lifetime review SHA256:
`d8612031aae8fa34ff079a76021409fa7553431c30105f7e65d3d523cc403e2d`;
actual enabled x86 C/O2/ELF and disabled ARM review SHA256:
`532cbffa91db6b0d08960d684b5af7fdd6bb67e0c2ba53256558d2be0884bf98`.

Evidence is under `smp-oct10/priority-*` and `worker-priority-*`. The earlier
author-only frontend invocation issue and bounded O2 timeout remain labeled;
the exact complete root builds and saved objects are the executed evidence.
GPU support remains incomplete. Continue through original declaration closure
and real task/MM, device, mapping and DRM dependencies.

Final four-guest artifact/ISO/chronology and parser-control map SHA256:
`a933c5e082bdd51a7e5e9ae3a4d4c7758af775dfe2f4ac97ff0d33c2bee65273`;
independent four-guest/default artifact review SHA256:
`39a837fa711234987741480e83577ad50ecbe7841907cd14a1c8d516b11e2527`.
Default raw C still contains ordinary unlinked helper definitions, matching its
previous baseline; linked APIs and conditional IRQ tests are absent. The early
overbroad reviewer assertion is preserved without treating it as a production
failure. The final review authenticates all saved default compiler artifacts.

## Latest page-backed deferred RCU free increment

Native `kvfree`, `kvfree_call_rcu`, embedded original `kfree_rcu`/`kvfree_rcu`
and headless `kvfree_rcu_mightsleep` now work for page-backed kmalloc owners.
The 32-byte prefix's unused tail holds a discriminator; its initialized low
byte rejects packed-cache slots before reading the whole tag. Full original
allocation geometry and embedded-head containment are validated before head
mutation/publication. This requires a caller-owned live pointer, not arbitrary
pointer validation. Cache slots, vmalloc and vfree remain unsupported.

Private embedded offsets below 4096 use the original intrusive callback field.
Zero is valid. No allocation or invalid function-pointer construction occurs
on enqueue. Dispatch copies successor/raw bits before clearing and invoking or
freeing; nothing reads the head afterward. Callback/barrier ordinal completion
follows actual freeing. Headless calls require ordinary sleepable task context
and use the pinned implementation's legitimate synchronous GP/free fallback.
External producers and readers still have their ordinary ownership duties.

The focused host suite passes both production C dialects and ASan/UBSan,
181 full-module-identical generated bodies, two safe runs and 36 fatal children.
The original RCU matrix passes 70 safe and 12 fatal children. The old ordinary
transport explicitly aborts if it enters allocator branches; only the new
fixture executes actual runtime/cache allocation ownership. No fake allocator
or queue model supplies the new coverage. Repeat:

```sh
V=<authenticated-router> V3CACHE=<private-cache> VTMP=<private-temp> \
  build-support/run-v-tool.sh tests/linuxkpi/deferred_free.v \
  --keep-directory <new-directory>
```

Fresh isolated builds at `b5f2131e` plus 14 frozen paths pass enabled/default
x86 and default ARM. Saved enabled ELF is
`1ec6c7ce063aec1ea206f386e875c5eeda1c8144fce6ed2830415a4176e545a7`.
Normal, SSE and four-level guests each pass 47 markers and 29 strict allocation
rows. New native coverage holds real implicit readers, queues with IRQs off and
pins held, mixes embedded frees with self-free/requeued callbacks, waits a
headless actor and joins both actors through actual off-stack retirement.
Three warmups precede a fourth lifecycle with exact PMM and every live heap
class restored. The enqueue context is an ordinary IRQ-off/pinned task, not an
actual interrupt handler. Default startup passes; actual ARM/default C/ELF
exclude the feature. Independent generated-C/object lifetime reviews pass.

Evidence root remains `/Users/alex/.cache/vinix-linuxkpi/smp-oct10`.
`rcufree-native-freeze-v2.json` SHA256 is
`34d81f4350c0fca3fdfc94dcb20efd32aa70640fca54802cb170a2f0a0d689f7`;
`rcufree-guest-review-oct16/final.json` SHA256 is
`d2aef5cb646dc6a59a7b0e6b072e95b2bce7e088771564a23b8e554e7a3f9615`.
Focused host result: `rcufree-host-oct15-final-v2/result.json`, SHA256
`3ef4b633092f3334a9cc8923945cd1ef385399e2946e3a97b0f9a91f6ac95cc8`.
Preserve the first failed x86 generator-allowlist attempt and the original
13-path freeze; v2 adds the genuine maintained generator choice. Native code
uses compiler/SDK `335214a9`; host tooling uses copied compiler/SDK `26b0f007`
through the existing V router. Import verification still passes 7,668 files.

The next dependency at this increment was IRQ work, now implemented below.
i915 uses ordinary initialization,
local deferred queueing and breadcrumbs synchronization. Do not reuse local
`smp_async` execution: it invokes inline and breaks GuC lock ordering. Actual
hard-IRQ dispatch, pending/busy/requeue ordering and post-callback ownership
must follow the pinned semantics. Review original `kernel/irq_work.c` in
`sw-fence-link-design-oct15/reference/` and the native SMP IPI transport first.
DMA fence and reservation lifetime/producer APIs remain a larger separate
service; implementing only two reservation iterators cannot supply ownership.
The last executed full audit remains 6/269. Full driver compile/link, confirmed
PCI identity and real Tiger Lake validation are still pending.

## Latest native IRQ-work increment

Original IRQ-work records/macros now use a real dedicated maskable APIC vector.
Ordinary local work defers through a self-IPI; remote queueing wakes its selected
CPU. Local lazy work is promoted only by the actual PIT handler, not generic
clock-update hooks. Remote lazy work raises immediately. Empty-list transitions
coalesce doorbells. `CONFIG_IRQ_WORK` and `CONFIG_X86_LOCAL_APIC` select the
genuine original declarations and APIC-capability helper. NMI, RT, hotplug,
NOHZ and general Linux IRQ registration remain unsupported.

Preserve original PENDING/BUSY flags and post-callback BUSY CAS. Cross-CPU
requeue may overlap callbacks; the public bit is not an execution count.
Private pointer-only stack running records share one IRQ-save lock with claim,
retirement and sync scans. They prevent sync from returning while a concurrent
callback still executes after BUSY clears. Objects must remain backed through
post-callback retirement; real RCU deferred free is supported. Immediate free
requires a separate valid ownership mechanism. The request execute cache's
`SLAB_TYPESAFE_BY_RCU|SLAB_RECLAIM_ACCOUNT` is still rejected by native caches.
Do not claim that caller works merely because IRQ-work APIs exist.

Focused host checks pass 32 sanitizer runs: 14 safe over seven CPU counts up to
256 and 18 fatal controls. All 88 selected production bodies are identical to
full modules; no algorithm adapters or implicit production allocation imports
are used. Four owned host paths are frozen by
`irqwork-host-oct15-four-path-manifest.json`, SHA256
`b5d108d1c471e875aae8dac334853de091846f39000c6f2255c065cd73d515e2`.
Repeat with the authenticated router and private V caches:

```sh
build-support/run-v-tool.sh tests/linuxkpi/irq_work.v --keep-directory NEW_DIRECTORY
```

Both first native guests failed exact heap equality. A local node published to
the ledger became a hidden 72-byte `memdup` allocation per lifecycle; a fixed
array also escaped in compiler preflight. Final code stores that parallel
control node explicitly in the boot ledger, resetting it only after drains and
actual actor retirement. The production execution records remain genuine stack
objects. Preserve failed v1 source/C/ELF/logs and the fixed-array preflight; no
assertion was relaxed. Final review checks all new generated function bodies.

Fresh builds at `a97f0490` plus 14 frozen production/tool paths pass enabled and
default x86 and default ARM. Freeze v2 SHA256:
`5da9fea0111d715de73cd36a19b9731a4488137e91e09d9e885503938c7c3e8e`.
Final enabled ELF:
`c5fa1b88cd414dd71dfc2ecf3ef912ef5f4d504af9681d7e2f56b88254419bbb`.
Normal, SSE and four-level guests each pass 48 markers and 30 strict allocation
rows, including exact fourth-lifecycle PMM/all-live-heap recovery after three
warmups. Native cases cover real target IRQs/idle wake, lazy ticks, concurrent
callbacks, record-aware sync and nine RCU-deferred owners per lifecycle. Default
startup passes; actual ARM/default C and ELF omit the service. Independent
allocator/fixture and backend lifetime reviewers approve saved C and objects.
Final native approval: `irqwork-guest-review-oct15/final-v2.json`, SHA256
`a14b6ae1aac5298d4a8c3c044fda518379d659daa24ad2085411250033ecaa7b`.

The final v2 full audit remains 6/269, with 7,971 stable broad guards and only
11 emitted dependency files. First errors: 229 task/MM/vfork, 33 CPU-bug queries,
one entry-stack record. Whole original `i915_sw_fence.c` compiles in GNU11/GNU99
with actual native flags and original Kbuild identities. It retains ten exports
and 42 imports; 35 are present in the final ELF, including real IRQ-work and
RCU-free exports. Six substantive gaps remain: four DMA-fence operations and
two unlocked reservation iterator operations. The seventh absent name,
`round_jiffies_up`, exists in saved native C/object and is discarded when unused.
Closure evidence: `irqwork-sw-fence-native-v2-closure/result.json`, SHA256
`7971350ffd48ccf756c9fcbf05e4e6d18df5cbf9e54de1fc92dc18a314ebf162`.

Continue with the coherent DMA-fence core, including custom ops, callback races,
waits, reference ownership and real deferred release, then reservation producer
and iterator ownership. Use original public records: i915 breadcrumbs directly
access flags/list/timestamp. A sidecar record or just four compile helpers is
insufficient. Full driver compile/link, PCI identity, device/memory services and
physical Tiger Lake validation remain unfinished.

## Native DMA-fence core increment

Baseline for the isolated build is `beb571021`, plus 11 frozen production/tool
paths. The original DMA-fence record/ops/callback ABI now has 18 real
synchronization services. Keep `dma_fence_describe` unresolved until a real
`seq_file` sink exists. Arrays/chains were implemented in the following
increment; reservation ownership remains pending.

Preserve stack callback-list detachment before timestamp union overwrite;
save callback/function/next before invocation and never inspect a self-freed
callback owner afterward. Default wait callbacks are stack records. Every
wait-any exit removes earlier registrations before task-put and array-free.
Custom release owns storage and any lockless reader lifetime. Default free
requires a page-backed kmalloc base owner and uses the real offset16 RCU head.
Callers retain a fence reference through waits and registration.

Preflight corrected a hidden sentinel allocation, deep typed-pointer equality
in the separate native facade and Darwin/private 64-bit declaration mismatch.
The original failed sentinel C file was regenerated in place: its preserved
focused reproduction is explicitly a reproduction, not the original artifact.
All preliminary freezes/build logs are retained. Final v4 also preserves
direct-default positive completed/pending fast returns from atomic contexts;
the sleep-context snapshot precedes locking and is enforced only before an
actual positive-wait callback. The wrapper remains an ordinary task API.
Context-ID fetch-add uses the original full ordering.

Final source freeze `dmafence-native-freeze-v4.json` SHA256:
`fd41ea37fc45668cefaf98617c78d7a017f69c1c20220c5b94e384d792e8dd85`.
Enabled proof `dmafence-x86-native-oct15/proof.json` SHA256:
`3a700909c83f94c613aab67bdd0d38e5cd43fe3d43092b7fe713fcd718688bff`.
Exact enabled ELF:
`e1e35d98c6006f18a97f876f66876615862b73e45ccb69f86f7c666e7d942805`.
Default and ARM proofs are in matching `dmafence-*-native-oct15` directories.
Use the same compiler/SDK router as the preceding increment.

Strict host GNU99/GNU11 ASan/UBSan passes 22 runs. Of 353 selected bodies, 350
match full modules; three disclosed existing completion adapters serve only
host RCU bootstrap. Actual allocator/task/time/RCU algorithms execute with
explicit native transport. Host result SHA256:
`9ed2515e8c7356a66dd2665957b122fb75e8947413188d8a1c480b716a062d85`;
four-path manifest `dmafence-host-final-four-path-manifest.json` SHA256:
`ceaa13a318fa4e8d7a9fdf49e2b18c29f38c44d9306282fdc6acfff365104735`.
The previous IRQ-work suite also passes 32 sanitizer runs.

Final enabled/default x86 and default ARM builds pass. Normal, SSE and
four-level guests use that exact enabled ELF and pass 49 markers/31 strict
PMM/all-live-heap rows. DMA-fence has three full warmups then an exact-equal
fourth lifecycle; actual IRQ callback polling, finite/infinite/interrupted
task waits, callback self-free, wait-any cleanup/OOM and held-reader default
free all execute. All actors join and retire off stack before measurement.
Default ABI startup passes and actual default/ARM C/ELF omit the feature.
Root guest receipts are under `dmafence-guest-review-oct15`.
Independent guest/ISO/chronology approval is
`dmafence-guest-independent-oct15/final.json`, SHA256
`f1fddf2d58feab1432b13aaca9de3e8fb0485e148e2591b619513cf01f72da92`.

Independent native lifetime approval:
`dmafence-native-review-oct15/final-native-v4-lifetime-review.json`, SHA256
`775afc9e34059c2b113644b634c5c871be7b8eadba2c68cdb110f169e531041c`.
The other reviewer checks all 173 new actual bodies across blob/headercore/
separate fixture and final host source/evidence. Full audit remains 6/269,
with unchanged import verification. Whole original SW-fence compilation and
symbols: `dmafence-sw-fence-native-v4-closure/result.json`, SHA256
`177cdc7ba5e479044f5a937d2eca33a1826265f0043f23411f3b5a5e78e5321e`.
It retains all ten public exports and 42 imports; 39 imports exist in the
saved native ELF. Two genuine reservation iterator services remain missing;
`round_jiffies_up` is present in actual native C/object and GC-discarded from
the ELF. No whole-object link or GPU execution has passed.

Array/chain containers are now implemented as described in the next increment.
Next implement reservation producer/iterator ownership, including real
growth/ref transfer, partial OOM cleanup and RCU protection. Pinned chain
callbacks deliberately reuse callback/IRQ-work union storage; preserve original
snapshot/CAS retirement and backing through IRQ return.
Reservation unlocked iteration holds one fence reference per returned body,
restarts on list changes or failed get-unless-zero, and uses low two pointer
bits for usage. It requires actual init/reserve/add/replace/fini services.
Growth transfers unsignaled refs, publishes the new list, drops signaled refs
and defers the old list through RCU. Page-backed allocation still needs real
`kmalloc_size_roundup`/`krealloc_array` contracts; do not invent Linux cache
buckets. Verified private research is under `dmafence-native-review-oct15` and
`rcufree-backend-oct16`. Hardware identity and access remain pending; continue
independent work without claiming full i915 support.

## Native fence-container increment

The isolated baseline is `c136b3209` plus 15 frozen production/tool paths.
Complete original array/chain APIs and immutable operations tables are present;
original layouts are 120/128 bytes with 32-byte appended array callbacks.
Constructor success consumes vector/child ownership; OOM does not. Invalid
array count/vector/NULL children warn and return NULL without taking ownership.
Nested containers preserve the original warning and construction behavior.

Preserve signed ANY tails and one parent reference per registered callback.
Error sentinel CAS preserves the first real child error. Pending acquire
precedes enable-bit observation. Chain walk consumes its input and transfers
predecessor references through the original RCU-safe get and CAS win/loss paths.
Final release unlinks predecessors before puts and runs iteratively.

Chain callback/IRQ-work storage is the original shared union. The next child
callback may overwrite and requeue it while an older IRQ dispatcher still owes
its post-callback BUSY CAS. Keep its captured flags/function and pointer-only
running records. Final RCU free must retain backing through real IRQ return.
Never `irq_work_sync` the union while it contains a DMA callback. Native cleanup
signals all producers and waits for callback references to retire while holding
the external head reference. In the final-put-in-IRQ case, a held actual reader
backs raw observations; wait for refcount zero and pointer-only running-record
retirement before taking the barrier snapshot. Refcount zero alone can precede
the release body's RCU publication.

Source freeze `fencecontainer-native-freeze-v1.json` SHA256:
`1c1d8e2f6659915ed75ec280c3f1c1f34da7865af87d5858f0087131e5fa81bd`.
Enabled proof `fencecontainer-x86-native-oct15-v1/proof.json` SHA256:
`cf14008f658e71960a8636b55ebcc907d247036529a361c611078b18eb6d5e9f`.
Exact enabled ELF:
`0a3fc002078595a35c82dea2accc62788c5a5a7d42e97c35c4a1ef282136254d`.
Default proof SHA256:
`4d3de707b47345198eb3e2cd5390612f8b1a8a1197e79077490f11b5aa4c52ed`.
ARM64 proof SHA256:
`3e00924a0680d6f5564ed851f4bf7b7a558f81ba777bebfde4fad444c311f26c`.
Matching fresh architecture worktrees now use sparse checkout for kernel,
LinuxKPI tests, build support and docs; source bytes remain frozen. Read-only
dependency symlinks and copied architecture runtime caches remain isolated.

Enabled/default x86 and default ARM builds pass. Native complete container
lifecycles have three warmups and a fourth exact PMM/all-live-heap measurement,
including three retained actors, target hardware IRQ signaling, OOM ownership,
signed ANY tails, deadlines, consuming chain traversal, 129-node iterative
release and final owner free behind a remote implicit reader. Actual generated
C and O2 object review covers 145 new function/export bodies.
Independent source/actual artifact approval:
`dmafence-chain-oct15/native-v1-enabled-review/review.json`, SHA256
`33b0e490595098008ca05be433d1310b8d3ef9974eeee0978b9c7bbf44d231e9`.
Normal/SSE/four-level guests each pass 50 markers and 32 strict PMM/live-heap
rows. Default startup passes. Actual default/ARM C and ELF omit the feature;
ARM validation is build/artifact evidence. Independent ISO/kernel/chronology
aggregate `dmafence-chain-oct15/native-v1-validation-summary.json` SHA256:
`996c3932b6f8a28f9958e1c2c41e5b4b791d99a3831b6ec5e35119cbbc7c6af7`.

Strict GNU99/GNU11 host production objects and ASan/UBSan pass 26 runs, with
497 selected bodies/494 exact complete-module matches and three disclosed
existing RCU bootstrap completion adapters. Eight controlled union lifetimes
exercise remote requeue before the earlier post-callback CAS and genuine RCU
exclusion through final modeled IRQ exit; real CAS wins/losses, 40 concurrent
array lifecycles and 1,024-node release also pass. Terminal callback-list bytes
are compared as callback storage, never interpreted as live IRQ flags. Earlier
preflight expectation failures and superseded inspection scopes are retained.
No production source changed for those test corrections. Host result
`fencecontainer-host-final-v2/result.json` SHA256:
`0dde5336ac63cbae761dbd37ec745ef94a7d08f58066e7afb5b90680f756fafa`.
Exact four-path manifest `fencecontainer-host-final-four-path-manifest.json`
SHA256: `30dbe4ea96d505705bb93c4418e55af6d5a212aea154d906f6e88289f367196b`.
Repeat via the maintained V controller `tests/linuxkpi/dma_fence_containers.v`;
the README documents the explicit scheduler, IRQ, CAS, clock and page transport.
The fresh full audit `fencecontainer-final-v1-isolated-audit/i915-audit.json`
remains 6/269 with the exact unchanged 7,668-file import.

Next implement reservation producers and iterators coherently. The pinned
references and allocator design notes are in `dmafence-container-design-oct15`;
do not implement just the two unlocked iterator symbols while leaving producers
or ownership fake. Hardware identity/access and full driver closure remain
pending; continue independent implementation.

Reservation research verified original layouts in native GNU99/GNU11:
`dma_resv` 48 bytes (fences at 40), iterator 48 bytes, private list prefix
24 bytes and mutable Wait-Die class 32 bytes. The archive-checked metadata
receipt is `dma-resv-abi-research-oct15/probe/receipt.json`, SHA256
`00d5db1b5e416c5d65e3f5d391eaec5b81867bb9fe4dfe93a23278432ef22d90`.
The active non-lockdep scope has 15 public functions plus the class; a real
`seq_file` description sink remains separate. Independently confirmed pinned
source corner: restarting an unlocked iterator after concurrent copy replaces
its list with NULL leaves the previous cursor fence intact; the original walk
then returns immediately and can repeat that fence indefinitely. The future
native implementation must explicitly test and document a correction that
drops and clears the prior cursor reference on an empty restart. No reservation
implementation or correction is included in this container increment. Keep the
verified upstream sources unchanged and distinguish native corrections from
exact upstream behavior.

## Native DMA-reservation increment

The isolated baseline is `321bb4c63` plus 13 frozen production/tool paths.
All 15 configured non-lockdep public APIs and the genuine mutable original
Wait-Die class are implemented. Original object/iterator/list/class sizes are
48/48/24/32 bytes. Writer operations enforce actual native lock ownership;
disabled lockdep assertions are not used as an ownership substitute.

Preserve pre-reservation, low-two-bit usage tags, reference transfer before new
list publication, signaled puts afterward and ordinary RCU release of retired
lists. Add/replace get new owners before publication and put old owners after.
Locked iterators borrow; unlocked iterators retain one fence until next/end.
Every copy/get/singleton failure drops temporary references and vectors.
`dma_resv_describe` still requires a real `seq_file` sink.

Two documented native corrections leave the import intact: an empty-list
restart releases and clears the previous cursor fence; a smaller live list
count at a reused address triggers restart before entry reads. Ordinary count
growth keeps the original cached snapshot. Preserve the original weak aggregate
prefix behavior when a concurrent restart returns no next eligible fence; do
not silently promise atomic collection. New host cases reproduce real page
reuse through the page transport and real producer/RCU algorithms.

Native kmalloc size reporting returns its actual requested span, never Linux
bucket sizes or unadvertised physical-page slack. Checked `krealloc_array`
delegates to real allocate/copy/free only after multiplication succeeds. OOM
preserves the old owner. Changing only the requested-size metadata on shrink
would invalidate its alignment geometry and is not implemented.

Final freeze `dma-resv-native-freeze-v1.json` SHA256:
`c0834f4d9232a65603a27b55aba0716ba3669bf6df6b0b59c534efddd9d38b3f`.
Enabled proof `dma-resv-x86-native-oct15-v1/proof.json` SHA256:
`4f5627679641c9c6cef78c123bfef56607a11fd54d2fd9d5366f4c1b307772a8`.
Exact enabled ELF:
`05080e308061d332adc4771edc75a606e2b2aed40e5918263333c1450819e8bb`.
ARM proof SHA256:
`32a259406e7a08a2280e8c6fb26d0af428304d6b4d21e6981e2171f26c886a4c`.
Default proof SHA256:
`822f2a19211782ff1fffd7325ee3b1a18183f4541df2b5d89bbdf111179f85a8`.
Source and compiler freeze remains unchanged after initial sparse-checkout
prerequisite failures: add `tests/native-generators` and `tools/sourcecommand`
alongside kernel, LinuxKPI tests, build support and docs. Preserve the failed
`dma-resv-x86-build-oct15-v1.log`/`v1b.log`; completed native build is `v1c.log`.
Fresh architecture worktrees are under the private
`/Volumes/HommV66Scratch/vinix-linuxkpi-resv-oct15-321bb4c63` directory. All final
native proofs/ELFs, guest images/logs and host results are durable under
`/Users/alex/.cache/vinix-linuxkpi/smp-oct10`. Completed container build worktrees
were retired after exact source/commit/artifact verification; their saved
proofs, guest evidence and audit receipts remain intact.

Strict GNU99/GNU11 ASan/UBSan passes 14 host runs, including six fatal controls
per dialect. Of 638 selected production bodies, 635 match full modules and three
existing completion adapters serve only RCU bootstrap. All 277 fixture bodies
are inspected using unique occurrence keys. The final host result is
`dma-resv-host-final-v1/result.json`, SHA256
`1fee365297b7807c399aa584e5a991be64698ddfb4ae2fa6d87edeaf76882513`;
four-path manifest `dma-resv-host-four-path-manifest-v1.json`, SHA256
`412d425f546b3690dc683c3258d5166dda1a769e55866e37ee99e295acdad268`.
The README lists exact scheduler/clock/page/pointer-load scheduling boundaries.

Enabled/default x86 and default ARM builds pass. Normal/SSE/four-level enabled
guests pass 51 markers/33 strict PMM/live-heap rows. Reservation tests have three
complete warmups then the exact-equal fourth lifecycle, with three retained
actors joined and off stack before measurement. Default startup passes and
actual default/ARM C and ELF omit the feature; ARM is build/artifact evidence.
Independent actual native C/O2 artifact review of backend/bindings/helpers:
`dma-resv-native-independent-v1/review.json`, SHA256
`8abea2c788482f70a3764ef4c4a72c8f9dab2a4ca6727b5686125fe4a9096c37`.
Reciprocal independent native fixture/root integration review:
`dma-resv-independent-x86-oct15-v1/review.json`, SHA256
`30a8862488503bc5d305748f33506e01a82ee64337a97ee49569df6813820fc8`.
All 168 new actual function/export bodies are covered, along with original
mutable class bytes/relocations and genuine stack aggregate cursors.
Independent final host evidence review:
`dma-resv-independent-host-oct15-v4/review.json`, SHA256
`07670cb578264324b6b69204bdf39648d2d1d8a0b1225130d1512f128f3a0818`.
Reviewer-only typed JSON decoding failed before producing a receipt; preserved
failed tools/logs are separate from the passing host execution. The completed
review uses dynamic parsing over the same frozen evidence.
Independent actual ISO/kernel and allocation chronology aggregate:
`dma-resv-guest-independent-oct15/final-v1.json`, SHA256
`f188c50c526610812aeecd0770ee500fa7eaed9537e2a1ac313c569c0ea8d1f2`.

Fresh full audit `dma-resv-final-v1-isolated-audit/i915-audit.json` remains 6/269.
Independent input/import review checks 8,026 combined frozen/generated/dependency
paths and all 7,668 unchanged imported files:
`dma-resv-independent-audit-oct15-v1/review.json`, SHA256
`819ca3e0bac0e7f5fcad4f45eb42fde5213da034637e96e21fef1f0b681355ad`.
Continue through actual driver/core consumers and remaining device, memory and
DRM services. Full driver compile/link, confirmed PCI identity and physical
Tiger Lake validation remain pending.

## Latest unchanged software-fence increment

The isolated baseline is `59b1e9ac5` plus nine frozen production/tool paths:
the new native self-test, typed facade and two metadata headers, plus Make,
bridge, fixture allowlist and the two public VM harness policy/marker files.
The complete original `i915_sw_fence.c` is now compiled, linked and executed;
all ten configured exports survive the actual enabled ELF and every original
import resolves. The four pinned Kbuild identities are preserved. Keep the
original source SHA256
`4876074a64e975fd4823d4f442aab9c5a30f857f0ec9b970abea77c84c5491e9`.
This is a synchronization component, with no GPU initialization or binding.

Original storage sizes are SW fence 40, supplied wait entry 40, DMA callback 32
and private timed owner 128 bytes. Preserve the exact original notify enum,
including its nominal identity for Clang function sanitization; an
unsigned-int alias passed ordinary C compatibility assertions but failed the
host sanitizer. The typed facade calls original `__i915_sw_fence_init` with a
valid runtime callback; the public init macro requires a compile-time callback.

FREE may release the target owner, but supplied wait entries must remain live
through the wake callback's later flags read. Waiter backing survives
`finish_wait`. Timed owners keep the DMA callback/reference after timeout until
late DMA, actual IRQ-work synchronous timer shutdown and genuine RCU retirement.
Native tests use a remote ordinary reader through raw-owner metadata/IRQ sync;
current-task RCU cannot surround a sleeping sync. Do not use a generic DMA
callback's 24-byte prefix as a 128-byte timed owner. The dedicated diagnostic
lookup checks allocation span and producer identity before extension reads.

Preserve the original continuation/error behavior and weak reservation
iteration contract. Declining COMPLETE leaves pending zero without done/FREE;
no resumable notification is supplied. Configured DAG/debug-object checking is
disabled. Atomic allocation failure is tested with supported GFP zero; the
limited native allocator does not accept all GFP_ATOMIC bits.

Final freeze `sw-fence-native-freeze-v2.json` SHA256:
`1d26673b11ba2787c0a8996d6d42aeb5ec1dccc11ea6b34aeb8c7ade5e9518dc`.
Enabled proof SHA256:
`bb272b92ae5d055cf8505fc0cbb9f4e93cbb6e8913245e0a9ff3f2dbc43b22c8`;
ELF `31578e45624d33fdd1623d8e0d506fc277b5c6deb94333151f54663e372cb5f4`.
ARM proof SHA256:
`9ec6a410418ce6bb015c66cac56d429e799457098b5e898499e6df1cbb459f02`.
Default proof SHA256:
`f1bfef20bfc2255967415f14534d2a0f0610eb9836cf686337c16edde7db0ef0`.
V1's full x86 V compile caught an i64 fixture OOM gate passed to i32; v2 changes
only that field and rebuilds both architectures. Preserve v1 failure/audit logs.
Author facade preflight alone did not establish a full generic-blob build.

GNU99/GNU11 ASan/UBSan host tests pass 8,296/8,515 assertions. All ten original
exports are retained and exercised; each of 39 host service imports has one
concrete definition, with compiler/sanitizer imports recorded separately. The
earlier native compile inventory has 42 imports and is a separate profile.
723 selected V bodies comprise 720 exact bodies and three disclosed completion
adapters; 268 fixture occurrence keys are inspected. The typed notice transport
is explicit; full preprocessing against the genuine variadic control differs
only in the sink identifier. Host result SHA256:
`1907b9231e4c78633f9b6339ca1cc7806860aa6ae85d6277c43eb3eb030cb54b`;
four-path manifest SHA256:
`0278712d5f56c76d1e5937d29a94e5b6e9823f04d11cc472fa03d4a87620247d`.

Normal/SSE/four-level enabled guests pass 52 markers/34 strict PMM/live-heap
rows, with three complete software-fence warmups before its measured fourth
lifecycle. All three actors join and retire off stack. Default startup and
enabled/default x86/default ARM builds pass; ARM is build/artifact evidence.
Independent native actual-C/O2 review covers all 65 new bodies:
`sw-fence-independent-x86-oct15-v2/review.json`, SHA256
`621c0121719f487b7c2039a57e535680f1ea9515e23dd6608edc7003048a821c`.
Reciprocal root-integration/actual stack review:
`sw-fence-independent-root-integration-v2/review.json`, SHA256
`44a81e595e71403fb6d8a6fddeca4d81eeaae778a92aa51f841b0f6adae0a29d`.
Independent final host source/lifetime/evidence review:
`sw-fence-independent-host-lifetime-v1/review.json`, SHA256
`06bccfd36eb17c387c74dd1c49574f1ddf760d0511d66489c4ccefbdf9425ca5`.
Independent four actual ISO/init/image-id and guest chronology review:
`sw-fence-independent-guests-oct15-v2/review.json`, SHA256
`faf260668a753cc67a5555ca5f6c3e9e5631321111180c954044dfc0595e46e2`.
Final full audit remains 6/269, all 7,668 imports unchanged. Independent 8,028
input/dependency/log review:
`sw-fence-independent-audit-oct15-v2/review.json`, SHA256
`389b2e031184c95714fd9e2c08f76bb7b5321a435b739bd80b54c0fdd82d43fb`.

New worktrees are private under
`/Volumes/HommV66Scratch/vinix-linuxkpi-swfence-oct15-59b1e9ac5`; all final proofs,
ELFs, guest images/logs and receipts remain durable under
`/Users/alex/.cache/vinix-linuxkpi/smp-oct10/sw-fence-*`. Enabled artifacts now
also save the actual storage assembly object before the default rebuild.
Completed older DMA-fence x86/ARM worktrees were retired after source/commit and
saved-artifact verification; all durable evidence is retained.

The next source-backed audit frontier is recorded in
`audit-next-native-services-oct15-v1/review.json`: real L1TF bug queries; coherent
native vfork/real-parent/shared-map identity and task/MM lifetime services; then
page/SG/DMA ownership, mapping pinning/invalidation and MMIO/PCI services.
Adding placeholder task fields or constant CPU-bug answers is not an
implementation. Device binding, full driver/core compile/link, confirmed PCI
identity and physical Tiger Lake validation remain pending.


## Original boot-CPU L1TF query (2026-10-15)

Continue from the implemented original BSP-only L1TF observation, not a constant
answer or all-CPU union. Only `X86_BUG_L1TF` (722) is accepted. Actual IRQ-off
sampling precedes CPU online publication; advertised ARCH_CAPABILITIES uses the
native fault-safe MSR helper. Every boot record is validated, then CPU zero is
published once. Unknown/early/duplicate/unresolved cases fail explicitly. The
complete pinned whitelist, full-family model decode and original u8 family
storage are preserved. AP observations are not a migration-immunity guarantee.

Fresh isolated baseline `156ef022a` plus 15 frozen production/tool paths:
`cpu-bug-native-freeze-v1.json`, SHA256
`0d10f6dd3dd869c5cbe8629bcf9d8213e0e407f5a5d1ffa0260620f0cf16bbd1`.
Enabled ELF SHA256:
`82c7c231a7ed58d4acd91c332edbbc07ba2a71b7c367e4094ed8384e4b34d8d4`.
Enabled/default x86 and default ARM builds pass. Seven enabled guests each pass
53 markers/35 exact PMM and live-heap rows; default startup passes. Three full
CPU-bug warmups precede the measured fourth lifecycle, including all three
actors' actual sleep, query and off-stack retirement. Actual witnesses cover
AMD, affected Intel60 and exempt Goldmont92, plus observed Tiger Lake140 without
ARCH_CAPABILITIES. Requested RDCL0/RDCL1 properties are masked by TCG; both strict
requested-profile gates reject those intended branches. Native positive-MSR
execution remains pending. Preserve this limitation when reporting evidence.

Host six GNU99/GNU11 O0/O1/O2 sanitizer profiles each pass 3,460,560 classifier,
57,600 sampler and 2,380 fatal cases with eight concurrent readers; 54 exact V
bodies, six exact production bodies and six allocator-free import inventories.
`cpu-bug-host-final-v1/result.json` SHA256:
`9ba0ef6c75160fede6d8caf1a02fd3790d10873f622bbb68d54c349229782fe1`;
host-four-path manifest SHA256:
`0807141f24014c8a6c19411b6347fe35d4aaa1c6c0f29d12d556e3860b43d994`.
Independent source review:
`cpu-bug-independent-source-oct15-v1/review.json`, SHA256
`129be35c1ed76674d5d994255fad9b44984295ca7fa2bfdb902e93f1c03a245d`.
Independent actual native C/O2 review:
`cpu-bug-independent-x86-oct15-v2/review.json`, SHA256
`bc14c730b2ea0c6599f772fe8c70fef9c45cd5f62d65d6dde3cbe1d5528f930c`.
Independent host lifetime review SHA256:
`aacf281d9914d9950290994881f57514be23845e2c9571e163fd0ae582215714`.
Independent eight-ISO/guest review SHA256:
`3a03fbc38da99c97a328a178dbe191ad3e01a216618dc61afe4c35fca48ee366`.
Root eight-guest/ISO/chronology proof map SHA256:
`fec44da496ab3a0820f828643f44a113d8a6ed69b15bb65a35996c3e01bd46e7`.
Independent requested-MSR coverage rejection review SHA256:
`355fc603c5072eb76bab75dcbdd76bfb8a003bf74ce39e6957946017c66a2495`.
Default C retains dormant backend functions; initialization/sampling/native
fixture and final public-query ELF export are absent. ARM excludes x86 code.

All evidence is durable below
`/Users/alex/.cache/vinix-linuxkpi/smp-oct10/cpu-bug-*`; private build worktrees
are below `/Volumes/HommV66Scratch/vinix-linuxkpi-cpubug-oct15-156ef022a`.
The last four RAM guest states also have verified durable copies, with source
states retained. The final audit remains 6/269 and checks 8,042 input/generated/
dependency paths, including 8,009 guarded inputs:
`cpu-bug-independent-audit-oct15-v1/review.json`, SHA256
`2d6069da4912e76f50150f94e8bc5f88a3316fec94e587f2b5acbae95fc19ec9`.
Next: correct `slab_flags_t`'s original type-header ownership; real task/MM/vfork
identity and lifetimes; sleep-preserving migration pins if providing those APIs.
Five migration diagnostics are parsed PREEMPT_RT alternatives, not five executed
i915 migration sites. Do not add placeholder task fields or claim Linux page,
MMIO, PCI/DRM ownership from header closure. GPU completion is still pending.


## Slab flag type header ownership (2026-10-15)

The exact original `slab_flags_t` typedef is now owned by `linux/types.h`, with
the duplicate removed from `linux/slab.h`. No allocator mode or lifetime changes.
Isolated enabled/default x86 and default ARM builds pass from `d7b24c4bf` plus
only these two headers. Freeze SHA256:
`e3ceb4721eacf4583a15288172117306003b8fe5ee5893a3d6bbd55528db90ce`.
Maintained `tests/linuxkpi/slab_flag_types.v` passes 48 strict GNU99/GNU11 cases:
24 production objects, 12 valid old include orders, 12 intended old-owner
failures; all 36 compiled objects have zero imports. Actual AArch64 scalar/cache
probes and original Sparse preprocessing are compiler evidence only.

`slab-flag-types-final-v1/result.json` SHA256:
`38d2e36eea13e5235c63a7ab5481625c59c39c2ad8df7975bc8a985734c467cd`;
`slab-flag-types-three-path-manifest-v1.json` SHA256:
`1614cad8cdc4ca05ccf41b0d8b11f46bb8d113b7b942866d5d87ce8b08932aa9`.
This includes 153 saved compiler-dependency byte snapshots. Exact 25-command
isolated replay receipt SHA256:
`b0bae05001e55af8e86eded373bdf8858d92d63680f00c3eee0ce825d8fe9553`.
Independent source, object/input and full-audit review SHA256:
`2da86f390896a22a29190b7b92c6b008f592794cf17012f0edc362d384218ef2`.
The full audit remains 6/269: 229 real task/MM/vfork, 28 type declaration,
five migration API declarations, one entry-stack record. All 7,668 imported files
are unchanged. The 25 slab errors now expose genuine DECLARE_FLEX_ARRAY usage
in original memremap.h, not successful complete translation units.

Evidence/build worktrees are durable below
`/Users/alex/.cache/vinix-linuxkpi/smp-oct10/slab-*`. Migration-pin work may be
in progress separately; it is not part of these type-only artifacts. Continue
through real task/MM, page/mapping/device and DRM dependencies. GPU validation
and full unchanged driver/core compile/link remain pending.

## Task-owned migration pins (2026-10-15)

Native x86 `migrate_disable`/`migrate_enable` store depth and logical CPU+1 in
one atomic Thread tail word, with no new allocation/reference. New and cloned
threads start at zero. Nesting permits actual sleep/preemption; existing
requested affinity remains separate. The outer release restores ordinary mask
policy and posts deferred scheduler notifications. Entry IF and preemption depth
are preserved. Balanced active-task maskable IRQ pairs are covered; idle, NMI,
hotplug and deep-sleep CPU removal are unsupported. Encoding accepts the fixed
boot domain through 256 CPUs; worker binding still rejects machines above 64.
Native tests exercise four CPUs. ARM has the shared zero-initialized field and
scheduler predicate, with no x86 compatibility API.

Mandatory eligibility is rechecked after acquiring a runqueue candidate's lock:
the original precheck alone could admit a task that published a migration pin
before switching off. Release selects and validates against one atomic requested
mask snapshot, avoiding a false fatal when a remote valid mask change stales its
wake hint. Dispatch and post-unlock wake still use latest policy. Empty eligible
snapshots remain fatal. Worker binding away from a pin returns EBUSY before
mutation; Process identity checks avoid structural Process copies.

Final 18-path source freeze `migration-native-freeze-v4.json` SHA256:
`af737fa4de3568b827188d531c03a35eac1ab2fcde91ff99663ce0765b46a5f1`.
Build worktrees start at `6896a6ea9` and carry only that overlay. V3 normal/SSE/
four-level guests passed but predate the snapshot correction; preserve them as
historical evidence, without treating them as final-source validation.

Maintained V host checks stage 34 production bodies unchanged in 129 selected
definitions, retain 256 input snapshots/77 artifacts, and pass all six strict
GNU99/GNU11 O0/O1/O2 sanitizer and six freestanding object profiles. Each run
includes 4,649 fatal controls, six deterministic scanner controls, 48 affinity
publication controls (24 corrected successes/24 historical false-fatals) and
eight concurrent observers. Host transports are models, not real CPU dispatch.
Result SHA256:
`caf0061c6dbe315bdc7dd3272e2344139c1fdab67357e849cf4d2252866c7850`;
four-path manifest SHA256:
`2e2a3e4f50e121a463c34e8ada789248cfbd04a5b33b512713ed84f2c4d76bce`;
independent host rereview SHA256:
`40a8c0b718e9543422de528cc5501aafddeb34ca6fd2248d812d5929eecf03b4`.
Source/lifetime snapshot correction review SHA256:
`23b3bea51f39ed970715bc569b07a29543aea46f3ca7de90a313dde72dfad7a0`.

Enabled/default x86 and disabled ARM builds pass. Final enabled proof SHA256:
`f406092be4f2365f63b03f2ad48bdcf48133854a441c2a4974ebd1678c87a243`;
ARM proof SHA256:
`4d82c0f9619b5598788b042569dd002734c943f6527bf22395115a0b9bc4e096`;
default x86 proof SHA256:
`a468b993508e5f42333bc03fff3b9422daf6678fd1d03646a26bcbcd8fa2e602`.
Final enabled ELF SHA256:
`8851b859bde79880ac2060d8bb9bbe1eec3ed93ef44dea7af8a0ae9461ff620c`;
default ELF SHA256:
`7cf26666ce3fc95fcc322cdb4ab8bfb80de80a7d834a8b99ca7e430782ade107`.

Final normal/SSE/four-level guests and the default guest pass. Each enabled
guest has 54 required markers and 36 strict page/live-heap equalities. All eight
constructor-failure cases (stages1..4 before any actor and after one actor) check
the actual failure index and consumed stage, then recover pages/all live heap
classes. Three full lifecycle warmups precede the measured fourth, each with
600 pin/yield contention cycles and actual timed sleeps. Independent pins,
remote requested affinity, idle target wake, IRQ-off release, actual scheduler
preemption deferral and balanced real maskable IRQ pin pairs are covered.
Every actor joins and retires off-stack before measurement. Generated C/O2
review distinguishes valid allocation-free paths from compiler-generated fatal
bounds diagnostics. These are feature measurements, not a global allocator pass.

The fresh isolated full audit remains 6/269: 232 task/MM/vfork, 30 declaration,
one entry-stack record. All 7,668 imports are unchanged. Independent audit/input
guard review checks 8,053 paths and actual 269 Kbuild commands, SHA256:
`230d93b20e8b8d64c8b30f5fbeea7dce23098ad3ed60d5145a47b340ee0866f5`.

Final four-guest artifact/ISO/chronology and parser-control map SHA256:
`b40c95795f83fac7879b09174cf7fd76febf3890ce93bb6a947ea77030840782`;
independent exact ISO/PID1 reconstruction, observed profiles and guest review:
`a9df2ded1d3c86cd144f98132765cee85b1e8075ba70244673089ff69ecf8722`.
Final independent actual native/shared/constructor/layout/ARM/default C/O2 review:
`06b3cd5b07c34b92cd6ec54ac7c2318ee459b8ba16f283bfd512b6390f70b9c9`.
It excludes the reviewer's authored backend2, covered by a separate reviewer.
Final 17-body backend/shared C/O2/ELF review SHA256:
`fc04706a129927b2a12c9cbb19b857e3576470e488a00357e751cfddfd0f537f`.

Evidence is durable under `/Users/alex/.cache/vinix-linuxkpi/smp-oct10/migration-*`.
Next concrete work includes the legacy priority worker's Process identity and
IRQ-enabled-handler guard, original stddef group/FAM closure, and genuine
task/MM/vfork lifetimes. Do not add dummy task fields. Linux device/page/DMA/DRM
ownership, full unchanged driver/core link and Tiger Lake validation remain
unfinished.
