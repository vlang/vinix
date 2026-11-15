# Native epoll registration identity

Epoll registrations now match both the descriptor number used for registration
and the retained open-file description. Closing that number while a duplicate
keeps the old description alive, then reusing the number, no longer makes ADD
return EEXIST or lets MOD/DEL alter the old watch. Two registrations can share a
number while referring to different descriptions. A separately reopened pipe
has its own description even when its underlying pipe inode is the same.
Linux uses the same pair in [eventpoll's lookup key](https://github.com/torvalds/linux/blob/v6.12/fs/eventpoll.c#L349-L362).

The change adds an explicit address comparison to the three existing lookup
predicates. Both addresses are retained by the existing watch and descriptor
lookup while the epoll lock protects its list. No new reference, allocation,
release, callback or lock is introduced. Complete generated C must be identical
except for those three predicates. An initial typed-pointer expression caused
V to emit structural equality; the final explicit voidptr comparisons emit only
C address equality. The initial build and runs remain retained.

The maintained V fixture covers raw and musl epoll_ctl as root and
UID1000/GID2000, ADD/MOD/DEL, two high descriptor layouts, all four combinations
of queued/empty pipes, and four identity cases: a different pipe at a reused
number, the original description restored to the number, another-number alias,
and a separately reopened description of the same pipe. Checks include exact
return/errno, repeated level-triggered event sets and unique tags independent
of order, event fields, output guards/unused records, queue lengths, flags,
MOD/DEL selection when two watches share a number, and removal after the last
original description closes. ARM epoll padding is unasserted; surrounding bytes
and unused records are guarded.

The final identical musl ELFs pass all 5,760 checks on both corrected native
kernels and Linux. Matching original kernels fail exactly 840 checks each.
Both 200-cycle credential cohorts keep all 18 ARM / 14 x86 slab classes flat,
large pages 91/91 (root) and 93/93 (UID1000) on ARM and 252/252 on x86, with
zero writes after free. This storage qualification covers the stable-description
operations described below. The registered epollkey, pipeready and selectwake
suites pass 3/3 on each architecture. Baselines and candidates are built in isolated
worktrees at `4a0c5476ca0185599148f631192d4054e5956865`, with V 0.5.2 `7d74206`,
PROD=true, LIMINE_MP=1, ALLOC_TRACK=0 and link seed 42. The pinned Linux kernels
are 6.12.51. The strict parser has six positive and 928 negative controls;
generated-C scope has one positive and eight negative controls. Historical
checkers and evidence bundles retain their original contracts.

The first full-churn fixture grows size-48 objects by 7,200 over 200 cycles
in both credential cohorts, on both original kernels and the first candidate.
Those complete failures, generated C and exact source snapshots remain
retained. The growth is not attributed or fixed here. The final cleanup guard
holds its pipe descriptions, reopened description and epoll set stable; after
64 warmup cycles it measures 200 cycles of descriptor replacement and watch
ADD/MOD/DEL, with strict checks for every slab class, large pages and writes
after free. Semantic probes still create, reopen and close fresh descriptions.
This separates registration cleanup from the unresolved full-churn growth;
it does not qualify full endpoint/procfs-open churn as leak-free.

`tests/linux-compat/run --cases epollkey` freezes both fixture sources and gives
the case a 600-second default budget. `epollkey-reference.v` runs its identical
musl ELF and recorded launcher on a supplied Linux kernel. Build
`epollkey-evidence.v` without `-prod`; its bundle, serial, scope and self-test
modes check complete inventory, source/C/ELF identity, original refusals,
corrected/Linux results, cleanup and registered regressions. The first fixture
compilation failures and ARM image-assembly disk-full refusal remain retained.
An additional x86 registered replay was stopped once the complete primary
cohort passed; its partial artifacts are retained without a passing claim.

Complete evidence is retained at `/Users/alex/.cache/vx-ek-1115/bundle`: 812 files,
manifest SHA-256 `bd62b318d024217bd533aa6358473d4f18f3b5d3119d48db659ac47cc2d0ed95`.
The complete sealed-bundle audit passes.

Concurrent close/reuse, nested epoll, fairness, ET/oneshot transitions, pressure,
GNU/foreign/32-bit paths and application installation/integration remain
unqualified. The broader section 15 gates and historical memory issues remain
open.

The subsequent [builder-lifetime qualification](linux-procfd-builder-lifetime.md)
attributes and removes the recorded full-churn size-48 growth. Its new complete
runs do not change the historical failed measurements or bundle above.
