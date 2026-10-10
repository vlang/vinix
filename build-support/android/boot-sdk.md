# Native Android build-object bindings

`_boot_native.py` borrows the invoking CPython interpreter's actual objects
through `boot_sdk_library.v`. Object registration, argument
conversion, invocation, releases and the bounded collection primitives live in
`../cpythonhost/boot_d_cpython_boot.c.v`. The caller still owns the resource
dictionary, integer IDs, error list and entered-manager table. Each native entry
borrows those objects synchronously and gives its returned value an independent
reference.

Recursive snapshot traversal retains its original Python body, recursion limits,
and failure-frame ownership. Snapshot result conversion also stays in the original Python primitive frame
so an active native bridge does not reduce the accepted recursion depth. The
original operation comparisons remain in that frame; selected nonrecursive
bodies execute in V.
The wire codecs, archive and filesystem bindings, process transport, pool and
loader policies, and exceptional manager exits remain counted Python during
this bounded stage. Exact pair unpacking and mapping expansion are narrow
Python syntax bindings. Named objects and returned aliases remain live through
their existing owners; pending exceptions preserve the caller's handled state.
Failed native scopes retain their original local references in the binding
traceback frame until the actual error's traceback is cleared.
Private binding traceback frames are not an exact layout contract. Near-limit
recursion performed inside an arbitrary supplied callback can observe the
native bridge stack overhead; exact global recursion-budget equivalence inside
those callbacks is outside this interface. Recursive helpers and their
maintained result-conversion call sites preserve their original accepted depth.
Replacing a translated private helper's Python body is outside this adapter's
contract; its public signature and supplied-object behavior remain supported.

The first native call builds a host library using `build-support/find-v.sh` and
the invoking interpreter's public development headers. This backend requires
matching CPython headers and architecture; it does not claim the limited ABI.
To use a separately built library:

```sh
build-support/build-v-host-library.sh build-support/android/boot_sdk_library.v /tmp/boot-sdk.dylib \
  -d cpython_boot -d use_bundled_libgc
VINIX_ANDROID_BOOT_LIBRARY=/tmp/boot-sdk.dylib python3 tests/alloc-bench/test_v_bench.py --help
```

This host adapter does not establish a new kernel build, guest boot, hardware
result or benchmark measurement.

The standard-library primitive dispatcher is native V in
`cpythonhost/boot_stdlib_d_cpython_boot.c.v`. It evaluates the original rich
operation comparisons in order and calls the caller's actual Path, archive,
subprocess and module objects. Fixed operand names have a finite strong literal
pool; dynamic arguments are not cached. The original named locals remain owned
through a saved error, and unnamed receivers retire before detached methods run.

Python retains the actual keyword expansion, comprehensions, conditional tuple
selection, archive context managers, deterministic ZipInfo construction and
import-loader syntax in `_boot_stdlib_syntax`. Those leaves and the independent
fixtures receive zero translation credit. Qualification compares actual files,
archive contents, subprocess results, error identity and object retirement on
ARM, x86 and sanitizers. It does not establish fresh kernel, QEMU or device results.

Delegated syntax transfers its genuine original named locals to one dictionary
in the original local-variable order, then clears the temporary binding frame
and its cached locals view. Native duplicate references retire before that
owner. A successful call releases the dictionary immediately; a saved error
keeps it until its traceback retires. This preserves path, method, archive and
context-manager destruction order across the split implementation.
