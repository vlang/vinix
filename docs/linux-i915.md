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
build-support/run-v-tool.sh tests/linuxkpi/upstream_source.v fetch
build-support/run-v-tool.sh tests/linuxkpi/upstream_source.v verify
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
`lib/ctype.c`, `lib/siphash.c` and i915's `i915_config.c`, `display/intel_qp_tables.c`,
`i915_memcpy.c` and `i915_sw_fence.c`. These supply timeout policy, DSC lookup
tables, a WC memory-copy component and software dependency fences; they do not
initialize the GPU or submit commands. Importing
the complete i915 source tree is not evidence that the driver runs.

Enabled native builds and driver audits derive `generated/bounds.h` by compiling
the exact pinned `kernel/bounds.c`, extracted outside the verified import. The
generator uses the caller's actual target, configuration and generated ABI
headers, verifies the archive and import, and records compiler/input hashes.
`CONFIG_MMU=1` reflects Vinix's hardware page tables; Linux page ownership,
zones, DMA and GPU mapping services remain unresolved. The native Make rules
track the compiler command and discovered headers, including canonical paths
on macOS. Failed generation preserves the previous header. Individual output
replacements are atomic; the header/provenance hashes detect a mismatched bundle
after a filesystem failure. Mutable build inputs still require isolation.

## Implemented APIs

- Linux integer types, error pointers, overflow helpers and compiler macros.
  Original Linux `log2.h` and `minmax.h` supply power-of-two, logarithm,
  rounding and clamp operations. Exact original `lower_32_bits` and
  `upper_32_bits` retain single evaluation and safe split shifts for 32-bit
  operands. `ERR_CAST` preserves pointer identity while removing const;
  `umode_t` is the original unsigned-short type. Native headers preserve the
  transitive includes required by the unchanged DRM color LUT helpers. The original
  checked `u64_to_user_ptr` conversion, `pgoff_t` representation and pinned
  integer type-limit/overflow macros are preserved. These compiler helpers
  supply no Linux page ownership or address-space runtime.
- `irq_hw_number_t` preserves the pinned unconditional `unsigned long` type,
  including C type identity distinct from `unsigned long long`. It supplies no
  native IRQ domain, registration or routing service.
- Original x86 page-table types and complete upstream page/folio/descriptor
  records are visible through their genuine transitive includes. The compiler
  profile supports five-level paging, matching native Limine support for four
  or five levels. Original UAPI integer aliases, endian/Sparse annotations and
  aligned types have one owner, avoiding duplicate GNU99 typedefs and include
  order conflicts. Linux page ownership, descriptor/PFN services and runtime
  page-table geometry bindings remain unresolved.
  The original unconditional x86 `ARCH_HAS_MEM_ENCRYPT` selection exposes
  the configured-disabled SME/SEV masks. AMD/X86 encryption services remain
  disabled; their original mask values are zero.
- Generated x86 `asm/early_ioremap.h` and `asm/kmap_size.h` wrappers forward
  to the original generic headers selected by the pinned Kbuild. Mapping
  references retain their genuine unresolved symbols; no early-MMIO, fixmap or
  kmap runtime is supplied. Configuration-disabled initialization follows the
  original inline behavior.
- The generated x86 `asm/irq_regs.h` wrapper matches pinned Kbuild and exposes
  the original per-CPU frame-pointer declaration and getter/setter ABI. Frame
  storage and translation from native interrupt frames remain unresolved.
  Scheduler/raw-lock facades restore original timer, CPU-mask, completion and
  lock-class type visibility; this does not supply Linux kthread workers,
  high-resolution timers or configured lockdep.
- Generated x86 `asm/resource.h` forwards to the exact original generic
  resource header selected by UAPI Kbuild. Original resource IDs, infinity
  types and records are available; resource-limit enforcement remains unresolved.
- Original x86 instruction helpers are visible through the genuine
  `processor.h` dependency closure, including the exact 64-byte MOVDIR64B
  helper and `iosubmit_cmds512` loop. Compiler probes preserve their real
  instruction bytes and memory operands. Privileged CR0/CR4 writers and
  alternative patching keep genuine unresolved references. This compiler
  closure supplies no device portal, MMIO ownership or instruction execution
  validation; the following CPU feature bridge is a separate runtime change.
- Original SMP/CSD records, initialization macros and x86 dispatcher records
  come from the unchanged headers. Native CPU queries and scheduler pins retain
  their existing Vinix accessors rather than interpreting GS as Linux's
  `pcpu_hot`. Original early per-CPU declaration macros preserve genuine
  unresolved storage/map references. The exact x86 Kconfig frame-helper
  selection avoids a duplicate generic fallback; with frame pointers disabled,
  the original helper returns `NOT_STACK`, without stack validation. Remote
  callbacks are supplied by the native SMP service described below. Hotplug,
  `smp_ops` and Linux thread-info/TIF ownership remain separate dependencies.
- Original Linux possible, present, online and active masks describe Vinix's
  initialized logical boot CPUs; the dying mask is empty. The boot owner writes
  every word of the original four-word records and the original CPU counters
  before publishing readiness, ahead of compatibility consumers and workers.
  Original compressed `cpumask_of` constants and `cpu_all_mask` retain all 256
  configured bits, independently of the installed CPU count. Publication is
  permanent; hotplug, concurrent initialization, firmware-disabled CPU inventory
  and `total_cpus` remain unsupported. This supplies no remote callback dispatch
  or extension of the scheduler's 64-bit worker-affinity masks.
- Original `cpu_feature_enabled` applies the pinned 22-word configured masks
  to constant arguments. Disabled constants avoid the native query entirely;
  nonconstant arguments retain the original capability-query path. The bounded
  native policy also publishes the common hardware SHSTK capability, with its
  XSAVES, XSAVE, FXSR and FPU prerequisites, and validates active LA57 against
  every CPU's CR4 and native paging geometry. SHSTK hardware does not supply CET task state or
  configured USER_SHSTK. These immutable queries allocate nothing and preserve
  IRQ/pin state; other unsupported words/bits fail explicitly.
- `boot_cpu_has_bug(X86_BUG_L1TF)` publishes the original Linux bootstrap-CPU
  meaning from real pre-online CPUID/MSR observations. Its exact-version
  whitelist and RDCL_NO policy are implemented in V; AP observations validate
  boot completion without changing the BSP result. Queries allocate nothing
  and preserve caller state. Unsupported bug indices fail explicitly. This
  observation supplies no L1TF mitigation or GPU mapping policy.
- Raw x86 `rdtsc` uses the native volatile RDTSC instruction and preserves
  the original unsigned-long-long result type. The unchanged `get_cycles`
  header retains its feature/configuration guard. This supplies no ordered
  TSC read, cross-CPU synchronization, frequency service or MSR operation.
- Ordinary boot-online SMP calls use the original Linux CSD records and real
  native maskable IPIs. `smp_call_function_single`, its caller-owned async
  variant, `smp_call_function_many`, `smp_call_function` and
  `on_each_cpu_cond_mask` have native implementations. Synchronous calls retain
  their stack CSD until callback completion; async dispatch releases its CSD
  before the callback and retains no node access afterward, supporting reuse
  and self-free. Detached batches preserve FIFO within the original synchronous
  and asynchronous classes, with synchronous callbacks first. Mask selection
  captures all four words before conditions run; recursive conditions cannot
  strand an earlier submission behind a deferred IPI.
  Initialization checks the published boot topology and ordinary task context,
  unwinds both checked allocations on failure, and retains two raw owners for
  boot lifetime. Submission allocates nothing. Generic calls require IRQ-on
  task context; caller-owned async calls support IRQ-off submission. Callbacks
  cannot block and preserve the real IRQ/pin state. The native transport keeps
  the complete LAPIC identity and orders queue publication before x2APIC WRMSR.
  Hotplug, NMI/softirq dispatch, mixed `__smp_call_single_queue` node kinds,
  `smp_ops` and NUMA-aware CPU selection remain unresolved.
- Workqueue callback identity excludes real maskable interrupt context. An
  interrupt borrowing a worker's native thread cannot claim its callback or
  chain new work into a draining queue. Ordinary IRQ-off and pinned callbacks
  keep their ownership and may chain work while draining.
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
  Typed exchange and compare/exchange accept naturally aligned 1/2/4/8-byte
  records and unions, including original `pte_t` and `pmd_t`. Operands retain
  single evaluation and exact object bytes. Const, floating, array, packed,
  unsupported-width and 16-byte aggregate operands fail compiler checks.
  Scalar 128-bit dispatch retains its separate existing availability boundary.
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
  With lockdep disabled, normal/raw `spin_lock_irqsave_nested` retain the
  original unsigned-long flags check and discard the subclass argument.
  Their native V leaf evaluates the lock before saving IRQ state and publishes
  flags after acquisition. This adds no configured lockdep or non-IRQ nested API.
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
  either allocation. There is no allocation per reader or callback.
  NMI-safe SRCU, down/up context-independent SRCU and CPU hotplug remain
  unresolved; SRCU does not provide ordinary RCU's implicit read regions.
- Ordinary nonpreemptible RCU retains the original Linux reader and pointer
  publication macros. Grace periods force real maskable interrupts on every
  immutable boot CPU and wait for CPU-owned outer returns with interrupted
  IF enabled, no scheduler pins and no remaining maskable IRQ depth. Arbitrary
  IRQ-off and pinned regions are protected, including callbacks that never
  explicitly call `rcu_read_lock`. Saved IF belongs to the original interrupt
  frame; enabling IF inside a handler does not acknowledge its interrupted
  reader. The IRQ hook uses permanent scalar storage and full memory ordering,
  with no allocation, lock, task borrow or wakeup.
  Two private boot-lifetime pthreads advance grace periods and serial callbacks
  independently of workqueue capacity. Original intrusive heads allocate
  nothing on enqueue; callbacks run with IRQs enabled and preemption disabled,
  may self-requeue or free their detached object, and dispatch never reads a
  head after invocation. `rcu_barrier` captures the submitted ordinal at its
  call boundary and waits for callback return, excluding later submissions.
  Synchronization and polling require a full grace period starting after their
  snapshot; exact upstream cookie comparisons preserve wrap and old-cookie
  behavior. Expedited synchronization uses the same forced native service,
  without a separate latency guarantee. Constructor failures join and verify
  actual off-stack retirement before releasing either worker owner.
  `kfree_rcu`/`kvfree_rcu` now accept native page-backed kmalloc owners,
  with original embedded heads and allocation-free enqueue. Dispatch frees
  only after a future grace period and retires its barrier ordinal after the
  actual free. Headless `kvfree_rcu_mightsleep` uses a real synchronous grace
  period in ordinary sleepable task context. `kvfree` supports the same
  page-backed owners; cache slots and generic vmalloc owners remain unsupported.
  PREEMPT_RCU, NMI/BH/task RCU, CPU hotplug/NOHZ and the completed-cookie
  shortcut remain unresolved. Selecting
  `CONFIG_TREE_RCU` supplies the original nonpreemptible ABI; it does not import
  Linux's hierarchical implementation. Native validation is recorded below.
- Non-RT IRQ work retains original records, flags and initialization macros.
  Local and explicit-CPU submissions use real APIC interrupts; local lazy work
  waits for an actual PIT tick unless another IRQ-work interrupt drains it.
  Queueing allocates nothing. Callbacks execute with IRQs disabled in real
  maskable interrupt frames and may overlap after cross-CPU requeue.
  Original PENDING/BUSY transitions are preserved; separate stack execution
  records make `irq_work_sync` wait for every invocation even if BUSY clears
  while another callback still runs. Producers must stop before final sync
  and destruction. Storage must survive the post-callback flag update;
  page-backed RCU deferred free supplies that lifetime. NMI, PREEMPT_RT,
  hotplug, NOHZ and typesafe-cache ownership remain unsupported.
- The DMA-fence synchronization core uses original Linux fence, callback and
  operations records, including their shared list/timestamp/RCU storage.
  Signaling publishes the timestamp and invokes detached callbacks under the
  supplied IRQ-save lock. Callback owners may free themselves after detachment.
  Custom signaling, status, wait, deadline and release hooks retain their
  original signatures. Ordinary waits use native task state, wakeups and timed
  deadlines; wait-any removes every registered callback before freeing its
  temporary array, including interruption and partial-registration paths.
  Blocking waits require ordinary sleepable context; direct default waits
  preserve completed-fence and pending-signal fast returns in atomic context.
  Original reference helpers, context IDs and standard already-signaled fence
  APIs are available. Default release uses a real future RCU grace period for
  native page-backed kmalloc base owners. Custom release hooks own storage
  lifetime, including any RCU readers. Callers retain references throughout
  callback registration and waiting. The `seq_file` description sink and
  i915's typesafe request cache remain separate dependencies.
- DMA-fence arrays and timeline chains use the original intrusive records,
  appended array callbacks, shared chain callback/IRQ-work union and immutable
  operations tables. Arrays preserve ALL/ANY signaling, signed pending tails,
  first-error propagation, deadlines and borrowed iteration. Chains preserve
  consuming traversal, reference-safe RCU predecessor acquisition, concurrent
  predecessor replacement, context/sequence rules and iterative release.
  Successful construction transfers the original child/vector references;
  failed construction leaves them with the caller. Final owner release uses
  genuine native RCU, retaining storage through the IRQ dispatcher's final CAS.
  The typesafe i915 request cache remains unresolved.
- DMA reservation objects use original records, a genuine mutable Wait-Die
  class and native writer locks. Producers reserve capacity, transfer references
  during growth, publish tagged fence entries and defer old lists through RCU.
  Locked iteration borrows fences; unlocked iteration owns one reference until
  the next step or `dma_resv_iter_end`. Copy/get/singleton, usage filtering,
  waits and deadlines have real ownership and allocation-failure cleanup.
  Native bounds/restart corrections are documented below. `dma_resv_describe`
  still requires a real `seq_file` sink; this supplies no DRM device or GPU VM.
- The complete unchanged `i915_sw_fence.c` uses the native synchronization
  services. Its original dependency graphs, notification phases, DMA callbacks,
  timeout ownership and reservation iteration execute in native tests. A timed
  wait retains its DMA callback owner after expiry until the late DMA signal,
  IRQ-work timer shutdown and RCU retirement. Supplied wait records and sleeping
  waiters must retain their backing through their final accesses. Configured
  DAG and debug-object checking remain disabled.
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
  reports scheduler pins only. Full Linux IRQ/NMI/softirq context encoding and
  `in_interrupt`/`in_atomic` are not implemented.
- `might_sleep_if` evaluates its C scalar predicate once. False predicates
  skip the context query; true predicates enforce the existing native
  `might_sleep` sleep-context invariant without rescheduling. This is stronger
  than the pinned upstream annotation with debug/voluntary preemption disabled.
  Caller file/line reach the bug ABI; the current native panic remains generic.
- Native x86 maskable interrupts have CPU-owned nesting and entry counters
  from CPU initialization onward. Real vectors 32 through 255 enter after
  installing kernel GS; their ordinary thunk returns close the region with
  IRQs disabled before task-return work. Scheduler handoffs close their own
  entry before releasing the outgoing task or changing GS. A scheduler IRQ
  nested inside an IRQ-enabled handler defers the switch and rearms its timer.
  Sleep/fault predicates and voluntary scheduler/pthread operations reject
  actual interrupt context before ownership changes. Blocking event waits
  reject before consuming pending events or attaching listeners. Ordinary
  task wait behavior, including ARM's existing IRQ contract, is preserved.
  This does not implement Linux's context bit layout, NMI entry, BH dispatch,
  IRQ registration. Ordinary RCU uses the saved outer-return state described
  above. Scheduler IST1 still requires
  IRQ exclusion while it is active; nesting accounting cannot repair a frame
  overwritten by reentering that same stack.
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
  acquisition. On x86, each checked page chunk uses a single serialized,
  exact-count `REP MOVSB` transfer while holding the pagemap lock. The portable
  `CPUID` fallback avoids speculative width or count selection after permission
  checks; it adds a serialization cost per chunk. Native vendor/feature-based
  `LFENCE` selection and broader kernel speculation mitigation remain pending.
  Dynamic hardened usercopy checks, x86 LAM and flush-cache variants remain
  unresolved.
- Ordinary `get_user` and `__get_user` read 1/2/4/8-byte scalars, evaluate their
  source and output once, preserve source signedness on assignment and clear
  the complete output on `-EFAULT`. Single-page reads use a width-specific,
  read-only x86 `MOV` immediately after `CPUID` in the same assembly block;
  naturally aligned loads retain the architecture's coherence guarantees.
  Unaligned cross-page reads use protected page chunks and publish only after
  every byte succeeds; they make no cross-page atomicity promise. Page faults
  resolve outside the pagemap lock and retry against fresh permissions.
  Both interfaces use ordinary faulting task context, or resident-only access
  when the current task disables fault resolution.
- Ordinary `put_user` and `__put_user` store 1/2/4/8-byte scalars, convert the
  value to the destination type and evaluate each argument once. Single-page
  writes use one serialized width-specific x86 `MOV` under the checked map
  lock; aligned ordinary-RAM stores retain x86 coherence. COW and missing-page
  resolution occur outside that lock before fresh permission checks. Split-page
  writes may commit a protected prefix before `-EFAULT`; they promise neither
  rollback nor cross-page atomicity. Fault-disabled scopes preserve resident
  accesses and reject missing or COW pages without resolving them.
- Task-owned `pagefault_disable`/`pagefault_enable` nesting survives native
  sleeps, preemption and CPU migration; new tasks start at zero. The operations
  preserve IRQ and preemption state and place compiler barriers around depth
  changes. `faulthandler_disabled` also checks native preemption pins and actual
  maskable interrupt depth. Checked
  user copies and kernel fault handlers reject page-in/COW before allocation
  when resolution is disabled. Unknown direct kernel faults remain fatal;
  Linux exception-table fixups and complete IRQ/NMI/BH encoding remain pending.
  `__copy_{from,to}_user_inatomic` always uses resident-only page chunks,
  returns the exact uncopied suffix and leaves that suffix untouched, including
  at task depth zero. NMI use remains unsupported.
- `__copy_from_user_inatomic_nocache` preserves the pinned x86 unsigned
  32-bit size and signed 32-bit residual bits. It reads only resident user
  mappings, uses actual aligned integer `MOVNTI` stores for 4/8-byte kernel
  destinations, and uses cached stores for page/alignment edges. Each exact
  source load follows `CPUID` in the same assembly block; `SFENCE` completes
  stores before each source-map unlock, including a later mapping failure.
  The exact uncopied suffix remains untouched. It allocates nothing, resolves
  no missing/COW pages and preserves task-fault, IRQ and preemption state.
  Callers own accessible kernel destination storage through the synchronous
  call. Kernel/WC destination exception and machine-check recovery, actual GPU
  aperture mapping and physical WC validation remain pending. Protected-page
  prefix boundaries may differ from Linux's virtual-copy exception fixups.
- `user_access_begin` and its read/write aliases use the generic numerical
  `access_ok` check; end operations supply a compiler barrier. `unsafe_put_user`
  preserves the existing checked scalar conversion/evaluation rules and
  branches to the caller's cleanup label on failure. Earlier successful writes
  remain committed. Scopes open no direct user-virtual access window, retain no
  mapping and change no IRQ, preemption or task-fault state. Scalar access
  inherits the native ordinary/resident-only context contract. Unsafe reads
  and unsafe bulk-copy helpers remain unresolved.
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
- Native PCI discovery builds a privately owned, bounded topology from explicit
  root bus numbers and configured PCI/CardBus bridges. Boot currently supplies
  domain-zero root bus zero; firmware discovery of additional roots remains
  pending. The scanner retains bridges, records their actual parent BDFs and
  allocates device records only for present functions. Cycles, intersecting bus
  windows, malformed headers and transport failures cause complete private
  rollback. CRS responses require a future retry policy and return an explicit
  not-ready error. All eight conventional functions remain discoverable.
  Read-only conventional capability parsing validates links and known MSI/MSI-X
  extents before publishing either capability, including the correct MSI-X
  entry count. Rejected chains advertise neither interrupt capability. Private
  snapshots are freed after scalar copying; published native devices and their
  exact-capacity vector have boot lifetime. There is no rescan/hotplug interface
  or Linux PCI/device/devres registration. BAR/resource ownership, extended
  capabilities and unknown capability payload validation remain pending.
- Boolean static branches without text patching; legacy CPUID feature words 0
  and 4. Original MOVDIRI/MOVDIR64B IDs 539/540 use an immutable intersection
  of the actual boot CPUs' hardware observations. Each CPU samples only these
  two leaf-seven ECX bits before publishing its online acknowledgement. The
  boot owner validates all members and publishes the intersection before
  compatibility users, including a valid empty intersection. Queries allocate
  nothing and preserve caller IRQ/preemption state across migration. Other
  word-sixteen features, hotplug and policy replacement remain unsupported.
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
sh build-support/run-v-tool.sh tests/linuxkpi/nocache.v
sh build-support/run-v-tool.sh tests/linuxkpi/asm_generated_headers.v
sh build-support/run-v-tool.sh tests/linuxkpi/special_insns.v
sh build-support/run-v-tool.sh tests/linuxkpi/cpu_feature_policy.v
sh build-support/run-v-tool.sh tests/linuxkpi/smp_types.v
sh build-support/run-v-tool.sh tests/linuxkpi/smp_headers.v
sh build-support/run-v-tool.sh tests/linuxkpi/cpu_masks.v
sh build-support/run-v-tool.sh tests/linuxkpi/user_access_scope.v
sh build-support/run-v-tool.sh tests/linuxkpi/static_key_declarations.v
sh build-support/run-v-tool.sh tests/linuxkpi/pgtable_types.v
sh build-support/run-v-tool.sh tests/linuxkpi/pagefault.v
sh build-support/run-v-tool.sh tests/linuxkpi/irq_context.v
sh build-support/run-v-tool.sh tests/linuxkpi/uaccess.v
sh build-support/run-v-tool.sh tests/linuxkpi/bounds_generation.v
python3 tests/linuxkpi/audit_generation_test.py
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
passed the full normal and SSE native suites. New copy tests exercise real page holes,
read-only/PROT_NONE pages, demand faults and COW; three warmups plus a measured
batch return every physical page and live heap class to baseline. Independent
source and final generated-C reviews found no retained borrows or hidden
allocations. Earlier normal/SSE and clean-baseline runs exceeded the outer
180-second limit; the final normal run used 600 seconds without changing any
runtime callback deadline. The final SSE run also used that outer limit and
completed the full suite. The paired allocation gate has 414 sites,
192 groups and 158 pre-existing failing groups, with no added groups; this is
not a global allocation pass. The audit at that milestone passed 3/269. Evidence uses
the `/tmp/vinix-linuxkpi-uaccess-oct06-` prefix, including source/provenance,
allocation comparison, independent reviews and preserved failed guest logs.

Scalar-read commit `c3ab77ea` adds ordinary faulting `get_user`/`__get_user`
and serialized x86 page-copy transfers. Strict production-core/header host
checks pass 1,033 assertions per GNU99/GNU11 build with ASan/UBSan. Enabled x86,
default x86 and disabled ARM builds, plus both default Linux-ABI boots, pass.
The same saved enabled ELF, SHA256
`80b9288aaca113d487d90d286b0ae9d201b08ca5ac937298daca34dea9966f4a`,
passes the complete normal and SSE native suites. Those guests take about
700 and 973 seconds with a 1,200-second outer limit; the earlier 600-second
timeout is preserved, and runtime callback deadlines are unchanged.

Native scalar checks cover aligned/unaligned widths, cross-page faults,
protection, demand faults and concurrent aligned-load coherence. Three complete
worker-lifecycle warmups precede the fourth measurement; both resident batches
and the complete joined/off-stack/reaped lifecycle recover exactly every page
and live heap class. The first complete lifecycle retains 8 KiB of physical
pages, recorded in both final logs; later lifecycles are flat. Its allocation
sites are not established. Independent lifetime and actual optimized-object
reviews verify width-local `CPUID`/`MOV`, checked chunk `CPUID`/`REP MOVSB`,
lock placement and no hidden V allocation in the reviewed paths. This is scoped
feature evidence, not a global allocation pass or an ARM LinuxKPI test.
The compiler binary and its runtime library are private, frozen inputs:
recovery of the library after a concurrent compiler update is recorded,
with all 78 actual kernel builtin inputs matching the earlier captured hashes.
Evidence is `/tmp/vinix-linuxkpi-scalar-oct06-final-validation.json` and
`/tmp/vinix-linuxkpi-scalar-oct06-frozen-library-provenance.json`.

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

Typed-pointer checks pass 25,603 strict sanitizer assertions per C standard;
wrong integer types fail compilation. The page-offset type compiles for both
architectures. Integer-limit tests compare the complete production and pinned
headers over 454 boundaries and 4,099 runtime assertions per standard, including
constant-expression and operand-evaluation behavior. The pinned overflow macros
retain their local-name collision limitation for operands named `v`, and
`overflows_type` itself is not a file-scope expression; `castable_to_type` supports
that constant-expression use. Independent checks and exact artifacts use the
`/tmp/vinix-linuxkpi-{user-pointer,overflow-types,page-offset}-oct06-*` prefixes.

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
exit with status 1. The current result is **4/269** translation units passing.
Each invocation generates real native ABI adapter headers from current metadata
in its own temporary directory, ahead of other includes, and cleans up after
all compiler jobs. The same private include tree now contains genuine
compiler-derived bounds. Regression tests cover repeated real compilation,
invalid metadata and bounds-compiler rejection before driver compilation.
The latest isolated report is
`/tmp/vinix-linuxkpi-smp-headers-oct06-enabled-proof/full-audit-report.json`; `i915_memcpy.c`,
`i915_config.c`, `display/intel_qp_tables.c` and `i915_user_extensions.c` pass
syntax. The last unit is not yet linked into the native kernel. Logging/WARN/taint,
device-number types, integer limits and native CPU spin-hint visibility
blockers are cleared. The report uses a frozen isolated source/profile rather
than other sessions' changing metadata. Original page-table types, static-key
declarations and instruction-header closure clear their prior first errors.
Leading first errors include `rcu_read_lock` in 213 units, RCU pointer APIs and
`cpu_feature_enabled`. The seven former CSD type errors now reach RCU.
All fifteen former MOVDIR
declaration blockers advance; complete diagnostics contain no MOVDIR errors.
These are syntax
paths, not a complete runtime dependency inventory.
Even a successful syntax audit would still require actual
object linking, unresolved-symbol checks and runtime/hardware testing.

Generated-wrapper validation executes the actual pinned Kbuild scripts and
compiles twelve strict GNU99/GNU11 objects with genuine private bounds and ABI
headers. Declaration-only objects emit no symbols; mapping consumers import
exactly the six original services. The extra original-header configuration
retains all four initializer/copy externs. Independent replay produces identical
objects and wrappers. The isolated enabled kernel links; its native V C/object
are byte-identical to the fully passed nocache ELF. No guest boot is claimed for
the separately linked wrapper ELF. These compiler checks supply no mapping or
cache runtime. Evidence:
`/tmp/vinix-linuxkpi-asm-generated-headers-oct06-final-validation.json`.

Bounds checks compile four real GNU99/GNU11 profiles against the original
enums and `sizeof` values, reject eleven invalid or changing-input cases,
and check command stamps and malformed compiler markers. Audit preparation
passes four regression tests. Six independent Make checks compile a real
consumer and verify regeneration after flag/config changes, followed by no
rebuild on an unchanged invocation. GNU Make 3.81 tests separate prerequisite
timestamps by whole seconds. Evidence is in
`/tmp/vinix-linuxkpi-bounds-oct06-independent-final/independent-review.json`.

User-access scope tests exercise the actual production V range/store
frontends and compiler macros against independent callbacks: 449,253 strict
ASan/UBSan assertions per GNU99/GNU11, including the unchanged relocation
record, single evaluation, signed/narrow values, prefix failures and cleanup
branches. Independent x86/ARM O0/O1/O2 checks verify compiler barriers and
control flow without hardware fences, STAC/CLAC or added runtime imports.
These compiler checks do not validate native mapping or hardware access.
Evidence: `/tmp/vinix-linuxkpi-user-access-scope-oct06-independent/` and
`/tmp/vinix-linuxkpi-user-access-scope-oct06-integrated-host/result.json`.
Typed static-key extern declarations match the original two wrapper types;
separate actual definitions/consumer objects and existing boolean branches
pass strict compilation, linking and sanitizer checks. No CPU-frequency key
definition or text-patching runtime is fabricated.

Page-type checks compile complete original records and entry representations
under strict GNU99/GNU11, with both kernel-first and UAPI-first include orders
and no typedef-warning suppression. Independent x86/ARM compiler checks verify
all sixteen scalar aliases, endian/checksum/poll types and aligned layouts in
four include orders without runtime imports. Existing user-copy and scalar-store
sanitizer checks still pass. The isolated enabled compiler-profile kernel
compiles and links; its generated native V C/object are byte-identical to the
passed task-fault ELF. This compiler-only milestone adds no native Linux page
operations and makes no guest-boot claim for that separately linked ELF.
Evidence: `/tmp/vinix-linuxkpi-types-oct06-corrected-independent/result.json`
and `/tmp/vinix-linuxkpi-compiler-next-oct06-final-artifacts.json`.

## Remaining driver integration

The complete i915 build still fails. Ordinary per-CPU storage and scheduler
pins, current-task identity, ordinary blocking task states/wakeups and retained
task references now have native implementations. Namespace-relative
PID queries, full Linux interrupt-context encoding and runtime page-table
geometry/ownership still need a bridge. No `mm` field or dummy address space is exposed.
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
   timer modes, high-resolution timers and remaining RCU lifetime interfaces.
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

Task-owned fault-control validation uses the isolated baseline `27aaf760` plus
the owned feature overlay. The same saved enabled ELF
`22979f43e8511c33097d69ef8537781da96831814896390bedd8ccc675ea6ce2` passes
the complete normal and SSE guests, including actual task sleep/migration,
new-task zero depth, resident access under IRQ/preemption guards, demand-page
rejection and real COW rejection/recovery. Three full lifecycle warmups precede
a fourth batch with equal physical free bytes and every live heap size class.
The first normal run passed this feature but failed a later I/O fixture; its
failed result remains recorded, and the cause has not been established. A fresh
normal run of that same ELF passed the complete suite. Default x86 and arm64
builds and Linux-ABI guest startup pass. Host GNU99/GNU11 checks exercise
433,858 fault-depth assertions and eight fatal invariant cases per profile;
separate user-copy checks pass 9,200 assertions per profile. Actual generated
C and optimized objects received independent lifetime and ordering reviews.
Evidence uses `/tmp/vinix-linuxkpi-pagefault-oct06-`, including
`final-validation.json`. These measurements cover this feature and its complete
actor lifecycle; they do not establish a global kernel allocation pass.

Resident non-temporal user-copy validation uses the same isolated baseline and
owned overlays. The saved enabled ELF
`ebecc3ef0e7127f73cec652266dc00572e18eadf41cd88e1998c7c328e8ff783`
passes complete four-CPU normal and SSE guests. Actual separated physical
pages, every source/destination alignment, protected and absent suffixes,
read-only/COW sources and eight native IRQ/preemption/fault-depth combinations
pass. Three complete map-lifecycle warmups precede a fourth with exact physical
free-byte and every live heap size-class equality in both guests. Default x86
and disabled arm64 builds and Linux-ABI startup also pass.

Strict GNU99/GNU11 host checks each pass 25,299,139 ASan/UBSan assertions using
the actual V frontend and public ABI. Eight frontend, eight ABI and six primitive
compiler profiles retain 32-bit size/result types and real integer non-temporal
instructions; independent negative checks reject widened ABI declarations.
Independent review of the actual saved generated C, optimized object and linked
ELF confirms distinct assembly address operands, fences before unlocks, fixed
stack buffers and complete map/COW cleanup without hidden V allocation. Tests
use ordinary RAM; they establish no GPU WC-memory or display/rendering result.
Existing partial map/fork OOM rollback remains outside this feature. The first
compile rejected a reserved V identifier; the reviewed identifier-only correction
and failed result are preserved. Aggregate evidence:
`/tmp/vinix-linuxkpi-nocache-oct06-final-validation.json`.

Native maskable-IRQ validation uses the frozen 28-path integration overlay and
the same saved enabled ELF
`aaad1db6f60f17a4ea84ad98e457c5d2e7687a2b43ca36aa17777309300f3381`
for complete four-CPU normal and SSE guests. Actual nested software interrupts,
hardware scheduler IPIs, idle-target wakeups, sleep/yield and user-mode interrupt
delivery pass. A pending blocking event remains untouched inside a handler.
User-mode entry counters and a later depth-zero task return have separate serial
markers; they do not prove that a particular interrupted task returned through
the ordinary non-scheduler IRET path. Three complete actor-lifecycle warmups
precede a fourth with physical free bytes exactly `348405760` before and after,
and every live heap class equal in both guests. The first warmup retains 14 pages;
the measured fourth retains none.

Strict GNU99/GNU11 IRQ host checks each pass 280,732 ASan/UBSan assertions and
inspect all 224 paired IRQ thunks, 32 untouched exception thunks and the real
saved-CS offset. Fault-control checks each pass 494,347 assertions plus eight
fatal cases. Independent reviewers checked the final generated C, optimized
objects, linked ELF, two scheduler handoff paths, fixture join/off-stack cleanup
and all frozen sources. Default x86 and disabled ARM builds and Linux-ABI startup
pass. An earlier broad event-wait guard timed out on ARM; the final guard tests
actual x86 maskable depth and preserves ordinary task wait behavior. The failed
attempt and passing private diagnostic variant remain recorded.

The disabled ARM desktop harness completes `ops,churn,cache,idle,apps,drag` with
the saved final kernel. It reports retained allocations, including
16–32 KiB per 300-process churn batch, so no global leak-free result is claimed.
The allocation-site gate exits 1 on both the clean `24afa95c` baseline and this
feature: 354 ARM sites, 293 x86 sites and exactly the same 158 failing groups.
The first gate invocation never started because its isolated checkout lacked
the harness; its corrected failure record is preserved. Aggregate evidence:
`/tmp/vinix-linuxkpi-irq-context-oct06-final-validation.json`.

Workqueue callback identity still needs an interrupt-context gate: an IRQ that
interrupts a worker must not inherit its callback/drain-chaining privileges.
The currently shared workqueue backend is awaiting that separate repair and
native regression coverage. NMI/BH entry and ordinary RCU remain unresolved.

Native PCI topology validation uses fresh architecture worktrees at `e2641335`
and the frozen eight-path implementation overlay. Strict GNU99/GNU11 host
checks each pass 7,150,771 ASan/UBSan assertions against the actual topology,
capability parser and checked transport core. Tests cover actual relationships,
malformed bus windows, all eight functions, every transaction failure, each
private allocation failure, repeated destruction and reader quiescence. Host
transport and allocation observers do not establish hardware discovery.

The same saved enabled ELF
`fee7d8617e9ab98e5810f6b84183a3481f3cb4494698fb9c523198b26b129687`
passes the complete four-CPU normal and SSE guests. After three full rollback
warmups, the fourth restores physical free bytes exactly from `420929536` to
`420929536` and every live heap class. Default x86 with the optional fixture
restores `423432192` bytes; actual ARM ECAM/configuration and topology fixtures
restore `960380928` bytes. All warmups also recover their starting bytes. True
default x86 and disabled ARM builds/startup pass with both PCI fixtures absent.
Four configured ARM CPUs do not establish native ARM SMP support.

Independent final generated-C, optimized-object, linked-ELF and source review
checks allocation ownership, callback lowering and complete failure cleanup on
both architectures. Earlier compile failures exposed a global-name collision,
an implicit array clone and a V callback-name collision with `encoding.binary`;
their failed logs and generated C are retained. Final native callbacks lower
directly without interface boxes or vector clones. The first ARM guest attempt
failed during bootloader preparation; the explicit bootloader retry passed.
Recoverable OOM claims cover private graph allocation and raw descriptor
rollback. The permanent publication vector and MSI-X bitmap still use existing
fatal allocator paths.

The broader allocation gate still exits 1: 354 ARM sites, 293 x86 sites and
158 failing groups. Its only site change replaces the old per-probe device
allocation with the boot-owned vector initialization. The separate disabled ARM
desktop harness completes `ops,churn,cache,idle,apps,drag`; it reports up to
48 KiB retained per 300-process churn batch and positive syscall allocations.
No global leak-free result is claimed. Aggregate
evidence: `/tmp/vinix-linuxkpi-pci-topology-oct06-final-validation.json`.

Original instruction-helper validation passes sixteen strict GNU99/GNU11
compiler objects and four deliberately rejected missing-dependency probes.
Independent replays check every input hash, complete undefined-symbol output,
real MOVDIR opcode bytes and original alternative sections/relocations. An
isolated enabled build at `e2641335` plus only the processor-header overlay
compiles and links, retaining genuine unresolved privileged/patching references
in the reference objects; its saved ELF has no new instruction caller or guest
execution claim. Ten additional objects replay actual native Make flags.

The full frozen Kbuild audit remains **4/269**, expected exit 1. All fifteen
previous MOVDIR declaration failures advance to genuine remaining dependencies;
zero MOVDIR errors remain in its complete diagnostics. RCU, `cpu_feature_enabled`,
original CSD integration and other services still block the driver. QEMU TCG
does not expose MOVDIRI/MOVDIR64B on this host and rejects forced feature exposure;
positive instruction execution needs capable hardware. Evidence:
`/tmp/vinix-linuxkpi-movdir64b-oct06-final-validation.json`.

Native direct-store feature-policy validation uses fresh isolated worktrees at
`079e3ccd` with only its six owned native paths and the processor-header
prerequisite now committed in `909f6a4b`. Enabled x86, default x86 and disabled
ARM builds pass. Both complete enabled guest suites boot the same saved ELF,
SHA256 `4dd8a5f11371b90f69387fb446f4f0d8b2c54dc2a8aaf8cc452ec2daf986635f`.
The fourth query batch preserves free bytes exactly: normal
`390782976 -> 390782976`; SSE `390787072 -> 390787072`. Every measured heap
class also matches, after three warmups. Queries run with IRQs enabled,
disabled and two nested preemption pins; caller state is restored. Both guests
observe a valid zero intersection across four actual initialized CPUs. Default
x86 and disabled ARM reach Linux-ABI PID 1 with LinuxKPI fixtures absent.

`tests/linuxkpi/cpu_feature_policy.v` executes unchanged generated policy
and frontend bodies with explicit scalar CPU/atomic/fatal observers. GNU99 and
GNU11 each pass 1,116,514 ASan/UBSan assertions, including all 256 member
positions, genuine 64-bit online acknowledgements and 64-bit V array lengths,
malformed membership, mixed feature intersections, unsupported IDs, immutable
publication and eight concurrent query actors. Eighteen compiler objects and
two genuine cold-header objects retain exact expected imports. Independent
review checks the real full native Local layout, per-CPU sample before online
publication, release/acquire ordering and generated C/object/ELF lifetimes.
Earlier host attempts with narrower private fields are superseded by these
final runs. QEMU exposes neither direct-store bit; this validates feature
selection and query state, without positive MOVDIR execution or device MMIO.

The broader allocation gate still fails with the same 158 groups as its PCI
baseline; no group changes appear. Disabled ARM completes all six desktop
scenarios. Churn retains 16–48 KiB per 300-process batch and some syscall
measurements remain positive, so this is not a global leak-free claim.
Aggregate evidence:
`/tmp/vinix-linuxkpi-directstore-policy-oct06-final-validation.json`.

Original SMP-header integration passes 22 strict GNU99/GNU11 and assembly
objects, with six genuine incomplete-prerequisite rejections. Production and
original CSD/node, cpumask and fourteen-callback `smp_ops` ABI vectors match
byte for byte. Six CPU query/pin/unpin functions retain their expected native
relocations; no Linux `pcpu_hot` reference appears. Original dispatch/mask and
early-map consumers keep eight and six unresolved symbols respectively. Cold
include orders emit no symbols. The unchanged initializer test also passes
420,004 ASan/UBSan assertions per standard, and both actual production full
header probes now compile.

Fresh isolated enabled/default x86 and disabled ARM builds at `909f6a4b` plus
only four header/config paths compile and link. Enabled ELF SHA256:
`f2e594e33c380e620d79c09b278d81109fec17827bf187763e02c13a0e9a570c`.
Saved objects preserve the existing native CPU accessor ABI; linker garbage
collection removes an unreferenced accessor from this ELF. This header change
adds no allocation, callback or IRQ-dispatch algorithm and has no new guest
execution claim. The full audit stays **4/269**, with exactly seven CSD first
errors advancing to RCU. The corrected test uses separate section-dump outputs,
preserves all 22 compiler objects and records the four derived object hashes;
the earlier stale pre-dump receipts are superseded.

`current_thread_info()` still assumes a Linux task/thread-info layout which the
native compatibility task view does not supply. TIF/status accessors and Linux
stack ownership are not enabled by these declarations. Early maps, hotplug,
`smp_ops` and remote callback execution were unresolved at that milestone; the later boot-mask
runtime is described below. Evidence:
`/tmp/vinix-linuxkpi-smp-headers-oct06-final-validation.json`.

Boot CPU mask validation was repeated on 2026-10-07 in isolated worktrees at
`95234fa286b400561671ff68bcc3df45d026dd73`, with only the eleven CPU-mask
implementation and harness paths overlaid. Enabled x86, default x86 and disabled
ARM builds pass with the frozen V compiler and private LLVM compiler-runtime
archives (160 members each). Default x86/ARM guests reach Linux-ABI PID 1 with LinuxKPI fixtures absent.
The enabled ELF SHA256 is
`65038097451fcddbfd33a764ee59fa24942b5967e424f1d12fcf54678af5530a`.

Complete four-CPU normal (`max`) and SSE (`max,hypervisor=off`) guests pass all
42 required markers and nineteen exact free-byte/heap equalities. Each fourth
mask query batch preserves `390762496 -> 390762496` bytes and every live heap
class after three warmups, including IRQ-on/off and nested preemption pins.
The unchanged 3,600-second outer allowance and all intrinsic assertions remain;
runs complete in 275.47/271.42 seconds. The earlier 41-marker FPU binaries are
not evidence for this feature.

The maintained `cpu_masks.v` passes 15,810,213 ASan/UBSan assertions per
GNU99/GNU11 dialect across 17 cold processes. The test preserves 28 generated
V bodies, fourteen native object proofs, every compressed constant view and
exact readonly bytes from the pinned Linux 6.6.157 archive. Cases cover the
64-bit boundaries through 256, invalid counts, repeat publication, complete
mask tails and four joined immutable readers. Host scalar/TLS observers do not
establish native 256-CPU operation, hotplug or remote callback execution.

The publisher and queries introduce no allocation or reclamation. Peer source
review confirms permanent borrowed original storage, a sole boot publisher,
release/acquire readiness and publication before compatibility users. The new
C data file contains pinned upstream constant definitions and native typed
storage declarations; it has no functions or runtime imports. The surrounding
file, declaration headers and authored embedded C test oracle/runner remain
first-party maintained sources. They are not marked vendored and receive no
C-to-V migration credit; they remain follow-up under the repository-wide
first-party C removal instruction.

The earlier draft cited `/tmp/vinix-linuxkpi-cpu-masks-oct06-final-validation.json`
for normal/SSE guests, complete x86 host modules, baseline host-header failures,
an allocation gate and desktop scenarios. That receipt and its worktrees are
absent in this session. Those old claims are archived as unverified draft text,
not carried forward as fresh validation. Durable current evidence is under
`/Users/alex/.cache/vinix-c-to-v/firstparty-only-20261006-011023/`, beginning with
`cpu-mask-oct07-final-validation.json`, with host, native and build receipts
beside it.

## Native SMP and interrupt work identity, 2026-10-10

The final enabled x86 kernel was built in an isolated worktree at committed
baseline `a0ae707a`, with only this feature's overlay and the committed
`9d9d90a3` user-copy fixture owner correction. The saved ELF SHA256 is
`92588ce66dab0bb36262f55221a92679a66641959a85fafefbd1b1ddaae50041`.
Both complete four-CPU normal and SSE guests pass all **44** required markers
and **21** exact free-byte/live-heap equalities. After three warmups, the fourth
SMP actor lifecycle and the separate workqueue IRQ lifecycle each recover
`345255936 -> 345255936` bytes and every live heap class. Tests cover real
hardware IRQ deferral, a 2,048-node intrusive FIFO batch, callback self-free,
overlapping CSD reuse on different CPUs, post-IRET retirement, ordinary work
chaining and rejection of interrupt submissions during an observed drain.

The maintained `tests/linuxkpi/smp_calls.v` runs 72 cold ASan/UBSan processes
per compiler snapshot, covering strict GNU99/GNU11 production bodies, CPU-mask
boundaries through 256, both constructor failures, context preservation,
synchronous-first batch order and recursive/mutating conditions. An independent
reviewer replayed all 144 processes and compared every selected generated
production body with its unmodified generated source. These host CPU/context
observers do not establish native 256-CPU operation. The actual ordered
workqueue host suite also passes 20 interrupt-context/drain regressions; a
private negative control restoring the old identity test fails as expected.

Independent source, generated-C and object reviews cover raw/interior allocation
ownership, original aligned stack CSDs, callback detachment, post-IRET/task
retirement, native constructor rollback and all native pthread exit paths.
The full x86 enabled/default and ARM default builds pass. A fresh default x86
guest passes Linux-ABI startup with compatibility markers absent. The compiler
used for native artifacts is the frozen V binary SHA256
`335214a9c904435eb87e580948a7de76c2b4de03a65f0ee23babaa76981a7373`.

The equal-source official allocation gate exits 1 for both baseline and feature:
318 ARM sites, 261 x86 sites, 376 merged sites, 185 groups and 151 existing
failures, with identical normalized counts. This gate uses the default disabled
profile. Feature-specific enabled measurements pass; no global allocation pass
is claimed. The broad host runner stops at existing pinned-header signedness
warnings promoted to errors in its overflow probe; the separate SMP and
workqueue tests above pass. Desktop `ops,churn,cache,idle,apps,drag` were not
rerun: the official cache identity rejects the available image, and regenerating
its 7.84 GB ISO exceeds available disk space. Earlier claims remain historical.

The final full i915 syntax audit remains **4/269**, with ordinary RCU the largest
first-error group. This runtime feature supplies neither GPU binding nor graphics
validation. Durable build, guest, host, review and baseline-comparison evidence
is retained under `/Users/alex/.cache/vinix-linuxkpi/smp-oct10/`; the final
validation receipt identifies exact inputs and preserves failed earlier builds
and the native fixture's corrected missing `pthread_exit` failure.

## Worker binding from IRQ-enabled handlers, 2026-10-10

Native worker binding now rejects actual maskable interrupt depth before
publishing affinity or NUMA state. A handler that enables IF still borrows its
interrupted thread. The fixture interrupts a bound, unpinned kernel actor 200
times per batch, enables IF inside the real handler and verifies rejection,
restored IF, CPU/task identity, affinity, NUMA hint and the armed allocation
failure gate. Its stack observation remains live through synchronous CSD
completion and the target task's acknowledgement after actual IRET. Actor
retirement joins and verifies off-stack reclamation before resetting its ledger.

The isolated final enabled ELF SHA256 is
`1b4e997729f4f988a0d1c22f0fb450f6decbbdbf8e8acdc5fcb2a5fe98494ba1`.
Complete normal and SSE guests pass all **45** markers and **22** exact fourth
batch page/heap equalities. This fixture recovers `345231360 -> 345231360`
bytes and every live heap class after three warmups. Restoring only the old
predicate in a private kernel makes the same fixture fail at its expected
rejection assertion. Enabled/default x86 and default ARM compile and link;
independent review covers the final source, generated C, objects and native
lifetimes. The first guest attempt caught the fixture checking CPU-local state
with IF enabled; the final fixture captures restored IF and closes it before
native accessor checks. Failed evidence is retained.

This fix adds no new worker allocation. Default profiles exclude the enabled
fixture. The official allocation gate again has the same 376 sites and 151
existing failures as its baseline; desktop limitations remain as recorded above.
A fresh default x86 guest passes Linux-ABI startup without LinuxKPI markers.
Final evidence is under
`/Users/alex/.cache/vinix-linuxkpi/smp-oct10/worker-irq-final-validation.json`.
Ordinary RCU remains the next implementation dependency; this worker fix does
not establish GPU support.

## Ordinary RCU and native V validation, 2026-10-12

The ordinary callback, synchronization, barrier and polling-cookie service
described above is now implemented. Native validation uses fresh detached
x86 and ARM worktrees at **`ebefd710`**, with only this feature's explicit
overlay. The final enabled ELF SHA256 is
`7d0625d34d71b79d4e52664ed5df59a66dcacd118155e04bd572e1d0661763ee`.
Both complete four-CPU normal and hypervisor-off SSE guests pass all **46**
markers and **28** exact fourth-batch PMM/all-live-heap equalities. Ordinary
RCU's measured fourth lifecycle recovers `381243392 -> 381243392` bytes in
both normal and SSE guests. The actual
ISOs contain that exact saved ELF; the SSE run executes the original copy
helper and verifies FPU preservation. Neither run exercises GPU memory.

The maintained V host runner passes strict GNU99/GNU11 ASan/UBSan profiles
at CPU counts 1, 2, 4, 64, 65, 128 and 256, including both worker allocation
and pthread construction failures, 20 overlapping barrier snapshots,
self-free/requeue callbacks and 26 exact cookie boundary cases. Host CPU
counts do not establish native operation on 256 CPUs. Independent source,
actual generated-C, object and lifetime reviews cover the final native
artifact, including the real IRQ frame offset and off-stack worker rollback.
Enabled/default x86 and default ARM kernels compile and link. The final
default x86 guest passes Linux-ABI startup without compatibility markers.

The native heap observers now fill fixed caller-owned buffers without
allocating. A diagnostic traced an observer's old 463-byte array request to
one retained 512-byte-class slab page. A separate, allocation-free scalar
diagnostic accounted for a later 12 KiB loss exactly: classes 48, 192 and
768 each gained one page with unchanged live counts as the controller moved
between CPUs. The scalar fixture now executes its real complete workload
once on every boot CPU, with a bound neighbor writer, before its original
three warmups and measured fourth lifecycle. It restores original affinity
and NUMA state on all returning paths. No equality is relaxed, no allocator
is trimmed between snapshots, and failed earlier artifacts remain recorded.

The fixed online CPU domain rejects deep-suspend/hibernation plans before
filesystem flush, userspace freeze, device suspension or CPU parking.
The same captured plan is used after flushing, so a concurrent configuration
change cannot enable parking after a safe preflight. Suspend-to-idle and
device-only rehearsals remain available. Default profiles keep their original
planning boundary. Both profiles pass 72 configuration/mutation controls;
deleting the rejection makes its production-body control fail as expected.

Boot-image restoration also preserves the CPU domain: the original named-device
lookup and image/parent mode restrictions run, then restoration is declined
before loader allocation or image reads, consumption, memory replacement or
parking. Existing protection for valid and unreadable named images remains.
Both profiles pass 24 metadata/protection cases; removing the guard, erasing
the image or skipping device publication each fails a separate control. The
first pre-open design failed unreadable-device protection review and was
corrected. Removing only the saved-IF IRQ predicate in a private kernel fails
the native held-reader fixture with its deadline; the log does not identify
the precise reader mode or directly observe early acknowledgement.

Import verification, fixture generation, ABI/bounds generation, native guest
supervision and pinned ISO assembly use V tools without Python. The guest
runner preserves the existing marker/failure policy and has separate process,
signal and image-identity controls. The official default allocation gate
still exits 1: baseline and feature have identical **394** sites, **199**
groups and **166** existing failures. This is not a global allocation pass.
Later shared-checkout Ethernet/boot-log commits are outside this frozen
native evidence. The latest complete driver audit remains **4/269**; Linux
task/MM, device, DMA and DRM dependencies and Tiger Lake validation remain.
Durable evidence is under `/Users/alex/.cache/vinix-linuxkpi/smp-oct10/`,
including the `rcu-oct12-*` artifacts and independent review receipts.

## Scalar and resource helper closure, 2026-10-12

The exact integer extractors, `umode_t`, pointer-only `ERR_CAST` and generated
resource wrapper above pass ten strict GNU99/GNU11 ASan/UBSan profiles, including
both type-header orders and a separately generated original UAPI-only path.
An independent V replay passes the same profiles. The actual native `ERR_CAST`
object moves the input pointer to the result without calls or allocation.
The original resource wrapper is generated by the pinned Kbuild scripts,
outside the verified import, and its include bytes match the overlay.

Fresh architecture worktrees at **`1d0f5b00`** contain only the five helper
paths and six maintained V test paths. Enabled/default x86 and default ARM
compile and link. Both enabled guests boot the exact saved ELF
`2c75b056fa5e9eb9da9f8e10598886b69e70cf28966d77e552b7772c6549059a`,
pass all 46 markers and recover every measured page/live object in 28 strict
existing lifetime checks. These integration checks add no GPU validation.

A fresh full V syntax audit passes **5/269**, with unchanged upstream sources.
Task/MM ownership and configured CPU-feature queries are the largest remaining
compile blockers. This parity profile also exposes a missing `KBUILD_MODNAME`
audit flag in one file; that invocation defect is separate from missing APIs.
Task fields, vfork rendezvous, resource enforcement, device,
DMA and DRM lifetimes are not supplied by these helpers. Reproduce the scoped
host checks with `build-support/run-v-tool.sh tests/linuxkpi/scalar_helpers.v`.
Evidence is under `smp-oct10/scalar-helper-*` and `scalar-audit-oct12/` in the
cache root above; the independent helper receipt is
`scalar-helper-independent-review/review-result.json`.

## Configured CPU features and complete V audit tooling

The configured-mask and native SHSTK/LA57 policy above builds in fresh
architecture worktrees at **`86090210`**, with six owned production paths.
Enabled/default x86 and default ARM compile and link. The saved enabled ELF
`0d52878a83cdaf82a9ebd44751beef39fca725a72d9c9d6de381c012e92e1bea`
passes normal, hypervisor-off SSE and `max,la57=off` guests, each with 46
markers and 28 exact PMM/all-live-heap equalities. Native query batches recover
`387440640 -> 387440640` bytes in the normal five-level guest,
`387444736 -> 387444736` in its SSE counterpart, and
`387473408 -> 387473408` in the four-level guest. Actual witnesses report
LA57=1 with geometry `1 << 56`, or LA57=0 with geometry `1 << 47`.
QEMU reports SHSTK=0; these runs establish no CET operation.

Six strict GNU99/GNU11 sanitizer profiles and six freestanding object checks
pass. The V fixture runs the unchanged sampler block through 513 cases covering
every prerequisite flag and leaf acknowledgement, both CR4 modes and the
independent SSE branch. It also covers fixed-domain membership, immutable
publication, original constant/dynamic mask behavior and concurrent queries.

Independent generated-C/object checks preserve every existing Local field
offset and its 1,424-byte size: two new booleans use prior padding. The sampler
runs on each CPU before online publication. Default x86's setup is unchanged;
default ARM's generated C matches after replacing only assertion path prefixes.
The default guest passes Linux-ABI startup without compatibility markers.
The successful constructor and query paths allocate nothing; the generated
kernel object retains exceptional compiler bounds-check panic formatting.

The maintained full V audit now obtains per-object module metadata from the
exact original Kbuild scripts. It keeps compiler/generated inputs and full
diagnostics in a private directory, joins its jobs before cleanup, rejects
changed inputs and publishes an explicit output atomically. The latest correct
profile remains **5/269**. Its largest first-error groups are task/MM/vfork
ownership (225 files), missing encryption-header closure (33), and remaining
timer/entry/IRQ/TSC/lock interfaces. Syntax counts supply no link or GPU proof.

```sh
build-support/run-v-tool.sh tests/linuxkpi/audit_full.v --jobs 4 --keep-dir /tmp/vinix-i915-audit-fresh
```

The corrected saved-ELF guest and review evidence is under
`smp-oct10/cpu-policy-v2-*`, `cpu-policy-independent-oct12/` and
`scalar-cpu-policy-*-native-v2/`. The corrected full report is under
`cpu-policy-v2-full-audit/`. Disk-full preparation/extraction
failures remain separate; fresh retries pass. Four completed owned build
worktrees were removed after saving source patches and immutable proofs, and
old supervisor-control ISOs were losslessly compressed with hash receipts.
Other sessions' files and the verified import remain unchanged.

## Original x86 encryption-header selection

The exact pinned x86 Kconfig unconditionally selects `ARCH_HAS_MEM_ENCRYPT`.
This profile now makes that selection, retaining the original zero SME/SEV
masks with AMD/X86 encryption and confidential-computing services disabled.
No encryption service or Linux page ownership is supplied.

Twelve GNU99/GNU11 compiler controls pass across both include orders, disabled
and configured profiles, and a missing-selection control. Independent original
page-mask probes reproduce the undeclared-mask failure without a fixture guard.
Configured encryption retains four genuine external owners and fails a strict
link when they are absent. Disabled-profile objects import nothing.

Fresh worktrees at `69a4d10f` with only the configuration overlay build
enabled/default x86 and default ARM. Enabled ELF
`25b5ea1fa5791569e2fa01474d911ef663d36fc17064f21b2d0afdfdf78e37ab`
passes normal/SSE guests; existing lifetime measurements retain no pages or
heap objects. Default Linux-ABI startup passes. The coherent isolated full
audit remains **5/269**: all 33 former encryption-mask first errors now reach
the genuine aggregate `pmd_t` exchange type-check blocker. Task/MM/vfork
ownership remains the largest group, with 225 files.

Run `build-support/run-v-tool.sh tests/linuxkpi/mem_encrypt_policy.v`.
Evidence is under `smp-oct10/mem-encrypt-*`, `sme-*-native/`,
`sme-guest-review/` and `sme-isolated-full-audit/`. The concurrent shared-tree
audit rejected changed inputs and published no coherent report.

## Native raw TSC access

The V bridge reads the existing native CPU accessor; a V facade copies all
64 bits into the original Linux unsigned-long-long return type. Original
MSR constants, UAPI records and shared record types remain visible through
a bounded overlay. Ordered TSC and MSR operations have no implementation.

Four strict GNU99/GNU11 sanitizer profiles execute 1,160 value patterns each,
including every individual bit and its complement. They verify one raw read,
the exact return ABI, both include orders and original `get_cycles` routing
with TSC configuration absent/enabled. Four genuine x86 instruction objects
retain only `memcpy` as an unresolved dependency. The executed host producer
matches the separately generated production bodies; it supplies CPU reads
through V observations rather than executing hardware instructions.

Fresh worktrees at `cb9d07f2` with eleven native/tool paths build enabled/default
x86 and default ARM. Exact enabled ELF
`95542475f713df3dfd57f40167f97d22141450a11a8d43d220fd7d113e99793e`
boots normal, SSE and four-level guests. Each has 46 markers and 28 strict
existing allocation equalities. The CPU query batches now include real raw
and guarded cycle reads with IRQs enabled/disabled and nested pins; fourth
batches recover `387420160` bytes in normal/SSE and `387448832` in four-level,
with unchanged live heap counts. Default Linux-ABI startup passes.

Actual native body/object review distinguishes the monolithic bridge producer
from the separately compiled module facade. The module export retains its
existing allocation-free initialization guard, warmed during bootstrap before
measured queries; it is not byte-identical to a standalone test export thunk.
No asynchronous pointer ownership or per-query allocation is introduced.

That increment's coherent full audit remained **5/269**. The former TSC declaration error
reaches task/MM/vfork ownership, bringing that first-error group to 226 files.
Thirty-three files still fail the aggregate exchange type witness. Hardware
operation, full linking and GPU support remain unvalidated.

Run `build-support/run-v-tool.sh tests/linuxkpi/raw_tsc.v`. Evidence is under
`smp-oct10/raw-tsc-*`. Initial guest image preparation and default source staging
failed with disk exhaustion and did not validate a boot; use the fresh retry
states and saved final artifacts. The existing broad allocation baseline is
unchanged in scope; these measurements do not establish a global gate pass.

## Original typed aggregate exchange

The V ABI generator now uses an unevaluated generic atomic type witness for
naturally aligned word records and unions. The original Linux wrappers and
the existing V byte backend remain unchanged. The witness performs no storage
load; exchange and failed/successful CAS return the exact previous bytes.
Callers still provide valid storage aligned for its declared type. This adds
no Linux MM, page-table ownership or new scalar 128-bit guarantee.

Two strict GNU99/GNU11 sanitizer profiles pass 792 bit-pattern cases each,
including original PTE/PMD and volatile storage, single operand evaluation,
16,000 concurrent token exchanges and 16,000 successful CAS increments.
Fourteen compiler controls reject unsupported operands; two scalar128
controls preserve the separate original helper imports without executing them.
Four freestanding production objects retain only `memcpy` as an unresolved
dependency. Independent replay authenticates the actual generated header and
unchanged production bodies.

Fresh worktrees at `0a94db7c` with six integration overlays build enabled/default
x86 and default ARM. Enabled ELF
`0fbde437f087f965aea860649857394c80e8ba0fa817fc5fa63d545740674e45`
boots normal, SSE and four-level guests. Each passes 46 markers and 28 strict
allocation equalities. The query batches execute 120,000 native fixture calls
through original `xchg`/`cmpxchg` wrappers across enabled/disabled IRQs and nested
pins. All ten concrete types use synchronous stack operands/results; no hidden
V allocation or asynchronous owner is introduced. Fourth-batch free bytes
recover `387395584` in normal/SSE and `387424256` in four-level, with all live
heap counts unchanged. Default Linux-ABI startup passes.

The coherent isolated full audit remains **5/269**. All 33 former aggregate
exchange first errors now reach `boot_cpu_has_bug`; 226 task/MM/vfork first
errors and the remaining timer/entry/IRQ/lock dependencies remain unresolved.
Full compile/link and Tiger Lake GPU validation are still pending.

Run `build-support/run-v-tool.sh tests/linuxkpi/aggregate_exchange.v`.
Evidence is under `smp-oct10/aggregate-*`, including independent source/lifetime
review, exact saved native artifacts, guest ISO proofs and complete audit
diagnostics. These feature measurements do not establish a global allocation
gate pass.

## Original nested IRQ-save spinlocks

The configured-disabled lockdep normal/raw nested IRQ-save forms now use a
real V leaf and structured ABI metadata. The unchanged Linux `typecheck`
witness retains flags diagnostics; subclass expressions are discarded entirely.
Lock operands are evaluated once before saving IRQ state, and saved flags are
stored after acquisition. Distinct locks each acquire a native preemption pin;
reverse unlocking restores the caller's IRQ state and original pin depth.
This increment does not change ordinary IRQ-save adapter ordering or implement
configured lockdep and non-IRQ nested-class handling.

Two focused strict GNU99/GNU11 ASan/UBSan profiles pass the existing raw-lock
regressions and eight IRQ/pin/acquisition-order cases. Independent replay
authenticates 53 selected production/test bodies. Thirty-eight compiler profiles
cover 12 accepted and 26 rejected cases, including flags types, subclass
elision, operand order and configured-lockdep rejection. Seven malformed
metadata controls preserve existing output. Native leaf objects and actual
full-module C/object review find no allocation or retained operand ownership.
These are focused checks; the broader host suite is not declared passing.

Fresh worktrees at `41587f08` plus five frozen native/tool overlays build enabled
and default x86-64 and default ARM64. Enabled ELF
`0d463db9277a7070002e271d8ede652c1fbcf96144d2f6def89371621c012d4d`
passes fresh normal, SSE and four-level four-CPU guests. Each passes 46 markers
and 28 existing strict allocation equalities. The new fixture runs inside the
separate existing 200-runtime page-recovery check: 1,600 nested cases and 3,200
acquisitions, with no pages retained. Those 28 other measurements are not a
new per-case heap measurement. Default Linux-ABI startup passes; actual default
and ARM C/ELF exclude the compatibility fixture.

The saved V executable initially selected the mutable checkout's standard
library despite its copied SDK. Failed attempts are preserved. Explicit macOS
caller transport fields select the frozen SDK; separate architecture caches
and a private transparent `execv` launcher add `-nocache -gc none`. Successful
build logs, exact arguments/environment, actual SDK include paths and saved
artifacts are authenticated under `smp-oct10/nested-spin-*` and
`smp-oct10/native-compiler-diagnosis-oct12/`. No compiler headers were removed.
Executable hashes alone did not authenticate older builds' library root:
the saved successful aggregate ARM C also names the live standard library.

The coherent full audit remains **5/269**. The former nested-lock first error
now reaches `might_sleep_if`; task/MM/vfork, CPU-bug policy and other runtime
dependencies remain. Full unchanged-driver compile/link and real Tiger Lake
validation are still required. These feature checks do not establish a global
kernel allocation pass or working GPU support.

## Conditional sleep annotation, 2026-10-15

`might_sleep_if` now has a V implementation and generated statement adapter.
The C call boundary preserves scalar truth conversion and one predicate
evaluation, including pointer, floating and complex operands. False predicates
return before querying context. True predicates use the existing stronger
native `might_sleep` invariant: IRQs enabled, no scheduler pins and no actual
maskable interrupt frame. There is no implicit yield. The configured upstream
annotation is a no-op after predicate evaluation, so this native policy is
not claimed equivalent to that disabled-debug runtime. File/line transport
is tested through the bug ABI; the native bug bridge still prints a generic
panic rather than reporting those arguments.

Two strict GNU99/GNU11 ASan/UBSan profiles and an independent cold replay pass.
Each executes 31 safe cases, with 13 false predicates making no context query
and 18 true predicates making one. Eight separate fatal children cover
IRQ-off, pinned and IRQ-enabled depth-one/depth-two contexts and caller-location
transport. Twenty-four selected V bodies remain unchanged, including the leaf;
four production leaf/export/initialization bodies match a full module generation.
Ten compiler controls accept scalar operands and reject records/unions at the
actual Boolean parameter boundary. Seven malformed metadata controls preserve
the previous output. Statement grouping is source-checked and exercised through
V branches; there is no handwritten unbraced-C or postincrement runtime test.

The native fixture adds five safe calls to each of the existing 200 measured
runtime iterations, including false annotations under IRQ exclusion and pins.
The real outer/nested interrupt fixture also invokes false predicates while
IF is enabled and verifies CPU, task identity, depth, pins and IF afterward.
CPU-local snapshots themselves require IRQ exclusion. The first two v3 guest
runs caught an IRQ-enabled snapshot in that new observer and failed; their logs
are retained. V4 masks around both snapshots and restores IF before invoking
the annotation and before the final context queries. Successful final guest
results are recorded separately from those failures.

Final enabled/default x86-64 and default ARM64 builds pass. Saved enabled ELF
`f55eabf3a0f120ff3a3cedcfee7ea734065dfd5ee4a42b69d50d67341bc7fc6f`
passes fresh normal, SSE and four-level four-CPU guests. Each passes all 46
required markers and 28 existing strict allocation equalities. The 1,000 new
runtime calls retain no pages; the full interrupt actor lifecycle also recovers
its page and heap baselines after three warmups. This does not create a new
per-call heap measurement. Default Linux-ABI startup passes, and actual default
and ARM C/ELF exclude the fixture. Independent review covers the saved native
leaf, initialization guards, adapter, IRQ observer, objects and guest images.

Builds use isolated worktrees at `fe594a9c` with eight frozen native/tool
overlays. Native code uses the saved compiler and actual copied SDK; host tools
use a separately copied newer compiler/SDK because the older host producer
conflicts with the current typed spawn header. The private V launcher preserves
arguments and status, selects native `-gc none` for `-os vinix`, and uses Boehm
for host tooling. Initial host-header and monolithic Linux-header failures remain
archived; no compiler headers or diagnostics were suppressed. Inspect actual
generated SDK paths as well as executable hashes.

The coherent full audit now passes **6/269**, including original
`i915_sw_fence.c`. Its native object compiles but has eight remaining services:
four DMA-fence operations, two unlocked DMA-reservation iterator operations,
`irq_work_queue` and `kvfree_call_rcu` (the latter is implemented in the later
deferred-free increment below). This is not a full-object link or a GPU
execution result. Remaining first-error groups include task/MM/vfork, CPU-bug
policy, timer include closure, entry-stack layout and the IRQ-register wrapper.
Full driver linkage and Tiger Lake validation remain pending.

Run `build-support/run-v-tool.sh tests/linuxkpi/conditional_sleep.v --keep-dir NEW`
with a fresh output directory, the compiler/SDK selection described in the
handoff, and a Boehm host analysis build. Evidence is under
`smp-oct10/conditional-sleep-*` and `conditional-host-probe-oct15/` in the private
LinuxKPI cache. Focused evidence does not establish the broader host suite or
global kernel allocation gate.

## Scheduler and IRQ header dependencies, 2026-10-15

The native scheduler facade now includes the original timer and CPU-mask
headers and exposes completions after its task view and scheduler prototypes,
preserving wait-header recursion. Raw spinlock types restore the original
`lockdep_types.h` dependency. The new `asm/irq_regs.h` is byte-identical to the
wrapper emitted by the exact pinned Kbuild scripts; it forwards to the original
generic header without defining frame storage or inventing native frame layouts.

Four strict GNU99/GNU11 first-header probes and independent replay compile
without diagnostics, object symbols or storage. Separate generated-V reference
objects retain genuine unresolved IRQ/kthread symbols; final links reject the
missing `__irq_regs` storage. The maintained generated-wrapper test now checks
this fourth wrapper, repeated inclusion and original getter/setter ABI types.
Its broader profile stopped at an original `thread_info.h` signedness warning;
six unchanged-baseline/candidate/include-order controls reproduce that same
single error. That full profile is not a passing result. No warnings or original
sources were suppressed or rewritten.

Fresh worktrees at committed `df3389b5` with the four frozen overlays build
enabled/default x86-64 and default ARM64. These separately saved ELF files have
no new guest-boot or allocation-measurement claim; the earlier conditional
annotation guest results remain bound to their exact saved ELF.

A fresh coherent full audit remains **6/269**. Both incomplete timer-record
first errors and the missing IRQ-register header are gone. Remaining groups
are 228 task/MM/vfork, 33 CPU-bug policy, one entry-stack record and one missing
original `irq_hw_number_t` alias. The audit guards all 7,958 inputs; only 11
units emit dependency files, so it does not claim complete discovered graphs
for every failed unit. These are include/type results, with no new runtime
ownership, allocation, IRQ service or working GPU claim.

Evidence is under `smp-oct10/include-closure-*`, including the exact source
freeze at `df3389b5` plus four header/tool overlays, independently derived Kbuild
contracts, compiler controls and the full audit. Native build results and the
separate earlier conditional-annotation guest results have distinct artifacts.

## Original hardware IRQ number type

The reduced types facade now restores Linux 6.6.157's exact unconditional
`typedef unsigned long irq_hw_number_t`. Sixteen strict original/candidate
GNU99/GNU11 controls cover x86-64/arm64 and kernel/UAPI include order; eight
absent-type baseline controls reject as expected. Independent replay verifies
type identity, width, alignment, unsignedness and the full range against the
actual original header. Declaration objects emit no storage or runtime symbols.
The unchanged GSC source passes that missing type and reaches genuine task/MM
dependencies. This adds no IRQ object, Linux IRQ domain or enabled ARM LinuxKPI
runtime.

Fresh worktrees at `4abd5cc6` plus the one frozen type-header overlay build
enabled/default x86-64 and default ARM64. Actual native artifacts consume that
header; the eleven previously reviewed runtime/guard/IRQ bodies are unchanged.
No new boot or retained-allocation measurement is claimed for these ELFs.
The full audit remains **6/269**, with all 7,958 guarded inputs stable. Remaining
first-error groups are 229 task/MM/vfork, 33 CPU-bug policy and one original
entry-stack record. Evidence is under `smp-oct10/irq-number-type-*`.

## Native x86 UAPI compiler profile

Native LinuxKPI compiler flags now include the pinned
`arch/x86/include/uapi` directory after the architecture kernel headers.
The full syntax audit already supplied this directory. Without it, an actual
native-profile compilation of original `i915_sw_fence.c` stopped at missing
`asm/auxvec.h`; adding the genuine original include path compiles the whole
object in both GNU99 and the imported-object GNU11 dialect. No replacement
header, runtime stub or warning suppression is involved.

The full object retains all ten configured public exports and 42 imports. The
saved native kernel supplies 33 names; eight genuine runtime services remain,
plus the existing `round_jiffies_up` implementation discarded when unused by
the kernel link. This is an object/compiler-profile result, not full-object
linkage or GPU operation. Original diagnostics and the failed native controls
remain preserved under `smp-oct10/sw-fence-current-closure-oct15-v2/`.

Fresh enabled/default x86 and default ARM builds pass at `41f6da03` plus the
one frozen Makefile overlay. Actual enabled object/bounds commands include the
directory, while opt-out commands omit it. Whole-object replay uses the saved
fixed native command without manually adding another include; both dialects
authenticate 274 actual dependencies and preserve four original warnings.
No new boot or allocation measurement is claimed. All 7,958 prior audit inputs,
269 driver commands and regenerated ABI/bounds remain unchanged; the executed
full-audit result remains **6/269**. Final evidence uses `smp-oct10/native-uapi-*`
and `sw-fence-fixed-native-closure-oct15/`.

## Page-backed deferred RCU frees, 2026-10-15

`kvfree`, `kvfree_call_rcu` and the original embedded `kfree_rcu`/`kvfree_rcu`
macros now release genuine native page-backed kmalloc allocations. The existing
32-byte allocation prefix uses its unused tail as an ownership discriminator;
payload layout and allocation size do not change. An initialized byte rejects
packed-cache slots before any wider tag read. Geometry and complete embedded
head containment are checked before publication. Callers must supply a live
owned allocation; this tag is not a live-pointer registry. Cache slots and
generic vmalloc/vfree ownership remain unsupported and fail explicitly.

Embedded enqueue allocates nothing, preserves IRQ/pin state and accepts head
offsets below 4096, including zero. Private offset bits occupy the original
callback field without constructing an invalid function pointer. The existing
RCU queue starts a future grace period. Dispatch saves its successor and raw
bits, clears the head before invoking a callback or freeing pages, and never
reads that head afterward. Barrier ordinals retire after the actual free.
The headless `kvfree_rcu_mightsleep` path uses the original permitted synchronous
fallback: an ordinary sleepable task waits for a real future grace period,
then frees its owner. It supplies no asynchronous headless batching service.

The focused V host fixture passes strict GNU99/GNU11 production compilation
and ASan/UBSan: two complete safe runs and 36 isolated fatal children. It
checks 181 generated production bodies against full modules, including exports
and initialization guards. Real allocator/cache bodies and original free macros
cover immediate recovery, mixed callbacks/frees, self-requeue/free, offset
0/8/4088 under four held-reader modes, allocation-free enqueue, a barrier paused
at actual free, exclusion of later submissions and joined headless execution.
Invalid owners, head ranges and contexts fail before changing original head
bytes, callback ordinals or page-free counts. The existing ordinary RCU matrix
also passes its 70 safe and 12 fatal runs. These are focused suites, not a new
global allocation or complete host-suite pass.

Fresh worktrees at `b5f2131e` plus 14 frozen production/tool paths build enabled
and default x86-64 and default ARM64. Enabled ELF
`1ec6c7ce063aec1ea206f386e875c5eeda1c8144fce6ed2830415a4176e545a7`
passes fresh normal, SSE and four-level four-CPU guests. Each passes 47 markers
and 29 strict allocation equalities. Three complete actor/callback warmups
precede the new fourth-lifecycle measurement; every page and live heap class
returns to baseline. Native coverage includes real nested pins, an IRQ-off
reader, allocation-free IRQ-off/pinned enqueue, mixed callbacks and synchronous
headless waiting. This enqueue test is not an actual interrupt-handler test.
Default Linux-ABI startup passes; actual default/ARM C and ELF exclude the feature.
Independent reviewers approve the allocator, deferred dispatch and fixture
lifetimes in saved generated C and native objects. The first x86 build's missing
fixture-generator choice is preserved as a failed attempt; the corrected
allowlist is part of the final freeze.

Evidence is under `smp-oct10/rcufree-*`. Focused host results are
`rcufree-host-oct15-final-v2/result.json`; independent native approval is
`rcufree-guest-review-oct16/final.json`, SHA256
`d2aef5cb646dc6a59a7b0e6b072e95b2bce7e088771564a23b8e554e7a3f9615`.
Repeat with `build-support/run-v-tool.sh tests/linuxkpi/deferred_free.v
--keep-directory NEW_DIRECTORY`, using the authenticated native/host compiler
router and private architecture caches described above. The import verifies
all 7,668 files unchanged. This closes the page-backed RCU-free runtime gap;
IRQ work, DMA fences/reservations and generic VM ownership remain dependencies.
The last full audit remains 6/269; no new full-driver link or Tiger Lake result
is claimed.

## Native IRQ work, 2026-10-15

Original `irq_work` records and initialization macros now use a native non-RT
backend. A dedicated real APIC vector dispatches local and remote work with
IRQs disabled. Local queueing always defers execution through an interrupt;
it never invokes the callback inline. Local lazy work waits for a genuine PIT
tick, while remote lazy submissions raise an immediate target interrupt.
Empty-list transitions coalesce doorbells. Queues and private execution records
allocate nothing. Fixed boot CPUs, ordinary tasks and maskable IRQs are the
supported domain; NMI, RT, hotplug and NOHZ remain unsupported.

The original PENDING-clear/full-barrier/callback/BUSY-CAS sequence is retained.
Cross-CPU requeue can execute two callbacks concurrently. BUSY is not an
invocation count, so `irq_work_sync` also scans pointer-only execution records
under the same IRQ-save lock that publishes and retires those stack records.
Successful sync makes no subsequent object access. Producers must stop before
final sync and destruction. A callback's enclosing storage must survive the
post-callback flag operation; real RCU deferred freeing supplies this lifetime.
The i915 request execute cache's `SLAB_TYPESAFE_BY_RCU` and reclaim flags still
require their own allocator implementation. This change does not make that
caller operational or supply general Linux IRQ registration.

The focused host suite passes 14 safe and 18 fatal sanitizer runs across seven
CPU counts through 256. All 88 selected production bodies match complete
modules, including export/initialization code. Strict GNU99/GNU11 production
objects and original macros cover duplicate/coalesced queueing, deferred local
and lazy execution, remote routing, requeue and a synchronization waiter that
starts after BUSY clears while another invocation remains active. Invalid
CPUs, flags, callbacks and contexts fail before changing the node. The host
transport observes modeled IPIs; actual delivery is validated separately.

Fresh isolated builds at `a97f0490` plus 14 frozen paths pass enabled/default
x86 and default ARM. Final enabled ELF
`c5fa1b88cd414dd71dfc2ecf3ef912ef5f4d504af9681d7e2f56b88254419bbb`
passes normal, SSE and four-level guests: 48 required markers and 30 strict
allocation equalities each. New coverage exercises actual local/remote IRQs,
idle wakeup, lazy PIT delivery, two concurrent callbacks with BUSY already
cleared, synchronous waiting and RCU-deferred callback containers. Three
warmups precede the fourth complete actor lifecycle, recovering every page
and live heap class. Default startup passes; actual default/ARM C and ELF
exclude the feature. Independent source, generated-C and native-object lifetime
reviews pass.

Both initial guests failed heap equality despite page recovery. Generated C
revealed one 72-byte boxed test node per lifecycle; even a proposed fixed array
escaped. The final parallel control record has explicit boot lifetime and is
reset only after callback drains and actual actor retirement. The original
equalities remain; failed source, C, ELF and guest evidence are preserved.
Final allocation review checks every new production/native function body.

Evidence is under `smp-oct10/irqwork-*`. Independent native approval
`irqwork-guest-review-oct15/final-v2.json` has SHA256
`a14b6ae1aac5298d4a8c3c044fda518379d659daa24ad2085411250033ecaa7b`.
Repeat focused tests with `build-support/run-v-tool.sh tests/linuxkpi/irq_work.v
--keep-directory NEW_DIRECTORY` and the authenticated compiler router/private
caches. The new full syntax audit remains 6/269, with all 7,971 guarded inputs
stable; only 11 units produce actual dependency files. Remaining first errors
are 229 task/MM/vfork, 33 CPU-bug queries and one entry-stack record.

Entire unchanged `i915_sw_fence.c` compiles with the final native GNU11 command
and a GNU99 control plus pinned Kbuild identities. All ten public exports and
42 imports remain; 35 imports now exist in the final native ELF. The six
substantive gaps are four DMA-fence operations and two unlocked reservation
iterator operations. The additional absent `round_jiffies_up` is genuinely
implemented in saved C/object and discarded when unused by this kernel.
`irqwork-sw-fence-native-v2-closure/result.json` records this compiler/symbol
evidence, not a whole-object link or GPU execution. Full driver compilation,
device binding, memory ownership and Tiger Lake validation remain unfinished.

## Native DMA-fence synchronization, 2026-10-15

The 18 non-lockdep synchronization APIs from pinned `dma-fence.c` now run on
native locks, task waits, clocks, references and ordinary RCU. Original records
and typed driver hooks remain intact. `dma_fence_describe` still requires a real
`seq_file` sink and remains unresolved. Fence containers were implemented in
the next increment below; reservation ownership remains pending.

Signal dispatch detaches callbacks onto a stack sentinel before replacing the
list/timestamp union. It saves the next callback and function before invocation;
the callback may free its own owner. Default wait callbacks remain on the waiting
task's stack. Every wait-any cleanup path removes registered callbacks before
releasing task references or its allocated array. Default fence release defers
freeing a page-backed kmalloc base owner through an actual future grace period.
Custom release hooks supply their own storage and reader lifetime.

Preflight caught hidden sentinel boxing, a deep pointer comparison in the test
facade, and private wait declarations whose `long` spelling differed from V's
64-bit type on Darwin. Final generated C has genuine stack records, pointer
identity comparisons and portable private declarations; public Linux signatures
remain exact. Direct default waits preserve atomic completed/pending fast
returns, with sleep-context enforcement before an actual positive wait.
The original context-ID fetch-add retains full ordering.

Validation passes:

- Strict GNU99/GNU11 host production objects with ASan/UBSan: 22 runs, including
  callback/enable/context races, interrupted and timed waits, wait-any OOM and
  partial cleanup, self-free callbacks and real reader-held deferred release.
  Of 353 selected generated bodies, 350 match complete modules byte for byte;
  three existing completion adapters serve only host RCU-worker bootstrap.
  Scheduler, page, clock and console transport boundaries are documented in
  `tests/linuxkpi/dmafencefixture/README.md`.
- Fresh enabled/default x86-64 and default arm64 builds. Normal, SSE and
  four-level guests use the same saved enabled ELF and each pass 49 markers and
  31 exact PMM/live-heap equality rows. Three complete DMA-fence warmups precede
  its measured fourth lifecycle, including retained actor creation/join,
  actual IRQ signaling/polling and reader-held RCU release. Default startup
  passes; actual default/arm64 C and ELF exclude the service.
- Independent source, actual generated-C and native-object lifetime reviews,
  including all 173 new bodies across the main blob and both separate modules.
  The existing IRQ-work host regression also passes all 32 sanitizer runs.

Evidence is under `smp-oct10/dmafence-*`. Final native source freeze v4 SHA256:
`fd41ea37fc45668cefaf98617c78d7a017f69c1c20220c5b94e384d792e8dd85`.
Enabled ELF:
`e1e35d98c6006f18a97f876f66876615862b73e45ccb69f86f7c666e7d942805`.
Host result `dmafence-host-final-v1/result.json` SHA256:
`9ed2515e8c7356a66dd2665957b122fb75e8947413188d8a1c480b716a062d85`.
Independent guest/ISO/chronology approval
`dmafence-guest-independent-oct15/final.json` SHA256:
`f1fddf2d58feab1432b13aaca9de3e8fb0485e148e2591b619513cf01f72da92`.
Repeat with the authenticated compiler router/private caches and
`build-support/run-v-tool.sh tests/linuxkpi/dma_fence.v --keep-directory NEW_DIRECTORY`.

The fresh full syntax audit remains **6/269**; all 7,668 imported files remain
unchanged. The entire original `i915_sw_fence.c` compiles in GNU99/GNU11 with
its pinned Kbuild identities. Now 39 of its 42 imports exist in the final ELF.
Only two substantive services remain missing from that object:
`dma_resv_iter_first_unlocked` and `dma_resv_iter_next_unlocked`.
`round_jiffies_up` is implemented in the native object and discarded when
unused. This is compiler/symbol evidence, with no whole SW-fence link or GPU
execution claim. Full i915 compilation/linking, device/memory services,
confirmed PCI identity and physical Tiger Lake validation remain unfinished.

## Native DMA-fence arrays and chains, 2026-10-15

The complete pinned array and chain operations now run over their original
120-byte/128-byte records, appended 32-byte array callbacks and genuine immutable
80-byte operations tables. Valid constructor ownership matches Linux: success
consumes child references and an array's allocated vector; allocation failure
consumes neither. Invalid array counts, vectors or NULL children produce a
warning and NULL before ownership transfer. Nested containers retain the
original warning-and-construction behavior.

Arrays preserve signed ANY tail counts, callback-owned parent references,
first-error selection, acquire ordering before the enable flag, polling,
deadlines, context matching and borrowed iteration. Chains preserve context and
sequence rules, consuming traversal, RCU-safe predecessor references, concurrent
CAS ownership transfers and iterative final release. Their callback and IRQ-work
storage deliberately share the original union. A child callback publishes IRQ
work before its final child put; dispatch may rearm that same union before the
previous IRQ callback's final BUSY CAS. The original snapshot/CAS logic and real
RCU backing remain intact. Never call `irq_work_sync` on a union currently holding
a fence callback.

Fresh enabled/default x86-64 and default ARM64 builds pass. Native container
tests cover constructor OOM ownership, original operations identities, ALL/ANY
errors and negative tails, deadlines, chain context/find/walk behavior, 129-node
iterative release, real target-IRQ child signaling, repeated union transitions
and a final container free blocked behind an actual remote implicit reader.
Three complete actor lifecycles warm the runtime before the measured fourth;
all actors join and leave their stacks before the exact PMM/all-live-heap check.
Independent source and actual generated-C/object reviews approve the new
lifetimes; the 145 new function/export bodies contain no hidden V allocation or
deep pointer equality.

Strict GNU99/GNU11 production host objects and ASan/UBSan pass 26 runs. Of 497
selected production bodies, 494 match the complete generated modules exactly;
three disclosed completion adapters serve only existing host RCU bootstrap.
Eight controlled union lifecycles retain backing after both post-callback CASes
and pointer-record retirement until the modeled IRQ scope exits. Separate
gates exercise genuine chain predecessor CAS wins/losses. The suite also covers
40 concurrent array lifecycles, original warning paths, partial registration,
nested deadlines and 1,024-node iterative release. Transport limits and the
terminal callback representation are documented in
`tests/linuxkpi/fencecontainerfixture/README.md`. Repeat with:

```sh
build-support/run-v-tool.sh tests/linuxkpi/dma_fence_containers.v \
  --keep-directory NEW_DIRECTORY
```

Normal, SSE and four-level guests each pass 50 required markers and 32 strict
PMM/live-heap rows; default startup passes and default/ARM C and ELF omit the
feature. ARM evidence is a build and artifact check. Independent guest review
authenticates each actual ISO kernel and the warmup/measurement chronology.

The isolated baseline is `c136b3209` plus 15 frozen production/tool paths.
`smp-oct10/fencecontainer-native-freeze-v1.json` SHA256:
`1c1d8e2f6659915ed75ec280c3f1c1f34da7865af87d5858f0087131e5fa81bd`.
Saved enabled ELF:
`0a3fc002078595a35c82dea2accc62788c5a5a7d42e97c35c4a1ef282136254d`.
Independent actual native review `dmafence-chain-oct15/native-v1-enabled-review/review.json`
SHA256: `33b0e490595098008ca05be433d1310b8d3ef9974eeee0978b9c7bbf44d231e9`.
Host result `fencecontainer-host-final-v2/result.json` SHA256:
`0dde5336ac63cbae761dbd37ec745ef94a7d08f58066e7afb5b90680f756fafa`.
Independent native/guest aggregate `dmafence-chain-oct15/native-v1-validation-summary.json`
SHA256: `996c3932b6f8a28f9958e1c2c41e5b4b791d99a3831b6ec5e35119cbbc7c6af7`.

The fresh full i915 syntax audit remains **6/269** with all 7,668 imported files
unchanged. This increment supplies fence containers; reservation producers and
iterators, the typesafe request cache, complete driver compile/link and real
Tiger Lake operation remain unfinished.

## Native DMA reservation ownership, 2026-10-15

All 15 configured non-lockdep reservation services now use original 48-byte
objects/iterators, 24-byte list prefixes and the mutable 32-byte original
`reservation_ww_class`. Writer APIs check actual native lock ownership.
Pre-reservation remains required before adding a fence. Growth transfers
unsignaled references before publishing a new list, then drops signaled owners
and defers the old list through genuine RCU. Add/replace retain new owners before
publication and release replaced references afterward. Finalization requires
stopped API users and an unlocked object.

Unlocked iterators retain one fence across caller bodies, retry failed
get-unless-zero, report restarts and drop their current reference on the next
step or end. Locked iterators borrow while the writer lock remains held.
Copy/get/singleton and their partial allocation failures release temporary
owners correctly. Singleton construction uses the real array implementation.
Original usage ordering, Wait-Die locking, waits and deadlines remain intact.
`dma_resv_describe` and `dma_fence_describe` remain unresolved until a real
`seq_file` sink exists.

Two explicit native corrections address pinned iterator control flow without
changing any upstream source. Restarting onto a NULL list drops and clears the
old cursor reference rather than returning it indefinitely. If an allocator
reuses a retired list's address with fewer active entries, a live count smaller
than the cached count triggers restart before reading entries. Ordinary
in-place append retains the original cached snapshot. Queries still have the
original weak concurrent aggregation behavior: a restart that returns no next
fence can leave an earlier collected prefix. Returned owners remain valid;
these APIs do not promise an atomic snapshot.

`kmalloc_size_roundup` reports Vinix's actual requested capacity, including zero
and oversized inputs, without advertising physical page slack or Linux buckets.
`krealloc_array` checks multiplication before calling the real allocator.
Allocation failure preserves the old owner; successful resizing allocates a new
owner, copies the bounded old contents and frees the old allocation. Zero size
keeps the existing native free/sentinel behavior. No allocation-prefix alignment
metadata is edited to simulate an in-place shrink.

Strict GNU99/GNU11 host production objects and ASan/UBSan pass 14 runs: two normal
runs and six fatal controls per dialect. Of 638 selected production bodies, 635
match complete generated modules exactly; three existing RCU bootstrap adapters
are disclosed. All 277 generated fixture definitions are inspected separately.
Tests exercise real writer blocking/interruption and Wait-Die recovery, usage
tags, growth/pruning/replacement, iterator references and both corrections,
same-page allocator reuse, zero-reference retry under RCU, partial collection
and restart OOM, singleton transfer, allocator requests, waits and deadlines.
The host scheduler, pointer-load scheduling gates and physical-page transport
are documented in `tests/linuxkpi/resvfixture/README.md`.

Fresh enabled/default x86-64 and default ARM64 builds pass. Normal, SSE and
four-level guests use the same saved enabled ELF; each passes 51 required markers
and 33 strict PMM/live-heap rows. Three complete reservation warmups precede its
measured fourth lifecycle, including retained actor creation/join, actual writer
waits, collection failures and old-list/default-fence reclamation behind a real
RCU reader. Default startup passes. Actual default/ARM C and ELF omit the feature;
ARM evidence is a build and artifact check. Independent source and actual
generated-C/O2 reviews cover all 168 new function/export bodies and original
class data; all aggregate cursors and task-owner arrays are genuine stack data.

The isolated baseline is `321bb4c63` plus 13 frozen production/tool paths.
`dma-resv-native-freeze-v1.json` SHA256:
`c0834f4d9232a65603a27b55aba0716ba3669bf6df6b0b59c534efddd9d38b3f`.
Enabled ELF:
`05080e308061d332adc4771edc75a606e2b2aed40e5918263333c1450819e8bb`.
Host result `dma-resv-host-final-v1/result.json` SHA256:
`1fee365297b7807c399aa584e5a991be64698ddfb4ae2fa6d87edeaf76882513`.
Independent native artifact review `dma-resv-native-independent-v1/review.json`
SHA256: `8abea2c788482f70a3764ef4c4a72c8f9dab2a4ca6727b5686125fe4a9096c37`.
Independent host evidence review `dma-resv-independent-host-oct15-v4/review.json`
SHA256: `07670cb578264324b6b69204bdf39648d2d1d8a0b1225130d1512f128f3a0818`.
Independent guest/ISO/chronology aggregate
`dma-resv-guest-independent-oct15/final-v1.json` SHA256:
`f188c50c526610812aeecd0770ee500fa7eaed9537e2a1ac313c569c0ea8d1f2`.
Evidence is under `smp-oct10/dma-resv-*`. Repeat host checks with:

```sh
build-support/run-v-tool.sh tests/linuxkpi/dma_resv.v --keep-directory NEW_DIRECTORY
```

The full unchanged i915 audit remains **6/269**, with all 7,668 imported files
verified unchanged. Reservation ownership closes another synchronization
dependency; DRM device/file services, typesafe request caches, memory/device
ownership, complete driver compile/link and Tiger Lake validation remain pending.

## Unchanged i915 software-fence execution, 2026-10-15

The opt-in native link now includes the complete original `i915_sw_fence.c`,
with all four identities from its pinned Kbuild rule. Its source SHA256 remains
`4876074a64e975fd4823d4f442aab9c5a30f857f0ec9b970abea77c84c5491e9`.
All ten configured public exports are retained in the actual object and enabled
ELF, and every original import resolves to an existing concrete implementation.
The driver source is unchanged; the new callers and diagnostic tooling are V.

Native cases exercise initial/committed notification phases, first-error
handling, reinitialization, sleeping waiters, a 129-node continuation chain,
allocated and supplied dependencies, a separately owned target freed by its
FREE notification, DMA callbacks, blocking/nonblocking allocation failure,
reservation usage filtering and partial registration failure. Original
continuation/error behavior is preserved. Declining COMPLETE leaves the
original terminal pending-zero state; no resumable-notification guarantee or
configured cycle detection is added.

Both DMA-before-expiry and expiry-before-late-DMA execute the real timer,
maskable IRQ work, synchronous timer shutdown and RCU release. A remote ordinary
reader retains the private 128-byte timeout owner while the controller checks
metadata and synchronizes its work. The timer notification verifies actual
IRQ-off/preemption state. Expiry alone does not release the callback or its DMA
reference. Supplied wait entries live separately from immediately freed target
owners because the original wake function still reads their flags after FREE.
Waiter backing remains alive through `finish_wait`.

Strict GNU99/GNU11 ASan/UBSan host runs pass 8,296/8,515 assertions. They execute
the entire original object and retain all ten exports. Each host profile's 39
service imports maps to exactly one retained concrete definition; compiler and
sanitizer imports are recorded separately. Of 723 selected V bodies, 720 match
full generated modules and three disclosed completion adapters serve bootstrap.
All 268 fixture occurrence keys are inspected. The typed timeout-notice
transport preserves argument evaluation; full preprocessing against a genuine
variadic control differs only by the sink identifier. Native printk is a
separate already implemented service. Exact original enum callback identity is
preserved, including Clang's sanitizer function-type identity. The host README
documents scheduler, clock, page, IRQ and logging transport boundaries.

Enabled/default x86-64 and default ARM64 builds pass. Normal/SSE/four-level
enabled guests use the same saved ELF and pass 52 required markers and 34 strict
PMM/live-heap rows. Three complete software-fence warmups precede its measured
fourth lifecycle; all three actors are joined and off stack before measurement.
Default startup passes without LinuxKPI markers. ARM is build/artifact evidence.
The public VM runner now requires all six newer deferred-free/IRQ-work/fence/
container/reservation/software-fence markers. Independent actual generated-C
and O2 review covers all 65 new native/facade/export/init bodies.

The isolated baseline is `59b1e9ac5` plus nine frozen production/tool paths.
Final freeze `sw-fence-native-freeze-v2.json` SHA256:
`1d26673b11ba2787c0a8996d6d42aeb5ec1dccc11ea6b34aeb8c7ade5e9518dc`.
Enabled ELF:
`31578e45624d33fdd1623d8e0d506fc277b5c6deb94333151f54663e372cb5f4`.
Host result `sw-fence-host-final-v1/result.json` SHA256:
`1907b9231e4c78633f9b6339ca1cc7806860aa6ae85d6277c43eb3eb030cb54b`.
Independent native review `sw-fence-independent-x86-oct15-v2/review.json` SHA256:
`621c0121719f487b7c2039a57e535680f1ea9515e23dd6608edc7003048a821c`.
Independent host lifetime/evidence review SHA256:
`06bccfd36eb17c387c74dd1c49574f1ddf760d0511d66489c4ccefbdf9425ca5`.
Independent four-ISO/guest chronology review SHA256:
`faf260668a753cc67a5555ca5f6c3e9e5631321111180c954044dfc0595e46e2`.
Evidence remains under `/Users/alex/.cache/vinix-linuxkpi/smp-oct10/sw-fence-*`.
Repeat the host consumer with:

```sh
build-support/run-v-tool.sh tests/linuxkpi/i915_sw_fence.v --keep-directory NEW_DIRECTORY
```

The complete i915 syntax audit remains **6/269**, with all 7,668 imported files
unchanged. This executes a synchronization component; GPU device binding, full
driver/core compile/link and physical Tiger Lake validation remain pending.


## Original boot-CPU L1TF policy (2026-10-15)

The V backend now implements `boot_cpu_has_bug(X86_BUG_L1TF)` using the pinned
Linux 6.6.157 vulnerability whitelist and the original bug index 722. Actual
boot initialization samples each CPU with interrupts disabled before its online
acknowledgement. Missing CPUID leaves or a faulted advertised ARCH_CAPABILITIES
read fail initialization. An IRQ-enabled sampler returns unresolved before any
probe. Only advertised leaf-7 EDX bit 29 permits fault-safe MSR 0x10a reads,
including on vendors otherwise exempt from L1TF. Unknown bug indices, early
queries, duplicate initialization and incomplete boot membership fail explicitly.

The published answer means the bootstrap CPU, as in the original forced bug
policy. Logical CPU zero is the native BSP; AP records validate boot completion
without forming an all-CPU vulnerability union. Immutable publication has boot
lifetime; queries borrow no task or CPU and perform no CPUID/MSR access. The
classifier preserves original first-match exemptions, decoded model behavior
and the original u8 family storage, including synthetic extended-family aliases.
Tiger Lake model identity alone is not an L1TF exemption: RDCL_NO is relevant.
This implements vulnerability observation, without supplying mitigations or GPU
mapping services.

Six GNU99/GNU11 O0/O1/O2 ASan/UBSan host profiles each pass 3,460,560 classifier
cases, 57,600 sampler cases, 2,380 fatal controls and eight concurrent readers.
The independent archive oracle covers all 38 whitelist rows and 15 vendor
inputs. All 54 selected generated bodies match exactly, including six production
bodies checked against separately compiled freestanding objects. Those six
objects have strict import inventories without allocator imports. CPUID, IRQ,
MSR, atomic, boot-record and fatal transports are explicitly modeled; host tests
do not prove actual native MSR execution.

Enabled/default x86-64 and default ARM64 build successfully. Seven enabled
four-CPU guests use one saved ELF and each pass 53 required markers and 35 strict
page/live-heap equality rows. Three complete CPU-bug warmups precede the measured
fourth lifecycle. Three retained actors visit every CPU, yield, sleep for 100
ticks with observed off-queue state, execute repeated original-macro queries,
and join off stack before measurement. The default guest passes Linux ABI
startup without compatibility markers. ARM evidence is build/artifact only.

Actual vendor/signature/leaf-7/MSR/sample/query telemetry verifies unaffected AMD,
affected Intel model 60 and exempt Goldmont model 92. Both requested Tiger Lake
model-140 RDCL_NO configurations actually expose no ARCH_CAPABILITIES under TCG:
QEMU reports four unsupported-bit warnings and masks bit 29. Both therefore
observe sample 2/query 1 without an MSR read. Strict requested-profile validators
reject both intended MSR branches; separate observed-profile checks pass. Native
positive-MSR and RDCL_NO execution remain pending. No requested QEMU property is
counted as an observed capability.

Independent source/lifetime, actual generated-C/O2, host and guest/ISO reviews
pass. The valid paths retain sampler Options, actor owners and heap snapshots
on stack. Invalid checked-index diagnostics may allocate outside validated
membership and are not included in the allocation-free valid-path claim. Default
x86 C includes dormant backend bodies, while startup sampling, initialization,
fixture execution and the final public-query ELF export are absent. ARM excludes
the x86 implementation.

The isolated build baseline is `156ef022a` plus fifteen frozen production/tool
paths. `cpu-bug-native-freeze-v1.json` SHA256:
`0d10f6dd3dd869c5cbe8629bcf9d8213e0e407f5a5d1ffa0260620f0cf16bbd1`.
Enabled ELF:
`82c7c231a7ed58d4acd91c332edbbc07ba2a71b7c367e4094ed8384e4b34d8d4`.
Host `cpu-bug-host-final-v1/result.json` SHA256:
`9ba0ef6c75160fede6d8caf1a02fd3790d10873f622bbb68d54c349229782fe1`.
Independent native C/O2 review SHA256:
`bc14c730b2ea0c6599f772fe8c70fef9c45cd5f62d65d6dde3cbe1d5528f930c`.
Independent host review SHA256:
`aacf281d9914d9950290994881f57514be23845e2c9571e163fd0ae582215714`.
Independent eight-ISO/guest review SHA256:
`3a03fbc38da99c97a328a178dbe191ad3e01a216618dc61afe4c35fca48ee366`.
Root eight-guest proof manifest `cpu-bug-final-guests-v2.json` SHA256:
`fec44da496ab3a0820f828643f44a113d8a6ed69b15bb65a35996c3e01bd46e7`.
It includes two requested-MSR rejection controls; 37 synthetic/known-failure
validator controls are parsing evidence only. Evidence remains under
`/Users/alex/.cache/vinix-linuxkpi/smp-oct10/cpu-bug-*`. Repeat host tests with:

```sh
build-support/run-v-tool.sh tests/linuxkpi/cpu_bugs.v --keep-dir NEW_DIRECTORY
```

The fresh complete i915 syntax audit remains **6/269**, with all 7,668 imported
files unchanged and 8,042 input/generated/dependency paths checked, including
8,009 guarded inputs. The 33 former CPU-bug first
errors now advance to real dependencies. Remaining first-error groups include
229 task/MM/vfork ownership, 25 `slab_flags_t` include ownership and five
`migrate_disable` declarations in a parsed PREEMPT_RT alternative. The configured
atomic I/O mapping path uses preemption pins; declaring migration APIs alone
would not implement I/O mapping. Full driver/core compile/link, device binding,
confirmed PCI identity and physical Tiger Lake validation remain pending.


## Original slab flag type ownership (2026-10-15)

`slab_flags_t` now belongs to `linux/types.h`, matching the pinned original
`typedef unsigned int __bitwise slab_flags_t;`. The duplicate declaration in
`linux/slab.h` is removed. Original KASAN declarations can therefore include
types before slab, without changing allocation flags, accepted cache modes,
allocator behavior or any object lifetime.

The maintained V test checks 48 GNU99/GNU11 cases: 24 corrected production
objects, 12 valid historical include orders and 12 expected wrong-owner
failures. Every compiled object has zero runtime imports. It verifies exact
unsigned-int identity, width/alignment/signedness, original cache prototypes and
flag expressions, and original disabled-KASAN return identity. Eight production
objects use an actual AArch64 compiler for generic scalar/cache declarations;
they do not supply an ARM LinuxKPI runtime. Original Sparse annotation expansion
matches in both dialects; no Sparse semantic-analyzer run is claimed.

Fresh enabled/default x86 and default ARM kernel builds pass from isolated
baseline `d7b24c4bf` plus only these two header edits. Source freeze
`slab-types-native-freeze-v1.json` SHA256:
`e3ceb4721eacf4583a15288172117306003b8fe5ee5893a3d6bbd55528db90ce`.
Host result `slab-flag-types-final-v1/result.json` SHA256:
`38d2e36eea13e5235c63a7ab5481625c59c39c2ad8df7975bc8a985734c467cd`.
The three-path manifest records 153 saved compiler-dependency snapshots so
later unrelated header work cannot be mistaken for this test's inputs.
Independent source, compiler-input, object and full-audit review SHA256:
`2da86f390896a22a29190b7b92c6b008f592794cf17012f0edc362d384218ef2`.
Evidence is under `/Users/alex/.cache/vinix-linuxkpi/smp-oct10/slab-*`.
Repeat with:

```sh
build-support/run-v-tool.sh tests/linuxkpi/slab_flag_types.v --keep-dir NEW_DIRECTORY
```

All 25 previously blocked commands now pass the slab flag type declaration and
reach original `memremap.h`'s existing `DECLARE_FLEX_ARRAY` dependency. The full
unchanged audit remains **6/269**, with 229 task/MM/vfork first errors, 28 type
declaration errors, five migration API declarations and one entry-stack record.
The 7,668-file import is unchanged. This is compiler/type closure; driver/core
linking, device ownership and physical Tiger Lake validation remain pending.
