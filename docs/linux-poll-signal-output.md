# Native interrupted poll output

Poll and ppoll now publish the final poll-array contents when a handled signal
interrupts a wait. Previously, their shared helper returned EINTR before
copying the cleared revents fields to userspace. Successful copyout preserves
EINTR; the existing refused-copyout path still returns EFAULT. This follows
[Linux v6.12 do_sys_poll](https://github.com/torvalds/linux/blob/v6.12/fs/select.c#L949).
The change adds no allocation, retained reference or release operation.

The same newly compiled static musl ELF runs 672 checks per architecture on
original Vinix, corrected Vinix and Linux 6.12.51. Original kernels fail twenty
poll-output checks each; corrected kernels and Linux pass every semantic check.
Root and UID1000/GID2000 cover raw ppoll, libc ppoll and libc poll, pending
signals and observed empty/nonempty waits, read-only timeouts and SA_RESTART
on/off. Libc poll controls use observed waits with SIGUSR1 already unblocked;
pending-signal tests use ppoll's atomic temporary mask.

Each call checks exact EINTR, complete guarded poll output, timeout guards and
remaining-time bounds, restored masks, unchanged queued socket data, one handler
invocation, the handler's mask and timeout view, observer delivery and consumed
pending signals. Raw writable ppoll publishes remaining time before the handler;
libc and read-only inputs remain unchanged. SA_RESTART still produces EINTR.
An observer first sees the main thread sleeping, then waits five milliseconds
and verifies at least one millisecond of monotonic advance before sending the
signal. Only these observed raw waits require strict timeout decrease; pending
calls permit coincident samples. Observers join before shared State reuse.
The strict parser passes six positive and 1,104 negative controls, including
exact baseline diagnostic kinds/counts and allocator evidence refusals.

The corrected production kernels build in isolated worktrees from
`e1b1b8e5eb62143ea1ce41bbbc0e6762fce951e5` plus the retained file.v change,
using V 0.5.2 `7d74206`, PROD=true, LIMINE_MP=1, ALLOC_TRACK=0 and link seed 42.
The original kernels reuse the preceding ppoll timeout qualification's builds.
After canonicalizing ignored-loop path hashes, generated C differs only in
poll_user_fds. Independent lifetime/arithmetic review passes for both kernel C
outputs and the final fixture C. The syscall owns the poll array through this
synchronous copyout, then performs its existing array/budget cleanup.

Each cohort warms 64 complete matrix cycles and measures 200, including thread
creation, interrupted waits and joins. Passing final replays retain every live
slab class, large pages at 89/89 on AArch64 and 222/222 on x86-64, and taint 0/0.
An earlier corrected AArch64 root cohort retained two size-64 objects and one
size-192 object; an earlier baseline probe also grew those classes. The exact
corrected ELF replay and registered run retain flat cohorts. The earlier strict
guard refusal remains audited; its cause is unqualified, and passing replays do
not establish why it happened. The broader memory gate remains open.

Initial Linux runs refused sixteen checks because the first fixture incorrectly
expected unchanged poll arrays after EINTR. The corrected expectation exposed
the Vinix bug. Initial sources, ELFs and refusals remain preserved. Two x86-64
native runs exceeded the old 240-second controller budget before completing;
the same ELFs are replayed with the versioned ppollsignal-host controller's
600-second budget. Their incomplete receipts remain failures.

Fresh registered ppollsignal, ppolltime and ppollargs pass on both corrected
kernels. `run.v --cases ppollsignal` freezes all three fixture inputs and uses
a 600-second budget. `ppollsignal-reference.v` runs the identical ELF on Linux
and provides `--self-test`. Build `ppollsignal-evidence.v` without `-prod` and
supply the complete external bundle to audit inventories, reviewed identities,
source/ELF pins, original failures, generated-C scope, cleanup and regressions,
while retaining initial Linux refusals, memory-guard refusal and native timeouts.

Evidence: `/Users/alex/.cache/vx-ps-1114/bundle`. Its 785-file manifest has SHA-256
`f2721913f472189a9e1a84e72d9ecdebde97acaa0e516ce3c1298645b08c101e`.

Read-only poll-array faults during signal delivery, partial copies, concurrent
mutation/aliases, cancellation, pressure and GNU/foreign/32-bit ABIs remain
separate. Broader §15 semantics, application installation/integration and
translated-runtime acceptance gates remain open.
