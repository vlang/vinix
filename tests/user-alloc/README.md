`verify.c` exercises the allocator in the actual default libc, including dirty
mapping reuse through `calloc`, resize and aligned allocation, cache bounds,
trimming with live allocations, cross-thread frees, and allocation and trim
after a multithreaded `fork`. Child processes also verify that double frees
and nominal-size overruns are rejected.

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
