# Software Metal backend

Build the iOS runner with `-d ios_metal_software` to enable a CPU backend for
shared buffers, shared 2D textures, buffer blits and bounded scalar compute.
`MTLCreateSystemDefaultDevice` then returns
an owned device implemented by Vinix. Without that build flag it returns nil.
This backend executes deferred buffer operations and a narrow AIR compute
profile on the CPU. Rendering, presentation and GPU execution remain absent.
It cannot yet render Fortnite.

Implemented Objective-C API:

- Device: `newBufferWithLength:options:`, `newBufferWithBytes:length:options:`,
  `newBufferWithBytesNoCopy:length:options:deallocator:`,
  `newCommandQueue`, `maxBufferLength`, `newTextureWithDescriptor:`,
  `newTextureWithDescriptor:iosurface:plane:`, `newLibraryWithData:error:`,
  `newLibraryWithFile:error:`, `newDefaultLibrary`,
  `newDefaultLibraryWithBundle:error:`, `newSamplerStateWithDescriptor:`,
  `newComputePipelineStateWithFunction:error:`,
  `minimumLinearTextureAlignmentForPixelFormat:`.
- Sampler descriptor: `init`, `copy`, `copyWithZone:`, min/mag/mip filters,
  max anisotropy, S/T/R address modes, border color, compare function,
  normalized coordinates, LOD clamps/averaging, argument-buffer flag and label.
- Sampler state: `device`, `label` (immutable configuration snapshots).
- Library: `device`, `functionNames`, `newFunctionWithName:`.
- Function: `device`, `name`, `functionType`.
- Compute pipeline: `device`, `maxTotalThreadsPerThreadgroup`,
  `threadExecutionWidth`, `staticThreadgroupMemoryLength`.
- Compute encoder: `setComputePipelineState:`, `setBuffer:offset:atIndex:`,
  `setBytes:length:atIndex:`, `setBufferOffset:atIndex:`,
  `setBuffers:offsets:withRange:`,
  `dispatchThreads:threadsPerThreadgroup:`,
  `dispatchThreadgroups:threadsPerThreadgroup:`, `endEncoding`.
- Buffer: `contents`, `length`, `device`, `storageMode`, `cpuCacheMode`,
  `newTextureWithDescriptor:offset:bytesPerRow:`.
- Queue: `commandBuffer`, `device`.
- Command buffer: `blitCommandEncoder`, `computeCommandEncoder`, `commandQueue`, `device`, `commit`,
  `waitUntilCompleted`, `addCompletedHandler:`, `waitUntilScheduled`,
  `addScheduledHandler:`, `status`, `error`.
- Blit encoder: `copyFromBuffer:sourceOffset:toBuffer:destinationOffset:size:`,
  `fillBuffer:range:value:`,
  `copyFromTexture:sourceSlice:sourceLevel:sourceOrigin:sourceSize:toTexture:destinationSlice:destinationLevel:destinationOrigin:`,
  `copyFromBuffer:sourceOffset:sourceBytesPerRow:sourceBytesPerImage:sourceSize:toTexture:destinationSlice:destinationLevel:destinationOrigin:`,
  `copyFromTexture:sourceSlice:sourceLevel:sourceOrigin:sourceSize:toBuffer:destinationOffset:destinationBytesPerRow:destinationBytesPerImage:`,
  `endEncoding`.
- Texture descriptor: `texture2DDescriptorWithPixelFormat:width:height:mipmapped:`
  plus width, height, pixel-format, usage and storage-mode getters/setters,
  `copy` and `copyWithZone:`. Copies own independent metadata and survive the
  source descriptor's autorelease pool. Allocated textures snapshot each
  descriptor. General `init` construction and other descriptor fields remain
  outside this profile.
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
are supported for all twelve formats; RGBA 70/71 and BGRA 80/81 reinterpretation
require usage PixelFormatView (16) in this conservative profile. Other format changes return
nil. Views preserve dimensions, usage, device, plane and padded stride; CPU
transfers/blits share bytes without conversion. Parent-relative level/slice
are zero. The type/ranges constructor accepts texture type 2 and exactly
`{location: 0, length: 1}` for both levels and slices. Empty, oversized,
nonzero-base and overflowing ranges, or other types, return nil before
allocating a view. Both constructors share format validation and ownership.
Existing alias-overlap checks apply. Swizzles and texture-type changes remain
unsupported.

Textures support R8Unorm (10), RG8Unorm (30), RGBA8Unorm (70),
RGBA8Unorm_sRGB (71), BGRA8Unorm (80) and BGRA8Unorm_sRGB (81).
Floating storage additionally supports R16Float (25), RG16Float (65),
RGBA16Float (115), R32Float (55), RG32Float (105) and RGBA32Float (125),
using 2, 4, 8, 4, 8 and 16 bytes per pixel respectively. CPU and deferred
transfers preserve raw floating bits, including NaNs and infinities; they do
not interpret or convert numeric values. Float views require the same format.
RGBA and BGRA are distinct view families; views cannot swizzle between them.
Upload/readback preserves raw bytes without color conversion. Only shared,
single-level, single-sample 2D storage is supported,
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
returns 256 for every supported format, including the six floating formats.
Queries for other formats fail explicitly. The allocator and query share one alignment policy;
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

The no-copy constructor instead borrows caller-owned pages. Pointer and length
must be aligned to the host page size, length must be positive and at most
64 MiB, and pointer-plus-length must not overflow. Options must be zero.
A nonnil deallocator must be a runtime block with an invoke function; creation
copies it, including captures. Invalid input returns nil before copying the
block or taking ownership. The caller must keep the entire
region mapped and writable until all buffers, textures, views and encoded
commands using it have been released. At final buffer destruction the copied
block is detached, invoked once with the original pointer/length, then released.
The callback owns memory cleanup; a nil deallocator leaves cleanup to the
caller. The runtime itself never frees/unmaps these pages. Callbacks run on
the releasing thread and may execute under a recursive runtime lock inherited
from object cleanup. Same-thread runtime calls are allowed; callbacks must not
wait for another thread that needs that lock. Contents, fills, blits and
buffer-backed textures all use the borrowed
bytes directly. Separately wrapped overlapping memory participates in alias
checks; nonempty overlapping buffer copies reject, while disjoint copies and
empty copies are valid. Access through contents still requires synchronization.

Copies execute in encoding order when committed, under the runtime's recursive
lock. Commit completes synchronously and transitions status from 0 to 2 to 3
to 4 on success, or 5 when compute execution fails.
Buffer fills participate in the same command order: each records a retained
destination, byte range and 8-bit value, and writes only when committed.
Ranges are byte granular; an empty range at the end of a buffer is valid.
Overflowing/out-of-bounds ranges, foreign-device buffers and ended encoders
reject before recording. Fill commands use the existing operation array and
its shared limit; they retain no source object. See
[Apple's fill API](https://developer.apple.com/documentation/metal/mtlblitcommandencoder/fillbuffer%3Arange%3Avalue%3A).
Completion means destination bytes are visible to the CPU. Commit invokes
completed handlers synchronously, in registration order, outside the runtime
lock. Handlers receive the command buffer at status 4 or 5. Registration copies the
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
command buffer is limited to 65,536 operations. Invalid encoding/state/ranges fail
explicitly. Client accesses through `contents` still require synchronization
with command submission. Render methods and presentation remain absent.

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

These handles expose container metadata; compute pipeline creation performs
additional AIR profile checks. General LLVM verification, specialization and
shader execution remain pending; a valid container alone does not establish
executable LLVM IR. Source compilation
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

Compute pipeline creation parses the selected module and requires a matching
classic `air.kernel` entry. It accepts only the ordinary void, one-block
[scalar memory execution profile](../airbitcode/MEMORY-EXECUTION.md), with
scalar binary arithmetic/comparisons/select/casts/fneg/freeze, pointer arguments with
supported constant GEPs,
explicit access alignment and final ret void. Calling convention and LLVM function attributes must be
zero. This is a bounded interpreter profile, not a general LLVM verifier.
Valid LLVM IR remains a precondition. No source compilation is provided.

Every argument requires explicit `air.buffer` metadata, a unique location
in slots 0..30 with count one, address space 1 or 2, and read/write/read_write
access matching the body. Space 2 is readonly. Conditional/unused arguments,
unknown attribute tails, structures and builtins reject. Declared and actual
minimum buffer extents are combined; alignment must not exceed the virtual
buffer base alignment of 256 bytes. Pipeline creation returns an owned state
retaining its function/library/device, leaves a success error slot untouched,
and uses the library NSError path for unsupported/invalid input.

Both compute dispatch selectors require grid and threadgroup dimensions
exactly `(1, 1, 1)`. The reported thread execution width and maximum group size
are one; static threadgroup memory is zero. There are no thread IDs, loops,
dynamic/negative GEP indexes, vector values, texture access, barriers or
threadgroup memory in this profile.
Setting a buffer accepts nil to clear a slot; dispatch requires every argument
to have an in-bounds, aligned binding from the queue's device. Encoding checks
state and resource requirements before recording work.

Each dispatch snapshots and retains its pipeline, buffer handles and offsets.
Later rebindings do not affect it; buffer contents are read at commit. Compute,
copies and fills share one ordered command array and limit. Aliased compute
buffers observe ordinary instruction order. Execution borrows buffer bytes
under the runtime lock, without copying or owning their storage. Dynamic
interpreter failure sets command status 5 and an owned NSError in
`MTLCommandBufferErrorDomain` (code 1); earlier writes remain visible and later
commands are skipped. The domain global is exported from Metal.framework.
Scheduled/completed notifications and waits still finish.
Clients must synchronize direct buffer access against submission.

Scalar comparison/select kernels support all ten integer predicates and all
sixteen half/float predicates. Comparisons produce i1; select chooses between
matching i1..i64, half or float values using a scalar i1 condition. Unselected
poison/undef constants are not read. Selected undef rejects and poison flows
to the existing failed-command path if stored. Comparisons and selects each
cost one step, retain zero-flags requirements, and do not add branches or
skip earlier instructions. Synthetic integer and ordered-float max kernels
exercise this path through pipeline creation and deferred dispatch.

Buffer kernels also support scalar integer width casts, signed/unsigned
integer↔half/float conversions, half↔float precision changes and raw bitcasts
between i16/half or i32/float. Casts have one-step cost and no flags. Pointer,
vector, aggregate, double and bfloat conversions remain unsupported. Invalid
float-to-integer inputs yield poison; storing it follows failed-command
completion, while an unchosen select operand may discard it. Synthetic kernels
combine signed conversion with floating addition in both directions.

Scalar half/float `fneg` toggles just the sign bit, including NaN payloads and
signed zeros. Scalar i1..i64/half/float `freeze` preserves defined bits and
chooses a fixed zero for poison/undef. Both cost one step and require no flags.
Freeze does not skip earlier dynamic errors. Synthetic deferred kernels check
raw signaling-NaN negation and freezing an invalid conversion result.

Integer add/sub/mul/shl also accept `nuw`/`nsw`, and udiv/sdiv/lshr/ashr accept
`exact`, using the scalar interpreter's poison rules. Flags do not change step
cost. Unknown/wrong-family flags and floating fast-math flags reject during
pipeline creation. Synthetic deferred kernels check defined flagged sums,
freezing overflow poison, and failed command completion when poison is stored.

Buffer kernels admit direct LLVM `ctpop`, `bitreverse`, `bswap`, `ctlz` and
`cttz` calls with the scalar interpreter's exact declaration, signature and
attribute checks. Counts/reversal support i1..i64; bswap requires a multiple
of sixteen bits. Zero-count flags must be defined literal i1 constants.
Zero input returns the width when the flag is false and poison when true;
freeze can define that result before storing. Calls cost one step and execute
inside the interpreter. Indirect calls, call-site attributes, tail calls and
fast-math calls remain unsupported. Admitted intrinsic families are these five
and the funnel/extrema/abs/saturating intrinsics below. Synthetic deferred kernels
combine all five operations and consume zero-poison results through freeze.

Direct LLVM `fshl`/`fshr` calls support three matching i1..i64 operands. Amounts
are reduced modulo the width; equal inputs produce rotations. Zero amount
chooses the first input for fshl and the second for fshr. Poison in any input
propagates and undef rejects, including at zero amount. Calls cost one step
and use the same direct-call/attribute checks as bit intrinsics. A synthetic
deferred kernel loads two inputs and an amount from buffers, executes both
directions and stores two results using checked GEPs.

Direct LLVM `smin`/`smax`/`umin`/`umax` calls support two matching i1..i64
operands, using signed two's-complement or unsigned ordering. Results preserve
the chosen input bits. Both operands are evaluated; poison propagates and
undef rejects. Calls cost one step and share the existing direct-call checks.
A synthetic deferred kernel computes all four results and stores them through
checked GEPs, exercising signed/unsigned differences with the same raw inputs.

Direct LLVM `abs` calls support i1..i64 with a literal defined i1 flag. A false
flag preserves the signed minimum's raw bits; a true flag makes that input
poison. Other values yield their absolute-value bits. Poison input propagates
and undef rejects. Calls cost one step and share scalar validation/evaluation.
Synthetic deferred kernels check both flags, ordinary negative inputs and
freezing a poisoned minimum before storing.

Direct LLVM `sadd.sat`/`uadd.sat`/`ssub.sat`/`usub.sat` calls support matching
i1..i64 operands and results. Signed operations clamp to signed bounds;
unsigned operations clamp to zero/unsigned maximum. Defined overflow
saturates; poison input propagates and undef rejects. Calls cost one step
and share scalar validation/evaluation. Saturating shifts remain unsupported.
A synthetic kernel executes all four operations with signed/unsigned boundary
inputs across four deferred dispatches and offset snapshots.

`setBytes:length:atIndex:` immediately copies 1..4,096 client bytes into an
owned internal buffer and replaces that slot with offset zero. It does not
retain the client pointer. Each dispatch retains its own buffer reference, so
later stack writes, inline replacements and explicit buffer rebindings cannot
alter recorded inline data. Nil pointers, zero/oversized lengths, overflowing
address spans and slots outside 0..30 reject. This profile requires an explicit
MTLBuffer binding for `setBufferOffset:atIndex:`; inline and unset slots reject.
An offset at the buffer end is allowed, with kernel extents/alignment checked
when dispatching. See [Apple's inline-byte API](https://developer.apple.com/documentation/metal/mtlcomputecommandencoder/setbytes(_:length:index:)).

`setBuffers:offsets:withRange:` copies handle and offset arrays for a range
within slots 0..30. The empty range at location 31 is valid without arrays;
nonempty requests require both readable arrays. Nil entries clear slots and
their offsets are ignored. All resources, devices and offsets are validated
before mutation; all incoming handles are retained before replacing any slot.
This supports swaps where only the encoder owns the buffers. Explicit single
and bulk bindings reset inline state. Updates publish all new state before
releasing replaced resources, so reentrant no-copy deallocators observe the
completed update and may make further binding changes. Recorded dispatches
retain their earlier handle/offset snapshots. All setters require active,
uncommitted encoding.

Forward constant GEPs may select scalar array/structure/vector elements and
chain from earlier GEPs. They require explicit little-endian layouts with
64-bit pointer/index widths and defined nonnegative i1..i64 literals. Known
inbounds/nusw/nuw flags use the executor's checked, nonwrapping offset profile.
Pipeline buffer extents include every derived/unused pointer and accessed byte;
dispatch validates the combined extent plus the binding offset before recording.
Derived access offsets must independently satisfy alignment. Runtime loads and
stores use the preflighted virtual offsets, never AIR-supplied host addresses.

The compute tests assemble synthetic LLVM modules with AIR metadata and check
Objective-C dispatch ABI and byte results. They do not establish compatibility
with an Apple compiler-produced compute library or native Metal execution.

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
Compute fixtures additionally require `/opt/homebrew/opt/llvm/bin/llvm-as`.
The captured development compiler reloads some headers through absolute paths
with stale lengths. The harness preserves the original generated C and replaces
only its integer-128 and libc preambles with the complete captured headers;
generated program functions are preserved. An obsolete `sigaction` forward
declaration is removed in favor of the SDK declaration. It generates C from V, compiles
and links with ASan/UBSan, and runs twice with normal and
deterministic Swift hashing. These are macOS ARM64 host checks. Leak detection
is disabled; tests assert drained runtime objects rather than retained heap
measurements. The command ABI has not yet been exercised in a Vinix guest.
