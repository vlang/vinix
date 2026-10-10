# Native Roblox staging policy

`robloxstage/policy.v` owns native-runtime provenance, manifest construction,
launcher inventory and permission checks, staging preparation and publication
sequencing. `build.py` keeps the existing public functions and command line.
The controller borrows the caller's actual CPython Path, mapping, runtime-reader
and filesystem objects through the existing Package Session ABI. Values retain
their Python widths, rich comparisons and exception identities.

One dictionary owns each original function's named locals in their original
order. Native temporary references retire before that owner. Successful calls
release it immediately; saved exceptions keep it through their traceback.
Fixed operands use a finite strong literal pool. Dynamic paths and results are
never added to that pool.

Python retains the original streaming digest and module imports, launcher-file
comprehension, manifest read exception handler, temporary-directory context and
publication rollback handler. Those syntax bindings, the command line and the
independent `tests/roblox/build-test.py` fixture receive zero migration credit.
The publication handler still restores the prior stage when replacement fails.
The temporary-directory context still decides whether to suppress an error.

The first native call builds a private host library and controller using
`build-support/find-v.sh`. Both use the invoking CPython's architecture and
development headers. `VINIX_PACKAGE_STORE_LIBRARY` and
`VINIX_ROBLOX_STAGE_QUERY` may select separately built artifacts. Cold owners
use private temporary directories and retire at interpreter exit.

Validation compares the unchanged real-files staging fixtures and supplied
objects with the original Python implementation on ARM, x86 and sanitizers.
This host-policy change establishes no new Roblox, Android, GPU or QEMU result.
