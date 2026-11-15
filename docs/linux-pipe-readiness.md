# Native anonymous-pipe readiness

Anonymous pipes now report readiness for the open description's access mode.
Readers report IN/RDNORM only when bytes are queued and HUP after the final
writer closes. Writers report OUT/WRNORM when capacity is available and ERR
after the final reader closes, including OUT with ERR on an empty broken pipe.
Previously both ends exposed one shared status word, allowing readers to appear
writable and writers readable while omitting normal readiness bits.

The existing borrowed readiness callback receives an access-mode scalar from
the retained handle. The pipe callback reads queue/capacity/peer counts under
its existing lock. Eight existing backends accept and ignore that argument;
their bodies are unchanged. Epoll forwards requested normal/band/priority bits
alongside IN/OUT/RDHUP and unconditional ERR/HUP. ET/oneshot bookkeeping and
all allocation, reference, wait and release paths retain their ownership.
See [Linux 6.12 pipe_poll](https://github.com/torvalds/linux/blob/v6.12/fs/pipe.c#L609-L656).

The V fixture covers ten anonymous-pipe descriptions: both ends of empty,
queued and full pipes, empty/queued readers without writers and empty/full
writers without readers. Original, high and paired aliases exercise sixteen
poll/epoll masks and all seven select set combinations. Root and UID1000/GID2000
run raw ppoll, musl ppoll/poll, raw pselect6, musl pselect/select, level-triggered
epoll and the additional raw x86-64 poll/select entries. Checks include exact
return/errno, result masks/counts, fd/event fields, bitmap and output guards,
epoll tags independent of order, queued-byte counts and access/nonblocking flags.
ARM epoll padding bytes are not asserted; surrounding and unused output bytes
are guarded.

Final identical musl ELFs pass 24,180 AArch64 and 30,960 x86-64 checks on Linux
6.12.51 and corrected native kernels. Matching original kernels fail exactly
2,616 and 3,342 checks. Both 200-cycle credential cohorts keep all 18 ARM / 14
x86 slab classes flat, large pages 89/89 on ARM and 230/230 on x86-64, with zero
writes after free. Each cohort warms 64 cycles, then repeats poll/select/epoll
across every endpoint class using stable descriptions and explicit stack slots.
Parser controls pass six positive and 2,272 negative cases. Generated-C
comparison controls pass two positive and nine negative cases; complete scope
and independent lifetime/ABI review are recorded below.
The final registered pipeready, selectwake and pollcopy suites pass 3/3 on each
architecture. The pressure policy/subscription host tests pass both test files
after their direct readiness calls are updated for the scalar access argument.

An initial Linux comparison failed 432 ARM / 552 x86 assertions because a
one-slot pipe with one byte has no free buffer slot, although a later write
may merge into that page. The final queued-state fixture requests 8 KiB,
leaving a free slot on the pinned 4 KiB Linux kernels. Native ARM rounds that
request to its 16 KiB page size; full states write the entire observed capacity
in one operation. The mask oracle is unchanged. Single-slot/merge-specific
fullness remains unqualified, and the initial failed comparisons are retained.

The first native candidate omitted epoll normal-bit forwarding and retains 168
failures per architecture. Matching baselines and final candidates are rebuilt
from `b8a310c0a6435f2adffad7bf25df7d03256b6fda` in separate worktrees, with
V 0.5.2 `7d74206`, PROD=true, LIMINE_MP=1, ALLOC_TRACK=0 and link seed 42.
Earlier experiments using older select-wakeup kernels remain separate; their
unrelated committed kernel differences do not enter the final C comparison.

The scope auditor compares complete generated C, consistently alpha-renaming
compiler-owned ignored-local identifiers while preserving distinct bindings
and uses. Controls reject changed constants, merged bindings and changed uses.
Only the new pipe callback/prototype, scalar callback ABI/dispatch/call sites,
epoll mask forwarding and the compiler's Pipe type-test expansion are permitted.
Existing backend callback bodies must remain identical, and allocation/release/
resource-status/copy operation counts remain unchanged. Strings, character
literals and comments are preserved byte for byte. The new callback makes
no allocation or free. Historical auditors retain their original contracts.

Complete evidence is retained at `/Users/alex/.cache/vx-pd-1115/bundle`: 936 files,
manifest SHA-256 `8c6a097a25055effacdc64b4a3ac82e77cf95ccf640d9b10eaef08f28c884c82`.
The complete sealed-bundle audit passes. Failed fixture compilation, initial
Linux/native refusals, unmatched early baselines and incomplete first registered
attempts remain retained. `pipeready-evidence.v BUNDLE` verifies the entire
inventory, source/C/ELF identity, matching baseline failures, final native/Linux
results, storage, review and registered suites. Its self-test, serial and scope
modes expose individual checks; build without `-prod`. Fresh runs select
`tests/linux-compat/run --cases pipeready`, which freezes both fixture sources
and gives the case a 600-second default budget. `pipeready-reference.v` runs
the same ELF and its recorded launcher on a supplied Linux kernel.
The first two pressure-host attempts lacked the frozen compiler's test reporter
sources; those setup refusals and the successful complete host module tree are
retained separately.

Named FIFO readiness stays on its existing path: per-open writer-generation
accounting is separate. Linux pipe-buffer slot/merge rules beyond the listed
states, partial draining, readiness transitions/concurrent closure, ET/oneshot
transitions, pressure and GNU/foreign/32-bit paths remain unqualified. Broader
section 15 installation/integration/runtime gates and historical memory issues
remain open.
