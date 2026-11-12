# Software Metal default libraries — 2026-11-12

`1ddfd06e8` adds `newDefaultLibrary` and
`newDefaultLibraryWithBundle:error:` to the opt-in software device. Both load
`default.metallib` from the configured iOS main bundle resource root through
the existing bounded file loader and container validator. The explicit form
supports only the runtime-owned main NSBundle; nil, unrelated objects and
other bundles return unsupported. This follows the runner's current bundle
profile, not general native NSBundle resource resolution.

An unset, oversized or NUL-containing resource root fails before path creation.
Roots are capped at 1,006 bytes to leave space for the filename within the
file loader's 1,023-byte path limit. Each call reads a new owned library;
there is no cache. Libraries and function handles retain their existing
ownership behavior. The implicit form returns nil on failure; the explicit
form reports existing library errors and leaves the error slot untouched on
success. Neither needs dispatch initialization. See
[METAL.md](../../compat/ios/runner/METAL.md).

ASan/UBSan macOS ARM64 checks pass with normal and deterministic Swift hashing:
both Objective-C selectors, main-bundle lookup, Unicode resource roots,
function metadata after caller library release, unset/missing/corrupt/oversized
paths, nil/wrong-type/foreign bundles, success error-slot preservation, fresh
reads after file corruption and two runtime lifetimes without dispatch.
Object counts reach the single runtime-owned main bundle before shutdown.
All nine prior software groups pass. The ordinary runner/native suite was
not rebuilt in this checkpoint.

Qualified evidence is outside Git:

`/Users/alex/Library/Caches/vinix-ios/metal-default-library-validation-20261112-r1/`

Its archive was decoded/extracted into the sibling directory with `-restored`
appended. Saved source/compiler/header/executable identities match; the restored
sanitizer executable passes all ten groups. The archive checksum passes
afterward; receipts remain beside the bundle. The maintained harness retains
its documented compiler-preamble corrections. Toolchain library symlinks, host
dylibs and SDKs remain external prerequisites; dependency closures are not
sealed. This is not a full typed-inventory audit. Leak detection is disabled;
object drainage is checked, retained heap is not measured. Fixtures are
synthetic containers, not executable shaders. AIR verification, pipeline
creation, shader execution and presentation remain pending. No guest, iOS app,
GPU command, Fortnite frame or new launch gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` beside bundle | `f38bc35162cbe279b6baa7f8cc6ef837a0cf7f00575258ec84dd395b3714fd6f` |
| `source.tar`, revision `1ddfd06e8` | `c5ba725bc09a3850a15f74bd7eefb2deec37f415de6a2ddd5b24e00ab0d3c6e5` |
