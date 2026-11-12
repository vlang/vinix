# Software Metal scalar compute — 2026-11-13

`e81338f78` connects the AIR scalar memory executor to the opt-in software
Metal runner. `newComputePipelineStateWithFunction:error:` parses the selected
library module and checks a matching classic `air.kernel` entry, supported body
and buffer metadata. The owned pipeline retains its function/library/device.
The AIR layer now exposes an owned memory-function profile, reused for
pipeline validation and execution without duplicating instruction rules.

The compute encoder supports pipeline/buffer setters and both thread/grid
dispatch selectors. Every grid and threadgroup dimension must be one.
Dispatch records retained snapshots of pipeline, buffers and offsets; commit
reads current bytes in command order alongside blits/fills. Dynamic interpreter
errors set status 5 and an owned `MTLCommandBufferErrorDomain` NSError (code 1),
preserve earlier writes and skip later commands. Notifications and waits finish
normally. The error-domain global is scoped to Metal.framework. See
[METAL.md](../../compat/ios/runner/METAL.md) for the complete profile.

All 23 software Metal groups pass under ASan/UBSan on macOS ARM64 with normal
and deterministic Swift hashing. New checks assemble synthetic LLVM modules
with AIR metadata and cover sparse/reordered buffer slots, constant/device
address spaces, integer and float execution, an empty kernel, both aggregate
dispatch ABIs, writes after encoding, changed pipeline/buffer bindings, encoder
destruction before commit, retained resources, aliasing, ordered blits,
eleven encoding rejection modes, unsupported pipeline inputs, failed completion,
partial writes, skipped later commands, error-domain imports and two drained
runtimes. The ordinary runner's nil-device suite also passes in both modes.

Standalone ASan/UBSan regressions pass 16,896 scalar copies and 107,776 native
LLVM arithmetic comparisons (67 matching NaN classes, without payload/sign
equality), plus the maintained rejection guards. The interpreter/checkers are
instrumented; LLVM's JIT-generated native reference is not.

Evidence bundle:

`/Users/alex/Library/Caches/vinix-ios/metal-compute-validation-20261113-r5/`

The bundle includes the software build, default build and AIR regressions.
Its sibling `.tar.zst` was decoded and fully extracted to fresh `-restored`.
Saved source/compiler/header/executable identities match. Restored sanitizer
executables pass all 23 software groups, the default-device check and both AIR
regressions again, with fresh external generated fixtures. The archive checksum
passes afterward; restore receipts remain beside the bundle. The maintained
harness preserves its documented compiler-preamble corrections. The current V
compiler snapshot for standalone tools was saved after checks. Toolchain library
symlinks, host SDKs, assembler and dylibs remain external prerequisites; complete
dependency closures are not sealed. This is not a full typed-inventory audit.

This is a CPU interpreter profile, enabled only by `-d ios_metal_software`.
Only ordinary void, one-block scalar buffer functions with flag-free binary
arithmetic and direct pointers are accepted. Calling convention and LLVM
function attributes must be zero; valid LLVM IR remains a precondition, rather
than a general verifier result. Builtins, GEP, branches, vectors, textures,
barriers and threadgroup memory remain unsupported. Synthetic fixture success
does not establish Apple compiler-produced library compatibility or native
Metal kernel execution. Leak detection is disabled; object drainage is checked,
retained heap is not measured. No Vinix guest, GPU command, presentation,
Fortnite frame or new launch gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` beside bundle | `4ffead765e351c98fad3af6fc5e2e8e6842ed84a96efe6480cce9830f9f4e2bd` |
| `source.tar`, revision `e81338f78` | `1192014fe6b46083cd5fb9f0bd3b1015478a2373dd0143c293dbebc239d3966a` |
