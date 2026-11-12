# Software Metal library files — 2026-11-12

`393f63986` adds `newLibraryWithFile:error:` to the opt-in software device.
Filename and dispatch-data loading share an ownership-taking container parser,
index allocation and object construction path. Files need no dispatch runtime.
Successful libraries own their bytes independently of the file and path object;
existing function handles continue to retain their library and device.

Paths must be nonempty NSString values with no embedded NULs and at most
1,023 bytes, checked before copying. Nonblocking open and descriptor-based stat
reject nonregular files without waiting on FIFO writers. The 256 MiB limit is
checked before allocating input storage. Reads retry EINTR, reject early EOF
and probe for growth beyond the stat size. The descriptor and path snapshot
are released on return. Error codes and limits are documented in
[METAL.md](../../compat/ios/runner/METAL.md). Concurrent same-size file writes
are not detected as such; the resulting snapshot still needs container/hash
validation. No filesystem snapshot guarantee is provided.

ASan/UBSan macOS ARM64 checks pass with normal and deterministic Swift hashing:
raw/wrapped and independent/shared-module containers, Unicode filenames,
function use after file replacement and library/path release, empty libraries,
ten invalid inputs including embedded NULs, missing files, directories, sparse
oversized files and FIFOs, optional NSError output and two drained runtimes
without dispatch initialization. All eight previous software groups pass.
EINTR and concurrent file shrink/growth branches were reviewed, not fault
injected. The ordinary runner/native suite was not rebuilt in this checkpoint.

Qualified evidence is outside Git:

`/Users/alex/Library/Caches/vinix-ios/metal-library-file-validation-20261112-r2/`

The archive was decoded/extracted into the sibling directory with `-restored`
appended. Saved source/compiler/header/executable identities match; the restored
sanitizer executable passes all nine groups. The archive checksum passes
afterward; receipts remain beside the bundle. r1 passed before path validation
was moved ahead of copying. The maintained harness retains its documented
compiler-preamble corrections. Toolchain library symlinks, host dylibs and SDKs
remain external prerequisites; dependency closures are not sealed. This is not
a full typed-inventory audit. Leak detection is disabled; object drainage is
checked, retained heap is not measured. Fixtures are synthetic containers,
not executable shaders. No AIR verification, pipeline, shader, rendering,
presentation, guest or iOS app is validated. No Fortnite frame or new launch
gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` beside bundle | `e83b8599068720f1abfcb53dab61356f9f4e54b81695968a101483cd7dc1ae81` |
| `source.tar`, revision `393f63986` | `7587be28303455e8615d5e039bbac7cd7200cc5c261cb2f7e5784285a0eba857` |
