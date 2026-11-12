# Software Metal compute parameter bindings — 2026-11-13

`a6a6a6379` adds `setBytes:length:atIndex:`, `setBufferOffset:atIndex:` and
`setBuffers:offsets:withRange:` to the opt-in compute encoder. Inline bytes
copy immediately into an owned internal buffer, replace the slot and reset
its offset. Dispatch retains that buffer independently of later stack writes,
rebindings and encoder destruction. The supported length is 1..4,096 bytes;
zero/nil, oversized or overflowing spans reject. Offset-only updates require
an explicit buffer binding; inline and unset slots reject. Kernel bounds and
alignment remain checked at dispatch. See
[METAL.md](../../compat/ios/runner/METAL.md).

Bulk bindings copy both client arrays for a range in slots 0..30. An empty
range at location 31 accepts nil arrays. Nil entries clear slots. All objects,
devices and offsets are validated before mutation; every incoming handle is
retained before replacing any old slot, including sole-owner permutations.
Single/bulk explicit bindings clear inline state. New state is published before
releasing old resources, allowing no-copy deallocators to reenter the runtime
and make additional binding updates. Generated C confirms the three temporary
bulk arrays remain on the stack and no encoder state is read after old-resource
release begins. All setters require active, uncommitted encoding.

All 24 software Metal groups pass ASan/UBSan on macOS ARM64 with normal and
deterministic Swift hashing. The new group checks inline source mutation and
replacement, the accepted 4,096-byte boundary, explicit-buffer offset updates,
the bulk array/NSRange ABI, all 31 slots, empty ranges, copied client arrays,
nil clearing, sole-owner swaps and reentrant cleanup. Two bulk-replaced no-copy
buffers observe both new bindings; an inline replacement exposes its copied
value before invoking cleanup. Callback-made updates survive the outer setter.
Four deferred dispatches produce 579, 18, 24 and 579 after explicit source
buffers change, inline sources change, bindings change, the encoder is destroyed
and caller resource handles are released. Destination padding stays unchanged.
Nineteen invalid inputs/states reject. Each group drains two runtimes.

The maintained harness now requires the new execution marker and gives compute
fixture groups separate external paths. Existing compute, indexed-memory, blit,
texture, library, sampler and callback regressions remain in the same suite.
The ordinary runner and standalone AIR suites were not rebuilt for these
opt-in binding changes. API signatures were checked against the installed SDK
header, retained in the evidence; no native Metal binding/kernel comparison
is claimed. Tests assemble synthetic LLVM modules with AIR metadata.

Evidence bundle:

`/Users/alex/Library/Caches/vinix-ios/metal-compute-bindings-validation-20261113-r2/`

The sibling archive was decoded and fully extracted to fresh `-restored`.
Saved source/compiler/header/executable identities match, and the restored
sanitizer executable passes all 24 groups again with fresh generated fixtures.
The archive checksum passes afterward; receipts remain beside the bundle.
The current V compiler snapshot was saved after checks. The runner harness
retains its documented compiler-preamble corrections. Toolchain library
symlinks, SDKs, assembler and dylibs remain external prerequisites; complete
dependency closures are not sealed. This is not a full typed-inventory audit.

Compute remains a bounded single-thread CPU interpreter. These APIs do not
expand supported AIR instructions, specialize shaders or enable rendering.
Leak detection is disabled; runtime object drainage is checked, retained heap
is not measured. No Apple compiler-produced kernel, Vinix guest, GPU command,
Fortnite frame or new launch gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` beside bundle | `1873dd83a2e2d1b69ab764c3113ea0afad9838e03ee9c910b76725d67f563175` |
| `source.tar`, revision `a6a6a6379` | `bd8d8cb72c711696dd94d6c7e03497b01465a1af1566e518ea2e1a132b7b599e` |
