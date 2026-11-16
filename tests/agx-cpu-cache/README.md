# Native AGX CPU cache policy

Compile `run.v` with V, then run the resulting host tool with
`ASAN_OPTIONS=detect_stack_use_after_return=1`. The fixture executes the actual
GEM constructors/final release, authorized BO table methods, RAM retag helper,
ARM break-before-make helper, CPU cache-range loop and PRIME attribute method.
PMM backing, page-table lookup, locks and privileged instruction primitives are
recorded host substitutes. Native assembly is checked separately in the built
ARM kernel; these host tests do not execute privileged instructions or a GPU.

Checks include WRITEBACK and default NC objects, VM-private identities, retained
references, both HHDM and mmap/PRIME attributes, all-leaf validation before any
transition, clean/invalidate before NC descriptors, BBM ordering and restoration
before PMM reuse. They cover missing/invalid/RO/wrong-physical leaves, TTBR1
mismatch, invalid spans, allocation failure, original cacheable constructors,
external apertures, five cache-line geometries and ranges near `u64` limits.
The file-close regression separately executes the actual native ioctl and mmap
callbacks with distinct opaque Handle keys and adjacent opposite-policy BOs.

Optional `AGX_CPU_CACHE_BINARY` and `AGX_CPU_CACHE_C` outputs retain artifacts
outside Git. `--gem-source FILE`, `--bo-source FILE` and `--ram-source FILE`
support complete-module counterexamples without changing expected assertions.
The tests do not qualify native cache coherence, hardware timing or kernel heap
rates. Owned GEM metadata has its existing lifetime; this change adds no metadata
freeing.
