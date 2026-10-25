# Native alternate-stack restoration

Native Linux signal return now imports handler-modified uc_stack records.
Previously both architectures discarded that record, so a handler could not
replace or disable its alternate stack for subsequent signals. The kernel
also preserves configured SS_ONSTACK in saved signal frames; live
sigaltstack queries continue to derive flags from the current user SP.

AArch64 applies the record using the restored interrupted SP. x86-64 applies
it using the current handler SP, before restoring interrupted registers.
Consequently an x86-64 handler running on the alternate stack cannot replace
it through sigreturn, while an AArch64 return to the main stack can.
Invalid flags, undersized replacements and changes while the selected SP
is on the current stack are ignored, matching the measured Linux behavior.
Disabling normalizes the base and size to zero.

The probe runs 28 configurations as root and again as UID 1000/GID 2000:
initially enabled/disabled stacks, both SA_ONSTACK settings, and seven
mutations. These keep or replace the record, disable with junk base/size,
use invalid flags, use an undersized stack, set SS_ONSTACK, or change the
live configuration before returning the original record. Two 64 KiB stacks
have inaccessible guard pages. Nonzero upper flag padding checks the ABI's
32-bit flag field.

Each of 56 children reports exactly 16 checks and exits normally. The parent
adds one status/length/count check per child, for 952 checks. An observer
signal verifies the restored configuration, saved flags, placement and live
query behavior after the first handler returns.

| Execution | AArch64 checks / failures | x86-64 checks / failures |
| --- | --- | --- |
| Linux 6.12.51 reference | 952 / 0 | 952 / 0 |
| Original production kernel | 952 / 130 | 952 / 100 |
| Corrected production kernel | 952 / 0 | 952 / 0 |

Each architecture uses its identical native musl ELF on all three kernels.
Original failures match five expected post-return/observer stages in thirteen
AArch64 and ten x86-64 configurations, repeated in both credential cohorts.
Vinix AArch64 uses 16 KiB pages; x86-64 and Linux references use 4 KiB pages.

The isolated candidate is `6753f67b20200d10961e58d48f3d3ff2e1dd01de`, based on
`ca6031576041870ce9f8c23981594696a4bef84e`. Production builds use seed 42,
`MP=1`, `ALLOC_TRACK=0`, with identical before/after input hashes. Kernel SHA-256:

- AArch64: `758a9cdab47fd7ebc618a83a4285b39b27946f955552ccbaeadd6bc897fb5a3d`
- x86-64: `9ceaee6c2fb89619e17e1b963228e083e8938e34ee85c7bd148434b9c9394a9e`

Generated-C review compares 395 AArch64 and 434 x86-64 userland/table/timer
function bodies. Only three existing bodies change per architecture, plus
the new restore helper. Changed bodies add no allocation or release
operations. The AArch64 register state and stack record remain C stack
locals. This change introduces no object lifetime change; no leak
qualification is claimed.

All twenty maintained cases pass on each corrected production architecture:
altstackrestore, altstacknest, altstackframe, altstacksp, altstackhandler,
altstackabi, sigactionabi, sigactioncopy, sigmaskcopy, altstackcopy,
sigwaitorder, sigwaitcopy, sigpending, randomsignal, clonesignal, cloneclear,
seccomp, runtime, futex and jit. Controller, runner, fixture, compiler and
kernel pins remain unchanged before and after each selected run. Earlier
intermittent randomsignal/futex failures remain unresolved.

The complete bundle is
`/Users/alex/.cache/vinix-linux-compat/altstackrestore-20261025/evidence-final`.
Its source inventory, exact patch, production build receipts, generated C,
Linux/baseline/fixed runs, maintained suites, tools and all selected input
pins are retained. Artifacts are consolidated only when bytes and modes
match. Historical bundles remain unchanged.

The complete-bundle audit passes for all 18,676 artifacts, with zero omitted
selected input pins. Manifest SHA-256:
`82d45b4a14378b3d534cf708e15a51fd78bdf18e684830fd8e8ad8d27c7fe7d6`.

Earlier attempts remain in the bundle: compiler-wrapper launch and V
compilation errors, a probe incorrectly expecting configured SS_ONSTACK to
be discarded, the initial kernel candidate, Linux/baseline results from that
probe, and the generated-C review's initial incorrect textual cast
expectation. These attempts do not supply the selected passing results.

The Linux reference parser passes two positive and nine negative controls;
the evidence checker passes ten positive and 51 negative controls. Compile
both V tools without `-prod` to preserve assertions:

```sh
v -o /external/altstackrestore-reference tests/linux-compat/altstackrestore-reference.v
/external/altstackrestore-reference --self-test
v -o /external/altstackrestore-evidence tests/linux-compat/altstackrestore-evidence.v
/external/altstackrestore-evidence self-test
/external/altstackrestore-evidence check /external/complete-bundle
```

The maintained fixture is
[`altstackrestorefixture/core.v`](../tests/linux-compat/altstackrestorefixture/core.v).
The [test runner](../tests/linux-compat/README.md) accepts `--cases altstackrestore`.
Linux v6.12 reference snapshots are retained for
[`kernel/signal.c`](https://github.com/torvalds/linux/blob/v6.12/kernel/signal.c),
[`arch/arm64/kernel/signal.c`](https://github.com/torvalds/linux/blob/v6.12/arch/arm64/kernel/signal.c)
and [`arch/x86/kernel/signal_64.c`](https://github.com/torvalds/linux/blob/v6.12/arch/x86/kernel/signal_64.c).

This qualifies the specified native SA_SIGINFO frames and mutations.
SS_AUTODISARM, dynamic frames, minimum-stack delivery, faulting sigreturn
frames, general sigreturn context validation and races remain unqualified.
GNU libc, translated/32-bit paths, installation, services, sandboxing and
portals remain separate roadmap gates.
