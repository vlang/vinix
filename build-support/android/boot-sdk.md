# Native Android build-object bindings

`_boot_native.py` borrows the invoking CPython interpreter's actual objects
through `boot_sdk_library.v`. Object registration, snapshots, argument
conversion, invocation, releases and the bounded collection primitives live in
`../cpythonhost/boot_d_cpython_boot.c.v`. The caller still owns the resource
dictionary, integer IDs, error list and entered-manager table. Each native entry
borrows those objects synchronously and gives its returned value an independent
reference.

The wire codecs, archive and filesystem bindings, process transport, pool and
loader policies, and exceptional manager exits remain counted Python during
this bounded stage. Exact pair unpacking and mapping expansion are narrow
Python syntax bindings. Named objects and returned aliases remain live through
their existing owners; pending exceptions preserve the caller's handled state.
Failed native scopes retain their original local references in the binding
traceback frame until the actual error's traceback is cleared.
Private binding traceback frames are not an exact layout contract.
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
