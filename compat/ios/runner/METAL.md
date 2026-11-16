# Software Metal backend

Build the iOS runner with `-d ios_metal_software` to enable a CPU backend for
shared buffers, shared 2D textures, buffer blits and bounded scalar/vector compute.
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
  `dispatchThreadgroups:threadsPerThreadgroup:`,
  `dispatchThreadgroupsWithIndirectBuffer:indirectBufferOffset:threadsPerThreadgroup:`,
  `endEncoding`.
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
classic `air.kernel` entry. It accepts only the ordinary void, forward-control
[memory execution profile](../airbitcode/MEMORY-EXECUTION.md), with
scalar binary arithmetic/comparisons/select/casts/fneg/freeze, pointer arguments with
supported constant and bounded argument-derived GEPs,
explicit access alignment and final ret void. Calling convention and LLVM function attributes must be
zero. This is a bounded interpreter profile, not a general LLVM verifier.
Valid LLVM IR remains a precondition. No source compilation is provided.

Pipeline creation prepares the memory function once and owns its validated
profile alongside the immutable library/index storage. Deferred dispatches reuse
that preparation while checking every current buffer binding, permission,
alignment, extent, memcpy alias and step budget before writes. Each execution
still uses fresh temporary value storage; earlier results or failures do not
carry into subsequent dispatches. The pipeline releases the prepared profile
before releasing its borrowed indexes. The focused `vector-memory` runtime test
also checks eight dispatches reusing two pipelines across two drained runtimes,
changing buffer offsets and releasing caller references before commit.

Buffer loads/stores also accept fixed 1..16-lane vectors of i8/i16/i24/i32/
i40/i48/i56/i64, half and float. Lanes occupy consecutive little-endian bytes;
half/float transfers preserve raw bits. A load captures a complete vector before
later stores, including overlapping bindings, and composes with the existing
vector operations. A store validates every lane before writing; poison or undef
rejects the complete store while preceding instructions remain visible. Byte
counts use stored size, whereas vector GEP strides use allocation size. Explicit
alignment, permissions, bounds and all-block preflight apply. Non-byte-aligned
lanes, scalable vectors, vector returns and vector PHIs remain outside
this profile. Software dispatch uses the bounded grid described below. Deferred
Objective-C checks cover raw integer/floating vector transfers and poison/undef/
freeze behavior; this adds no rendering or GPU support.

Every buffer argument requires explicit `air.buffer` metadata, a unique location
in slots 0..30 with count one, address space 1 or 2, and read/write/read_write
access matching the body. Space 2 is readonly. Conditional/unused arguments,
unknown attribute tails, structures and other builtin forms reject. Declared and actual
minimum buffer extents are combined; alignment must not exceed the virtual
buffer base alignment of 256 bytes. Pipeline creation returns an owned state
retaining its function/library/device, leaves a success error slot untouched,
and uses the library NSError path for unsupported/invalid input.

The compute profile accepts geometry builtins as `ushort`, `ushort2`,
`ushort3`, `uint`, `uint2` or `uint3` (i16/i32 scalar, pair or triple).
`air.thread_index_in_threadgroup` is scalar only. Grid positions supply x,
(x, y) or (x, y, z). Local indices flatten the position
within the actual threadgroup, with x varying fastest: `(lz * sy + ly) * sx + lx`.
Here `sx`/`sy` are the actual group width/height, clipped at a partial grid edge.
`air.threads_per_grid`, `air.threads_per_threadgroup` and
`air.dispatch_threads_per_threadgroup` accept these same six forms.
They supply the normalized grid dimensions, actual clipped group dimensions,
and requested group dimensions respectively; a scalar receives the x component.
Grid position and grid size must use matching types when both are declared.
`air.thread_position_in_threadgroup`, `air.threadgroup_position_in_grid` and
`air.threadgroups_per_grid` accept the same six forms. They supply the
local position, group position and group counts, respectively; scalars receive x.
Local positions use the requested group dimensions for their modulo, group
positions use those dimensions for division, and counts round each grid axis up
to cover partial groups. Local position, actual size and requested group size
must use matching types when declared together. Group positions/counts may use
scalar projections independently of the grid-position and local-position types.
All declared geometry vectors must have the same lane count. Local position
and local index must have matching integer widths. Named types must match the
actual integer width and shape. Dispatch limits keep every supplied dimension
and index within ushort range; existing interpreter bindings carry raw words.
The sizes are captured with each dispatch and supplied afresh to each invocation,
so a prepared pipeline can index output using the current grid dimensions.
Builtins have no buffer location and do not
require encoder buffer bindings. Each semantic may appear once; metadata can
carry an argument name and matching type name, or omit those names. Pointer,
floating, other widths/counts, duplicate semantics, buffer/access/size/alignment
properties, unused/conditional arguments and opaque tails reject. Arbitrary
by-value uniforms and other builtins remain unsupported. Builtin
words are passed through the memory API's typed value bindings and captured
before execution; library, pipeline and buffer ownership are unchanged.
A scalar builtin can directly index a supported single-index GEP. Extracted
geometry lanes can also feed bounded integer add/subtract/multiply,
signed/unsigned division/remainder, scalar integer comparisons/selects/freezes, bitwise
AND/OR/XOR, left/logical-right/arithmetic-right shifts and width casts
to form a checked buffer index, including a flattened multidimensional position.
Scalar population count, bit reversal and byte swap intrinsics may also feed
these indices, with the existing declaration and poison checks.
Leading/trailing zero counts also feed indices with a validated constant i1
zero-poison flag; their poison results compose with select/freeze.
Signed/unsigned integer min/max can clamp indices using two checked expression
dependencies, with poison propagated from either input.
Integer absolute value also feeds indices, with a validated constant i1
signed-minimum poison flag and the same select/freeze handling.
Signed/unsigned saturating add/subtract also feed indices, clamping arithmetic
overflow while preserving poison from either input.
Signed/unsigned saturating left shifts feed indices with both dependencies
checked; oversized amounts produce poison for select/freeze handling.
Funnel shifts and rotations also feed indices, validating all three inputs and
reducing the shift amount modulo the integer width.
Only argument/literal dependencies are admitted; general SSA indices remain
unsupported. The memory profile limits expression graphs to 256 nodes/32 levels.
See [Apple's thread attributes](https://developer.apple.com/documentation/metal/creating-threads-and-threadgroups).

`tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR sizes` checks reusable
scalar and uint3 pipelines under normal and deterministic hashing. Independent
group/local enumeration checks every builtin lane, both dispatch selectors,
partial and oversized groups, maximum grids, buffer offsets and untouched
padding across two drained runtimes per mode. Negative pipelines check each
size semantic's types, metadata restrictions, duplicates and family mismatches.
A single image pipeline also writes RGBA8 pixels for four image dimensions;
existing buffer-backed textures expose the exact pixels through `getBytes`.
The image kernel decomposes a linear address with remainder and exact division,
then forms row/pixel addresses with flagged shifts and disjoint OR.
An integer samesign comparison of x against grid width selects the final address
or poison, followed by a scalar freeze. Prevalidation and execution preserve the
same defined address; poison/direct undef freezes choose zero.
Two bit reversal calls then preserve that address while exercising intrinsic
dependencies in the image pipeline.
Leading/trailing zero counts then form a self-XOR zero offset. The trailing
count uses a true zero-poison flag and freeze, including at the zero pixel index.
Signed maximum with zero and unsigned minimum with 16383 then clamp the address.
Negation followed by integer absolute value restores the clamped address.
Unsigned saturating overflow and subtraction form a zero offset, followed by
signed saturating addition/subtraction that preserve the final address.
An unsigned saturating shift doubles the address before an exact right shift;
a signed saturating shift by zero preserves it for the final store.
Funnel shifts rotate the address left and right by 37, exercising modulo-width
amounts while preserving the exact address.
The fixture preserves shader output as external PPM files and verifies all
backing-buffer padding. This uses CPU buffer stores and texture aliasing;
AIR texture arguments/intrinsics and GPU rendering remain unsupported.
The size semantics follow the
[Metal Shading Language specification](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf).

`tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR group-coordinates` checks
all eight geometry semantics together in reusable scalar, uint3 and mixed
pipelines. Tiled addresses reconstruct global positions from local positions,
group positions and requested group sizes. Independent group/local enumeration
checks every returned lane, explicitly counts group origins, and verifies all
output padding. Both selectors, partial groups on every axis, maximum grids,
snapshot offsets, late bounds refusal, invalid metadata/types/duplicates and
local-position/size family mismatches run in both hashing modes with two drained
runtimes per mode. Threadgroup coordinates add no shared memory or barriers.

The `geometry-types` mode extends that fixture to all six types, scalar/uint3
mixes, 2D pairs, and explicit width/lane mismatch refusals. Its narrow kernels
zero-extend values before computing tiled addresses and storing u32 records.
Negative geometry fixtures now use i8 and one-lane vectors for unsupported forms;
historical evidence bundles retain their original checker source and results.

`tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR builtins` runs the focused
Objective-C checks with normal and deterministic Swift hashing. Each mode
executes six deferred scalar/uint3/unnamed builtin dispatches across two drained
runtimes and refuses 38 invalid builtin pipelines. Sparse/reordered metadata,
output offsets, caller-reference release and untouched padding are covered.
Scalar/unnamed cases also store through a GEP indexed by the grid-position
argument.

Forward-only branches/switches and matching scalar/overflow-pair PHIs are supported.
Conditional branches require scalar i1 and distinct destinations; all targets
must be later blocks in function order. PHIs require exactly the actual
predecessors and read only the executed incoming values. Every block is checked
before pipeline creation or execution, and buffer requirements combine all
paths. The pipeline budget conservatively includes every static instruction
and every switch's maximum case comparisons;
execution charges only the taken path. Poison/undef branch conditions error
and earlier writes remain visible. Pointer PHIs resolve during preflight when
all incoming operands have the same pointer type, argument identity and byte
offset. Direct arguments, earlier GEPs and invariant pointer PHIs may converge;
different arguments/offsets or invalid incoming pointers reject, including on
inactive paths. Aliased bindings retain distinct argument identities. Pointer
PHIs cost one executed step and may interleave with scalar/pair PHIs. Backward
edges and loops reject. Deferred dispatches exercise both paths, scalar/pair/
pointer PHIs, mixed incoming values and preserved overflow flags; a loop
pipeline rejects.

Invariant pointer selects accept a scalar i1 condition and two pointer operands
of the result type, resolving to the same argument identity and byte offset. Both arms must
be supported and equivalent, including for literal conditions; aliased bindings
retain distinct argument identities. Arguments, GEPs, invariant PHIs and selects
may feed each other. The result resolves before dispatch. Each executed pointer
select costs one step and reads its condition; poison/undef conditions error
immediately, including for unused results, retaining prior writes. Untaken
selects do not read their conditions, and scalar freeze may define a condition.
This bounded profile has no runtime pointer poison tracking.

Pointer `freeze` and same-address-space pointer `bitcast` preserve an existing
virtual buffer address. Freeze requires matching operand/result types; bitcast
requires scalar pointer types in the same address space. Arguments, GEPs,
invariant PHIs/selects and earlier pointer freezes/bitcasts may feed each other.
Each costs one executed step and resolves during preflight, preserving the
original binding's bounds, alignment and permissions. Literal null/poison/undef
pointers and integer-pointer conversions reject. Freeze
does not bypass an earlier pointer select's defined-condition requirement.

Scalar pointer `addrspacecast` preserves binding identity and byte offset
between distinct spaces 0/1/2 in this flat virtual target. Both pointer and
index widths must be 64 bits in an explicit supported little-endian layout.
Flags, literal/vector pointers, unsupported layouts and other spaces reject.
Each executed cast costs one step and may feed the existing pointer operations,
scalar accesses and memory intrinsics. Bounds, alignment and permissions remain
attached to the original binding. A space-2 argument cannot gain write access
through a cast; nonempty writes through a space-2 view also reject. Deferred
checks exercise all six cast directions, shifted bindings and derived bounds.
Pipelines reject writes through converted constant arguments and constant views.

Pointer comparisons support `eq`, `ne`, `ugt`, `uge`, `ult` and `ule` on
exactly matching pointer types resolved within the same binding. Preflight
compares their bounded offsets, including one-past addresses, without reading
the source buffer or exposing host pointer bits. Each executed comparison
costs one step and produces a scalar i1 usable by branches and selects.
Cross-binding comparisons reject even for aliased storage; signed ordering
and literal null/poison/undef pointers reject. Earlier pointer selects still
evaluate their conditions when executed.

Nonvolatile `llvm.memset` fills accept a runtime i8 byte and a defined literal
i32/i64 length through a resolved destination pointer. Nonempty fills require
space 0/1 and write permission, with the complete extent checked before stores.
Each call costs one instruction step plus one step per byte; lengths across
all blocks/calls count toward the million-step limit. Poison/undef byte values
error before that fill writes, retaining earlier stores. Zero-length calls skip
the byte and need no write permission, including for empty readonly space-2
bindings. Pointer literals, volatile/dynamic-length fills, atomic
variants, tail calls and call-site attributes other than pointer alignment
reject. Exact declarations admit
canonical writeonly/captures(none), fourth immarg and memory(argmem: write)
properties with bounded validation. Deferred fills check byte ranges, untouched
prefixes and input changes after encoding.

`llvm.memset.inline` uses the same bounded literal i32/i64 fill path, including
runtime byte evaluation, zero-length poison/undef bytes, alignment, permissions
and one step per written byte. Its declarations may also mark length immarg.
Separate declaration slots allow ordinary and inline fills in the same kernel.
The executor uses indexed byte writes without invoking external declarations
or host fill routines. Deferred checks exercise both aligned fill variants,
retained resources, inputs changed after encoding and preserved prefixes.

Nonvolatile `llvm.memmove` accepts literal i32/i64 lengths and resolved source
and destination pointers, including overlap and aliases through different
bindings. Nonempty destinations require space 0/1 and write permission; sources
may use space 2 and require read access. Full extents are derived before stores.
Zero length adds no access requirement, including for empty readonly bindings.
Each move costs its instruction plus two steps per byte and shares the same
million-step budget with fills and scalar operations. One per-run scratch array,
sized for the largest move and freed on exit, snapshots source bytes before
writing; subsequent moves see earlier writes. Exact declarations admit source
readonly/captures(none), destination writeonly/captures(none), fourth immarg
and memory(argmem: readwrite) properties. Literal pointers, volatile/dynamic
lengths, call-site attributes other than pointer alignment and inline/atomic
variants reject.
Deferred dispatches exercise both overlap directions, identical/disjoint
ranges, different bindings to one buffer, repeated moves and preserved bytes.

Nonvolatile constant-length `llvm.memcpy` shares the move overloads, bounds,
permissions, scratch storage and two-steps-per-byte budget. Its declaration
attributes also admit canonical pointer noalias. Before executing a dispatch,
the interpreter checks every memcpy's actual bound byte ranges, including
inactive blocks: partial overlap and identical ranges reject before any store
in that kernel invocation. Zero length skips that check. Backing-array address
comparisons stay private to the guard and never expose addresses as AIR values.
Deferred copies cover separate buffers, disjoint aliases, adjacent ranges and
input changes after encoding; overlapping/equal ranges produce failed command
completion with the kernel's earlier marker store untouched.

`llvm.memcpy.inline` supports the same literal i32/i64 lengths, address spaces,
bounds, alignment, permissions and preflight overlap checks as ordinary copies.
It reuses indexed byte transfers and scratch storage without invoking external
declarations or host copy routines. Its declaration also admits an optional
length immarg. Distinct declaration-cache slots permit ordinary and inline
copies in the same kernel. Deferred inline-copy checks cover separate buffers,
disjoint/adjacent aliases, retained inputs changed after encoding and failed
overlapping/equal-range commands before the marker store. Atomic variants
remain unsupported.

Memory-intrinsic call sites accept only `align N` on their pointer arguments.
Destination and source requirements combine with ordinary accesses and must
fit the virtual buffer's 256-byte base alignment. Binding offsets and derived
pointer offsets must independently satisfy alignment, including zero-length
and inactive calls. Combined properties such as `align 8 noundef` still reject.
Alignment scans share the bounded declaration-work budget and a fixed stack
cache; the cached profile owns no additional allocation. Deferred fill, move
and copy checks exercise aligned calls through the same pipeline path.

Integer switches accept i1..i64 and zero through 64 distinct defined literal
cases with matching types. Default and case destinations must be distinct
forward blocks. Each tested case costs one additional step; default paths test
all cases in encoded order. Empty switches still evaluate poison/undef
conditions. Literal metadata and duplicate values reject before stores. Deferred
dispatches check scalar/pair PHIs, case/default tags and overflowing results;
a 65-case pipeline rejects. Loops and general SSA buffer indexes remain excluded.

Both direct compute dispatch selectors accept nonempty 1D, 2D and 3D grids and
threadgroups. Each dispatch permits at most 4,096 invocations and 256 threads
per group in total. `dispatchThreadgroups` multiplies group counts by group
dimensions after checking the complete volumes; `dispatchThreads` uses the exact
grid dimensions, including partial groups on any axis. Every intermediate
product is bounded before multiplication. Zero dimensions, oversized volumes
and overflowing products reject during encoding.
The conservative per-function step bound multiplied by invocation count must
not exceed 1,000,000. The reported thread execution width is one, maximum group
size is 256 and static threadgroup memory is zero. Loops, memory-dependent indexes, texture access,
barriers and threadgroup memory remain outside this profile.
Indirect dispatch retains a same-device buffer and a four-byte-aligned offset
covering three UInt32 group counts (12 bytes). It captures the requested group
dimensions and ordinary pipeline/buffer bindings at encoding, then reads counts
once when the command executes, after preceding blits or compute operations.
Any zero count produces no invocations. Nonzero counts pass the existing volume
and instruction limits before any invocation writes; invalid counts or output
addresses fail the command. Earlier commands retain their effects. Encoding
validates the group dimensions and the instruction cost of at least one group,
even if the eventual counts are zero. Indirect command buffers and indirect
`dispatchThreads` are not supported.

`tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR indirect` checks counts
supplied after encoding by the CPU, a prior blit and a prior compute dispatch;
3D grids, maximum work, zero axes, deferred volume/bounds failures, encoding
offset/range/group refusals, retained resources and output offset snapshots run
in both hashing modes with two drained runtimes each. The ABI follows
[Apple's indirect dispatch layout](https://developer.apple.com/documentation/metal/mtldispatchthreadgroupsindirectarguments).

Setting a buffer accepts nil to clear a slot; dispatch requires every argument
to have an in-bounds, aligned binding from the queue's device. Encoding checks
state and resource requirements before recording work.

Each dispatch snapshots and retains its pipeline, buffer handles, offsets and
normalized grid/group dimensions.
Later rebindings do not affect it; buffer contents are read at commit. Compute,
copies and fills share one ordered command array and limit. Aliased compute
buffers observe ordinary instruction order. Execution borrows buffer bytes
under the runtime lock, without copying or owning their storage. Dynamic
interpreter failure sets command status 5 and an owned NSError in
`MTLCommandBufferErrorDomain` (code 1); earlier writes remain visible and later
commands are skipped. The domain global is exported from Metal.framework.
Scheduled/completed notifications and waits still finish.
Clients must synchronize direct buffer access against submission.

Before its first invocation writes, execution validates the bindings and every
indexed address for every invocation, including cold blocks and the last partial
group. Any address failure leaves this dispatch's output untouched; earlier
commands may already have written. Invocations then run serially with x varying
fastest, then y, then z, each with fresh interpreter scratch and captured builtin words.
Arithmetic poison retains partial-write behavior, including earlier invocations.
There is no GPU concurrency, barrier or inter-thread synchronization support.
No parallel-memory ordering guarantee is inferred from this serial interpreter.

`tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR grids` runs the focused
sanitized Objective-C fixture in both hashing modes. It checks scalar/reordered
buffer arguments, uint3 coordinates, local-index reset, both selectors, partial
and maximum-size grids, geometry snapshots, deferred buffer reads, padding,
encoding limits and prewrite address failures across two drained runtimes.
The old dimension refusals now use zero/oversized dimensions; nonunit height
and depth are supported.

`tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR multigrids` additionally
checks both selectors across full and partial 2D/3D groups, first/last group
selection, reordered metadata and all grid coordinate lanes. An independent
group/local nested enumeration checks every coordinate and compact local index;
the AIR fixture writes coordinates through direct local-index GEPs. Controls
cover scalar x values, late cold-address failure, poison after earlier writes,
all six hostile dimensions, combined volume limits and exact step budgets.
The [Metal dispatch documentation](https://developer.apple.com/documentation/metal/calculating-threadgroup-and-grid-sizes)
describes full and partial threadgroups; this implementation executes synthetic AIR on the CPU.
The [Metal language specification](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf)
defines local indexing and actual versus dispatch-specified group sizes.

`tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR indices` checks flattened
3D buffer copies using extracted grid coordinates, flagged integer arithmetic
and zext. Independent group/local enumeration supplies expected values. Both
selectors, partial groups, deferred inputs, output offsets and padding are
covered. A final-coordinate bounds failure and late index-expression poison
leave the complete dispatch output untouched before any invocation executes.

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
between i16/half or i32/float. Casts have one-step cost. Integer `trunc` accepts
`nuw`/`nsw` (separately or together); `zext` accepts `nneg`. Violating these
promises produces poison. Other cast flags remain unsupported.
Integer-pointer, aggregate, double and bfloat conversions
remain unsupported. Invalid
float-to-integer inputs yield poison; storing it follows failed-command
completion, while an unchosen select operand may discard it. Synthetic kernels
combine signed conversion with floating addition in both directions.
Deferred dispatch checks also cover flagged truncation and extension, freeze of
their poison results, and failed-command completion for poison stores.

Scalar integer `or disjoint` and `icmp samesign` are admitted across i1..i64.
Overlapping OR input bits or different comparison input sign bits produce
poison. Same-sign comparisons support all ten predicates; other comparison
flags, including floating/pointer flags, reject. Existing freeze/select,
poison-store and branch-condition rules apply without extra execution steps.
Deferred kernels check ordinary results, frozen poison and failed commands.

`llvm.fptosi.sat`/`llvm.fptoui.sat` convert scalar half/float to i1..i64 with
truncation toward zero, destination-range clamping and NaN-to-zero semantics.
They use integer arithmetic independent of host rounding and exception flags,
cost one step and keep poison/undef, declaration attributes and call guards.
The 256 overloads have separate cache identities. Deferred dispatch checks mix
all four signed/unsigned half/float variants in a kernel and cover infinities,
NaNs, fractions and frozen poison results.

Scalar `extractelement` can select an i1..i64/half/float lane from a fixed
constant vector or earlier supported vector result of 1..16 lanes using a runtime
i1..i64 unsigned index. All lanes are checked before dispatch, with a
per-function million-lane validation budget shared by vector operations and
extractions. Only the chosen lane is evaluated: poison propagates, selected
undef errors and out-of-range indices produce poison. Extractions cost one
instruction; vector PHIs, vector arguments/returns and scalable vectors remain
unsupported. Loaded vectors use the byte-aligned buffer profile described above.
Deferred kernels select integer/half/float representations,
preserve NaN payloads and signed zeros, freeze out-of-range poison, fail poison
stores and reject an oversized-vector pipeline.

`insertelement` replaces one scalar lane while preserving older snapshots and
other lanes' poison/undef state. Invalid or poison indices poison the new
vector; undef indices error. Later insertions can repair individual lanes.
Each insertion costs one step. Up to 4,096 static vector construction results use one
execution-owned array freed on every exit, with slots reused on loop visits.
Deferred integer/half/float kernels exercise snapshots, repairs, raw NaN/zero
bits, frozen invalid indices and poison-store command failures.

`shufflevector` combines two supported vectors of the same type, using a
constant i32 mask and an independently sized fixed result of 1..16 lanes.
Poison and legacy undef mask entries produce poison; source undef remains
undef per lane. Defined bits and older snapshots are preserved. Both inputs
and the normalized/original mask identity are checked before dispatch; lane
work charges both input counts and the output count. One executed shuffle
costs one step and shares insertion storage. Deferred kernels cover chained
length changes, both sources, poison masks, undef repairs,
raw half/float bits, command failures and oversized-pipeline rejection.

Vector `freeze` preserves defined lane bits and independently chooses a fixed
zero for each poison/undef lane. Sources may be supported literals or earlier
supported vector results of the same fixed type. Its independent
snapshot may feed any supported vector operation; repeated uses agree and
repeated freezes are idempotent. It costs one executed step, charges the full
lane count and shares construction storage. Deferred integer/half/float
kernels check mixed lane states, old snapshots, exact NaN/zero bits and
insertion/shuffle chains. Earlier undef errors and later poison still fail
commands; oversized vector freeze pipelines reject.

Whole-vector `select` uses one scalar i1 condition to choose between two
same-type supported vectors. Both arms are checked before dispatch; only the
chosen arm is read during execution. The new snapshot preserves exact bits
and lane poison/undef independently of later updates. Poison conditions
poison the whole result; undef conditions reject under the existing scalar
policy. Unchosen poison/undef lanes do not affect a defined arm. Select costs
one executed step, charges both arm counts plus the result count, and shares
construction storage. Deferred integer/half/float kernels check both arms,
condition masking, freezing, updates, snapshot preservation and failed-command
write ordering. Select fast-math flags remain unsupported.

Per-lane vector `select` uses a matching fixed i1 vector condition. Each defined
condition lane chooses the corresponding arm lane; poison conditions affect
only their own lanes, and unchosen lane poison/undef does not taint the result.
Any undef condition lane rejects at select under the bounded execution policy;
freezing the condition first chooses zero for its indeterminate lanes. Supported
literal or earlier constructed conditions receive complete preflight validation,
as do both arms. Validation work also charges the condition's lane count.
Execution reads an arm only when some defined condition lane chooses it.
The result shares existing snapshot storage and costs one executed step.
Deferred integer/half/float kernels check independent lane choices, poisoned
and frozen conditions, old snapshots, exact NaN/zero bits and partial-write
failures. Seventeen-lane condition pipelines reject.

Vector comparisons produce fixed i1 masks from matching 1..16-lane vectors.
Integer i1..i64 comparisons support all ten predicates, with per-lane `samesign`
poison. Half/float support all sixteen ordered/unordered predicates through the
existing bit-based helpers. Poison stays local to each lane; any undef input
lane rejects execution at comparison. Constant FP false/true predicates follow
the scalar policy and do not read operands. Both complete sources still receive
preflight validation, and earlier instructions still execute. Results may feed
per-lane selections, other comparisons or any supported vector operation.
Each comparison costs one step, charges both source counts plus result count,
and shares bounded construction storage. Deferred integer/half/float kernels
check masks selecting data, frozen poison, old snapshots, NaN/zero behavior and
failed-command write ordering. Floating comparison flags reject at pipeline creation.

Vector integer arithmetic and bitwise operations support all thirteen scalar
opcodes at i1..i64 with matching fixed counts 1..16. Overflow/exact/disjoint
flags and oversized shifts poison only affected lanes. Both complete sources
receive preflight validation; undef lanes reject during execution. Poison
division/remainder, zero divisors and signed-minimum/-1 reject the whole
instruction under the scalar policy. Freezing sources can repair indeterminate
lanes; freezing the result does not suppress earlier evaluation errors.
Each operation costs one step, charges both source counts plus result count,
and shares bounded construction storage. Results may feed comparisons,
selections, later arithmetic, insertion, shuffle, freeze and extraction while
older snapshots retain their state. Deferred kernels cover thirty flag variants,
local poison, strict division, frozen sources/results, chained updates and
partial-write failures.

Fixed integer vectors support `trunc`, `zext` and `sext` across i1..i64
with unchanged lane count (1..16). Truncation requires a narrower destination;
extensions require a wider one. Truncation `nuw`/`nsw` and zero-extension
`nneg` follow the scalar promise rules, producing poison only in affected
lanes. Complete literal/earlier-construction sources are checked, including
inactive blocks. Any undef source lane rejects at the cast, even for discarded
results. Freezing a source repairs indeterminate lanes; freezing a result does
not suppress earlier evaluation errors. Results retain independent snapshots
and feed other supported vector operations, including another integer cast.
Each cast costs one executed step and charges source plus result count to
shared lane work. Results share the existing 4,096 static construction slots
and execution-owned allocation. Integer, mixed, void and memory APIs use the
same integer-vector rules. Vector reshaping, pointer casts, arguments/returns,
PHIs, loads/stores, scalable vectors and
widths beyond i64 remain unsupported. `tests/ios/air-vector-integer-cast.v`
checks every width pair and flag variant against native LLVM, explicit freeze
choices and poison failures, plus source/result freezing, composition, loop
reuse, unsupported profiles and exact shared storage/work limits.

Fixed vectors support raw `bitcast` between i16/half and i32/float
with unchanged lane count (1..16), in either direction. Every bit is preserved,
including signed zero, NaN signs/payloads and signaling NaNs; no floating
arithmetic or NaN quieting occurs. Complete literal/earlier-construction
sources are validated, including inactive blocks. Poison remains local to
each lane; any undef source lane rejects at the cast, even for discarded
results. Source freezes repair indeterminate lanes; result freezes do not
suppress earlier errors. Independent snapshots compose with supported casts,
arithmetic, comparisons, selects, shuffles and extraction. Each cast costs
one executed step and source plus result lane work, sharing the existing
4,096 construction slots and execution-owned array. Mixed, void and memory
execution support these casts; the integer-only API rejects floating lanes.
Other lane formats, vector reshaping, scalar/vector casts, pointer casts,
scalable vectors, vector arguments/returns,
PHIs and loads/stores remain unsupported. `tests/ios/air-vector-bitcast.v`
checks exact native LLVM bits, complete half encodings, raw float patterns,
poison/undef, freezing, composition, snapshots, loops and shared limits.

Fixed 1..16-lane half/float vectors support unflagged `fpext`
(half to float) and `fptrunc` (float to half), retaining the lane count. They
reuse scalar integer-based conversion: widening is exact for finite values;
narrowing rounds nearest/ties-to-even with gradual underflow and signed
zero/infinity. Conversion NaNs choose the preferred positive quiet NaN.
Poison remains local; any undef source lane rejects the executed cast, even
for discarded results. Freezing sources repairs indeterminate lanes; result
freezes do not suppress earlier errors. Complete supported literal/earlier
construction sources are validated, including inactive blocks. Results keep
independent snapshots and compose with other supported vector operations.
Each cast costs one step and source plus result lane work, sharing the
existing 4,096 construction slots and execution-owned array. Mixed, void and
memory APIs support these casts; the integer-only API rejects floating lanes.
Fast-math flags, other floating formats, reshaping, vector arguments/returns,
PHIs and loads/stores remain unsupported. `tests/ios/air-vector-precision.v` checks all half encodings, both
signs of every half midpoint and its neighboring float values, deterministic
float samples, NaN choices, snapshots, composition, guards and shared limits.

Fixed 1..16-lane integer vectors support unflagged `uitofp` and `sitofp`
to half or float, retaining the lane count. Source widths are i1..i64;
signed i1 true converts to -1. The existing integer-based scalar converters
round nearest/ties-to-even, independently of host rounding; half overflow
produces signed infinity. Poison stays local. Any undef source lane rejects
at the executed cast, including discarded results. Source freezes repair
indeterminate lanes; result freezes do not suppress earlier errors. Complete
supported literal/earlier-construction sources are validated, including
inactive blocks. Results retain independent snapshots and compose with
supported vector operations. Each cast costs one step and source plus result
lane work, sharing the existing 4,096 construction slots and execution-owned
array. Mixed, void and memory APIs support these conversions; the integer-only
API rejects floating lanes. Fast-math flags, `uitofp nneg`, other formats,
reshaping, vector arguments/returns and PHIs remain unsupported. Loads/stores use
the byte-aligned buffer profile above. `tests/ios/air-vector-int-float.v`
compares every source width with native LLVM, exhausts signed/unsigned i1..i16,
and checks rounding boundaries, poison/undef, freezing, composition, loops,
unsupported profiles and shared storage/work limits.

Fixed 1..16-lane half/float vectors support unflagged `fptoui` and `fptosi`
to i1..i64, retaining the lane count. Conversion truncates toward zero,
independently of host rounding. NaNs, infinities and values whose truncated
result is outside the integer range produce poison only in affected lanes.
Negative fractions between -1 and zero convert to unsigned zero; fractional
values just below a signed minimum remain valid if truncation brings them
into range. Signed i1 has range -1..0. Any undef source lane rejects at the
executed cast, even for discarded results. Source freezes repair indeterminate
inputs, but do not repair numeric invalidity; result freezes repair produced
poison without suppressing earlier undef errors. Complete supported literals
and earlier constructions are validated, including inactive blocks. Independent
snapshots compose with integer operations and existing vector casts. Each cast
costs one step and source plus result lane work, sharing the existing 4,096
construction slots and execution-owned array. Mixed, void and memory APIs
support these conversions; the integer-only API rejects floating sources.
Nonzero flags, other formats, reshaping, vector arguments/returns, PHIs and
loads/stores remain unsupported. `tests/ios/air-vector-float-int.v` uses defined
native saturation and separate range tags, including truncation before range
checks, without executing invalid native casts.

Fixed 1..16-lane half/float vectors support direct unflagged calls to
`llvm.fabs.vNf16`/`vNf32` and `llvm.copysign.vNf16`/`vNf32`. Fabs clears
the sign bit; copysign copies only the second operand's sign bit. Every other
bit is preserved, including NaN payloads and signaling bits; no NaN quieting
occurs. Poison remains local to each lane. Any undef source lane rejects
at the executed call, even for discarded results. Source freezes repair
indeterminate inputs; result freezes do not suppress earlier undef errors.
Both copysign sources must be supported complete literals or earlier
constructions. Validation includes inactive blocks. Independent results compose
with existing vector operations and raw bitcasts. Each call costs one step;
fabs charges two lane counts and copysign three to shared work, reusing the
existing 4,096 construction slots and execution-owned array. Mixed, void and
memory APIs support these calls; the integer-only API rejects floating lanes.
Canonical overload names, exact signatures and direct declaration identity
are checked. Harmless declaration attributes use the existing bounded scanner
once per overload, with a separate 64-entry duplicate-declaration cache.
Fast-math flags, tail calls, call-site attributes, unsupported declaration
attributes, other vector intrinsics/formats, vector arguments/returns, PHIs
and loads/stores remain unsupported. `tests/ios/air-vector-sign-intrinsics.v`
checks exact native LLVM bits, every half encoding, all lane counts, poison/undef,
freezing, snapshots, composition, malformed calls/declarations and shared limits.

Fixed 1..16-lane half/float vectors also support unflagged `fadd`, `fsub`,
`fmul`, `fdiv` and `frem`, using the integer-based scalar math at the lane
precision. Rounding is nearest/ties-to-even with gradual underflow. Signed
zeros and infinities retain IEEE results. Zero divisors and invalid FP
arithmetic yield infinity or the preferred positive quiet NaN, without
poison or a host trap. Arithmetic NaNs choose `0x7e00` or `0x7fc00000`;
copying operations retain their bits. Poison propagates per lane, including
division/remainder. Any undef operand lane rejects at the binary instruction,
including discarded results; freezing sources first repairs indeterminate
lanes, while freezing the result cannot suppress prior evaluation errors.
Both complete sources are checked before execution, including inactive blocks.
Each operation costs one executed step and charges both source counts plus
result count to the shared lane-work budget. Results use the existing bounded
snapshot allocation and may feed any supported vector operation. Fast-math
flags, other formats, scalable vectors, vector PHIs/arguments/returns and vector
loads/stores remain unsupported. `tests/ios/air-vector-float-binary.v` checks
native LLVM values with arithmetic NaNs normalized, exact copied bits,
poison/undef, freezing, composition, loop reuse, rejected profiles and exact
shared storage/work boundaries. Its sweep covers every half left encoding,
permuted right encodings, deterministic float pairs and complete edge grids.

Fixed 1..16-lane half/float vectors support unflagged `fneg`, from literals
or earlier supported constructions. It flips only the sign bit, including
signed zeros, preserving NaN quiet/signaling bits and payloads. Poison is local to
each lane; any undef source lane rejects at evaluation, including discarded
results. Freezing a source repairs indeterminate lanes before negation;
freezing a result does not suppress an earlier undef error. New results
retain independent snapshots and feed further negation, insertion, shuffle,
freeze, comparison, select or extraction. Each executed negation costs one
step. The source and result lane counts charge the shared 1,000,000-unit
validation budget, and results share the existing 4,096 static construction
slots and execution-owned allocation. Preflight validates complete sources
and inactive blocks. Fast-math flags, other lane formats, scalable vectors,
vector arguments/returns and vector PHIs remain outside this bounded profile.
Loads/stores use the byte-aligned buffer profile above.
`tests/ios/air-vector-fneg.v` checks exact LLVM values,
poison/undef policy, source/result freezing, snapshots, loop slot reuse,
composition, rejected profiles and exact/exceeded storage/work limits.

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
and the float-sign/rounding/sqrt/floating-extrema/classification/fma/fmuladd/ldexp/funnel/extrema/abs/saturating/shift/bit-permutation intrinsics below. Synthetic deferred kernels
combine all five operations and consume zero-poison results through freeze.

Direct LLVM `fabs`/`copysign` support matching half/float values and results.
Absolute value clears the sign bit; copy-sign replaces it from the second
operand. NaN payloads, quiet/signaling bits, zeros, subnormals and all other
magnitude bits are preserved. Both copy-sign operands are evaluated; poison
propagates and undef rejects. Each call costs one step and shares scalar
validation/evaluation. Synthetic deferred dispatches check half/float NaNs and
signed zero with input changes after encoding and pipeline release before
commit, storing exact representations through bitcasts and checked GEPs.

Direct LLVM `floor`/`ceil`/`trunc`/`round`/`roundeven` support matching half/float
operands/results, rounding toward negative infinity, positive infinity, zero,
nearest with ties away from zero, and nearest with ties to even. Zero results
preserve input sign; infinities/integral values remain unchanged and NaNs use
the scalar evaluator's preferred quiet choice. Poison propagates and undef
rejects. Each call costs one step and shares scalar validation/evaluation
without consulting host rounding mode. Synthetic deferred dispatches check
both signs of 2.5 and 0.5 in both precisions, exact zero signs and the differing
tie rules, across four offset snapshots.

Direct LLVM `rint`/`nearbyint` support matching half/float operands/results,
rounding to nearest integral values with ties to even in LLVM's default
environment. Scalar integer bit evaluation preserves zero signs and chooses
the preferred quiet NaN. Poison propagates and undef rejects; each call costs
one step. Host rounding modes and exception flags do not participate; dynamic
or constrained FP environments and exception modeling remain unsupported.
Eight deferred dispatches mix rint/nearbyint/roundeven in both precisions,
checking both tie signs, signed zero, signaling NaNs, infinities and subnormals.

Direct LLVM `sqrt` supports matching half/float operands/results. Scalar
integer root/remainder evaluation produces roots rounded to nearest with
ties to even, independent of host rounding mode. Signed zero is preserved;
positive infinity remains unchanged. Negative nonzero inputs and NaNs use
the preferred quiet NaN choice. Poison propagates and undef rejects. Each
call costs one step. Synthetic deferred dispatches check sqrt and
sqrt-of-absolute-value for 2, -4, negative zero and the minimum positive
subnormal in both precisions, across four input/output offset snapshots.

Direct LLVM `minimum`/`maximum` support matching half/float operands/results.
Either NaN input produces the scalar evaluator's preferred quiet NaN; other
results preserve the chosen input bits, with negative zero ordered below
positive zero in both argument orders. Both operands are evaluated; poison
propagates and undef rejects. Each call costs one step and shares scalar
validation/evaluation. Synthetic deferred dispatches check both zero orders,
NaNs in either operand and infinity ordering in both precisions, across five
input/output offset snapshots.

Direct LLVM `minimumnum`/`maximumnum` support matching half/float operands and
results, preferring the exact numeric operand over either NaN class. Two NaNs
produce the preferred quiet NaN; negative zero sorts below positive zero in
both orders. Both operands are evaluated, so poison propagates and undef
rejects even with a NaN counterpart. Each call costs one step and shares scalar
validation/evaluation. Seven deferred dispatches check both zero orders, single
and paired NaNs, infinity ordering and signed subnormals in both precisions.

Direct LLVM `minnum`/`maxnum` use the scalar evaluator's permitted
`minimumnum`/`maximumnum` refinement, including when an input is a signaling
NaN. A single NaN selects the exact numeric operand, two NaNs produce the
preferred quiet NaN and negative zero sorts below positive zero. Both operands
are evaluated; poison propagates and undef rejects. Calls cost one step and
share scalar validation/evaluation, with distinct legacy/modern declaration
cache identities. Seven deferred legacy dispatches repeat the modern extrema
checks, preserving exact bits through half/float loads, calls and stores.

Direct LLVM `is.fpclass` accepts half/float and a literal defined i32 mask in
0..1023, returning i1. It distinguishes ten raw-bit classes: signaling/quiet
NaNs and both signs of infinity, normal, subnormal and zero. Empty/full masks
select none/all defined inputs. Poison still propagates and undef rejects.
Calls cost one step, share scalar validation/evaluation, and admit parameter
two's exact immarg. Each call's mask is validated even with a cached declaration.
Synthetic deferred dispatches classify all ten classes in both precisions,
checking NaNs, finite values and signaling NaNs, i1-to-i32 casts and integer
selection, across ten input/output offset snapshots.

Direct LLVM `fma` supports three matching half/float operands and result, using
the scalar evaluator's exact integer product-plus-addend and a single rounding
to nearest with ties to even. Host rounding mode does not participate. All
operands are evaluated; poison propagates and undef rejects. Each call costs
one step and shares scalar validation/evaluation. Synthetic deferred kernels
check cancellation, overflow avoidance and a subnormal tie that differ from
separate multiply/add, plus negative zero and invalid infinity multiplication,
in both precisions across five snapshots.

Direct LLVM `fmuladd` accepts the same three matching half/float operands and
result and consistently chooses the permitted fused result through the scalar
FMA evaluator. It retains one nearest-even round, poison/undef behavior and
one-step cost, independently of another backend's optional fusion choice.
Five deferred optional-fusion dispatches repeat the FMA fixture, including
cancellation, overflow avoidance and subnormal ties that differ from separate
multiply/add. FMA and fmuladd declarations keep distinct cache identities.

Direct LLVM `ldexp` accepts half/float plus a signed i32 exponent and returns
the same floating type. Scalar integer unpack/pack evaluation rounds scaling
to nearest with ties to even, independent of host rounding mode. Overflow
becomes signed infinity and underflow rounds through subnormals to signed zero.
Zeros/infinities retain their bits at extreme exponents; NaNs use the preferred
quiet choice. Both operands are evaluated; poison propagates and undef rejects.
Each call costs one step. Deferred dispatches check scaling, subnormal ties,
negative zero, overflow, NaNs and INT_MIN/MAX exponents in both precisions
across seven snapshots.

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
and share scalar validation/evaluation.
A synthetic kernel executes all four operations with signed/unsigned boundary
inputs across four deferred dispatches and offset snapshots.

Direct LLVM `sshl.sat`/`ushl.sat` calls shift matching i1..i64 values left with
signed/unsigned saturation. Amounts below the width are valid; amounts at or
above it produce poison even for zero input. Amounts never reduce modulo the
width. Poison operands propagate and undef rejects. Calls cost one step and
reuse scalar validation/evaluation. Synthetic deferred kernels check both
clamp directions, zero shift, freezing zero-input overshift poison, and failed
command completion when that poison is stored without freeze.

Direct LLVM `pext`/`pdep` calls support matching scalar i1..i64 operands and
results. Extraction packs input bits selected by a mask into low positions;
deposition scatters low input bits into the selected positions, in low-to-high
order. Zero masks produce zero; full masks preserve input. Poison propagates
even with zero operands and undef rejects. Calls cost one step and share
scalar validation/evaluation. A synthetic deferred kernel executes both
primitives and round-trip chains, checking independent masked identities with
inputs changed after encoding and the pipeline released before commit.

Direct LLVM `clmul` supports matching scalar i1..i64 operands/results. It
multiplies binary polynomials over GF(2), using XOR instead of carries and
truncating to the low result-width coefficients. Both operands are evaluated;
poison propagates even with zero input and undef rejects. Each call costs one
step and shares scalar validation/evaluation. Seven deferred dispatches check
i32/i64 products, high-bit truncation and distributive identities through
cached calls, distinct offsets and exact u64 output words.

Direct signed/unsigned add/subtract/multiply `*.with.overflow` intrinsics
support i1..i64 inputs and literal unpacked `{iN, i1}` results. Overflow leaves
both the wrapped value and flag defined; input poison propagates to both fields
and undef rejects. `extractvalue` checks pair shape, source/result types and a
single field index 0 or 1; extracted scalars can feed arithmetic, freeze/select
and stores. Calls/extractions each cost one step and share scalar validation
and evaluation. Zero/poison pair constants are supported, while general
aggregate memory/arguments/returns remain unsupported.
Seven deferred dispatches check all six i32 operations plus i64 unsigned
multiplication, keeping separate flags and wrapped values through exact u64
output words. Bad extraction and cached-call metadata reject before stores.

`freeze` accepts the supported literal unpacked overflow pairs. Defined fields
remain unchanged; poison fields independently choose zero and a direct undef
pair chooses two zero fields. Earlier scalar undef/errors are still evaluated.
Each freeze costs one step, uses the shared scalar validator/evaluator and
keeps repeated uses in the same result slot consistent. Seven deferred frozen
overflow dispatches preserve defined values/flags; additional dispatches check
literal poison/undef pairs and computed poison before storing both fields.

Unflagged overflow-pair `select` uses a scalar i1 condition and exactly matching
pair arms/result types. It reads the chosen pair and preserves both fields and
their poison tags. A poison condition poisons both fields; pair freeze can make
fixed zero choices afterward. Undef conditions and preceding errors still
reject, as do undef pair constants in either arm during preflight. Zero/poison
pair constants are supported. Each select costs one step and reuses the scalar
validator/evaluator. Deferred dispatches check both condition values, preserved
overflow flags, zero arms, unchosen poison and frozen poison conditions.

Overflow-pair `insertvalue` requires zero flags, one literal index 0 or 1,
matching source/result pair types and the selected field's exact scalar type.
It replaces that field and its poison tag while preserving the neighbor.
Defined scalars can repair poisoned fields; replacing both fields repairs the
pair. Zero/poison base constants are supported; undef bases reject in preflight
and undef replacements still error even if subsequently ignored or replaced.
Each insertion costs one step and shares the scalar validator/evaluator.
Deferred dispatches check both field replacements, neighboring values/flags,
partial poison through select/freeze, and complete repair before scalar stores.

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
Negative indexes over supported scalars and nonempty fixed aggregate paths
may step backward using layout strides. Each scaled-index prefix must stay
at or above the binding's logical base and within its extent. Negative
multi-index paths may include packed/unpacked/nested nonzero structure fields;
field offsets and scaled indexes are applied in traversal order. Earlier
prefixes retain their full extent even if the final pointer is lower.
The binding offset supplies no extra headroom. Plain, nusw and inbounds forms
are supported; nuw, zero-stride negative indexes, scalable layouts and
unsupported computed/poison/undef/wide indexes reject
before stores.
Pipeline buffer extents include every derived/unused pointer and accessed byte;
dispatch validates the combined extent plus the binding offset before recording.
Derived access offsets must independently satisfy alignment. Runtime loads and
stores use the preflighted virtual offsets, never AIR-supplied host addresses.

A single-index GEP may instead use an admitted argument-derived integer expression, with a
fixed base (possibly an earlier constant GEP) and fixed allocation stride.
Each execution masks argument words, evaluates the pure expression with the
ordinary integer poison rules, rejects negative final values and
checks every resolved pointer/access against the current buffer extent and
alignment before writes, including cold blocks. Offset arithmetic cannot wrap
or exceed 64 MiB. Unused pointers permit one-past addresses. Indexed pointers
can feed direct loads/stores only; pointer flow, further GEPs and memory
intrinsics reject. Static pipeline minimum sizes cover the fixed component;
execution also checks the resolved per-call addresses across the admitted grid.
Grids beyond the limits above remain unsupported.

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
