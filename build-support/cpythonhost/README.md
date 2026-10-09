# Optional CPython object backend

This V module borrows actual CPython objects through a thin `ctypes.PyDLL`
adapter. The API is intended for host libraries built with `-d cpython_host`;
normal query executables keep their existing process transport and do not need
Python development headers. It uses the matching interpreter's public CPython
headers and was qualified with Python 3.9; it does not claim the limited ABI.
It owns each object
ID with one reference. Explicit releases remove the ID before decrementing its
reference. Nested calls have separate thread-local contexts. Python threads
register with the host collector only for the duration of a native entry.

Raised exceptions and handled exceptions are separate. Saved exceptions keep
their actual current traceback; entered managers are consumed before exit.
Context entry binds special methods through the actual type MRO and caches
the exit callable before invoking entry, as a Python with statement does.
Normal callback boundaries check Python signals, while retirement paths finish
the current unwind. Returned objects receive their independent public reference.
The adapter retains only two Python syntax bindings: double keyword expansion
and exact pair unpacking. Their private invocation operands retire on failure.

The initial opt-in scope is the four verified-root helpers: command conversion,
filesystem block parsing, loader enrollment and byte mutation. The main workflow
and guest supervisor still use their existing backend. Build a matching host
library and select it explicitly:

```sh
build-support/build-v-host-library.sh tests/verified-root/runtime_library.v /tmp/runtime.dylib
VINIX_VERIFIED_ROOT_RUNTIME_LIBRARY=/tmp/runtime.dylib python3 -c \
  'import runpy; runpy.run_path("tests/verified-root/runtime.py")["command"](["/bin/echo", "native V helper"])'
```

The library must match the Python interpreter's architecture. `V` and
`VINIX_V_COMPILER` follow the existing compiler discovery; `VINIX_HOST_PYTHON`
selects the interpreter whose public development headers are used. Compiler
flags can follow the output argument. Qualification covers ARM, Rosetta x86,
sanitized native libraries, actual tamper FD exchanges, weak aliases, nested
callbacks, Python threads and SIGINT. This is a host backend foundation with no
Python reduction credit, kernel change or new guest-boot claim.
