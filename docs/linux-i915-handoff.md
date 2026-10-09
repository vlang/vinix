# Linux i915 next-session handoff

Updated 2026-10-10 for `/Users/alex/code/vinix`, on macOS ARM64 with zsh.
Native SMP validation baseline: **`a0ae707a`**, with the final feature overlay described below. Recheck HEAD and the worktree before
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
backend. The latest full syntax audit passes **4/269** i915 translation units.
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

## Committed progress

| Commit | Completed runtime change |
| --- | --- |
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

### Ordinary RCU prerequisites

Explicit SRCU counters do not cover ordinary RCU's implicit IRQ-off, preemption
or BH read regions. Native x86 maskable entry/exit and scheduler handoffs now
have real CPU-owned accounting; the final validation below covers actual
nested interrupts and task returns. Linux's full context encoding, softirq/BH
exclusion/dispatch and ordinary RCU remain pending. Current x86 NMI entry also needs paranoid GS and stack
handling: an NMI can arrive during ring-0 windows with user GS or a released
old Thread. A counter hook on the current ordinary thunk would be unsafe.
Do not resolve in_nmi/local_bh/ordinary RCU with constant or explicit-reader-only
stubs. Read-only next-step design is in
`/tmp/vinix-linuxkpi-context-design.md`, with pinned entry reference paths.

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

1. Remaining synchronization (ordinary RCU), SMP/context,
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
