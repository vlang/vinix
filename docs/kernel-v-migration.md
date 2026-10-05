# Kernel C to V migration

Port first-party implementations in small stages, preserving their external
interfaces. Keep third-party libraries, their C headers, and independent C
test callers. Generated C from V is a build artifact, not maintained source.
Architecture instructions stay in V inline assembly where its constraints
can express the required ABI and ordering.

Each stage needs its subsystem tests and builds for both kernel architectures
before committing. Inspect generated C for allocations and optimized machine
code for volatile accesses or assembly ordering when these matter. Kernel
tests build in isolated worktrees to avoid incorporating concurrent changes.

| Stage | Implementations | Status |
| --- | --- | --- |
| Memory runtime | `memcpy`, `memset`, `memmove`, `memcmp`, `atoi` | Committed as `6fd8cf1b`; 410,739 sanitizer cases and both architecture core suites passed |
| Runtime and CPU helpers | Secret erasure, hardware random words, ARM granule switch | Host erasure/ChaCha/SHA-256 and network randomness tests passed; both builds, ARM core/persistence and both native reseeding tests passed |
| Network randomness | Output pool, IP IDs, TCP ISNs, ephemeral ports, SipHash | Next |
| Integrity helpers | Verity hashing, tree layout and verification | Pending |
| Architecture glue | Stack protection, speculation, PCI access and virtualization | Pending |
| Network and Apple drivers | lwIP bridge, ANS, SMC, speakers, keyboard, Wi-Fi and GPU helpers | Pending |
| Linux driver compatibility | LinuxKPI runtime, synchronization and work queues | Pending |
| Benchmark and allocation instrumentation | Kernel benchmark and allocation tracking implementations | Pending |

The first x86 core attempts after the runtime/CPU-helper port hit the same
free-memory accounting assertion (`tests/qemu-core/test.c:275`) seen during
the memory-runtime port. The untouched C baseline passed on rerun. Record
the final migrated-kernel result here rather than treating targeted tests as
a replacement for the full core suite.

The reseeding test runs 10,000 production reseeds and partial reads, requires
zero retained objects in every heap class and zero large pages, and reaches
userspace. ARM was tested both without FEAT_RNG (native M1 virtualization)
and with it (QEMU `max` under TCG); x86 used QEMU `max` with RDSEED.
