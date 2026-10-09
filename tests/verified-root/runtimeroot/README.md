# Native verified-root runtime helpers

`runtime_query.v` compiles the maintained V command argument conversion,
filesystem block parsing, loader enrollment, byte mutation and the authenticated
fixture/scenario workflow.
The Python module retains the public call signatures and borrows the caller's
actual paths, tool callbacks, boot metadata and standard-library managers.
The shared package-store transport keeps entered values distinct from their
managers and consumes each exit once, including suppressed exceptions.

The parser, early log-directory guards and guest supervisor remain in Python.
The native workflow preserves the source/ext2/Merkle/bootstrap construction,
Secure Boot loader restoration and all corruption/policy scenarios. Named
objects live through their original scopes; temporary managers and expression
operands retire at their original boundaries. Independent controls compare the
frozen original with the production V core on ARM, Rosetta x86 and ARM
sanitizers. Actual host fixture qualification compiles the unchanged independent
guest C fixture for both architectures and builds/verifies ext2 and Merkle images.
It does not claim a new kernel build, QEMU enforcement, physical
storage operation or enabled firmware Secure Boot.

`VINIX_VERIFIED_ROOT_RUNTIME_QUERY` overrides the executable; default builds
follow the repository's compiler discovery and native host installer.
