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
| Runtime and CPU helpers | Secret erasure, hardware random words, ARM granule switch | Committed as `7e996557`; host erasure/ChaCha/SHA-256, network randomness, both builds/core suites, ARM persistence and both native reseeding tests passed |
| Network randomness | Output pool, IP IDs, TCP ISNs, ephemeral ports, SipHash | Committed as `3f4280f7`; host C ABI/sanitizer and allocator-import checks passed; both builds, network options and IPv4/IPv6 guest suites passed with zero retained objects over 500 socket exchanges |
| Integrity helpers | Verity hashing, tree layout and verification | Committed as `5d7f2d0a`; host C ABI/sanitizers, 267 SHA-256 lengths against hashlib, 139 geometries against the builder, both builds and all verified-root boot/corruption cases passed; 1000 verified reads and 1000 shared fault/unmap cycles retained zero objects/pages on both architectures |
| PCI transactions | Configuration bounds, serialized reads/writes and atomic COMMAND updates | Committed as `6f38f210`; both host C dialects passed with sanitizers and allocator traps; both kernel builds, ARM ECAM/full-DAIF fixture, x86 network-options guest and LinuxKPI host regression passed |
| CPU mitigation policies | Active per-CPU controls and original helper ABI | Host sanitizers passed 12,288 active-policy and 6,144 original-helper cases; allocation failure/retry and allocator-import checks passed; both builds, ARM boot, x86 compatibility guest, 1,024 assembly cases and linked retpoline scan passed |
| Architecture glue | Stack protection and virtualization | Pending |
| Network and Apple drivers | lwIP bridge, ANS, SMC, speakers, keyboard, Wi-Fi and GPU helpers | Pending |
| Linux driver compatibility | LinuxKPI runtime, synchronization and work queues | Pending |
| Benchmark and allocation instrumentation | Kernel benchmark and allocation tracking implementations | Pending |

The first two x86 core attempts after the runtime/CPU-helper port hit the same
free-memory accounting assertion (`tests/qemu-core/test.c:275`) seen during
the memory-runtime port. The untouched C baseline passed on rerun, and the
final migrated-kernel run passed the full core suite with four CPUs and the
native reseeding self-test enabled.

The reseeding test runs 10,000 production reseeds and partial reads, requires
zero retained objects in every heap class and zero large pages, and reaches
userspace. ARM was tested both without FEAT_RNG (native M1 virtualization)
and with it (QEMU `max` under TCG); x86 used QEMU `max` with RDSEED.
