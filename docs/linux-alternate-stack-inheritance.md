# Native alternate-stack inheritance

Fork and clone now initialize the child's alternate signal stack from the
calling thread. A private address space inherits the configured base, size
and flags. CLONE_VM clears the child's stack unless CLONE_VFORK also suspends
the parent. Both native architectures use the same helper before publishing
the new thread. This also covers clone3 and pthread creation.

The probe runs eight creation paths with three initial configurations
(disabled, enabled, and enabled with configured SS_ONSTACK), as root and as
UID 1000/GID 2000. The paths are musl fork, clone with private memory, clone
with CLONE_VM, clone with CLONE_VFORK, clone with both flags, pthread_create,
and private clone3 with and without CLONE_VFORK. Two guarded 64 KiB alternate
stacks and a separate guarded 256 KiB callback stack exercise actual delivery.

Each descendant checks its inherited configuration, SA_SIGINFO saved stack
record, SA_ONSTACK placement, live queries, return state, replacement with the
second stack and disabling. The parent checks completion and its unchanged
configuration, then delivers another signal. There are 48 independent cases,
with 19 descendant checks, ten parent checks and one outer status check each:
1,440 checks in total. Explicit kernel PID/TID queries avoid libc's cached
thread identity on shared-memory clone paths.

| Execution | AArch64 checks / failures | x86-64 checks / failures |
| --- | --- | --- |
| Linux 6.12.51 reference | 1440 / 0 | 1440 / 0 |
| Original production kernel | 1440 / 120 | 1440 / 120 |
| Corrected production kernel | 1440 / 0 | 1440 / 0 |

Each architecture runs its identical native musl ELF on all three kernels.
Original failures match five inheritance/first-delivery checks in 24 cases;
CLONE_VM without CLONE_VFORK and pthread creation already cleared the stack.
Vinix AArch64 uses 16 KiB pages; x86-64 and Linux references use 4 KiB pages.

The isolated candidate is `c6b5455ee837f44b843d03255294c8b610ad7635`, based on
`6753f67b20200d10961e58d48f3d3ff2e1dd01de`. Production builds use seed 42,
`MP=1`, `ALLOC_TRACK=0`, with identical before/after input hashes. Kernel SHA-256:

- AArch64: `98bfeb6bbfb247ef476e462cd89f055d7b9ec92c2452f5a550cdf277ef394999`
- x86-64: `d67907f73051497e642ee091085e70fb6938b651ac4ffa1ae0615c05843186d4`

Generated-C review compares 396 AArch64 and 435 x86-64 userland/table/timer
function bodies. Only the two clone constructors change, with one new helper
that copies or clears three scalar fields. No allocation or release operation
is added. This introduces no object lifetime change; no leak qualification
is claimed.

The selected maintained run covers 25 cases on each corrected architecture:
altstackclone, clonestack, cloneflags, clonethreadns, cloneparent,
altstackrestore, altstacknest, altstackframe, altstacksp, altstackhandler,
altstackabi, sigactionabi, sigactioncopy, sigmaskcopy, altstackcopy,
sigwaitorder, sigwaitcopy, sigpending, randomsignal, clonesignal, cloneclear,
seccomp, runtime, futex and jit. Controller, runner, fixture, compiler and
kernel pins are checked before and after each selected run. Earlier
intermittent randomsignal/futex failures remain unresolved.

AArch64 passes all 25 cases. The x86-64 run passes 24 of 25: randomsignal
reports one failed transfer check. Its first root transfer completes the full
8 MiB request with a signal observed and no saved read frame; the other 47
transfers pass. The one-shot timer may have fired before syscall entry, since
the fixture has no entry handshake. This is an inference, not a resolved
kernel diagnosis. The complete failing serial log is retained with SHA-256
`2e189c0392e19ca4939eb8ce906697791aeed6fba7a7f97b4e769111f21af497`.
The evidence checker requires this exact diagnostic and exit status; its
VALID result reports the partial maintained result and does not imply an
all-passing regression suite.

The complete bundle is
`/Users/alex/.cache/vinix-linux-compat/altstackclone-20261026/evidence-final`.
It retains the exact source patch, source inventory, production build
receipts, generated C, Linux/baseline/fixed runs, maintained suites, tools
and all selected input pins. Artifacts are consolidated only when bytes
and modes match. Historical bundles remain unchanged. The manifest is
stored beside the bundle's README.

The manifest covers 18,435 artifacts with zero omitted selected input pins.
Its SHA-256 is
`775b390b910ed7ea1b7fc9faa9d9771f9d53a4c1dc19e39571c454991543e0c8`.

Earlier preparation attempts remain in the bundle, including evidence
checker generation/compilation failures. They do not supply selected passing
results. The Linux reference parser passes two positive and nine negative
controls; the evidence checker passes eleven positive and 57 negative controls.
Compile both V tools without `-prod` to preserve assertions:

```sh
v -o /external/altstackclone-reference tests/linux-compat/altstackclone-reference.v
/external/altstackclone-reference --self-test
v -o /external/altstackclone-evidence tests/linux-compat/altstackclone-evidence.v
/external/altstackclone-evidence self-test
/external/altstackclone-evidence check /external/complete-bundle
```

The maintained fixture is
[`altstackclonefixture/core.v`](../tests/linux-compat/altstackclonefixture/core.v).
The [test runner](../tests/linux-compat/README.md) accepts `--cases altstackclone`.
The bundle retains the Linux v6.12
[`kernel/fork.c`](https://github.com/torvalds/linux/blob/v6.12/kernel/fork.c)
reference snapshot, including the CLONE_VM/CLONE_VFORK reset condition.

Creation while a signal handler is active, the libc vfork wrapper,
SS_AUTODISARM, races and general signal-context validation remain unqualified.
GNU libc, translated/32-bit paths, installation, services, sandboxing and
portals remain separate roadmap gates.
