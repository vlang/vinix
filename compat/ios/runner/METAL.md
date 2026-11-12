# Software Metal backend

Build the iOS runner with `-d ios_metal_software` to enable a CPU backend for
shared buffers, shared 2D textures and buffer blits. `MTLCreateSystemDefaultDevice` then returns
an owned device implemented by Vinix. Without that build flag it returns nil.
This backend does real deferred buffer work; it does not run shaders, render
textures, present drawables or use a GPU. It cannot yet render Fortnite.

Implemented Objective-C API:

- Device: `newBufferWithLength:options:`, `newBufferWithBytes:length:options:`,
  `newCommandQueue`, `maxBufferLength`, `newTextureWithDescriptor:`.
- Buffer: `contents`, `length`, `device`, `storageMode`, `cpuCacheMode`.
- Queue: `commandBuffer`, `device`.
- Command buffer: `blitCommandEncoder`, `commandQueue`, `device`, `commit`,
  `waitUntilCompleted`, `status`, `error`.
- Blit encoder: `copyFromBuffer:sourceOffset:toBuffer:destinationOffset:size:`,
  `endEncoding`.
- Texture descriptor: `texture2DDescriptorWithPixelFormat:width:height:mipmapped:`
  plus width, height, pixel-format, usage and storage-mode setters.
- Texture: dimension/format/usage/device/storage queries,
  `replaceRegion:mipmapLevel:withBytes:bytesPerRow:` and
  `getBytes:bytesPerRow:fromRegion:mipmapLevel:`.

Textures support R8Unorm (10), RG8Unorm (30), BGRA8Unorm (80) and
BGRA8Unorm_sRGB (81). Upload/readback preserves raw bytes without color
conversion. Only shared, single-level, single-sample 2D storage is supported,
with dimensions 1..16,384 and at most 64 MiB per texture. Mipmapped descriptor
creation and unsupported allocations return nil. Textures snapshot descriptor
metadata, own zero-initialized storage and retain their device independently.
Descriptor/texture state is freed through the existing CoreVideo metadata
destructor; pixel storage and device references use normal object cleanup.
Transfers validate positive 2D regions, level zero, row pitch and pointer
arithmetic before copying rows; caller memory must cover the requested span.
Pitch must be a multiple of the pixel size; zero pitch is accepted for a
single row, following [Apple's transfer contract](https://developer.apple.com/documentation/metal/mtltexture/replace%28region%3Amipmaplevel%3Awithbytes%3Abytesperrow%3A%29).
Only requested pixel bytes are touched, preserving client row padding.

Only resource options zero (shared storage, default cache/hazards) are
supported. Buffers must have a positive length at most 64 MiB; rejected
allocations return nil. New buffers are zero initialized; bytes constructors
copy the input. A device owns no resources: each buffer/queue retains its
device, command buffers retain their queue, and encoders retain their command
buffer. Encoded copies retain source and destination until command-buffer
destruction. Autorelease ownership applies to command buffers and encoders;
device, queue and buffer creation transfer a reference to the caller.

Copies execute in encoding order when committed, under the runtime's recursive
lock. Commit completes synchronously and transitions status from 0 to 2 to 4.
Completion means destination bytes are visible to the CPU. Wait requires a
committed buffer. Encoding cannot overlap on one command buffer; every encoder
must end before commit. Resources must belong to the queue's device. Bounds
checks use subtraction to avoid overflow; overlapping ranges in the same
buffer reject. Zero-length copies at the end of a buffer are valid. Each
command buffer is limited to 65,536 copies. Invalid encoding/state/ranges fail
explicitly. Client accesses through `contents` still require synchronization
with command submission. Texture blit commands, shader/render methods,
IOSurface imports and presentation remain absent.

Run the maintained V harness from the repository root:

```
v -path '@vlib|compat/ios|tests/ios|@vmodules' run tests/ios/metal-software-checks.v /external/fresh-bundle software
v -path '@vlib|compat/ios|tests/ios|@vmodules' run tests/ios/metal-software-checks.v /external/fresh-default-bundle default
```

The harness uses the captured runner compiler and headers from
`build/ios/fortnite/ns-calendar-checks/toolchain`, creates an isolated compiler
executable/resource root, and references its captured library/dependencies.
The captured development compiler reloads some headers through absolute paths
with stale lengths. The harness preserves the original generated C and replaces
only its integer-128 and libc preambles with the complete captured headers;
generated program functions are preserved. An obsolete `sigaction` forward
declaration is removed in favor of the SDK declaration. It generates C from V, compiles
and links with ASan/UBSan, and runs twice with normal and
deterministic Swift hashing. These are macOS ARM64 host checks. Leak detection
is disabled; tests assert drained runtime objects rather than retained heap
measurements. The command ABI has not yet been exercised in a Vinix guest.
