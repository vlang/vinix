# Native ppoll remaining timeout

Raw ppoll now records a saturating monotonic deadline when it imports a valid
timeout and returns the remaining duration after core polling. Expiry writes
zero; count and poll-array errors also finish the timeout. Timeout/mask import
or validation errors leave it untouched. A refused timeout copyout preserves
the completed syscall's return value and errno. Libc ppoll preserves its input
by passing the kernel a private copy.

This follows [Linux v6.12's ppoll entrypoint and timeout finishing](https://github.com/torvalds/linux/blob/v6.12/fs/select.c#L1031).
The kernel reuses the existing select deadline, subtraction and copyout helpers,
and adjusts the internal relative duration immediately before polling.
Finishing runs after existing poll-array and scratch cleanup, before syscall
exit can deliver a signal. This qualification does not cover signal interruption.

Both architectures run identical newly compiled static musl ELFs on original
Vinix, corrected Vinix and Linux 6.12.51:

| Architecture | Checks | Original failures | Corrected failures | Linux failures |
| --- | ---: | ---: | ---: | ---: |
| AArch64 | 360 | 10 | 0 | 0 |
| x86-64 | 360 | 10 | 0 | 0 |

Root and UID1000/GID2000 cover raw/libc ppoll, normal ready timeouts, expiry,
huge durations, invalid counts, inaccessible arrays, read-only poll output,
and invalid mask size/pointer precedence. Read-only timeouts preserve the call's
result and original contents. Six checks per call verify exact return/errno,
full guarded poll output, guarded timeout contents, restored signal mask and
queued socket data. Normal remainders obey canonical/enclosing clock bounds;
huge outputs obey signed64 saturation bounds. The strict parser passes six
positive and 712 negative controls.

Each native cohort warms 64 matrix cycles and measures 200 cycles. Every live
slab class stays flat and allocator taint remains 0/0. Original and corrected
AArch64 large pages stay 83/83 for root and 85/85 for UID1000; x86-64 stays
222/222 for both cohorts. Linux explicitly skips Vinix storage checks.

Corrected production kernels build in isolated worktrees from
`a1ce88ddf7e9093bd52d0c098aebfec16e953bc2` plus the retained file.v change,
using V 0.5.2 `7d74206`, PROD=true, LIMINE_MP=1, ALLOC_TRACK=0 and link seed 42.
Original kernels reuse the preceding poll-count qualification's corrected
builds, whose kernel sources match this base. After canonicalizing ignored
loop-variable path hashes, generated C differs only in the ppoll entrypoint.
Its deadline is a plain stack value and existing timeout storage is reused;
allocation, reservation and release counts remain unchanged. Independent
lifetime/arithmetic review passes for both kernel and fixture C outputs.

Fresh registered ppolltime, ppollargs and selecttimeout regressions pass on
both corrected kernels. The runner freezes all three ppolltime fixture sources.
Use `run.v --cases ppolltime` with an isolated kernel and fresh external state.
`ppolltime-reference.v` runs the same ELF on Linux; `--self-test` checks the
parser. Build `ppolltime-evidence.v` without `-prod` and pass the complete
external bundle to audit artifact inventory, reviewed source identities,
same-ELF comparisons, original failures, generated-C scope and flat cleanup.

Evidence: `/Users/alex/.cache/vx-pt-1114/bundle`. Its 440-file manifest has SHA-256
`dad3631667eef62b444604baeea6801f8cd3abac7be70214fec68131bca4938b`.

EINTR/handler-visible output, pending signals and restart behavior, resource
pressure, partial copies, aliases and concurrent mutation, personality flags,
GNU/foreign/32-bit ABIs remain separate. Broader §15 semantics, application
installation/integration and translated-runtime acceptance gates remain open.
