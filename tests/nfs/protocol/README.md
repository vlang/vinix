# NFS production protocol and facade fixtures

Use an existing complete V compiler/vlib; no dependencies are installed:

```sh
V=/absolute/path/to/v /absolute/path/to/v -cc clang \
  -o /tmp/nfs-protocol-tests tests/nfs/protocol
V=/absolute/path/to/v /tmp/nfs-protocol-tests "$PWD" --keep --negative
```

If a relocated compiler has a baked-in missing library path, supply the matching
library explicitly with `VFLAGS='-path /absolute/path/to/vlib|@vmodules'` to both
commands. Record the actual compiler version; passing with another version does
not qualify the production compiler.

The runner builds and executes wire/XDR and facade suites with `-gc none
-manualfree`, and generates Linux amd64 C. `--keep` preserves assembled source,
C and binaries. `--negative` additionally compiles three disposable mutants
that restore the reviewed old behaviors. Each must fail its designated runtime
assertion; a compilation failure does not count as a rejected negative control.
Mutations are confined to assembled fixture sources and restored afterwards.

The repair regressions cover:

- Eight populated failed instances with 512 identities, several directories and
  production dot nodes. Fixed-storage `track_heap` callbacks require live V
  allocations and bytes to return to zero after every cleanup. A probe verifies
  the compiler actually implements the hooks. This measures manual V heap
  allocations in the host fixture, not kernel slabs or guest RSS.
- Refresh queued at backend unlock across normal VFS rename and all three
  overlay backing rename publication windows. Same/cross-directory file and
  directory cases require the original live identity, consistent maps/parent/
  dot redirect, and subsequent REMOVE/RMDIR. The publication windows and adopt
  body are extracted from production sources. Locks assert ownership and run
  the queued callback serially: this is deterministic interleaving evidence,
  not proof of real scheduler or memory-order behavior.
- NFS rejected exchange, stale source/destination snapshots, dead-session
  guard release, local fallback rename/exchange, and overlay atomic-whiteout
  fallback success/failure.
- Both production statfs syscall bodies and the actual resource dispatcher:
  successful NFS statistics, denied FSSTAT, transport/dead-session errors,
  usercopy EFAULT, infallible local providers and the default provider.
  Path/fd/policy/usercopy services are fixture implementations.

The generated-C allocation check covers 21 wire/resource/publication functions,
including failed cleanup and both optional-capability dispatchers. Production
kernel builds, allocation allowlist checks and QEMU/runtime qualification remain
separate parent-owned gates. Successful boot retention stays at four sessions
and 512 identities per session including retired identities.
