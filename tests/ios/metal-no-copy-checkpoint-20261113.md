# Software Metal no-copy buffers — 2026-11-13

`c326eb8dc` adds `newBufferWithBytesNoCopy:length:options:deallocator:`.
The bounded profile accepts host-page-aligned pointers and positive,
page-multiple lengths up to 64 MiB, default shared options and nil deallocator.
Pointer-plus-length overflow rejects. Nonnil deallocators return nil without
being copied or invoked. The caller owns the pages and must keep them mapped
and writable until every buffer, texture, view and encoded-command owner is
released. Runtime destruction never frees/unmaps these pages.

Contents/length, buffer copies/fills, buffer-backed texture allocation and
buffer/texture transfers now share owned/borrowed storage helpers. Buffer
copies detect overlapping addresses across separately wrapped aliases, while
disjoint and empty copies remain supported. Existing texture alias checks
apply to borrowed storage too. See [METAL.md](../../compat/ios/runner/METAL.md).

All nineteen software groups pass under ASan/UBSan on macOS ARM64 with normal
and deterministic Swift hashing. New checks cover pointer/length ABI, eight
invalid constructors, live caller writes observed at commit, overlapping alias
rejection, ordered owned/borrowed buffer copies and fills, buffer-backed CPU
texture writes, both deferred buffer/texture transfer directions, owner release
before commit and two drained runtimes. Caller pages remain writable after
shutdown and are unmapped by the test. The ordinary runner suite was not
rebuilt for this opt-in change.

Evidence bundle:

`/Users/alex/Library/Caches/vinix-ios/metal-no-copy-validation-20261113-r1/`

The sibling archive was decoded/extracted to a fresh `-restored` directory.
Saved source/compiler/header/executable identities match, and the restored
sanitizer executable passes all nineteen groups. The archive checksum passes
afterward; receipts remain beside the bundle. The maintained harness retains
its documented compiler-preamble corrections. Toolchain library symlinks,
host SDKs and dylibs remain external prerequisites; dependency closures are
not sealed. This is not a full typed-inventory audit. Leak detection is
disabled; object drainage is checked, retained heap is not measured. Shader
execution and presentation remain pending. No Fortnite frame or new launch
gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` beside bundle | `92566716601d1bb87bc1c9b61fe56f5731b5de5e5161d1eed0e32e49bc1bac98` |
| `source.tar`, revision `c326eb8dc` | `4fa579f7c9382b07fa47a6e4f5bcbfdb365e61ee1430d468a02c0cc47969dc82` |
