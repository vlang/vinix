# Vinix allocation runner host policy

`run-vinix.py` keeps its public CLI and calls `vinixcore` through the shared
Package Session ABI. V owns input preparation, rootfs staging, build and
extraction commands, kernel and libc identity checks, launch configuration,
stage reporting and completion policy. The parser, shell source expressions,
tarfile and log owners, process retirement and generator syntax remain Python.
The benchmark, allocator fixtures and C generator inputs are independent.

The bridge borrows actual objects and the caller frame's actual builtins table.
Named main locals use one ordered private mapping; new values publish before
old values retire. Failed calls retain that same mapping in a genuine Python
traceback frame. Temporary operands retire before rich-result truth tests, and
callables are captured before path expressions. The original output cell is
shared with retained generators. Fixed implementation constants have a bounded
module-owned pool; dynamic operands and errors are not cached.

Set `VINIX_ALLOC_VINIX_QUERY` to a prepared query executable and
`VINIX_PACKAGE_STORE_LIBRARY` to a prepared Package Session library when needed.
Without overrides both are built privately on first use and retired at exit.
`V` selects the compiler and `VFLAGS` supplies its host build flags.

Qualification compares the independent original controller and this policy on
ARM64, Rosetta x86-64 and ASan/UBSan: staging and receipts, callback failures and
incoming errors, manager and saved-traceback ownership, retained generators,
controlled real child processes, warm reference and descriptor baselines,
reentry and threads. Actual cold installers are checked separately. Controlled
children establish host process behavior; they provide no new benchmark
measurement, kernel build, QEMU boot or guest allocation result. Additional
private bridge frames consume stack budget for arbitrary supplied callbacks;
no exact near-limit callback recursion threshold claim is made.
