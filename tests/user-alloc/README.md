`verify.c` exercises the allocator in the actual default libc, including dirty
mapping reuse through `calloc`, resize and aligned allocation, cache bounds,
trimming with live allocations, cross-thread frees, and allocation and trim
after a multithreaded `fork`. Child processes also verify that double frees
and nominal-size overruns are rejected.

Allocation framing skips offset cycling when a slot has no whole alignment
unit to spare, because the selected offset is always zero. Slots with spare
units keep musl's offset cycling. Header stamping uses the selected slot
index directly; resize keeps the existing header index. Group, secret,
nominal-size and overflow-byte checks stay in both paths.

Ordinary single-thread allocations can consume an available slot, or refill
the sole active group from already active freed slots, before entering the
mapping and locking path. This requires both the thread state and the actual
malloc lock to be clear. Other states use musl's existing allocation path.
Freeing shares the slot index and stride obtained during metadata validation;
the original header, secret, bounds, live-slot and nominal-size checks remain.

Compile with the guest's native GCC and run both link modes:

```sh
gcc -std=c11 -O2 -Wall -Wextra -Werror -fno-builtin -pthread verify.c -o verify
gcc -std=c11 -O2 -Wall -Wextra -Werror -fno-builtin -pthread -static verify.c -o verify-static
./verify
./verify-static
```

A pass prints `UALLOC-DONE`. `UALLOC-FOOTPRINT` includes the sum of mappings
before reuse, after reuse and after trim; the check allows 12 MiB of retention
and requires trimming to return within 128 KiB of the warmed baseline. The
direct cache itself permits at most 3968 KiB of free direct mappings. Retained
ordinary groups have at most 6 MiB of their own storage; counting nested
parents gives a conservative 12 MiB ordinary backing bound on 16 KiB ARM
pages, or less than 16 MiB including the direct cache. The 12 MiB test limit
is for the observed finite workload, rather than this maximum envelope. Run this test with both
`VINIX_MUSL_RETAIN=1` and `=0` versions of the same libc recipe.

`clock.c` checks the precise clock against the architectural counter during
sleep and a syscall-heavy interval. It also checks coarse snapshots, absolute
monotonic and realtime timerfds, absolute sleep, and absolute futex timeout.
Compile with `gcc -std=c11 -O2 -Wall -Wextra -Werror -fno-builtin clock.c -o clock`
and run in the guest; a pass prints `CLOCK-DONE`. This test requires the
corrected counter-based clock before allocation timings are meaningful.

`verify-all-classes.c` adds bursts at all 48 ordinary class boundaries, trimming
while allocations stay live, dirty reuse followed by `calloc`, and repeated
thread creation and teardown with allocations transferred between threads.
It also repeatedly exhausts and refills warmed groups while retaining a live
allocation, and allocates, resizes and trims inside all three public atfork
callbacks with a concurrent worker and again after that worker exits.
Run it against each staged allocator alongside `verify.c`, with both linkage
modes. A pass prints `UALLOC-SUPPLEMENT-DONE`:

```sh
gcc -std=c11 -O2 -Wall -Wextra -Werror -fno-builtin -pthread verify-all-classes.c -o verify-all-classes
./verify-all-classes
gcc -std=c11 -O2 -Wall -Wextra -Werror -fno-builtin -pthread -static verify-all-classes.c -o verify-all-classes-static
./verify-all-classes-static
```

The final v6 runtime validation passed on x86_64 with musl 1.2.5 and AArch64
with musl 1.2.6. Each architecture ran both suites with retention enabled
and disabled, using dynamic and static linkage: eight combinations, each
reporting 1,910 original checks and 30,942 supplemental checks, for 262,816
reported checks in total. All 32 corruption children terminated with the
expected signals, and `clock.c` passed on both architectures.

The enabled runs retained 3,575,808 and 3,584,000 bytes on x86_64, and
3,653,632 and 3,751,936 bytes on AArch64 (dynamic and static respectively).
Every one of the eight footprint measurements returned exactly to its warmed
mapping baseline after trim. These are finite-workload correctness and mapping
measurements; they do not establish the worst-case retention bound or a
performance result. The refill and atfork tests exercise public behavior;
they do not instrument which internal allocation branch each call takes.
