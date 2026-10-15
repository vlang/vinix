This fixture executes the actual generated native V L1TF classifier, IRQ-off
CPUID/MSR sampler, original fault-safe MSR Option helper, boot membership
validation/publication and public `boot_cpu_has_bug` query. It parses the entire
Linux 6.6.157 vulnerability whitelist in its original first-match order from
the pinned archive. Every original flag, model constant and vendor registration
is authenticated separately from the new implementation.

The generic oracle interprets those original rows. It covers every base family
and extended model, stepping/type/reserved-bit perturbations, all extended
families, u8 family aliases, all registered vendor names and their aliases,
three independently corrupted vendor words, and plausible nonaliases. The
sampler matrix checks absent/inconsistent CPUID leaves, ARCH_CAPABILITIES
advertisement and the RDCL_NO bit independently, faulted safe MSR transport,
MSR reads on otherwise exempt non-Intel CPUs, and IRQ-enabled refusal before
any hardware observation. Missing advertisement always supplies zero caps.

Boot tests distinguish BSP-only publication from an all-CPU OR, validate every
AP even after a decisive BSP observation, reject invalid membership and every
bad record before mutation, and check early/duplicate/unknown queries. Repeated
queries, including eight concurrent observers, preserve publication and CPU
records and perform no CPUID or MSR I/O. The macro evaluates its argument once.
Only CPU/IRQ/MSR/atomic/record/panic transports are modeled, in V; C supplies
ABI metadata, original Linux macros and libc/compiler interfaces.

Run with `build-support/run-v-tool.sh tests/linuxkpi/cpu_bugs.v --keep-dir NEW`.
The controller preserves exact generated production bodies, records dependency
hashes and compiler-visible input for every object, rejects allocator imports,
and runs GNU99/GNU11 at O0/O1/O2 with ASan/UBSan. No host fault model proves a
native #GP fixup, real CPU publication or kernel allocation recovery. Those
require the isolated native build and guest checks documented in linux-i915.md.
