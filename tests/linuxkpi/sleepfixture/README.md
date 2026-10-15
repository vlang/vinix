# Conditional sleep fixture

The controller is a V program, compiled with the repository's `hosttest` import
path. Run it with `--keep-dir NEW` to preserve generated sources, dependency
hashes, compiler logs, sanitizer outputs and `result.json`. A host analysis
build should use Boehm; the generated kernel/fixture code still uses `-gc none`.
Select the compiler and its actual SDK together using the environment documented
in `docs/linux-i915-handoff.md`; `V3CACHE` and `VTMP` are private per run.

The fixture executes 31 safe cases per C standard: 13 false predicates, which
must not query task context, and 18 true predicates, which query it once.
These include signed/unsigned boundaries, null and non-null pointers, floating
positive/negative zero, nonzero values and NaN, imaginary-only complex values,
Boolean branches and a once-only ordered side-effect provider. Four child
processes per standard abort through the production bug call for IRQ-off,
preemption-pinned and IRQ-enabled maskable depths one and two. A `#line`
directive checks the exact reported caller file and line.

The production leaf, public export thunk, initialization guard and empty
initializer must match a fresh generation of every real headercore source
before execution. All selected production, spy and fixture bodies remain
byte-identical to the V output. The test entry uses a metadata-only symbol
alias to retain the library producer's real initialization guard. The staged
module does not initialize the full module's unrelated workqueue or CPU-mask
globals.

GNU99/GNU11 profiles use strict warnings, ASan and UBSan. Ten compiler controls
accept integer, pointer and complex predicates and reject records/unions
solely at the actual predicate-to-Boolean argument boundary. Seven malformed
ABI metadata controls must leave an existing output file untouched. The
adapter's `do/while` grouping is checked as generated metadata and exercised
through V branches; this fixture does not execute a handwritten unbraced C
if/else or postincrement expression.

The C contract contains only includes, types, static assertions, symbol aliases
and a compiler complex-construction intrinsic binding. Runtime and test control
logic live in V. These host observations do not replace native CPU/IRQ testing,
retained-page measurement, full i915 linkage or Tiger Lake hardware validation.
