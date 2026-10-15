# Dependency failure diagnostics

The resolver reports an encountered failing requirement and its ancestry through
the selected dependency graph. Previously, a denied newer candidate could leave
its license error behind after an allowed older candidate was selected. A later
missing dependency then incorrectly reported that license refusal. The retained
baseline reproduces this with `Vendor-EULA` instead of the missing dependency.

Candidate policy refusals stay local until that choice is exhausted. A fresh
missing requirement replaces the previous branch's cause; an exhausted retry
with no new refusal preserves the deeper failure. Parent indices accompany the
FIFO requirements and are trimmed with them during backtracking. This reports
one encountered failing branch, rather than claiming an exhaustive explanation
of every possible alternative.

Messages include the requirement's minimum/exclusive upper bounds, selected
version for conflicts, and application ancestry for isolated-runtime failures.
Publisher closure validation includes its fixed advertised root. Paths retain
the root and last 14 requirements, plus the publisher root when applicable: at
most 16 identities. Omitted middle hops are marked explicitly. Reasons longer
than 1,024 UTF-8 bytes have an explicit truncation marker; the complete message is
bounded to 4,096 UTF-8 bytes. Search-limit errors propagate directly. Candidate
preference, accepted closures, policy decisions and search budgets are unchanged.

The host fixture covers policy fallback on both target configurations, discarded
branches, conflicting ranges, organization policy, architecture mismatch,
runtime and fixed-root failures, a 4,096-node missing chain, and a long UTF-8
reason. Existing exhaustive-oracle checks on 256 generated graphs, dense cycles,
maximum closures, runtime fallback, architecture preference and budget checks
continue to run. The tracked fixture constructs inputs outside measurement,
then frees search buffers, returned arrays, messages and error objects. It checks
1,000 cycles of successful 256-package resolution, missing/policy refusals,
policy fallback and a 256-node missing path. It retained **zero tracked bytes**
in both the native and ASan/UBSan runners. This measures resolver work and
diagnostics, rather than whole-service memory use; sanitizer leak detection is
disabled (`detect_leaks=0`, `halt_on_error=1` for undefined behavior).

The signed CLI fixture packs two versions, publishes an authenticated incomplete
catalog and refreshes separate AArch64/x86_64 roots. `plan`, `review` and
`install` report the current missing requirement and path without the skipped
license error. Catalog/trust bytes and the absent activation pointer remain
unchanged. `publish-release` still refuses the incomplete closure without
publishing a destination. The full distribution CLI lifecycle also runs.

The maintained administrator guest controller requires the new diagnostic
marker, along with the existing large graph, budget and authenticated package
administration workflows. Both guests use frozen kernels; no kernel source is
rebuilt. The runs qualify synthetic resolution and service behavior. They do
not qualify graphical login, a real application catalog, foreign runtime APIs or
performance. Roadmap 14 remains open for the broader distribution work.

The results retain failed qualification attempts as well as successful runs.
Initial allocation attempts found 32,000 bytes in the new test helper: generated
C boxed its local error interface on each return. Keeping the measured refusal
inline removed those wrappers; the resolver itself was not retaining them.
An initial baseline-helper basename collision and two AArch64 host-toolchain
setup failures are also retained. The final AArch64 invocation supplies the
installed musl sysroot and a V compiler adapter for the existing GCC toolchain;
compatibility warnings in existing generated C remain warnings. Public build
tooling is unchanged.

## Recorded results, 2026-10-16

All **25 focused compile/run checks** passed: nine core compile/run pairs, native allocation and sanitizer pairs, and three signed CLI compile/run checks. The resolver core pair was refreshed after correcting the measured test helper.

Both fresh QEMU TCG guests passed with clean shutdown and eight verified artifact hashes each: AArch64 **21.896 seconds**, x86_64 **49.059 seconds**. These are functional deadlines, not performance qualification.

- [baseline regression](results/2026-10-16/resolver-diagnostics-baseline.txt)
- [host results](results/2026-10-16/resolver-diagnostics-host.json)
- [host summary](results/2026-10-16/resolver-diagnostics-host.txt)
- [core assertions](results/2026-10-16/resolver-diagnostics-core.txt)
- [tracked allocations](results/2026-10-16/resolver-diagnostics-memory.txt)
- [sanitizers](results/2026-10-16/resolver-diagnostics-asan.txt)
- [signed CLI](results/2026-10-16/resolver-diagnostics-cli.txt)
- [initial attempts](results/2026-10-16/resolver-diagnostics-attempts.txt)
- [source/toolchain/artifact ledger](results/2026-10-16/resolver-diagnostics-toolchain.json)
- [aarch64 receipt](results/2026-10-16/resolver-diagnostics-aarch64.json)
- [aarch64 report](results/2026-10-16/resolver-diagnostics-aarch64.txt)
- [aarch64 serial](results/2026-10-16/resolver-diagnostics-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-16/resolver-diagnostics-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-16/resolver-diagnostics-x86_64.json)
- [x86_64 report](results/2026-10-16/resolver-diagnostics-x86_64.txt)
- [x86_64 serial](results/2026-10-16/resolver-diagnostics-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-16/resolver-diagnostics-x86_64.qmp.txt)
