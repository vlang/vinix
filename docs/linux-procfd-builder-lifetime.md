# Anonymous procfs descriptor-text builder lifetime

Refreshing `/proc/<pid>/fd` no longer retains one heap-allocated Text header for
each anonymous descriptor it formats. `anonymous_descriptor_text` consumes its
builder through the existing `lib.finish_text(text)` value helper. Generated C
now keeps the header on the stack; the returned string still owns independent
bytes, and the builder buffer is freed exactly once by the unchanged helper.
Link publication, clones, temporary-string cleanup, lookup locks and resource
references are unchanged.

The earlier [epoll registration qualification](linux-epoll-registration-key.md)
retained a full-churn failure: each credential cohort gained 7,200 size-48 slab
objects over 200 cycles. An isolated ALLOC_TRACK=1 AArch64 reproduction records
exactly 7,200 live 48-byte allocations, with zero dropped groups, at
`anonymous_descriptor_text <- refresh_fd_directory <- procfs_lookup_refresh_locked`
through the ordinary openat lookup. Six procfs reopens per cycle each format
six anonymous descriptors: 200 * 6 * 6 = 7,200 leaked headers, or 345,600 bytes.
Generated C identifies the exact `memdup(sizeof(lib__Text))` escape introduced
by the mutable `str()` receiver. The fixed complete C differs only in that
function: stack storage, synchronous address arguments and the value-consuming
finish call. One positive and eight negative scope controls and independent
lifetime review pass. No new deferred-free or owner lifetime is introduced.

The maintained full-churn fixture retains all 5,760 raw/musl epoll semantic
checks per architecture, across descriptor reuse, duplicates, same-inode reopen,
ADD/MOD/DEL, event tags, guards, queue counts and flags. Its memory cycle creates,
reopens, registers, modifies, deletes and closes fresh endpoints and sets. Each
root and UID1000/GID2000 cohort warms 64 cycles, measures 200 and waits 13 seconds
on each snapshot. Matching original kernels gain exactly 7,200 size-48 objects
per cohort while every other class, large pages and write-after-free counter
stay flat. Corrected native kernels and identical Linux ELFs pass every semantic
check; corrected native storage is flat in all 18 ARM / 14 x86 slab classes,
large pages 81/81 on ARM and 218/218 on x86-64, with zero writes after free.
The strict parser has six positive and 928 negative controls; its baseline mode
requires the exact old growth and rejects other storage changes. Original
historical checkers and complete bundles remain unchanged.

The epollchurn, epollkey and pipeready registered suites pass 3/3 on each
architecture. Both production kernels were built in isolated worktrees from
`cab44e91988c37aae1bab7af0fe7183dcd5ddd8a`, with V 0.5.2 `7d74206`, PROD=true,
LIMINE_MP=1, ALLOC_TRACK=0 and link seed 42; the attribution kernel enables only
ALLOC_TRACK in addition. Linux reference kernels remain pinned at 6.12.51.
An initial tracking run reached the root attribution but refused UID1000's
tracker reset with EACCES. The final optional tracker is root-only, while every
credential's slab/storage checks remain identical. The complete successful
tracking reproduction and the initial refusal are both retained.

Broader repository checks were attempted and remain separate from this focused
qualification. The unchanged allocation allowance scan compiles both
architectures but still rejects inherited excess groups. The performance
console's poll declaration now uses the host nfds_t width, matching its monitor
and command helpers, so both native staging adapters compile. ARM's 18 and
x86's 37 host self-checks pass, as do the native runner fixtures, including
100 PTY owners with flat descriptors. The larger host report suite still refuses
its existing strtod declaration/map-initializer issues. ARM six-scenario staging with both
`7d74206` and the frozen current `cbfc1be` compiler refuses generated initializer
C: `%.*s` receives a V i64 precision under the retained `-Werror=format` check.
The selected cached x86 runtime is refused because `/usr/bin/curl` is absent.
Thus broader ops/churn/cache and idle/apps/drag guest qualification remains
blocked before boot; no guest pass is claimed and no assertion, warning guard
or input requirement is relaxed. All partial stages and compiler logs remain
retained.

`tests/linux-compat/run --cases epollchurn` freezes both fixture sources and has
a 600-second default budget. `epollchurn-reference.v` runs the same ELF on a
supplied Linux kernel; `epollchurn-evidence.v` checks the complete bundle,
source/C/ELF identity, exact original growth, trace, fixed/reference results,
cleanup, registered suites and review. Build the evidence tool without `-prod`.

Complete evidence is retained at `/Users/alex/.cache/vx-ec-1115/bundle-r1`:
704 files, manifest SHA-256
`83d328f3a725458bfa5a31c49a19a27c796e7166529772d313c4773e820680d2`.
Partial performance stages and self-check trees, including guest symlinks, are
preserved in hashed tar artifacts; their original directories remain intact.
The initial seal remains at `/Users/alex/.cache/vx-ec-1115/bundle`, manifest
SHA-256 `1bad8d842d0549f05b84794cc1ad0c6941a88fc99e965992de8f9c368c4f4ec0`.
Its audit consulted a truncated wrapper error and refused the broader-check
record. The new seal pins the full compiler log already retained in the stage;
it preserves the exact error requirement and the first audit refusal.
The complete final sealed-bundle audit passes.

This resolves the recorded full-churn size-48 growth for the listed workload.
Concurrent procfs refresh/exit, pressure, other anonymous descriptor classes,
GNU/foreign/32-bit paths and broad application installation/integration remain
unqualified. The earlier reports retain their historical observations; broader
section 15 acceptance gates remain open.
