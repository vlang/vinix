# Compiled Metal library reader checkpoint — 2026-11-04

`f27c9c91b996e400459cd4a1e8c27cb16c1fc4f8` adds the V module
`compat/ios/metallib`, its unit fixtures and `metallib-inspect.v`.
This provides the container-reading stage needed before implementing Metal
shader execution. The most recent Fortnite launch remains the
[controller-discovery capture](controller-discovery-checkpoint-20261104.md):
Unreal reports unsupported Apple family 3 GPU features. Progress remains
**4/8 observed launch gates**, with no rendered game frame, menu, login or
playable match verified.

The reader supports the MTLB v2 profile with explicit NAME, TYPE, HASH, OFFT,
VERS and MDSZ function records. It checks little-endian fields, declared file
size, section extents and overlap, function/metadata group boundaries, UTF-8
names, duplicate required fields and names, relative metadata references,
module alias consistency and indexed module SHA-256 values. It recognizes
raw LLVM streams and version-0 LLVM wrappers and exposes the stream's range
without wrapper/padding bytes. Unknown metadata tags remain opaque.

Names borrow immutable caller-owned input. The index owns two arrays and
provides explicit cleanup. Input is capped at 256 MiB, functions at 65,536,
tags at 262,144, and terminated names at 4 KiB. Unique module ranges are checked
for overlap before hashing. Exact aliases share an index and are hashed once,
so total hashing work cannot exceed input size. The layout was checked against
the [MetalLibraryArchive research](https://github.com/YuAo/MetalLibraryArchive)
and LLVM's [documented wrapper format](https://llvm.org/docs/BitCodeFormat.html#bitcode-wrapper-format).

Normal and ASan/UBSan unit runs pass four groups: empty and populated libraries,
raw/wrapped streams, independent/shared modules, borrowed names and unchanged
input; 299 truncations plus directed corruptions of headers, fields, ranges,
metadata and wrappers; shared-module consistency, partial overlap and the tag
work cap; and 2,392 single-bit mutations checking input immutability and bounded
successful indexes. A padding mutation also confirms that module hashing covers
the complete MDSZ range, not only the extracted LLVM stream.

The independent native comparison loads the same files through macOS Metal,
compares all names and function counts, creates native vertex/fragment/kernel
functions and checks their reported types. Normal and sanitized runs agree on
430 names across the three libraries below. Type comparison covers 428
vertex/fragment/kernel functions; SceneKit's two visible functions are included
in the name/count comparison and are outside that type check.

| Copied native library | Functions/modules | Bytes | SHA-256 |
| --- | --- | --- | --- |
| Contacts | 1/1 | 5056 | `9ed368c6225e452258ec4e0574b96e59cbb6a3bf4e58c0e476384df5053919b6` |
| MetalFX | 90/90 | 1314612 | `da0225cc853c3dac172913805449a53057186e1beafeaac018f274977520be56` |
| SceneKit | 339/339 | 2403572 | `6ed8c241ed66c85481c2285519dd7b23cf3e823c9f4af9949d20c265ff6ca19f` |

Extracted Contacts and MetalFX module-0 streams pass LLVM's independent
`llvm-bcanalyzer -dump`. This establishes valid extraction of those bitstreams,
not AIR instruction semantics or shader execution. The portable unit program
also cross-compiles and links to a static little-endian AArch64 Linux ELF.
That binary was inspected with `llvm-readobj`; it was not executed in a guest.
The native corpus is macOS 27.2 MTLB 2.9 data. iOS-header coverage is synthetic;
Fortnite's packed shader libraries have not yet been extracted or tested.

An early native comparison hit a double-free in the tool's temporary string
cleanup. The corrected tool clones borrowed names into its owned string array
and uses the frozen compiler's array cleanup once. The final native comparisons
and unit runs pass sanitizers. This did not require changing the parser's input
ownership contract.

`MTLCreateSystemDefaultDevice` still returns nil. The new reader is independent
of that runtime path: it does not verify LLVM IR, interpret or translate AIR,
execute Metal commands, allocate GPU resources or present drawables. The next
backend work includes AIR decoding/translation, resource and pipeline objects,
command execution and presentation. No new Fortnite probe was run for this
container-only change, and no new launch gate is claimed.

Complete validation is preserved outside Git at:

`/Users/alex/Library/Caches/vinix-ios/metallib-validation-20261104-r1/`

The bundle includes copied native inputs, source snapshot, normal/sanitized unit
and comparison binaries/results, build logs, extracted streams, LLVM analyses,
generated AArch64 C, linked ELF and header inspection, environment/tool versions
and input hashes. Its external typed inventory records every current path,
file's bytes, type and permissions and passes independent rechecking.

| Artifact | SHA-256 |
| --- | --- |
| `metallib-validation-20261104-r1.inventory.json` beside the bundle | `e1f493dacbc9a4c6e84e1004b3af6429801e8e190c0fda261d68b2ffd2458562` |
| `source.tar`, revision `f27c9c91b` | `e88b35c1afcdc1d63fe7bd7a2700c99dda22dd24ec0cb7b4d8fff6233cb10e59` |
| `unit-aarch64` | `ad7e118770e8de65ba8a0e28a9da4354c1f40c23553a601b596aec4778ee0a63` |

Build with the existing frozen V toolchain at
`build/ios/fortnite/ns-calendar-checks/toolchain`: set `V_RESOURCE_PATH` to that
directory and `V_MACOS_V3_NO_FALLBACK=1`, use
`-enable-globals -nocache -gc none -cc clang`, and include `compat/ios` in `-path`. Compile `library_test.v` and
`metallib-inspect.v` with `-cflags -O2` for normal checks, or matching
`-fsanitize=address,undefined` compiler/linker flags with
`-O1 -g -fno-omit-frame-pointer` for instrumented checks. Inspector modes are documented
in its usage and the module README. Native comparison requires macOS Metal;
portable parsing does not. Compiler/SDK/native-framework closures are not sealed
by this small validation bundle.
