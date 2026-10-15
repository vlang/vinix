# Removal attachment policy

`unlinkat`, including `AT_REMOVEDIR`, now carries the starting directory's mount
route through the removal walk. Inode-only inference could falsely reject
writable aliases or remove entries through live, detached or retired read-only
routes when another alias was writable.

The syscall captures the directory and attachment together. Its private helper
walks with that stack context and checks attachment and backend read-only state.
The public helper used by initramfs setup initializes its route under the VFS
lock and keeps the conservative inode fallback. The complete existing removal
body retains its authorization, immutable/append-only, mount-point, file-type,
empty-directory and cgroup checks. Backend failure handling, notifications,
parent/resource pins, orphan publication and deferred cleanup keep their order.
No new owned allocation, retained context address, release or reference-count
transition is introduced.

[Linux v6.12's `do_unlinkat` and `do_rmdir`](https://github.com/torvalds/linux/blob/v6.12/fs/namei.c)
also require a writable destination mount before removing an entry.

Use `--case unlinks` or `up-0` through `up-7`. Native `all` and Linux
`move-reference` include the group. Each route pair sets the directory mode to
`0755`, then repeats sixteen rounds of regular-file, symlink and empty-directory
creation/removal. Read-only removal must return `EROFS`, preserve the entry's
identity, type, size, mode and ownership, and leave parent metadata and
timestamps unchanged.
A UID/GID 1000 child repeats those preservation checks with `EACCES` through the
writable alias and `EROFS` through the read-only alias. One authorized removal
round precedes these denial checks, so an old kernel's false writable refusal
is reported directly.

Successful removal must make the name disappear through both aliases while a
held description retains its identity, ownership and mode. Removed regular-file
descriptions still read `MOUNT-OK`. The symlink stores `marker` and its removal
leaves that marker's content intact. Removed-directory descriptions still allow
`fstat`. These checks exercise existing lifetimes; they do not measure flat
allocation counts or qualify mount reclamation.

| Case | Routes exercised |
| --- | --- |
| 0 | Directory descriptors, both bind-policy directions |
| 1 | Descriptors opened after a namespace copy, both directions |
| 2 | Chroot root and cwd through separate aliases, both directions |
| 3 | Absolute destinations with invalid dirfds and symlinked parents, both directions |
| 4 | Read-only bind retained through directory descriptors after lazy detach |
| 5 | Descriptors retained after a worker's private namespace retires |
| 6 | Read-only source/writable bind established before the first operation |
| 7 | Directory descriptions inherited across a namespace copy with unchanged flags |

Divergent inherited-FD remount flags, concurrent remount/setns/chdir, mounted-entry
and invalid-flag error precedence, broader sticky/ACL/MAC/attribute combinations,
and persistent/overlay backend integration remain outside this qualification.
Hard links, rename, full OCI/rootless acceptance and roadmap section 17 remain
in progress.

Evidence from 2026-10-15 is retained under `build/development17-20261013`:

| States | Result |
| --- | --- |
| `mount-unlink-{arm,x86}-up-{0,7}-before-b` | Previous kernels falsely return `EROFS` for authorized removal through writable aliases. |
| `mount-unlink-{arm,x86}-up-{4,5,6}-before-b` | Previous kernels remove entries through detached, retired and live read-only routes. |
| `mount-unlink-{arm,x86}-unlinks-after-a` | All eight corrected native cases pass. |
| `mount-unlink-arm-all-after-a` | The complete native mount suite passes, including inode flags, symlinks and removals. |
| `mount-unlink-{arm,x86}-linux-a` | The same probe ELFs pass the portable Linux 6.12.51 suite, including all eight removal cases. |

| Architecture | Final kernel SHA-256 | Shared native/Linux probe SHA-256 |
| --- | --- | --- |
| aarch64 | `ced19ad76895be1c797316853a93b56109280cd2ccce6aecc1294c640830bfa3` | `7a2c7bdd12fa559c23f101108cd9a72b0fa6bce13015834d5d7115754222593e` |
| x86_64 | `4dfe9f433e0982cd7e0fd8cf5c9abd615e497d3cdeaabbb2a55734d325462133` | `e9f3dc1f547d2ebcf02647bf99d773083d24b353cce3ae3e1f6fa4d370f5dc67` |

Both isolated builds start from the qualified symlink inputs and change only
the removal helpers and syscall in `vfs.v`. The other session's staged
pointer-return spelling edits, the pre-existing open-created descriptor hunks
and later checkout changes are excluded. Each `mount-unlink-{arm,x86}-input`
retains its complete kernel source manifest, changed source, generated C, ELF
and hashes. Builds use V source `f6358ecff9cffbf2d8b03e6a09269aac7707e26c`,
compiler SHA-256 `f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39`
and link seed 17. Native ARM uses HVF/four CPUs; x86 uses TCG/two. Networking
is disabled. Focused native timeouts are 300/900 seconds; the complete ARM suite
and Linux references use 600 seconds. This qualification does not include a new
full native x86 cumulative suite or persistent/overlay integration run.

The assertion-enabled evidence audit verifies all sixteen fixture sources,
artifact and receipt hashes, controls and native/Linux ELF identity. It compares
the complete generated removal helper against the prior helper after only
route initialization, route-aware walking and read-only policy substitutions;
generated return-temporary numbers are normalized. The complete syscall and
internal wrapper, plus unchanged walk, mount policy, authorization, orphan,
parent/resource pin and cleanup helpers, are checked too. Per-architecture
`unlink-c-audit.txt`, `mount-unlink-source-evidence-a.log` and
`mount-unlink-evidence-a.log` retain those results. A post-commit audit compares
the three committed removal functions with both isolated inputs and accounts
for the same excluded pre-existing descriptor hunks in the parent commit.

Initial `up-0-before-a` controls catch the same false `EROFS` during the
unprivileged permission assertion. The final fixture moves that assertion to
the second round, preserving every permission check while reporting authorized
writable refusal first. Fresh `before-b`, corrected native and Linux states all
share its final ELF and generated C.

Disk pressure during validation required lossless archiving of older completed
mount-test images as `test.iso.gz`. Each decompression hash was checked against
its original receipt before removing the redundant uncompressed copy; adjacent
`test.iso.archive.txt` files record the original hash and restoration command.
Those older sources, probes, kernels, logs and receipts remain available. This
qualification's images remain uncompressed. Identical immutable kernel copies
use independent APFS copy-on-write clones with unchanged artifact hashes.
