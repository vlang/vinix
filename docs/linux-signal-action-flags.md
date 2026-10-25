# Native signal-action flag normalization

Native rt_sigaction now retains only Linux UAPI signal-action flags in new
actions and queried records. Unknown bits, the internal SA_IMMUTABLE bit and
SA_UNSUPPORTED are cleared. Applications can query an action after setting
SA_UNSUPPORTED to probe which flag bits the ABI retains.

The probe exercises all 64 individual bits and eight combined values for
signals 10, 12 and 35, as root and UID 1000/GID 2000. Each of 432 iterations
checks installation, normalized queries, aliased input/output, output EFAULT
after a committed update, and input EFAULT preserving state and output.
There are 15 checks per iteration; no signal is delivered by this probe.

| Execution | AArch64 checks / failures | x86-64 checks / failures |
| --- | --- | --- |
| Linux 6.12.51 reference | 6480 / 0 | 6480 / 0 |
| Original production kernel | 6480 / 870 | 6480 / 870 |
| Corrected production kernel | 6480 / 0 | 6480 / 0 |

Each architecture runs the identical musl probe ELF on all three kernels.
The checker requires all six credential/signal summaries and the original
failure pattern, including the deliberately bounded mismatch log. Vinix
AArch64 uses 16 KiB pages; x86-64 and Linux references use 4 KiB pages.

The isolated candidate is `98b3b84e5ad79afe070597e67e13c95001736f11`, based on
`e56be5611e5e100b0126da5fb056163fd3bc0408`. Production builds use seed 42,
`MP=1` and `ALLOC_TRACK=0`, with identical before/after input hashes.
Signal source SHA-256 is
`adbdd587b060c6350c250afe5b608296393cca3c5f51d6800a9c424afcfcff43`.
Kernel SHA-256:

- AArch64: `a77b35189dbc6f805dc9d375e93980ca3e8f0ef6475cad7c7fbc49f79619582c`
- x86-64: `6650bd6a63e3dda5449421ac67c40bec4682a94b968c25e358aca1d0e22033d5`

Generated-C review compares 397 AArch64 and 436 x86-64 userland/table/timer
function bodies. Only rt_sigaction changes, with scalar masks. No function,
allocation or release is added. No lifetime or leak qualification is claimed.

The maintained suite adds sigactionflags to autodisarm, altstackclone,
altstackrestore, altstacknest, altstackframe, altstacksp, altstackhandler,
altstackabi, sigactionabi, sigactioncopy, sigmaskcopy, altstackcopy,
sigwaitorder, sigwaitcopy, sigpending, randomsignal, clonesignal, cloneclear,
seccomp, runtime, futex and jit. Controllers pin runner, fixture, compiler
and kernel inputs before and after each selected run. All 23 selected cases
pass on each architecture with unchanged controller inputs.

The complete bundle is
`/Users/alex/.cache/vinix-linux-compat/sigactionflags-20261026/evidence-final`.
Its manifest covers 18,819 artifacts with no omitted selected inputs;
manifest SHA-256 is
`69e0203b0c7f0b4d94e1426cc0b850c0f052ca208de98089f027b6ecdccb6ea5`.
It retains exact sources, production build receipts, generated C,
Linux/baseline/fixed runs, maintained suites, tools and selected input pins.
Identical bytes and modes use internal relative symlinks; the bundle has no
dependency on live input paths. Historical bundles remain unchanged.

Failed preparation attempts and the complete first x86-64 maintained attempt
are retained. That attempt passed 22/23 cases; randomsignal failed during
image creation with ENOSPC before boot. Earlier randomsignal/futex
intermittents remain unresolved.

The Linux reference parser passes two positive and 17 negative controls;
the evidence checker passes eleven positive and 190 negative controls.
Compile both V tools without `-prod` to preserve assertions:

```sh
v -o /external/sigactionflags-reference tests/linux-compat/sigactionflags-reference.v
/external/sigactionflags-reference --self-test
v -o /external/sigactionflags-evidence tests/linux-compat/sigactionflags-evidence.v
/external/sigactionflags-evidence self-test
/external/sigactionflags-evidence check /external/complete-bundle
```

The maintained fixture is
[`sigactionflagsfixture/core.v`](../tests/linux-compat/sigactionflagsfixture/core.v).
The [test runner](../tests/linux-compat/README.md) accepts `--cases sigactionflags`.
The bundle retains Linux v6.12 snapshots of
[`signal_types.h`](https://github.com/torvalds/linux/blob/v6.12/include/linux/signal_types.h),
[`signal-defs.h`](https://github.com/torvalds/linux/blob/v6.12/include/uapi/asm-generic/signal-defs.h),
the [AArch64](https://github.com/torvalds/linux/blob/v6.12/arch/arm64/include/uapi/asm/signal.h)
and [x86](https://github.com/torvalds/linux/blob/v6.12/arch/x86/include/uapi/asm/signal.h)
UAPI headers, and
[`kernel/signal.c`](https://github.com/torvalds/linux/blob/v6.12/kernel/signal.c).

This qualifies flag retention and raw ABI probing. Individual flag delivery
semantics, including child reaping and tagged fault addresses, require
separate tests. Full libc behavior, GNU libc, translated/32-bit execution,
installation, services, sandboxing and portals remain separate roadmap gates.
