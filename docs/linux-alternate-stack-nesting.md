# Repeated native alternate-stack nesting

AArch64 signal delivery now determines whether an alternate stack is active
from the interrupted user stack pointer. The previous bookkeeping flag was
cleared by an inner sigreturn while the outer handler was still running. A
second nested SA_ONSTACK signal consequently reused the stack top and destroyed
the outer frame. x86-64 already uses the interrupted stack pointer.

The regression probe exercises three sequential inner signals per outer
handler, enabled/disabled stacks and both outer/inner SA_ONSTACK settings.
Root and UID 1000/GID 2000 cohorts check saved uc_stack configuration, actual
placement, guarded live queries, a 512-byte outer-stack canary and return state.
Each cohort forks eight children with bounded waits; the parent requires exact
child totals and exit status. The alternate stack has 64 KiB of usable storage
between inaccessible guard pages.

| Execution | AArch64 checks / failures | x86-64 checks / failures |
| --- | --- | --- |
| Linux 6.12.51 reference | 592 / 0 | 592 / 0 |
| Original production kernel | 520 / 2 | 592 / 0 |
| Corrected production kernel | 592 / 0 | 592 / 0 |

Each architecture uses its identical native musl ELF across all three kernels.
Original AArch64 loses both enabled outer+inner SA_ONSTACK children with status
7 before they report their totals; the other fourteen children pass 36 checks
each. Unreported checks are not counted. Production AArch64 uses 16 KiB pages;
x86-64 and both Linux references use 4 KiB pages.

The isolated candidate is `ca6031576041870ce9f8c23981594696a4bef84e`, based on
`5b3178ace528631c0b4a60b167c9b9ecd6236860`. Production builds use seed 42,
`MP=1`, `ALLOC_TRACK=0`, with identical before/after input hashes. Kernel SHA-256:

- AArch64: `8e6e52d19bf4ed1cb9c0e18d2c5874d206ee446c92583befb4da2c4de627f181`
- x86-64: `4de60361e177630383da4dea1a865a8e331e424a08077a7a5ded621848ce5cda`

An exact whole-file generated-C comparison permits only the AArch64 helper
signature, interrupted-context argument and active-stack condition changes.
It compares 395 AArch64 and 434 x86-64 userland/table/timer bodies; two AArch64
bodies change and x86-64 C remains identical. There are no allocation, release,
usercopy or lifetime changes. No leak qualification is claimed.

All nineteen maintained cases pass on each corrected production architecture:
altstacknest, altstackframe, altstacksp, altstackhandler, altstackabi,
sigactionabi, sigactioncopy, sigmaskcopy, altstackcopy, sigwaitorder,
sigwaitcopy, sigpending, randomsignal, clonesignal, cloneclear, seccomp,
runtime, futex and jit. Controller, runner, fixture, compiler and kernel input
hashes are identical before and after each selected run.

The complete bundle is
`/Users/alex/.cache/vinix-linux-compat/altstacknest-20261025/evidence-final`.
Its manifest retains 19,766 artifacts and omits no selected input pins;
`manifest.json` SHA-256 is
`59d243fc1dd74a238b954503a86e2a8cd3067c3f02e0d81f6d768389e29252cb`.
It also retains earlier attempts: image/assembler ENOSPC failures in the
first batches, an incorrect AArch64 compiler-wrapper prefix in the second
batch, and thirteen AArch64 image-preparation command failures in the third.
The third batch's final host log/status are absent after interruption; its
remaining receipts do not establish an ENOSPC cause. Complete earlier guest
results remain available. Mode-aware SHA-256 consolidation maps and repair
receipts preserve artifact bytes and executable modes.

The complete-bundle checker passes with exit status zero; its retained host
log and status are `altstacknest-20261025/audit-complete-first.log` and
`altstacknest-20261025/audit-complete-first.status` beside the bundle.

The Linux reference parser passes two positive and nine negative controls;
the evidence checker passes eight positive and forty negative controls.
Compile both V tools without `-prod` to preserve assertions:

```sh
v -o /external/altstacknest-reference tests/linux-compat/altstacknest-reference.v
/external/altstacknest-reference --self-test
v -o /external/altstacknest-evidence tests/linux-compat/altstacknest-evidence.v
/external/altstacknest-evidence self-test
/external/altstacknest-evidence check /external/complete-bundle
```

The maintained fixture is
[`altstacknestfixture/core.v`](../tests/linux-compat/altstacknestfixture/core.v).
The [test runner](../tests/linux-compat/README.md) accepts `--cases altstacknest`.
Historical complete bundles and their checkers remain unchanged and required.

This qualifies three sequential nested deliveries with the specified guarded
stack. Handler-modified uc_stack restoration, SS_AUTODISARM, dynamic frames,
minimum-stack delivery and races remain unqualified. GNU libc, translated and
32-bit paths, installation, services, sandboxing and portals remain separate
roadmap gates. Earlier intermittent randomsignal/futex failures remain unresolved.
