The independent host fixture producer and suite controller are maintained in V.
`compile_host.v` stages only the original source files, including pending-name
fallbacks and the shared native declarations. `host_suite.v` owns the ordered
21-group contracts, generation, compiler and assembler commands, undefined
allocation guard, and response file. Original fixtures and warning policies
remain unchanged.

The maintained `host_suite` and `compile_host` commands invoke V directly.
Module replacement templates are parsed and applied by V. Compilation preserves
inherited standard streams, the caller's ABI, supplied compiler/source/nm
environment, signal restoration and lack of a deadline. ABI headers are generated
through the native API, and compiler fallback is rejected.

Qualification compares frozen full original controllers with native controllers
on ARM, x86 and ASan/UBSan profiles. Every group has exact actual generated
source parity after private staging-directory normalization. Isolated executable
controls additionally compare complete compiler plans, copied source bytes,
response files, environments and ordered errors. These controls are not a
runtime workload or guest test.

The unchanged original actual suite currently stops at its first strict compile:
ARM also encounters upstream x86 assembly constraints; both ARM and x86 report
an upstream `linux/thread_info.h` signed comparison. Native controllers preserve
that failure, command, generated input and status. No headers, assertions or
warning policies were weakened, and this host controller port claims no fresh
kernel build, workload execution or guest validation.
