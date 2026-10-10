# Kernel allocation sampler controller

`run-kernel-vinix.py` keeps its public CLI and eager compiler flags. Its
preparation, compiler checks, build recipes, kernel/hash verification, exact
configuration fields, launch and serial verdict policies run in
`kernelvinixcore`, through `kernel_vinix_query.v` and the committed Package
Session ABI. Supplied Python objects remain actual objects; the adapter
captures the public caller's builtins table. Override the query with
`VINIX_ALLOC_KERNEL_VINIX_QUERY`.

The original Python owns the archive and both log contexts, process retirement
(`poll`, `terminate`, five-second wait, `kill`, wait), output cell and lazy
marker/report generators. The untimed init source remains counted Python
data. Named controller values publish into an ordered private dictionary
before previous values retire. Dictionary metadata collects all RHS values before
construction, and failing argument/keyword stacks retire in reverse order. Saved errors retain that dictionary in the
actual adapter traceback, without rewriting exception attributes. Module
constants use a finite implementation pool; caller data is not cached.

Qualification compares the independent original against fresh ARM64,
Rosetta x86-64 and ASan/UBSan host builds, including successful and failing
preparation/verdicts, exact archive members/configuration/commands, injected
actual errors and prior contexts, named/drop and saved traceback lifetimes,
held generator cells, constant identities, repeated/nested/threaded calls,
controlled actual host children, descriptors, CLI, interruption and cold
query/library installation. Machine-local evidence is in
`alloc-bench-kernel-vinix-controller-20261010` under the migration cache.

Controlled host children qualify supervisor behavior. They establish no new
kernel sampler measurements, QEMU boots or guest performance results. The
sampler, generator and independent allocator/validation fixtures remain
unchanged. Arbitrary supplied callbacks can observe private bridge frames or
have less callback recursion headroom than a direct call. The original
maintained generator and cleanup syntax remains in Python; accepted recursive
codec/input paths are not ported here.
