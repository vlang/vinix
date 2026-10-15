This fixture executes the unchanged production sleeping rwsem V algorithm and
its genuine eleven typed Linux facade functions. Original Linux6.6.157
`rw_semaphore` records, static/init macros and prototypes are compiler inputs;
there is no replacement semaphore, synthetic MM field or C implementation.

Run `V=/path/to/v v -path 'tests/linuxkpi|@vlib|@vmodules' run
tests/linuxkpi/rwsem.v --keep-dir /new/evidence/directory` from the repository
root. The selected compiler must support native Vinix module generation and
host orchestration; an explicit compiler router may select separate binaries.
The Linux source defaults to the pinned third-party tree and may be set with
`LINUXKPI_SOURCE_DIR`. `CC` selects the C compiler command.

The retained result covers six GNU99/GNU11 and O0/O1/O2 combinations. Each
combination compiles both production objects for freestanding x86_64 with
bounded stack records and an exact undefined-symbol allowlist, then runs the
independent transport with ASan/UBSan: eleven safe scenarios, an intentional
post-unlock use-after-free control and fifteen fatal invariant controls.
Production and facade function bodies must match the full production module's
generated bodies exactly. Three additional fixture generations must select
identical bodies. Source/dependency hashes, commands, tools, generated sources,
preprocessed inputs, objects, stack usage, disassembly and logs are retained;
`result.json` hashes every artifact present before the receipt is written.

The native335 compiler used during development crashed in foreign-global
name metadata for the fixture's `C.stderr` and `C.rsh_static_sem` references.
Diagnostics now use `printf`/`fflush`, and the original `DECLARE_RWSEM` data
initializer lives in `contract.h`, addressed through a declaration-only macro.
These changes avoid foreign globals without changing production bodies.
Generation uses private scratch/cache paths and preserves failures; it never
retries a failed gate or substitutes cached generated C.

The independent V transport models current-task identity, IRQ/preemption state,
raw atomic spinlocks, pending/masked/fatal signals and condition-variable task
parking. Contexts, actors and queued records remain on real pthread stacks.
Libc owns pthread keys/condition variables; their allocations are separate from
the production no-allocation object/import proof and native guest measurements.
The model does not claim native CPU placement, interrupt entry or MM semantics.

Observable cases cover shared readers, exclusive writers, queued writer gates,
the original head-reader phase across intervening writers and its256-reader
limit, downgrade, cancellation, grant-before-signal, task-state restoration,
atomic try/unlock calls, fresh initialization and explicit misuse failures.
Reader-owner pointers are weak hints: they are neither retained nor dereferenced.
Read unlock also works without current-task identity. Fresh init never inspects
prior bytes; active reinitialization is unsupported caller misuse, with no side
table or detector claimed.

Lifetime controls release the real semaphore lock before allowing a grantee to
finish, release and free its containing allocation while the old releaser is
paused. They never grant API return while the semaphore lock remains held.
The ASan/UBSan matrix is distinct from actual native generated-C/O2 and guest
retained-page/live-heap evidence reviewed by independent owners.
