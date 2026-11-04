# AIR type/function index checkpoint — 2026-11-05

`a64f414f4c8ff9442fe673b52a24470eb0d3bae8` adds a bounded LLVM module-version-2
type/function index to `compat/ios/airbitcode`. It follows the
[raw bitstream reader](air-bitcode-checkpoint-20261105.md) and identifies function
names, signatures and bodies needed for subsequent AIR instruction decoding.
Fortnite remains at **4/8 observed launch gates**. Its last capture reaches the
[unsupported Apple family 3 GPU alert](controller-discovery-checkpoint-20261104.md);
no game frame, menu, login or playable match is verified. The gate fraction is
not an engineering completion estimate.

`stream.ir_module(data)` checks the supported type record schemas, type-reference
bounds and element categories, identified-struct forward references, version and
table scopes/counts, STRTAB name extents, declaration flags, function signatures
and body/DECLAREBLOCKS correspondence. Bodies pair with definitions in module
order. The index retains typed-pointer pointees, address spaces, packed/scalable
shapes, varargs and encoded convention/linkage fields. Function names borrow the
immutable raw input; type names, headers and three index arrays have explicit
cleanup. Formatting has separate depth/work/byte limits. See the [API and limits](../../compat/ios/airbitcode/IR.md).

Normal optimized and ASan/UBSan semantic fixture runs pass all five groups:
recursive identified types, legacy/opaque pointers and body mapping; 48 directed
schema/reference/name/scope/body corruptions; text/render limits; packed/scalable
shapes and escaped names plus **6,400** scalar bit mutations; and empty modules
plus the expanded-reference cap. These deliberate record fixtures are not
executable shaders. Existing raw-bitstream sanitizer tests also pass unchanged,
including 19 rejected prefixes and 160 input-bit mutations. Leak detection is
disabled in sanitizer runs; this is not a leak measurement.

The final sanitized inspector reads every extracted module and independently
runs LLVM 23.1.0's `llvm-dis`. It compares all function names, opaque-pointer
return/parameter types, declaration flags and basic-block counts, plus target
triple, data-layout text and source filename. Every function participates in a
bijection; LLVM's upgrade-induced declaration ordering is not assumed.
All 430 LLVM statuses and three corpus runs are zero.

| Copied native corpus | Modules | Types indexed | Function signatures compared |
| --- | ---: | ---: | ---: |
| Contacts | 1 | 31 | 8 |
| MetalFX | 90 | 5,693 | 1,451 |
| SceneKit | 339 | 13,686 | 2,489 |
| Total | 430 | 19,410 | 3,948 |

LLVM upgrades some legacy intrinsic declarations. The inspector explicitly
adapts typed-pointer memory intrinsic suffixes and checked two-argument lifetime
prototypes for this comparison, while preserving the original AIR names/types.
Its initial strict-order rejection and subsequent complete results are retained.
The documented rules follow LLVM's [intrinsic upgrader](https://github.com/llvm/llvm-project/blob/main/llvm/lib/IR/AutoUpgrade.cpp).
Both normal and sanitized oracle self-checks reject all 12 changed-header,
name/type/declaration, block-count, missing/extra-function and truncation controls.

These are copied macOS framework modules from the previous checksum-pinned
extraction, with the same original MTLB inputs retained here. Fortnite's packed
shaders are not covered. The disassembly comparison does not verify original
typed-pointer pointees, attributes or instructions. Portable fixtures also
cross-compile/link as a static little-endian AArch64 Linux ELF and pass header
inspection; that binary has not been executed in a guest.

Complete evidence is retained outside Git at:

`/Users/alex/Library/Caches/vinix-ios/air-ir-validation-20261105-r1/`

It includes committed source, native inputs, every compared raw stream and LLVM
disassembly/status, host/target binaries and build logs, intermediate rejections,
tool identities and reproduction notes. Final host artifacts and corpus trees
use `release` in their names. Compiler/SDK closures are not sealed.
The typed inventory passes rechecking. The complete archive was restored into
fresh `air-ir-restoration-20261105-r1/` under the same cache root; every recorded
path, byte, size, type and permission matches. The restored normal semantic
fixtures and sanitized 12-control oracle check also pass.

| Artifact beside/inside the bundle | SHA-256 |
| --- | --- |
| `air-ir-validation-20261105-r1.inventory.json` | `8d99450a4011ee5a51afa739cbd39fb7d484e30e8c8c28fe84964e98055989c8` |
| `air-ir-validation-20261105-r1.tar.zst` | `0cfb39cb5c08a815a20cbc669634ba0c5ed4d5dcd8e961e6f4bb8f34f9c968f0` |
| `source.tar`, revision `a64f414f4` | `40d00d1c53aafc7373f2f762f7a49791c905df2e36a662079a168fdbcf691d8f` |
| `unit-aarch64` | `0ae29058cbfdc5c267d76a9aaba5d1d669033072a5a4d1bd6e00a4b326e46a2a` |

No runtime capability changed and no new Fortnite probe was run. The default
Metal device remains nil. Next backend work includes constant/value IDs,
entry-point metadata, instruction decoding/lowering, resource and pipeline
objects, command execution and presentation. This index does not verify all
LLVM IR or establish executable AIR. Advertising and the prior capture's
historical auditor rejection remain unchanged.
