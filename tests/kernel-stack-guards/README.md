# Guarded kernel stack regression

Runtime kernel stacks use dedicated virtual mappings with an unmapped native
page below and above them. The backing pages retain their physical direct-map
aliases. Thread mappings remain owned until the scheduler has left the stack;
teardown invalidates their translations before returning physical pages.

The mappings cover user and kernel thread stacks, x86 page-fault, scheduler,
idle, abort and double-fault stacks, and ARM exception, emergency and idle
stacks. CPU stacks last for that CPU's lifetime. Bootloader stacks and ARM's
early static exception fallback remain necessary until Vinix installs its
page tables; the boot CPU then abandons its bootstrap stack before idling.

ARM current-level vector entry checks both endpoints of its save frame before
touching SP_EL1. An exhausted frame switches to a private emergency stack.
TPIDR_EL1 points at permanent per-CPU scratch; its public accessors still
return the CPU number. Full x15/x16/x17 values are restored and scratch is
cleared before calling C. TPIDRRO_EL0 remains zero when user code runs.
Exception entry masks DAIF, including SError, and Vinix does not enable NMI.
Recursive exhaustion of the emergency stack or a broken permanent kernel
mapping is outside this mechanism's recovery guarantee. Real exhaustion is
fatal; general kernel fault recovery is not enabled.

## Build and run

From an isolated worktree with the normal dependencies available:

```sh
make -C kernel ARCH=aarch64 CC=clang V=/Users/alex/code/v/v LIMINE_MP=1 STACK_GUARD_TEST=1 -j4
python3 tests/kernel-stack-guards/run.py --arch aarch64 --repo /Users/alex/code/vinix --kernel kernel

STACK_GUARD_TEST=1 NPROC=4 V=/Users/alex/code/v/v ./build-amd64.sh --no-userland --no-iso
python3 tests/kernel-stack-guards/run.py --arch amd64 --repo /Users/alex/code/vinix --kernel build-amd64-kernel/bin/vinix
```

`STACK_GUARD_TEST=1` performs actual reads and writes at both ends of both
guards, plus an actual stack-underflow instruction. Only the exact opt-in
probe PC and address pair may resume. It verifies full-width ARM register
preservation, supervisor writable NX stack mappings, the retained direct-map
alias, 64 allocation/free cycles, mapping failure rollback (including a
partially installed ARM native page), and 32 unpublished-thread constructor
failure/success cycles without retaining physical pages.

Build with `STACK_GUARD_TEST=2` and pass `--expect-overflow` to the same runner
to disable recovery for the actual stack-underflow instruction. The runner
requires SP, PC and fault-address serial diagnostics followed by the fatal
marker. This tests ARM's emergency entry and x86's independent page-fault
stack. Fatal builds are test artifacts, not deployable kernels.

The normal configuration is `STACK_GUARD_TEST=0`. Pass `--runtime-only` to
exercise it. Adding `ALLOC_TRACK=1` records surviving heap allocations.
The guest warms up, then performs two batches of five forked processes, each
with eight concurrent threads doing pipe I/O. Each process is stopped,
continued, killed and reaped. After the retirement grace period it reports
physical and slab memory, and dumps `/proc/allocsites`. The x86 guest redirects
its output to `/dev/com1` for headless runs.

## Validation limits

Both architecture builds passed with the self-test, fatal-overflow and normal
tracked configurations. Actual faults and constructor rollback passed on both.
The normal tracked guest measured ARM slab usage of 1328, 1328 and 1328 KiB,
and x86 usage of 928, 932 and 932 KiB across warmup and the two batches. Physical
retention was 16 then 0 KiB on ARM, and 8 then 0 KiB on x86. Allocation tracking
reported 12 and 30 live objects respectively, with no surviving call-chain
group reaching `/proc/allocsites`' 50-object threshold. The full four-CPU ARM
job-control regression also passed, including constructor/exit races, IPC
waiters, orphan transitions and 400 stop/continue cycles.

The complete static allocation audit already fails on this repository's
current V compiler. Compared with the same baseline, this change adds no
reported allocation category or count and reduces scheduler heap-struct
sites from four to one on each architecture. The allowance file is unchanged.
Read generated C and actual guest measurements when assessing ownership;
the compiler audit alone does not establish freedom from leaks.
