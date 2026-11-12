# Software Metal samplers — 2026-11-12

`815448669` adds MTLSamplerDescriptor and `newSamplerStateWithDescriptor:`
to the opt-in software backend. Descriptors expose integer filter/address/
comparison settings, BOOL properties, float LOD clamps and copied labels.
Defaults match the host SDK/native descriptor. `copy` and `copyWithZone:`
produce independent descriptors; states snapshot configuration and retain
their device and immutable label independently of the descriptor and caller.
Storage uses normal object data/field cleanup, without a new destructor.

Creation validates enum ranges, anisotropy 1..16 and finite, nonnegative,
ordered LOD clamps. Argument-buffer support is rejected. Unnormalized
coordinates require clamp-to-edge on all axes, no mip filter and anisotropy
one in this profile. Nil, wrong-type and uninitialized descriptors return
nil. Descriptor class/metaclass imports require Metal.framework and are
absent without the software flag. Shader binding, sampling, GPU resource IDs,
reduction mode and LOD bias remain unsupported. See
[METAL.md](../../compat/ios/runner/METAL.md).

ASan/UBSan checks pass on macOS ARM64 with normal and deterministic Swift
hashing. A shared probe exercises native and runner descriptor defaults,
integer/BOOL/float message ABIs and independent copies. Software checks cover
Unicode labels copied from a subsequently mutated NSMutableString, immutable
state snapshots, label/device lifetimes after caller releases, address modes,
comparison functions, all anisotropy values, 25 rejected inputs, eight workers
creating/releasing states and two fully drained runtimes. All ten prior
software groups pass. A separately rebuilt ordinary runner/native device
suite passes and verifies sampler imports remain absent without the flag.
The native device is available; these tests submit no GPU work.

Qualified evidence is outside Git:

`/Users/alex/Library/Caches/vinix-ios/metal-sampler-validation-20261112-r3/`

The bundle includes the ordinary runner qualification under
`default-validation/`. Its sibling `.tar.zst` was decoded and extracted to a
fresh sibling directory with `-restored` appended. Saved source, compiler,
header and both executable identities match. The restored software executable
passes all eleven groups, and the restored ordinary runner checks pass.
The archive checksum passes afterward; receipts remain beside the bundle.

The maintained harness retains its documented captured-compiler preamble
corrections. Toolchain library symlinks, host dylibs and SDKs remain external
prerequisites; dependency closures are not sealed. This is not a full typed
inventory audit. Leak detection is disabled; runtime object drainage is
checked, retained heap is not measured. Pipeline creation, shader execution
and presentation remain pending. No guest, iOS app, Fortnite frame or new
launch gate is verified.

| Artifact | SHA-256 |
| --- | --- |
| `.tar.zst` beside bundle | `1b2ff1a8bb97fef22b752e6ad9946b8a4c47b378666c42b9f40b21900677308d` |
| `source.tar`, revision `815448669` | `3bb15251cabcb6a019d493b4a24a39a2dc720ec4f5505b463a8e873cc90daafd` |
