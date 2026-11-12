# AIR void-return execution — 2026-11-13

`94936da8a` adds `IRTypedProgram.run_void_function`, returning an IRVoidRun
with the executed step count. Defined ordinary void functions use the existing
mixed scalar arithmetic/control-flow profile. `ret void` costs one step and
reads no result operand. Nonvoid signatures reject; integer and scalar result
APIs still reject void signatures. No new execution arrays or allocation
paths are introduced. Valid IR and matching immutable indexes remain
preconditions. See [VOID-EXECUTION.md](../../compat/ios/airbitcode/VOID-EXECUTION.md).

Normal and ASan/UBSan checks pass all 16 integer/mixed unit groups, including
the new API separation, argument-count and budget checks and existing integer,
binary16, binary32, conversion, poison and control-flow regressions.
The maintained V serialized-bitcode checker assembles fixtures with llvm-as
and passes 641 cases in both builds: empty void return, both branch paths,
128 PHI loops and 256 half/float arithmetic inputs. It checks exact path steps,
one-step-short budgets, separation from value APIs and rejection of unreachable,
infinite-loop, selected-undef and nonvoid fixtures. These are interpreter
path/step checks, not native-JIT value comparisons.

The current `v test` wrapper failed to compile, and the captured wrapper mixed
library roots. Both failures are retained. Direct compilation of the test
file and maintained checker with the current compiler works and passes; no
generated C was patched. A compiler executable snapshot was saved after the
checks. The complete toolchain/library/SDK/assembler dependency closure is not
sealed; host dependencies remain external. Leak detection is disabled and
retained heap was not measured. No architecture cross-build was performed.

Evidence bundle:

`/Users/alex/Library/Caches/vinix-ios/air-void-validation-20261113-r1/`

The sibling archive was decoded/extracted to a fresh `-restored` directory.
Saved source/compiler/executable identities match. Restored sanitizer units
pass all 16 groups, and the restored checker passes all 641 cases again in
fresh sibling `-restore-cases`. The archive checksum passes afterward; receipts
remain beside the bundle. This is not a full typed-inventory audit.

Kernel argument binding, pointers/memory execution, pipelines and Metal
dispatch remain pending. No AIR kernel, GPU command, Fortnite frame or new
launch gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` beside bundle | `a6a3d0493d664517b13285307f1831a52c71ab7f84b2d0dda9fd705f4bda71d3` |
| `source.tar`, revision `94936da8a` | `126937b827490af660f1aabfde7ee75365be82f1fcc1e79c449274f53c1f5404` |
