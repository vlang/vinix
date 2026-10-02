# Linux i915 next-session handoff

Prepared 2026-10-02 for `/Users/alex/code/vinix`, on macOS ARM64 with zsh.
Implementation baseline: **`de5db8a3`**. Recheck HEAD and the worktree before
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
> Start with the missing CPU-bound and high-priority workqueues, then continue
> through the remaining driver dependencies. Keep upstream sources unchanged,
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

The previous coding turn stopped after a transient missing command-runner
binary (`codex-code-mode-host`). Repository tools recovered during this
handoff. **No CPU-binding or CPU-bound workqueue implementation was written
after `de5db8a3`.** Do not treat the proposed design below as existing code.

## Committed progress

| Commit | Completed runtime change |
| --- | --- |
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
  macros are used. Native queues are aligned to 256 bytes so their pointers
  can be encoded in `work.data`. `PENDING|PWQ` means queued; `INACTIVE` also
  means a delayed timer reservation. Do not change upstream layouts.
- Explicit `alloc_ordered_workqueue(..., 0)` has one FIFO worker. Concurrent
  `alloc_workqueue(..., WQ_UNBOUND, max_active)` supports limits 1 through 512,
  with zero selecting 256. The current implementation has one affinity domain.
- Unordered queues with `max_active > 1` have a manager that creates workers
  with interrupts enabled, outside `work_lock`. Single-active and ordered
  queues need only one worker. Enqueue and delayed-arm paths allocate nothing
  and can run with interrupts disabled. Workers stay until destruction, so
  an unbound queue retains its peak worker count during its lifetime.
- Each `native_worker` owns a pthread, retained task and ready completion.
  Destruction drains, stops workers, removes the queue, **joins the manager
  before traversing its final worker list**, then joins/releases every worker.
  The manager can publish a just-created worker during destruction. Preserve
  this ordering and test partial construction/OOM rollback.
- `system_unbound_wq` is initialized at boot and has boot lifetime. Warm its
  peak before measuring temporary retained allocations. Other system queues
  remain unresolved, including default and high-priority queues.
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

## Immediate next feature: bound and high-priority queues

Actual upstream requirements still fail:

| Driver use | Current result |
| --- | --- |
| `i915_driver.c`: `alloc_workqueue("i915-unordered", 0, 0)` | CPU-bound allocation unsupported |
| `intel_display_driver.c`: high-priority unbound flip queue | `WQ_HIGHPRI` unsupported |
| Ordinary ordered i915/DP/modeset/GSC queues | Supported subset |
| Cleanup/TTM/PXP/GUC/display-power `system_unbound_wq` work | Queue API available; those subsystems remain incomplete |
| Heartbeat/timestamp/log/commit high-priority system work | `system_highpri_wq` unresolved |
| `schedule_work`, `_on` variants and default system work | Default bound system queue unresolved |

`WQ_FREEZABLE`, `WQ_MEM_RECLAIM`, reclaim rescuers, CPU-intensive/sysfs and
attribute modes, explicit CPU queueing and RCU work remain unsupported.
Review exact pinned Linux semantics before accepting additional flags.

The following is a **proposal**, not committed code:

1. Implement an internal native helper for a kernel worker to bind itself to
   an online CPU before publishing readiness. Validate IRQ/preemption state
   and CPU range, publish the affinity mask, wake the selected CPU, reschedule
   until actually running there, and test identity after sleep/yield.
   `proc.set_thread_affinity(tid, mask)` cannot simply be reused: anonymous
   kernel pthreads have TID 0 and public lookup requires a positive TID.
2. Existing `Thread.affinity_mask` is a 64-bit mask on both architectures;
   `sched/policy.v:may_run_here` does not constrain CPUs above 63. Do not claim
   bindings beyond that range. `CONFIG_NR_CPUS` is 256; either explicitly
   restrict bound support to machines with at most 64 online CPUs or extend
   the scheduler masks. Inspect enqueue wake selection: waking the
   first idle CPU without checking affinity may leave the actual target asleep.
   Clear/update NUMA hints consistently when moving a worker.
3. Provide bound pools with `max_active` enforced per CPU. Default queueing
   chooses the calling CPU under IRQ/preemption protection; explicit `_on`
   selects a valid CPU. If executing work is requeued on its same public queue,
   preserve Linux's selection of its original execution pool even when the
   producer runs on another CPU. One candidate is aligned pool objects encoded
   in `work.data`, each carrying a public queue owner and CPU. Choose the
   representation deliberately; this has not been implemented or finalized.
   Create workers on demand: each x86 kernel pthread currently owns two
   2 MiB stacks, and the native runnable queue has 512 slots shared with other
   threads. Eagerly creating 256/512 workers per CPU would be impractical.
   Keep sleeping callbacks counted toward per-CPU `max_active`. Current
   `wq->nr_running` counts in-flight callbacks, whereas Linux bound pool
   `nr_running` tracks runnable workers for concurrency management. Full
   bound semantics need distinct runnable accounting and sleep/wake hooks;
   do not release an active slot just because its callback sleeps.
4. Public queue flush must snapshot all pools atomically. Flushing each child
   pool sequentially would take different boundaries and include later work.
   Preserve cross-queue no-overlap, owner-based chaining, stack markers and
   partial construction/destruction safety. Delayed transfer must retain its
   selected CPU without allocating on each arm.
5. Implement real high-priority worker scheduling. Current nice is stored in
   `Process.nice`, and all kernel workers share a kernel process. Changing its
   nice would affect unrelated kernel threads. Consider a per-thread native
   weight/nice override with appropriate scheduler tests. SCHED_FIFO/RR is
   not Linux `WQ_HIGHPRI` negative-nice semantics; do not substitute it.
6. Add default/high-priority system queues only once their actual semantics,
   bootstrap failure handling and boot lifetimes are covered. Keep unsupported
   hotplug, reclaim/freezer and attribute behavior explicit.

## Parallel-agent execution plan

The last environment allowed **four active agents including root**. Use root
plus three workers continuously, then recycle completed workers into further
waves. If a new session has more slots, split research/review/build jobs
further. Spawn fresh agents; prior session names do not imply live agents.
Give every agent a concrete result, file ownership, ABI contracts, baseline
commit and validation requirements. They share the checkout.

### Wave 1: CPU-bound queues

Start by booting the final saved ELF in fresh normal/SSE guests, or boot a
fresh baseline build, to close the artifact gap described below while agents
inspect the next feature. Use current checkout harnesses rather than the
older scripts left in the temporary worktrees.

| Owner | Responsibility | Exclusive files / boundaries |
| --- | --- | --- |
| Root | Design contracts, shared integration, native test integration, build/boot, commit | `bridge_amd64.v`, `include/vinix/runtime.h`, `GNUmakefile`, `run.sh`, shared process/scheduler changes and docs |
| Agent A | Bound pool backend, routing, cross-pool flush/cancel/destroy | `kernel/c/linuxkpi_workqueue.c`; coordinate new bridge declarations with root |
| Agent B | Kernel-worker CPU binding and targeted wake support | New `kernel/linuxkpi/worker_amd64.v`; propose scheduler edits to root instead of concurrently editing shared files |
| Agent C | Independent bound-queue host model and regression tests | New `tests/linuxkpi/bound_work_test.h`; send integration changes to root |

Agree on the binding helper and queue/pool encoding before dependent edits.
Agent C should test externally observable semantics, not duplicate backend
logic. Essential cases: actual CPU placement through sleep/yield, idle target
wakeup, per-CPU active limits, explicit CPU routing, delayed routing, same-item
migration, atomic enqueue paths, whole-queue snapshots, cancellation/rearm,
partial failure and full native teardown. Root measures pages in a fresh
worktree and reviews generated V C for hidden allocations.

### Wave 2: review, priority and next dependency research

Recycle an available agent into independent read-only lifetime review before
committing new allocation/reclamation paths. Use another for high-priority
worker semantics and tests, and the third for a pinned-source RCU/SRCU and
audit dependency inventory. Keep workqueue backend changes under one owner;
parallelize priority bridge and test work, then integrate sequentially.

After each integrated feature, run the relevant host checks, builds and native
measurement. One agent can inspect audit diagnostics while another validates
an isolated architecture build and a third reviews lifetimes. Each build must
have its own writable objects/caches. Do not commit implementation fragments
that lack functioning integration or claim tests someone has not run.

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
| `kernel/c/linuxkpi_{timer,time,sync,task,percpu}.c` | Native runtime backends |
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

These are the previous implementation's recorded results, not fresh tests
run for this documentation-only handoff:

| Check | Result and artifact |
| --- | --- |
| Host runtime + import tests | ASan/UBSan and strict warnings pass; `/tmp/vinix-linuxkpi-unbound-host-final.log` |
| x86-64 `LINUXKPI=1` build | Pass; `/tmp/vinix-linuxkpi-unbound-enabled-build-final.log` and exact-source `...-enabled-build-commit.log` |
| arm64 `LINUXKPI=0` build | Pass; `/tmp/vinix-linuxkpi-unbound-arm-build.log`, `...-final.log`, `...-commit.log` |
| Default x86-64 build | Pass; `/tmp/vinix-linuxkpi-unbound-default-build.log` |
| Four-CPU default QEMU | Linux-ABI startup pass with no LinuxKPI markers; `/tmp/vinix-linuxkpi-unbound-default-vm/serial.log` |
| Four-CPU enabled QEMU, CPU `max` | Earlier saved ELF passed; `/tmp/vinix-linuxkpi-unbound-vm/serial.log` and sibling harness log |
| Four-CPU enabled QEMU, `max,hypervisor=off` | Earlier saved ELF passed including original SSE4.1 copy/FPU path; `/tmp/vinix-linuxkpi-unbound-sse-vm/serial.log` |
| Full i915 syntax audit | Expected exit 1, **1/269**; `/tmp/vinix-linuxkpi-unbound-audit.log`, `build/linuxkpi/i915-audit.json` |

The enabled guest logs contain the required new marker:

```text
linuxkpi: concurrent unbound workqueues, active limits, system_unbound_wq and teardown passed; no pages retained
```

The recorded harness PASS headline predates the wording update that mentions
unbound work; verify the serial marker itself. Both enabled guest runs used
the earlier saved ELF, not the final rebuilt ELF. Their hashes are:

```text
tested enabled.elf:
35913d5a06aeca78dd2d87e41efd304d450a5be516a6f99abec84e9266891545
rebuilt enabled-final.elf:
fcf2ac20f1036dc278b536a9c28b951cd04600250219f7de35772618644781ef
```

The subsequent source change was host-test-only, and the final compile/link
passed, but the available logs do not establish a guest boot of the final
ELF. Make that rerun an early next-session check. Older `host-initial.log`
printed PASS despite a UBSan alignment diagnostic; use the clean final host
log as evidence, not the earlier headline.

Native workqueue batches use three warmups plus a measured fourth batch.
The permanent system queue is
deterministically warmed to eight simultaneously held callbacks. Temporary
queues at limits two/four exercise real sleep/rearm, nested item flush and
24 self-freeing objects per batch; measured pages return exactly to baseline.
Host coverage includes limits one/two/four, 20 overlapping flushers, late-start
old work, manager-publication-versus-destroy races, 200 self-freeing objects,
shared delayed producers and system initialization failure/reuse/release.

Independent lifetime reviewers approved the committed task, sync, time,
timer, ordered/delayed and unbound changes. The final unbound review also
checked native OOM and timeout cleanup, publication, stack result ownership,
the manager gate and overlapping flush models. New changes need new review.

Do not claim the entire kernel allocation gate passes: previous broader
allocation checks had existing baseline failures outside this work. The
new per-feature page recovery measurements passed. Read/measure the current
baseline before diagnosing or claiming a global result.

The audit's prominent first-error groups include unknown SRCU implementation,
`WARN_ONCE`, `pr_warn`, `is_power_of_2`, `ktime_t`, `PF_VCPU`, `current`,
`clamp_val`, `add_taint`, missing `asm/kmap_size.h` and incomplete timer types.
These reflect compilation paths and missing integration, not a complete
runtime dependency inventory. Read full per-unit diagnostics and real callers.
Even 269/269 syntax success would still need actual object linking, symbol
closure, hardware operation and userspace validation.

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

Read-only handoff verification found that both unbound worktrees' tracked
kernel sources match `de5db8a3`, although their detached HEADs are older and
three implementation files are locally modified. Their docs/test harnesses
are older. Use current root test scripts against an explicitly chosen kernel.

For kernel lifetime changes follow `AGENTS.md`: measure repeated operations,
inspect generated C for hidden V allocation, use allocation-site tracking when
needed, build both architectures, and obtain independent lifetime review
before committing. Broader syscall/desktop allocation checks are documented
there; preserve known baselines and clearly scope feature-specific evidence.

## Remaining path to completion

1. Bound/priority and required system workqueues; remaining synchronization,
   RCU/SRCU, SMP/context and timer interfaces.
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
