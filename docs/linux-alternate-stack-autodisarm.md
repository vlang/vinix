# Native automatically disarmed signal stacks

Both native architectures now implement Linux SS_AUTODISARM. sigaltstack
accepts the high flag bit with the enabled, SS_ONSTACK or SS_DISABLE mode.
Queries preserve the configured bit. Delivery saves the complete stack
configuration in uc_stack and clears the live configuration before entering
the handler, including when SA_ONSTACK is absent. sigreturn restores the
saved configuration through the existing validation path. A handler can
install another stack while the original is disarmed.

The guarded probe uses three initial modes, delivery with and without
SA_ONSTACK, and five handler operations: leave disabled, install a normal
second stack, install an automatically disarmed second stack, disable with
the automatic flag, and replace the saved uc_stack. It runs as root and
UID 1000/GID 2000. Nested delivery checks placement, saved contexts and live
queries; inner and outer returns check restoration and handler changes.
Each of 60 cases has 25 child checks and one parent completion check.

| Execution | AArch64 checks / failures | x86-64 checks / failures |
| --- | --- | --- |
| Linux 6.12.51 reference | 1560 / 0 | 1560 / 0 |
| Original production kernel | 1560 / 640 | 1560 / 640 |
| Corrected production kernel | 1560 / 0 | 1560 / 0 |

Each architecture runs the identical musl probe ELF on all three kernels.
The original failure pattern is checked by case and stage, including fallback
delivery after the unsupported registration. Vinix AArch64 uses 16 KiB pages;
x86-64 and the Linux references use 4 KiB pages.

The isolated candidate is `e56be5611e5e100b0126da5fb056163fd3bc0408`, based on
`c6b5455ee837f44b843d03255294c8b610ad7635`. Production builds use seed 42,
`MP=1` and `ALLOC_TRACK=0`, with identical before/after input hashes.
Kernel SHA-256:

- AArch64: `37980a474a6aebbbd69bb2f60f1dca207177c1a9df3323c9bceb2fb231a55269`
- x86-64: `4e293afd1a1d1b65387a1527a0571d63e8c8f2f8f0edfc716af9778fffaff1ae`

Generated-C review compares 397 AArch64 and 436 x86-64 userland/table/timer
function bodies. Only signal delivery, stack queries, stack registration and
restoration change. No function, allocation or release operation is added;
all new state changes are scalar. No object lifetime or leak qualification
is claimed.

All 22 selected maintained cases pass on each corrected architecture: autodisarm,
altstackclone, altstackrestore, altstacknest, altstackframe, altstacksp,
altstackhandler, altstackabi, sigactionabi, sigactioncopy, sigmaskcopy,
altstackcopy, sigwaitorder, sigwaitcopy, sigpending, randomsignal,
clonesignal, cloneclear, seccomp, runtime, futex and jit. Controller,
runner, fixture, compiler and kernel inputs are pinned before and after
each selected run. Earlier randomsignal/futex intermittents remain unresolved.

The complete bundle is
`/Users/alex/.cache/vinix-linux-compat/autodisarm-20261026/evidence-final`.
It retains exact sources, production build receipts, generated C,
Linux/baseline/fixed runs, maintained suites, tools and all selected input
pins. Artifacts are consolidated only when bytes and modes match.
Historical bundles remain unchanged; the manifest is beside the README.
The manifest covers 18,467 artifacts with zero omitted selected input pins.
Its SHA-256 is
`8c23d2c2276481fdbf767785941902062e50aebfe39995cdf2bafe4f633a824e`.

Preparation failures remain in the bundle. The first AArch64 maintained
attempt failed fixture compilation because its copied compiler wrapper
required the previous fixture's state-directory prefix. The corrected
wrapper and controller use a fresh state directory; the failed attempt is
retained in full and supplies no selected passing results. The first x86-64
probe compilation failed during directory creation; its second attempt is
selected. The Linux reference parser passes two positive and nine negative
controls; the evidence checker passes ten positive and 51 negative controls.
Compile both V tools without `-prod` to preserve assertions:

```sh
v -o /external/autodisarm-reference tests/linux-compat/autodisarm-reference.v
/external/autodisarm-reference --self-test
v -o /external/autodisarm-evidence tests/linux-compat/autodisarm-evidence.v
/external/autodisarm-evidence self-test
/external/autodisarm-evidence check /external/complete-bundle
```

The maintained fixture is
[`autodisarmfixture/core.v`](../tests/linux-compat/autodisarmfixture/core.v).
The [test runner](../tests/linux-compat/README.md) accepts `--cases autodisarm`.
The bundle retains Linux v6.12 reference snapshots of
[`signal.h`](https://github.com/torvalds/linux/blob/v6.12/include/linux/signal.h),
[`sched/signal.h`](https://github.com/torvalds/linux/blob/v6.12/include/linux/sched/signal.h)
and [`kernel/signal.c`](https://github.com/torvalds/linux/blob/v6.12/kernel/signal.c).

This qualifies native flag acceptance, disarming, nested delivery and return
state. swapcontext/siglongjmp integration, creation from active handlers,
malformed general signal contexts and races remain unqualified. GNU libc,
translated/32-bit paths, installation, services, sandboxing and portals remain
separate roadmap gates.
