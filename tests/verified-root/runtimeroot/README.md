# Native verified-root runtime helpers

`runtime_query.v` compiles the maintained V command argument conversion,
filesystem block parsing, loader enrollment and atomic byte mutation policy.
The Python module retains the public call signatures and borrows the caller's
actual paths, tool callbacks, boot metadata and standard-library managers.
The shared package-store transport keeps entered values distinct from their
managers and consumes each exit once, including suppressed exceptions.

The guest supervisor, complete scenario workflow and parser remain in Python
in this helper stage. Its independent controls compare the frozen original
with the production V core on ARM, Rosetta x86 and ARM sanitizers. Host helper
qualification does not claim a new kernel build, QEMU enforcement, physical
storage operation or enabled firmware Secure Boot.

`VINIX_VERIFIED_ROOT_RUNTIME_QUERY` overrides the executable; default builds
follow the repository's compiler discovery and native host installer.
