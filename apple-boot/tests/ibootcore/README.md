# iBoot host helpers

The maintained V implementation owns the seven binary construction helpers in
`qemu_iboot.py`: alignment, C strings, 32-bit and 64-bit packing, Apple DeviceTree
nodes and the synthetic tree, and revision-2 boot arguments. The Python public
signatures, annotations and defaults remain the caller interface. The existing
QMP controller, assembly builder, real IORegistry tree workflow and
main parser are unchanged in this stage.

The V library uses the calling CPython's public object API. Arithmetic keeps
Python integer widths and overloaded operators. Imported packers, constructors
and helper callbacks are borrowed before their arguments are evaluated, and
actual results and errors remain Python objects. Named locals stay owned across
callbacks and are retained in the saved Python entry frame on failure; temporary
operands retire at their original expression boundary. Fixed attribute names,
text and numeric constants have a finite native implementation lifetime pool,
matching the original code's literal ownership. Dynamic formatted strings and
caller-supplied values do not enter those pools.

The library builds lazily through `build-support/build-v-host-library.sh`, using
`build-support/find-v.sh` and headers from the calling interpreter. An explicit
`VINIX_IBOOT_HELPER_LIBRARY` selects a previously built library. Cold outputs have
mode 0700 and their temporary owner is registered for exit cleanup. The bridge
holds the GIL and registers only otherwise unregistered native threads with the
V runtime before entry.

Qualification uses independent original Python helpers, callback/error/lifetime
controls, saved traceback retirement, repeated calls, nested calls and threads
on ARM, x86 and sanitizers. Boot-artifact guards parse the generated ADT, inspect
both boot-argument modes and cross-compile the unchanged ARM handoff assembly.
This helper stage does not claim a new kernel build, QEMU boot or physical Apple
hardware validation. Its original Python scope is 3,404 bytes across 76 lines;
net Python reduction accounts for the shared lazy loader added to the frontend.

The PNG writer now also lives in V. It preserves framebuffer row slicing,
channel conversion, chunk ordering, CRC calculation and compression policy,
using the actual imported Python objects and their overloaded operations.
Independent guards compare complete PNG bytes, parse every chunk and inflate
the image, including the full framebuffer. Callback, saved-error, repeated
file/FD, nested-call, thread and fixed-literal controls check lifetime boundaries.
The counted Python frontend keeps the one-item unpack and nested function
syntax; it contains no PNG algorithm. This stage removes 856 original
Python bytes across 17 lines; net Python reduction is 307 bytes.
