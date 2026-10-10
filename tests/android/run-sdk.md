# Android runner object bindings

`_run_native.py` binds the runner's V policy to actual CPython objects. Its
encoded argument conversion, provider selection, and
36 value/callback operations live in `cpythonhost/run_d_cpython_android_run.c.v`.
Recursive snapshot traversal and its result-conversion branches retain their
original Python frames and recursion behavior. Native selection returns before
those branches run, preserving contextual accepted depth.
The Python parser, process controller, thread startup, archive/stream managers,
error reconstruction, and cleanup retain their separate implementations.

The optional library is built against the invoking CPython's public headers
by `build-support/build-v-host-library.sh`. It requires the matching interpreter
ABI. `VINIX_ANDROID_RUN_LIBRARY` can select a prebuilt library; otherwise the
adapter builds and owns a temporary library directory. The runner query has
its separate `VINIX_ANDROID_RUN_QUERY` override and process lifetime.
The private installer captures its compiler, filesystem, and ctypes operands
at module import, so supplied policy providers are used only by policy calls.

V borrows the live namespace and preserves supplied objects, aliases, actual
standard-library factories, callback targets, keyword mappings, integer widths,
and exception objects. Private helper bodies being translated are implemented
in V; replacing those old bodies or inspecting their frame layout is outside
this interface. Near-limit recursion inside an arbitrary supplied callback can
observe native bridge stack overhead; its exact global recursion budget is
outside this boundary. Recursive helpers and maintained result-conversion call
sites preserve their original accepted depth. Operation selection preserves
the original rich comparison and truth sequence.

Small Python bindings retain unpack, lambda, starred-call, and keyword-call
syntax. A call's fixed operand table owns explicit CPython references. A public
CPython capsule borrows that table during a synchronous syntax call, and each
operand is transferred once to the Python evaluation stack. The table is
explicitly allocated and freed after the call; both syntax and transfer frames
clear the capsule on every return and failure. Nested calls use separate tables.

Failed named scopes and comprehensions are retained by the actual binding
traceback. They are released when that traceback is cleared; no attributes,
context, or replacement traceback are added to the error. Temporary references
retire at their expression boundaries under the incoming exception context.
The host runtime uses V's garbage collector for V scaffolding; CPython references
have explicit ownership. No kernel allocation or guest behavior changes here.
