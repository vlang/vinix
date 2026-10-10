# Native package-store object adapter

`_package_store_native.py` keeps the public `call(operation, arguments, namespace,
controller=...)` interface and the existing native-query transport. Its owned
object table, checkpoints, releases, error retirement, name resolution,
exception metadata and cleanup policy now live in
`build-support/cpythonhost/package_d_cpython_package.c.v`.

The adapter passes the caller's actual CPython objects through `ctypes.PyDLL`.
Values and aliases are held by explicit references, and a returned object gets
its own reference before its session retires. A session is attached to the
thread-local context only during an exported call. Nested calls have separate
sessions; entry on a Python thread registers that thread with the V collector
for the duration of the entry.

Context entry uses type-MRO special-method lookup and caches the exit callable
before entering, matching a Python `with` statement. Detached exit callbacks do
not keep the temporary manager alive. Custom closers retain their own manager,
condition and callable until the original cleanup boundary. Consumed exception
slots become tombstones without changing subsequent callback error IDs. Pending
exceptions and handled exceptions remain separate, and live traceback changes
remain visible to later callbacks.
Binding error IDs and the exported error-list slots belong to one active call.
Finishing the session consumes those slots; separately retained exception and
traceback objects keep their original ownership.

Native controllers may explicitly supply a module-owned finite literal cache
to the `literal` callback. Its values retain the original code's constant
lifetime across sessions; dynamic caller operands use the normal uncached
path. Fixed identifier literals and keyword names can opt into CPython
interning. The controller determines those finite literals and constant-folded
values in V; the dictionary remains owned by its counted Python module.

Controllers can opt into the `load_global` callback at an original Python
`LOAD_GLOBAL` boundary. Its `key` is the Session ID of a finite interned exact
Unicode name; `builtins` is the Session ID of that original caller frame's
builtins table. The callback uses the Session's actual globals dictionary,
returns an independently retained alias, and consults builtins only when the
name is absent. Dictionary and mapping lookup errors remain actual exceptions;
a missing name in both tables raises intrinsic `NameError`. The existing
`resolve` wire-plan callback keeps its original behavior.

The caller supplies its frame's actual table, rather than saving the module's
`__builtins__` at import or reading it again after callbacks. On CPython 3.9,
a later function call can acquire a replaced globals `__builtins__` table;
an already running frame keeps its own table. A thin controller wrapper can
capture `sys._getframe` privately and pass its caller's `f_builtins` at entry.

The counted Python adapter supplies double keyword expansion, exact pair
unpacking, dynamically named unbound locals, exception-raising syntax and the
upstream `contextlib.ExitStack` callback interface. These bindings contain no
object-table or cleanup policy. Their private failure operands are released.

The first call builds a matching V host library using the invoking Python's
public development headers. V discovery uses `build-support/find-v.sh`; this
backend requires CPython development headers and does not claim the limited ABI.
The library must match the interpreter's architecture. To build it explicitly:

```sh
build-support/build-v-host-library.sh tools/package_sdk_library.v /tmp/package-sdk.dylib \
  -d cpython_package -d use_bundled_libgc
VINIX_PACKAGE_STORE_LIBRARY=/tmp/package-sdk.dylib python3 tools/qemu-package-store.py --help
```

Normal query binaries continue using the existing process transport. The host
library implements the actual-object callbacks for those queries; it does not
change their wire format or independently establish a fresh kernel, guest or
hardware validation result. Private adapter traceback frames and post-return
cyclic-GC order are not an exact compatibility contract.
