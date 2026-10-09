# Native Mesa builder

`mesa_query.v` owns the Lavapipe builder's hashing and library inventory,
source preparation and patch checks, sysroot assembly, command/log policy,
cross-file generation, ELF checks and complete cached build sequence.
`mesa-build.py` preserves its parser, constants, generated LLVM shim and
public function signatures. The existing generic package bridge borrows
Python path, import, subprocess, archive and context-manager objects.

Keep the manager distinct from its entered stream. Consume each entered
owner once before exit, including suppressed errors, and preserve the
original unbound `result` behavior after a suppressed logged command.
The query has its own process session and ignores SIGINT; the Python caller
owns command interruption and query retirement.

The generation keeps the original provenance fields and adds a separate
`native_builder` field for maintained V sources, bindings and symlink
identities. Changes to any of these inputs must invalidate the artifact.
Upstream Mesa and its generated LLVM configuration shim remain unchanged.
