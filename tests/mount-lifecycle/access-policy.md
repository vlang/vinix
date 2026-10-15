# Access queries and mount policy

`faccessat` and `faccessat2` now retain the selected mount route while checking
pathname, empty-path descriptor and cwd targets. Their credential-aware lookup
uses the same existing walk body with a caller-supplied cursor. Other callers
keep the original wrapper, which initializes its own cursor.

Execute access to a regular file on a `noexec` attachment returns `EACCES`.
After existing permission checks, write access to a nonspecial file on a
read-only attachment returns `EROFS`. Character devices, block devices, FIFOs
and sockets retain their write-query exception: accessing them does not write
the containing filesystem. `noexec` does not deny directory search or execution
queries on a symlink inspected without following it.

The existing policy, MAC, DAC/ACL, real/effective credential selection, anonymous
descriptor handling, flag validation and cleanup remain. The new cwd lookup
failure uses the same string cleanup as existing directory lookup failures.
The change adds a stack cursor and copies contexts by value; it introduces no
heap owner, retained stack address, reference-count transition or new free.

[Linux v6.12 `do_faccessat`](https://github.com/torvalds/linux/blob/v6.12/fs/open.c)
uses this ordering: regular-file `noexec`, inode permissions, then read-only
write checks with the special-file exception. These queries do not reserve
write access or replace authorization at the actual operation.

Use `--case access` or `ac-0` through `ac-9`. Native `all` and Linux
`move-reference` include all ten cases:

| Case | Routes and policy exercised |
| --- | --- |
| 0 | Directory descriptors, both read-only/writable bind directions |
| 1 | Descriptors opened after a namespace copy, both directions |
| 2 | Separate chroot root and cwd aliases, both directions |
| 3 | Absolute paths with invalid dirfds and symlinked parents, both directions |
| 4 | A read-only directory retained after lazy detach |
| 5 | Descriptors retained after a worker namespace retires |
| 6 | Read-only source and writable bind established before querying |
| 7 | Descriptors inherited across a namespace copy with unchanged flags |
| 8 | `noexec` on either bind, combined read-only/noexec ordering, directory search and symlink no-follow |
| 9 | Real UID 1000/effective UID 0 traversal differences, `AT_EACCESS` and empty-path file queries |

Each regular-file matrix repeats all eight permission combinations sixteen
times through legacy `faccessat`, four `faccessat2` flag combinations and three
empty-path descriptor combinations. Root and UID/GID 1000 run the read-only
matrix. File and parent metadata/timestamps remain unchanged. Directory/cwd,
symlink and FIFO/character/block-node queries cover their distinct behavior.
A protected file returns `EACCES` before a read-only error for UID 1000.
Device nodes are queried as inodes and never opened. Socket exception code and
the unchanged anonymous branch are inspected in generated C; this fixture does
not add runtime socket or anonymous-descriptor coverage.

Evidence from 2026-10-15 is retained under `build/development17-20261013`:

| States | Result |
| --- | --- |
| `mount-access-{arm,x86}-ac-{0,4,5}-before-a` | Previous kernels incorrectly grant write queries through live, detached and retired read-only attachments. |
| `mount-access-{arm,x86}-ac-8-before-a` | Previous kernels incorrectly grant execute queries through `noexec`. |
| `mount-access-{arm,x86}-access-after-a` | All ten corrected native cases pass. |
| `mount-access-arm-all-after-a` | The cumulative native mount suite passes, including inode flags, writer lifetimes, node creation and access queries. |
| `mount-access-{arm,x86}-linux-a` | The same final probe ELFs pass the portable Linux 6.12.51 suite. |

| Architecture | Kernel SHA-256 | Shared native/Linux probe SHA-256 |
| --- | --- | --- |
| aarch64 | `4ccc41117b590f028b530bcbbb7a2f27ee1333c4e1f375be12a86aee34b5db64` | `25d0c93715a789731514d53baf1e41bd3f98aa43dd0fdd89204be8723f706c05` |
| x86_64 | `adaaaa484ac12554e31f31074e6ce51e7318ec2d6b48f84c8ca0cabd93976d98` | `6de2b309065a5edbc486eddff3cd00eff0a29cd5e7b4e5c5112346e5d7444679` |

Both isolated builds start from the qualified node-creation inputs, changing
only `kernel/fs/vfs.v`. Complete manifests, sources, generated C, kernels and
hashes are preserved in `mount-access-{arm,x86}-input`. The frozen baseline
still excludes the pre-existing open-created VFS hunks, staged pointer-return
spelling edits and earlier fcntl/descriptor/lock changes described in
[the writer qualification](writer-policy.md). The complete current checkout
kernel was not built or booted.

Builds use V source `f6358ecff9cffbf2d8b03e6a09269aac7707e26c`, compiler SHA-256
`f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39`
and link seed 17. Native ARM uses HVF/four CPUs; x86 uses TCG/two, with
1024 MiB. Linux uses HVF/TCG, two CPUs and 512 MiB. Focused native timeouts are
300/900 seconds; the cumulative ARM suite and Linux use 600 seconds.

The assertion-enabled source/C audit compares all parsed namespace-qualified
generated functions with the previous build after temporary/discard number
normalization. Only the credential wrapper, access syscall and permission helper
change; one credential helper is added. The new helper equals the old complete
walk body. The wrapper retains initialization and delegates that body. The
complete syscall matches after context capture and routed dispatch; the added
cwd failure reproduces existing directory-lookup cleanup. Removing the reviewed
`noexec` and read-only guards and added cursor parameter makes the complete
permission helper match. Per-architecture `access-c-audit.txt` and
`mount-access-source-evidence-b.log` retain the results.

`mount-access-evidence-a.log` verifies all twenty-one fixture hashes, artifacts,
receipts, boot images, shared probe/C identity, old-kernel controls and native/
Linux positive markers. The post-commit audit compares the committed helpers
and syscall with both isolated inputs and accounts for the same three excluded
open-created VFS hunks. Other sessions' staged VFS edits stay separate.
Older completed boot images may be losslessly archived as `test.iso.gz`; their
decompression hashes are verified before removing originals. Sources, probes,
kernels, logs and receipts remain available.

Divergent inherited-FD remount flags, concurrent mount/cwd/namespace changes,
broader ACL/MAC/attribute combinations, device I/O and persistent/overlay
integration remain open. There is no allocation-flatness or mount reclamation
claim. A new cumulative native x86 run and desktop performance scenarios are
outside this qualification. Full OCI/rootless acceptance and roadmap section 17
remain in progress.
