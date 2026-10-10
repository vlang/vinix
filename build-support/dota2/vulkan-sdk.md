# Vulkan host object adapter

`_vulkan_native.py` keeps the imported query interface and original recursive
encoding/decoding, context replay and process supervision. The optional V shared
library owns ordinary nonrecursive primitive dispatch, resolver and temporary-directory
policies, typed failure construction and callback protocol parsing/replies.
Paths, arbitrary-width integers, dictionaries, Unicode (including NUL and lone
surrogates), aliases, callbacks and exception objects remain actual CPython
objects. The recursive codec bodies remain byte-for-byte Python; their accepted
recursion depths and failure behavior receive no translation credit. Public/global/method/call/attribute/keys and context-exit target-decoding bodies also remain in the original primitive frame, preserving contextual decoder acceptance.

`vulkan_sdk_library.v` exports the synchronous CPython object entry point. The
`cpython_vulkan` guard selects the implementation under `build-support/cpythonhost`.
The calling interpreter supplies its public development headers. The loader
builds a private library lazily, or accepts `VINIX_DOTA_VULKAN_LIBRARY` as an
explicit prepared library. Its captured standard-library references serve only
library setup; policy lookups still read the actual SDK namespace and builtins.

The host V library uses the normal GC. Each native CPython reference has explicit
ownership. A stack context borrows the synchronous entry's namespace, argument
objects and error-pin list. On failure, scope dictionaries preserve the original
named expression and comprehension references in the real Python binding frame.
The pending error triple is fetched and restored around scope collection; no
exception attributes, context or traceback are changed by the native adapter.
Finite implementation literal pools preserve original constant identities and
lifetimes; caller data and session objects never enter these pools.

The same native library owns ordinary Dota preparation selection and filesystem/stdlib policies. The preparation adapter retains recursive packing, stream ownership, iteration/comprehensions and with bodies in their original Python frame. A fixed two-slot capsule owns a captured transform callable and actual result; each slot transfers once onto the Python operand stack before transformation. Explicit malloc/free allocation outlives the synchronous native call, and the capsule destructor releases unused slots. The native transformation plan preserves the original recursive packing depth instead of adding a native entry during packing.

The Python boundary retains counted syntax for argument splats, triple unpacking
and raising. Retire/context-exit bodies and their target conversion stay in the original primitive frame. Native selection preserves actual rich comparison order before handing back a fixed opcode. Recursive codecs, query child supervision,
SIGINT masking and authoritative final cleanup remain in Python. Private
translated helper replacement is outside this interface's contract. Private binding traceback frames are not an exact layout contract. An arbitrary supplied callback running near the global recursion budget can observe native bridge frames; exact callback-budget parity is outside this interface. The original recursive helpers and their maintained conversion call sites retain their original accepted depths. The stage's
signed Python reduction includes all new loader and syntax code.

Machine-local original-source comparisons and negative lifetime witnesses are
retained under `/Users/alex/.cache/vinix-python-to-v/vulkan-object-adapter-20261010/`.
Validation compares the original helper and whole staging fixture with actual
ARM64, x86-64 and ASan libraries, weak-object/error controls, references, process
retirement and cold builds. This host adapter makes no new kernel, QEMU guest,
physical Vulkan or rendering claim.
