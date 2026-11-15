# Native select wakeup filtering

Select and pselect6 now wait for a condition relevant to one of their requested
sets. A pipe hangup is a read condition; a pipe error is a read/write condition.
Neither satisfies an exception-only wait. The shared poll loop previously
returned on unconditional HUP/ERR, after which select returned zero immediately
even with a finite or absent timeout. This could make exception-monitoring loops
spin. Read/write controls retain their ready bits and return counts.

The poll loop now receives a scalar selecting flag and filters both its initial
scan and its post-registration rescans through the requested Linux select masks.
Raw poll/ppoll retain unconditional HUP/ERR. Descriptor validation, O_PATH handling,
generation-based waits, timers, signal masks and all references/cleanup retain
their existing ownership. No allocation or release is added. See the
[Linux 6.12 set masks and wait loop](https://github.com/torvalds/linux/blob/v6.12/fs/select.c#L428-L568).

The new V fixture uses real pipes: empty/queued readers after final writer close,
a writer after final reader close, and a quiet reader with a live writer. Low,
high and paired aliases cover three bitmap layouts. Raw pselect6 and musl
pselect/select run on both architectures, with raw select on x86-64, as root
and UID1000/GID2000 and with both SA_RESTART settings.

For unready exception-only waits, a sibling must observe the caller sleeping
twice across a five-millisecond pause before sending handled SIGUSR1. Finite
and indefinite waits must return EINTR with unchanged bitmaps, one handler,
correct live/restored masks and preserved timeout guards. Relevant read/write
controls return immediately with exact ready-bit counts and cleared exception
sets. Every case also preserves queued data/description flags and verifies that
raw ppoll still reports the same pipe HUP/ERR with only POLLPRI requested.

Identical musl ELFs pass 5,040 AArch64 and 6,720 x86-64 checks on Linux 6.12.51.
Original kernels fail 1,260 and 1,680 respectively, exactly seven assertions per
exception-only HUP/ERR case. Quiet waits and relevant-set/poll controls pass on
the originals. Corrected native kernels pass every check with those same ELFs.
Both credential cohorts retain all 18 ARM / 14 x86 slab classes flat, with
large pages 92/92 on ARM and 235/235 on x86-64 and zero writes after free.
Checker controls pass six positive and 1,192 negative cases. Complete
generated-C scope and independent lifetime/ABI review pass.
Registered selectwake, selectfds and pollcopy suites pass 3/3 per architecture,
including their full semantic and strict cleanup checks.

Both credential cohorts warm 64 cycles, then measure 200 cycles across all APIs
and ten profiles using stable pipe descriptions. The explicit positive-timeout
futex warmup initializes join-table capacity before qualification. Strict guards
require every slab class and large-page count to remain flat, with zero writes
after free. Explicit entry-frame State/Targets and synchronous stack slots
outlive signal handlers and joined observers. Independent lifetime/ABI review
also checks direct i32 atomics and the existing retained-resource wait lifetime.

Corrected production kernels build in isolated worktrees at
`1c078554a89bbfbd5b3eeeaaac4213a8396ab584`, with V 0.5.2 `7d74206`, PROD=true,
LIMINE_MP=1, ALLOC_TRACK=0 and link seed 42. Original kernels are the retained
poll-copyout builds from `4fbde3625b14eaf3d65c7ffba60d1bf6d86ae419` plus that
qualified copyout patch. Complete generated-C comparison permits only
poll_revents, ppoll, poll_user_fds and do_select bodies/prototypes, with unchanged
allocation, release, resource-status and copy operation counts.

Evidence is retained at `/Users/alex/.cache/vx-sw-1115/bundle`. Its 543-file
manifest has SHA-256
`b5f28863b0bdb2e4f7e354d061aaa730ea96375e7895aefe53f16e3fc162ae36`.
Initial V/C fixture compilation refusals and the first audit's overly broad
call-count refusal are preserved.
`selectwake-evidence.v BUNDLE` checks the complete inventory, source/C/ELF pins,
baseline failures, Linux/native results, storage, review and registered suites.
The complete 543-file audit passes.
Its self-test, serial and scope modes expose individual checks; build without
`-prod`. `selectwake-reference.v` boots the same native probe and recorded
launcher on a supplied Linux kernel. Fresh native runs select `--cases selectwake`
with `tests/linux-compat/run`, a matching built kernel and fresh external state.
Both fixture sources are frozen and its default guest budget is 600 seconds.

This qualifies the listed native musl pipe states. Norm/band-only readiness
producers, TCP/OOB, concurrent close/replacement or readiness transitions,
resource pressure, cancellation, and GNU/foreign/32-bit paths remain separate.
Broader section 15 installation, integration and translated-runtime gates remain
open; unrelated historical memory deltas are not resolved by this change.
