# Native process-wide one-shot signal handlers

Native Linux signal delivery now consumes SA_RESETHAND before entering the
handler and resets the disposition across all threads in the process.
rt_sigaction queries and updates use the same process lock. Resetting the
handler preserves its flags, mask and restorer, including SA_RESETHAND itself.
A sibling can install a replacement while the original handler is active;
returning from that handler preserves the replacement.

The probe runs 24 combinations: root or UID 1000/GID 2000, SIGUSR1/SIGUSR2/
SIGWINCH, and persistent, one-shot, one-shot with SA_NODEFER/SA_RESTART, or
one-shot with replacement by a sibling. It checks handler-entry metadata and
masks, a sibling created before installation, queries after return, a new
thread, fork inheritance, fatal/ignored defaults and SIG_IGN preservation.

| Execution | AArch64 checks / failures | x86-64 checks / failures |
| --- | --- | --- |
| Linux 6.12.51 reference | 420 / 0 | 420 / 0 |
| Original production kernel | 420 / 84 | 420 / 30 |
| Corrected production kernel | 420 / 0 | 420 / 0 |

Each architecture runs the identical static musl probe ELF on all three
kernels. Vinix AArch64 uses four virtual CPUs; Vinix x86-64 and both Linux
references use two. Vinix AArch64 uses 16 KiB pages; x86-64 and the Linux
references use 4 KiB pages. Pipe handshakes make the sibling queries
and replacement deterministic. The evidence checker verifies every case and
the original failure stages, rather than accepting a final PASS alone.

The isolated candidate is `8529354bc41c85e93958d4c1e9c0213e55d82b13`, based on
`8d81434c3484da21d23f08f4217d5b2e45c2a428`. Both production builds use seed 42,
`MP=1` and `ALLOC_TRACK=0`, with unchanged before/after input hashes.

| Source | SHA-256 |
| --- | --- |
| kernel/userland/signal.v | `411d614c7cd3614daa388aa25a2b8f03db51d7a2ebdba31b643ada40f650db3e` |
| kernel/userland/linux_signal_amd64.v | `537a36b46d4599dfed1e99df52ac7b9f502ff8812138d877a45e8c5288473196` |
| kernel/userland/userland_arm64.v | `5029f835e3266e1b4e1d0e3832a661d4a8af1959e7d8697d0375a7d4e8a6f3f8` |

Kernel SHA-256:

- AArch64: `2ab35c47e0ffa69bb14a20aa98fb8c76f59d36c996c5c49650a4f9e53c535b6c`
- x86-64: `b12ae783dc235a720eba83b26b10c7104da622c7a569fd6fe70890657656057c`

Generated-C review compares 397 AArch64 and 436 x86-64 existing userland,
table and timer function bodies. Only rt_sigaction and native dispatch change;
the added action-selection helper adds no allocations or frees. The unrelated
find_reaper body is identical after normalizing V's generated numeric loop
index. The lock is released before user-memory access and handler entry.
This is a lifetime review, without a leak qualification claim.

The maintained suite selects resethand, sigactionflags, autodisarm,
altstackclone, altstackrestore, altstacknest, altstackframe, altstacksp,
altstackhandler, altstackabi, sigactionabi, sigactioncopy, sigmaskcopy,
altstackcopy, sigwaitorder, sigwaitcopy, sigpending, randomsignal,
clonesignal, cloneclear, seccomp, runtime, futex and jit. Controllers pin
compiler, runner, fixture and kernel inputs before and after execution.
All 24 selected maintained suites pass on each architecture.

The complete audit bundle contains 19,411 artifacts, with no omitted selected
input pins, at
`/Users/alex/.cache/vinix-linux-compat/resethand-20261026/evidence-final`.
Its `manifest.json` records hashes, modes and original artifact locations;
SHA-256: `29402ca05d341d1f2f2e1e0abab1420858c58292badc591cf71dc46134872ec0`.
The committed evidence checker accepts the complete bundle.

Failed preparation and maintained-suite attempts remain in the complete
bundle. Initial maintained attempts exhausted host disk space before some
boots; two AArch64 retries rejected a compiler-wrapper destination mismatch.
Copy-on-write consolidation and identical-content hard links reclaimed space
without changing retained bytes or modes. Failed consolidation attempts are
also retained. Earlier randomsignal/futex intermittents remain unresolved.

The Linux reference parser passes two positive and 35 negative controls;
the evidence checker passes eleven positive and 429 negative controls.
Compile both V tools without `-prod` to preserve assertions:

```sh
v -o /external/resethand-reference tests/linux-compat/resethand-reference.v
/external/resethand-reference --self-test
v -o /external/resethand-evidence tests/linux-compat/resethand-evidence.v
/external/resethand-evidence self-test
/external/resethand-evidence check /external/complete-bundle
```

The maintained fixture is
[`resethandfixture/core.v`](../tests/linux-compat/resethandfixture/core.v).
The [runner](../tests/linux-compat/README.md) accepts `--cases resethand`.
The bundle retains the Linux v6.12 signal UAPI headers and kernel/signal.c
reference snapshots used by the preceding flag-probing qualification.

This qualifies native Linux one-shot disposition consumption. Legacy mlibc
signal entry retains its existing ABI. Simultaneous delivery storms, handler
frame faults, GNU libc, translated/32-bit execution and complete libc behavior
require separate qualification. Installation, services, sandboxing and portals
remain separate roadmap gates.
