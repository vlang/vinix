# Native timed-wait pending-signal ordering

Vinix rt_sigtimedwait now selects thread-directed signals before process-wide
signals. Within either pending set, synchronous signal numbers 4, 5, 7, 8, 11
and 31 take priority; the lowest number wins within each class. This follows
next_signal and dequeue_signal in
[Linux v6.12 kernel/signal.c](https://github.com/torvalds/linux/blob/v6.12/kernel/signal.c).

Identical static musl ELF64 probes run as root and UID 1000/GID 2000. Each
cohort checks 240 ordered pairs drawn from 16 signal numbers across four
thread/shared pool combinations. Filtered wanted sets, the same signal
independently pending in both pools, blocked bystanders, preserved masks,
unaligned/null siginfo output, surrounding bytes and empty-wait EAGAIN are
covered. Synchronous signal numbers are generated with kill/tgkill; these
checks do not deliver real hardware faults.

| Result on each architecture | Checks | Failures |
| --- | ---: | ---: |
| Linux 6.12.51 reference | 27,968 | 0 |
| Original Vinix production kernel | 27,968 | 4,160 |
| Corrected Vinix production kernel | 27,968 | 0 |

Native AArch64 uses 16 KiB pages. Native x86-64 and both Linux references use
4 KiB pages. Both production builds pass with unchanged before/after source
inventories. The maintained set is sigwaitorder, sigwaitcopy, sigpending,
randomsignal, clonesignal, cloneclear, seccomp, runtime, futex and jit.

All ten maintained suites pass per architecture.

The first x86-64 maintained attempt passed nine cases and timed out in
cloneclear at 900 seconds. The complete retry used a 3600-second per-case
limit and passed all ten cases. Both attempts and their inputs are retained.

The complete external audit passes. The bundle at
`/Users/alex/.cache/vinix-linux-compat/sigwaitorder-20261025/evidence-final`
retains 18662 files with zero omitted selected inputs. Its manifest
SHA-256 is `00ce2950c9e0285dd179dddc00c86b46d78ccae5585699d0cbbb0eba98098553`.
Historical complete bundles remain available at their original locations.

The isolated candidate is `39f1785dfece264c5ad209836ac46f1118472efd`, based on
`9e74d4592be58055c47f2a31a3fa1c64b13b1d5b`. Only signal.v changes, with SHA-256
`f54031b6cbbeebf4b93c8a6d5829f2645c0c2b9cd42db46fa023cffd290c4ab3`.

| Production kernel | SHA-256 |
| --- | --- |
| AArch64 | `a7cae4965253f7cb48e658abc47464ab0deea22659c1adc649adbaa99f537d63` |
| x86-64 | `6e7f398f074928ffcac08cbfe9f250dcd3be2eb00e945f245d437f75d3af2699` |

Generated C review compares 395 AArch64 and 434 x86-64 userland, syscall-table
and timer bodies. Only take_wait_signal changes and take_pending_wait_signal
is added. The new bodies use stack scalars and atomic load/bit claim. Timed
wait, timer acknowledgement, signal copy, usercopy, mapping and exit bodies
are unchanged. No allocation, release or new object lifetime is introduced.
This scope review does not claim a measured allocation-leak qualification.

Concurrent delivery/dequeue races, queued payload depth and provenance, real
fault delivery, GNU libc, translated/ELF32 applications and installation,
service, sandbox and portal acceptance remain separate qualifications. Three
broad section 15 gates remain open.

Initial private fixture compilation attempts failed on a reserved identifier
and cached-compiler fixed-array indexing. The corrected third compilation is
used unchanged by original, corrected and Linux runs. Diagnostic attempts and
their frozen inputs are preserved. Historical complete bundles remain required
by their original checkers.

Compile checkers without `-prod` to preserve assertions:

```sh
v run tests/linux-compat/sigwaitorder-reference.v --self-test
v run tests/linux-compat/sigwaitorder-evidence.v self-test
v run tests/linux-compat/sigwaitorder-evidence.v check /Users/alex/.cache/vinix-linux-compat/sigwaitorder-20261025/evidence-final
```

The reference parser passes two positive and rejects nine negative controls.
The evidence checker passes five positive and rejects 23 negative controls.
