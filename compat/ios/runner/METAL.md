# Software Metal backend

Build the iOS runner with `-d ios_metal_software` to enable a CPU backend for
shared buffers, shared 2D textures and buffer blits. `MTLCreateSystemDefaultDevice` then returns
an owned device implemented by Vinix. Without that build flag it returns nil.
This backend does real deferred buffer work; it does not run shaders, render
textures, present drawables or use a GPU. It cannot yet render Fortnite.

Implemented Objective-C API:

- Device: `newBufferWithLength:options:`, `newBufferWithBytes:length:options:`,
  `newCommandQueue`, `maxBufferLength`, `newTextureWithDescriptor:`,
  `newTextureWithDescriptor:iosurface:plane:`, `newLibraryWithData:error:`,
  `newLibraryWithFile:error:`, `newDefaultLibrary`,
  `newDefaultLibraryWithBundle:error:`, `newSamplerStateWithDescriptor:`,
  `minimumLinearTextureAlignmentForPixelFormat:`.
- Sampler descriptor: `init`, `copy`, `copyWithZone:`, min/mag/mip filters,
  max anisotropy, S/T/R address modes, border color, compare function,
  normalized coordinates, LOD clamps/averaging, argument-buffer flag and label.
- Sampler state: `device`, `label` (immutable configuration snapshots).
- Library: `device`, `functionNames`, `newFunctionWithName:`.
- Function: `device`, `name`, `functionType` (metadata handles only).
- Buffer: `contents`, `length`, `device`, `storageMode`, `cpuCacheMode`,
  `newTextureWithDescriptor:offset:bytesPerRow:`.
- Queue: `commandBuffer`, `device`.
- Command buffer: `blitCommandEncoder`, `commandQueue`, `device`, `commit`,
  `waitUntilCompleted`, `addCompletedHandler:`, `waitUntilScheduled`,
  `addScheduledHandler:`, `status`, `error`.
- Blit encoder: `copyFromBuffer:sourceOffset:toBuffer:destinationOffset:size:`,
  `fillBuffer:range:value:`,
  `copyFromTexture:sourceSlice:sourceLevel:sourceOrigin:sourceSize:toTexture:destinationSlice:destinationLevel:destinationOrigin:`,
  `copyFromBuffer:sourceOffset:sourceBytesPerRow:sourceBytesPerImage:sourceSize:toTexture:destinationSlice:destinationLevel:destinationOrigin:`,
  `copyFromTexture:sourceSlice:sourceLevel:sourceOrigin:sourceSize:toBuffer:destinationOffset:destinationBytesPerRow:destinationBytesPerImage:`,
  `endEncoding`.
- Texture descriptor: `texture2DDescriptorWithPixelFormat:width:height:mipmapped:`
  plus width, height, pixel-format, usage and storage-mode setters.
- Texture: dimension/format/usage/device/storage queries, `iosurface`, `iosurfacePlane`,
  `buffer`, `bufferOffset`, `bufferBytesPerRow`,
  `newTextureViewWithPixelFormat:`, `parentTexture`, `parentRelativeLevel`,
  `newTextureViewWithPixelFormat:textureType:levels:slices:`,
  `parentRelativeSlice`,
  `replaceRegion:mipmapLevel:withBytes:bytesPerRow:` and
  `getBytes:bytesPerRow:fromRegion:mipmapLevel:`,
  `replaceRegion:mipmapLevel:slice:withBytes:bytesPerRow:bytesPerImage:` and
  `getBytes:bytesPerRow:bytesPerImage:fromRegion:mipmapLevel:slice:`.

Sampler descriptors have the SDK defaults: nearest min/mag filters, no mip
filter, anisotropy one, clamp-to-edge addressing, transparent-black border,
comparison never, normalized coordinates, LOD range zero through FLT_MAX,
and no LOD averaging or argument-buffer support. Copies have independent
configuration; labels copy NSString contents, including mutable strings.
`newSamplerStateWithDescriptor:` snapshots the descriptor and label and
retains its device. It returns nil for invalid enum values, anisotropy outside
1..16, nonfinite/negative/reversed LOD clamps, or argument-buffer support.
Unnormalized coordinates require clamp-to-edge on all axes, no mip filtering
and anisotropy one in this bounded profile. Nil, wrong-type and uninitialized
descriptors also return nil. Sampler storage and label/device references use
normal object cleanup. The descriptor class and metaclass imports are scoped
to Metal.framework and available only with the software flag. This provides
configuration objects; shader binding, texture sampling and GPU resource IDs
remain absent. Newer reduction-mode and LOD-bias properties are unsupported.

Texture views alias the full single-level 2D storage and retain their immediate
parent, including for nested views and IOSurface planes. Same-format views
are supported for all four formats; BGRA 80/81 reinterpretation requires usage
PixelFormatView (16) in this conservative profile. Other format changes return
nil. Views preserve dimensions, usage, device, plane and padded stride; CPU
transfers/blits share bytes without conversion. Parent-relative level/slice
are zero. The type/ranges constructor accepts texture type 2 and exactly
`{location: 0, length: 1}` for both levels and slices. Empty, oversized,
nonzero-base and overflowing ranges, or other types, return nil before
allocating a view. Both constructors share format validation and ownership.
Existing alias-overlap checks apply. Swizzles and texture-type changes remain
unsupported.

Textures support R8Unorm (10), RG8Unorm (30), BGRA8Unorm (80) and
BGRA8Unorm_sRGB (81). Upload/readback preserves raw bytes without color
conversion. Only shared, single-level, single-sample 2D storage is supported,
with dimensions 1..16,384 and at most 64 MiB per texture. Mipmapped descriptor
creation and unsupported allocations return nil. Textures snapshot descriptor
metadata, own zero-initialized storage and retain their device independently.
IOSurface imports instead retain the supplied local surface and borrow its
selected plane, preserving the plane's row stride even for narrower descriptors.
The CoreVideo Metal texture cache can now import BGRA (80/81), 420v and 420f
planes (10/30) through this device. CPU transfers and deferred blits access the
same bytes; no snapshot or color conversion occurs. Imports validate plane,
format, dimensions, shared storage, usage and a maximum 64 MiB addressed span.
Textures keep their surface alive independently of the pixel buffer, cache and
view. `iosurface` returns nil for ordinary owned textures. Imported aliases of
one plane share overlap checks when encoding texture copies. Mach-port and
global-ID surface imports remain unsupported. See
[Apple's surface texture API](https://developer.apple.com/documentation/metal/mtldevice/maketexture%28descriptor%3Aiosurface%3Aplane%3A%29).
Descriptor/texture state is freed through the existing CoreVideo metadata
destructor; pixel storage and device references use normal object cleanup.
Transfers validate positive 2D regions, level zero, row pitch and pointer
arithmetic before copying rows; caller memory must cover the requested span.
Pitch must be a multiple of the pixel size; zero pitch is accepted for a
single row, following [Apple's transfer contract](https://developer.apple.com/documentation/metal/mtltexture/replace%28region%3Amipmaplevel%3Awithbytes%3Abytesperrow%3A%29).
Only requested pixel bytes are touched, preserving client row padding.
Buffer-backed textures alias a retained shared buffer with a snapshot of the
2D descriptor. The device's `minimumLinearTextureAlignmentForPixelFormat:`
returns 256 for R8Unorm, RG8Unorm and BGRA8Unorm/_sRGB. Queries for other
formats fail explicitly. The allocator and query share one alignment policy;
applications can round row sizes up and align offsets using the query.
Offset and row pitch must be multiples of 256 bytes; pitch must
cover a row and be at most 64 MiB. The full addressed span must fit the buffer.
Invalid layouts/descriptors return nil. Views preserve the buffer metadata and
stride, and CPU transfers and deferred fills/blits share the same bytes.
Buffers remain alive until all texture, view and encoded-command owners release
them. Textures without buffer storage report nil/zero buffer properties.
Blits reject overlapping buffer/texture address spans. Texture aliases with
different bases or strides also reject overlapping bounding spans, including
row padding; this is a conservative restriction. Existing identical-layout
texture aliases retain their rectangle overlap checks.
The full CPU transfer selectors use the same checks and storage path, requiring
slice zero and bytes-per-image zero for this 2D profile. Invalid values reject
before accessing client bytes. They also work on views and IOSurface planes;
3D and array-slice transfers remain unsupported.

Only resource options zero (shared storage, default cache/hazards) are
supported. Buffers must have a positive length at most 64 MiB; rejected
allocations return nil. New buffers are zero initialized; bytes constructors
copy the input. A device owns no resources: each buffer/queue retains its
device, command buffers retain their queue, and encoders retain their command
buffer. Encoded copies retain source and destination until command-buffer
destruction. Autorelease ownership applies to command buffers and encoders;
device, queue and buffer creation transfer a reference to the caller.

Copies execute in encoding order when committed, under the runtime's recursive
lock. Commit completes synchronously and transitions status from 0 to 2 to 3 to 4.
Buffer fills participate in the same command order: each records a retained
destination, byte range and 8-bit value, and writes only when committed.
Ranges are byte granular; an empty range at the end of a buffer is valid.
Overflowing/out-of-bounds ranges, foreign-device buffers and ended encoders
reject before recording. Fill commands use the existing operation array and
its shared limit; they retain no source object. See
[Apple's fill API](https://developer.apple.com/documentation/metal/mtlblitcommandencoder/fillbuffer%3Arange%3Avalue%3A).
Completion means destination bytes are visible to the CPU. Commit invokes
completed handlers synchronously, in registration order, outside the runtime
lock. Handlers receive the command buffer at status 4. Registration copies the
block (including captures) and is allowed only before commit, with at most
4,096 handlers. Each copied block is released after invocation; abandoning an
uncommitted buffer releases handlers without invoking them. Commit retains
the command buffer until all handlers return. `waitUntilCompleted` waits for
both work and all handlers, including when another thread commits the buffer;
the implementation polls under short lock acquisitions. Waiting before commit
rejects, and calling wait on the same command from one of its handlers would
deadlock. Scheduled handlers follow the same copying, ordering, release and
registration rules with a separate 4,096-handler limit. They run outside the
lock at status 3 before deferred copies/fills execute. `waitUntilScheduled`
waits for all scheduled handlers to return, independently of completed
handlers, and rejects waiting before commit. Waiting for scheduling from a
scheduled callback on the same command would deadlock. These are synchronous
CPU scheduling notifications; they do not submit work to a GPU. See
[Apple's handler contract](https://developer.apple.com/documentation/metal/mtlcommandbuffer/addcompletedhandler%28_%3A%29).
Encoding cannot overlap on one command buffer; every encoder
must end before commit. Resources must belong to the queue's device. Bounds
checks use subtraction to avoid overflow; overlapping ranges in the same
buffer reject. Zero-length copies at the end of a buffer are valid. Each
command buffer is limited to 65,536 copies. Invalid encoding/state/ranges fail
explicitly. Client accesses through `contents` still require synchronization
with command submission. Shader/render methods and presentation remain absent.

Compiled-library loading accepts live dispatch data containing the existing
[MTLB v2 reader's profile](../metallib/README.md). Inputs are capped at 256 MiB
before a concatenated dispatch-data object is flattened. The library copies
the bytes, validates container ranges, unique UTF-8 names and AIR module hashes,
and retains the parsed index until destruction. Input dispatch objects can be
released immediately after creation. Only vertex, fragment and kernel metadata
are accepted, with function types 1, 2 and 3. `functionNames` returns an
autoreleased array of copied strings; each named function is a new owned handle
that keeps its library and device alive. Missing names return nil. Failure
returns nil and, when requested, an autoreleased NSError in
`MTLLibraryErrorDomain`: unsupported input/profile (1), allocation failure (2)
or malformed container (3). The domain global is available from Metal.framework.
Success leaves the error slot untouched.

These handles expose container metadata. AIR instruction verification,
specialization, pipeline creation and shader execution remain pending; even
a valid container does not establish executable LLVM IR. Source compilation
and URL loading remain unsupported. See
[Apple's dispatch-data library API](https://developer.apple.com/documentation/metal/mtldevice/makelibrary%28data%3A%29).

Filename loading uses the same validation and ownership path without requiring
dispatch initialization. It accepts nonempty NSString paths up to 1,023 UTF-8
bytes without embedded NULs. Files must be regular and at most 256 MiB; a
nonblocking open prevents FIFOs from waiting for a writer. Reads retry EINTR,
reject early EOF and check for growth beyond the stat size. Open failures
return library error 6, stat failures 2, invalid paths/file types/size 1 and
incomplete or malformed content 3. Files may be replaced or deleted after
loading; the library keeps its own bytes. Source compilation remains absent.

Default-library loading reads `default.metallib` directly from the configured
iOS main bundle resource root, using the same bounded file loader. It requires
a nonempty root of at most 1,006 bytes without NULs. `newDefaultLibrary` returns
nil on failure; the explicit bundle form reports the existing library errors
and accepts only the runtime-owned main NSBundle. Other bundles return
unsupported (1). An unset resource root returns unsupported; a missing file
returns file-not-found (6). Success transfers an owned library and leaves the
error slot untouched. No library is cached, so subsequent calls reread the
file. Neither entry point requires dispatch initialization.

Texture-to-texture blits copy positive 2D regions between textures with the
same pixel format and device. Only slice/level zero, origin z zero and depth
one are supported. Both regions must fit; this bounded API rejects out-of-range
sizes instead of clamping. Overlapping regions in the same texture reject;
disjoint regions are supported. Encoding retains both textures and records
row offsets/strides, then commit reads source bytes and copies each row in
command order. CPU uploads before commit are therefore observed. Texture and
buffer copies share one ordered command array and its 65,536-operation limit.
See [Apple's copy contract](https://developer.apple.com/documentation/metal/mtlblitcommandencoder/copy%28from%3Asourceslice%3Asourcelevel%3Asourceorigin%3Asourcesize%3Ato%3Adestinationslice%3Adestinationlevel%3Adestinationorigin%3A%29).

Buffer-to-texture and texture-to-buffer blits use the same deferred row-copy
commands. They accept the existing 2D formats, slice/level zero and positive
regions. Buffer offsets and row pitches must be pixel aligned; pitch must
cover the copied row and cannot exceed 16,384 pixels. Bytes-per-image must be
zero in this 2D profile. The full span, including padding between rows, must
fit the buffer. Only pixel bytes are copied, leaving destination padding and
neighbors unchanged. Both resources must belong to the queue's device and
remain retained until command-buffer destruction. Options-bearing selectors,
3D, compressed formats and private storage remain unsupported. See
[Apple's buffer transfer contract](https://developer.apple.com/documentation/metal/mtlblitcommandencoder/copy%28from%3Asourceoffset%3Asourcebytesperrow%3Asourcebytesperimage%3Asourcesize%3Ato%3Adestinationslice%3Adestinationlevel%3Adestinationorigin%3Aoptions%3A%29?language=objc).

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
