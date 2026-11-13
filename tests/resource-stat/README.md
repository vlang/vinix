# Resource stat snapshots

Run from the repository root with a working V compiler:

```sh
CC=clang v run tests/resource-stat/probe.v
```

The probe compiles the production optional resource dispatcher and VFS copy
helper against the actual `Resource` and `Stat` contracts. Only the resource,
clock, lock, event, and errno storage is replaced. It checks cached local
resources, repeated remote refreshes, unlinked-file attributes, server error
propagation, unchanged output on failure, and resource pins released on both
success and failure. Local pathname stats never run a close callback. It also
inspects generated C for allocations in the dispatch and copy functions.

`fstat`, `fstatat` (including `AT_EMPTY_PATH` and the current directory), and
anonymous `/proc` descriptor stats use this helper after their existing access
checks. Descriptor lookups retain the FD until the snapshot completes; path
and current-directory queries retain the resource across a blocking refresh.
Remote providers return the snapshot while holding their own lock; providers
without the optional capability retain the cached-stat behavior.

This host probe does not execute syscalls in a booted kernel. The 9P and NFS
facade suites exercise their concrete remote snapshots; the SMB guest suite
includes a retained-descriptor host-edit case. Generated files stay under
`TMPDIR` and are removed after a successful probe.
