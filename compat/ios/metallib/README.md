# Compiled Metal library reader

`metallib.parse(data)` indexes an MTLB v2 container with explicit NAME, TYPE,
HASH, OFFT, VERS and MDSZ function records. It validates file and section
extents, non-overlap, tag-group boundaries, metadata references, unique UTF-8
function names, shared-module consistency and every indexed AIR SHA-256.
LLVM wrapper version 0 and raw LLVM streams are supported; returned bitcode
ranges exclude wrapper bytes and padding. LLVM IR itself is not verified.

The input must stay alive and immutable while using the index. Function names
borrow its bytes. Call `library.free()` once to release the two owned index
arrays, then release the input. No GPU or Objective-C runtime is needed.

Limits are 256 MiB of input, 65,536 functions, 262,144 tags and 4 KiB per
terminated function name. Unique modules must be disjoint and are hashed once;
the total hashing work cannot exceed input size. Exact shared-module aliases
are allowed. Unknown tags remain opaque and do not enable their features.

The reader is a shader-loading prerequisite. It does not create a Metal device,
interpret AIR, translate shaders, execute command buffers or present frames.
Vinix's default Metal device remains unavailable until those paths exist.

`library_test.v` constructs small containers in V, checks malformed input and
mutations, and deliberately does not treat their minimal LLVM signatures as
executable shader code. `tests/ios/metallib-inspect.v` can inspect real files,
compare function names/counts/types with native macOS Metal, and extract a
module to a fresh external `.bc` file for LLVM's independent bitcode analyzer.
Keep library files, extracted code, binaries and results outside Git.

Format references: [MetalLibraryArchive](https://github.com/YuAo/MetalLibraryArchive)
and [LLVM's bitcode wrapper format](https://llvm.org/docs/BitCodeFormat.html#bitcode-wrapper-format).
