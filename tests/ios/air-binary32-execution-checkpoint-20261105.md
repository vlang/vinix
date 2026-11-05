# Software binary32 execution checkpoint — 2026-11-05

`950e4974d3c5e262297b985edf3ac3e0edc69e31` adds software binary32 execution
through a mixed scalar IR entry point. Fortnite remains at **4/8 observed launch
gates**, last seen at the [GPU requirements alert](controller-discovery-checkpoint-20261104.md).
No game frame, menu, login or playable match is verified. The gate count is not
an engineering completion percentage.

The profile supports flag-free float add/subtract/multiply/divide, all sixteen
comparisons, negation and i32/float bitcasts alongside existing integer control
flow. Float arguments, constants, returns, select and simultaneous PHIs retain
raw bits and poison state. Integer significand arithmetic implements nearest,
ties-to-even rounding and gradual underflow without host floating-point state.
Arithmetic NaNs choose LLVM's permitted preferred quiet NaN; non-arithmetic
operations retain payload/signaling bits, with negation changing only the sign.
Constant false/true comparisons do not read their operands. See
[BINARY32.md](../../compat/ios/airbitcode/BINARY32.md).

The original integer API keeps its profile and result type. The mixed API shares
its budget and three owned temporary arrays. Valid LLVM IR and matching immutable
indexes remain caller preconditions; this is not a full LLVM verifier. Fast-math
flags, attributes, half/double/vectors, numeric/precision conversions, remainder,
calls/intrinsics, pointers and memory remain unsupported.

Normal and ASan/UBSan arithmetic unit runs pass two groups: 34 exact rounding,
underflow/overflow/zero/infinity patterns and all sixteen comparison predicates.
Mixed/interpreter unit runs pass nine groups, including API isolation, float
arguments/constants/returns, bit-exact signaling-NaN negation, poison/undef,
constant predicates, flag rejection and budgets. Existing 1,397,052 narrow
integer flag comparisons and 28 directed i64 limits pass. The final sanitized
integer reference passes all 17,280 native comparisons and its original controls.

Both final normal and sanitized float reference runs pass **517,120 native LLVM
comparisons across 29 functions**:

| Comparison | Count per run |
| --- | ---: |
| Exact result bits, including non-arithmetic NaNs | 512,863 |
| Arithmetic NaN class plus Vinix's exact preferred representation | 4,257 |

Arithmetic NaN payload/sign equality with hardware is not qualified. All other
results compare exact bits. Inputs include a 32-by-32 edge corpus and deterministic
mixed-bit samples, with branches, select, constants, bitcasts and float PHI swaps.
High incoming bits check argument masking. Vinix interprets the original
float-argument functions; LLVM-generated wrappers implement the native float ABI.
Vinix executes neither those wrappers nor their call instructions. LLVM verifies
the fixture, and the tool can execute only its own generated functions.

Seven guarded failures, three poison results, lazy select and five corrupted
results pass separately. Two software-only checks under upward/downward host
rounding retain the RNE result; native calls run only under the default environment.
LLVM and generated machine code are not sanitizer-instrumented. Leak detection
is disabled; leaks were not measured.

The mixed unit program cross-compiles and links as a static little-endian
AArch64 Linux ELF and passes header inspection. It has not run in a guest.
No native AIR corpus scan, AIR shader, iOS app, GPU work or new Fortnite probe ran.
The [runtime default Metal device](../../compat/ios/runner/metal_device.c.v)
still returns nil. Shader resources, pipelines, command submission and
presentation remain unfinished.

Complete evidence is retained outside Git at:

`/Users/alex/Library/Caches/vinix-ios/air-binary32-execution-validation-20261105-r1/`

Qualification uses `-final` binaries/results. Initial macro-boundary compile
failure and preliminary passes before the constant-predicate correction remain
preserved. Final builds have no diagnostics. The bundle includes committed
source, generated IR/bitcode, assembler status, JIT/fenv identity, every row,
binaries, generated target C, logs, identities and reproduction notes. Compiler,
SDK, fenv, LLVM dependency, JIT and sanitizer runtime closures are not sealed.

The unchanged complete inventory checker passes. A full fresh restore under
`air-binary32-execution-restoration-20261105-r1/` matches every recorded path,
byte, size, type and permission. Restored units and sanitized float reference
pass again, including all comparisons and controls. Sibling logs preserve the
receipts; installed identities and archive/inventory hashes pass recheck.

| Artifact beside/inside the bundle | SHA-256 |
| --- | --- |
| `air-binary32-execution-validation-20261105-r1.inventory.json` | `16a3964976a2800ce1dd6aaaec6f5ed108aacea8f2794fa00f9f0213ad39d4e7` |
| `air-binary32-execution-validation-20261105-r1.tar.zst` | `e90ed88c40787b8616505e2845694626741627a9d9ee05144abeddeaba089de8` |
| `source.tar`, revision `950e4974d` | `2fd3c9bebaeaa45e8e8a0acf2283c8c02bc66bc782fbc49dab253e4b8b032531` |
| `scalar-aarch64-final` | `65fa3df7cfbf928f9eb4bf7eedd3c1ab5de7bca2e83ff83529c5e70493042b54` |

This qualifies the supported scalar float profile only. The prior game capture
and historical auditor rejection are unchanged; no new launch gate is claimed.
