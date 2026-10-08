# Native N64 archive builder

This module owns the pinned source download, member validation, source patches,
compiler cache keys, parallel object production and final archive/staging policy
from `build.py`. The Python entry point retains its public signatures and exact
stdlib/library objects; `tools/_package_store_native.py` supplies synchronous
borrowed calls and owned resource retirement.

Managers and entered streams/pools stay distinct. Temporary-file unlink and
guarded source-directory retirement preserve the original `finally` order,
active errors and late library lookup. A pool failure matches the actual
`Exception` class before logging; context suppression preserves the original
first-use unbound-local boundary. No kernel manual-free lifetime is changed.

Corresponding-source staging includes the existing transport and native module
producer dependencies needed by the translated entry point. Upstream source
archives and patches remain pinned, and the independent bridge fixture is
unchanged. Host qualification covers ARM64, x86_64 and sanitizer controllers,
paired complete policy plans, real byte-identical upstream host archives,
interruption, forced controller exits and cold distributed-source construction.
It establishes no fresh kernel, guest or game result.
