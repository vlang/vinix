# Native package-store policy

The V core owns archive validation, HTTP routing and response policy, atomic
overlay uploads, source enumeration and deterministic source snapshot assembly,
desktop staging commands and server startup/retirement. The Python entrypoint
retains its existing public functions, handler/server classes, signatures,
annotations, constants and argparse declarations.

The binding retains actual caller objects, paths, streams, iterators, exceptions
and entered context-manager values while native policy runs. Library operations
use those objects directly. Explicit exits and cleanup callbacks execute under
the original active exception; an owner becomes inactive before user cleanup so
a raised cleanup error cannot cause a second exit. Unexpected controller exit
reaps the child before unwinding remaining owners. A returned snapshot transfers
the original spool to the caller. The legacy uncaught snapshot-error branch also
keeps its original spool ownership behavior.

The shared host controller compiles the query with `build-support/run-v-tool.sh`.
`VINIX_PACKAGE_STORE_QUERY` can select a prepared query for fixture runs. Native
host programs use the host GC; this module does not change the kernel allocator.
Python stdlib HTTP, tar, filesystem and process primitives remain library
bindings. No C implementation is added or credited.

Qualification uses the complete frozen original policy and unchanged six-case
loopback HTTP fixture, then independent archive/path, caller override, wide
integer, error identity/context, suppression and owner retirement controls. The
fixture's original 100 x 10 ms startup deadline and five-second server retirement
remain intact. Prepared matching-ABI binaries qualify HTTP behavior separately
from cold compiler ownership. Earlier contention-related startup failures are
retained in the receipt instead of changing the fixture deadline.
