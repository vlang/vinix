# Hard-link attachment policy

`linkat` now captures both starting directories and their mount routes. It
walks each path with its stack context and resolves `AT_SYMLINK_FOLLOW` before
comparing the source and destination mounts. A dangling followed source returns
its lookup error instead of passing a nil node to the link checks.

The destination attachment must be writable. Distinct bind mounts return
`EXDEV`, even when both are writable and share a backing filesystem. The same
applies to an inherited directory description and a freshly opened description
of its copied namespace mount: stable mount IDs alone cannot establish equality.
Two paths through the same inherited description remain usable. A source
symlink resolving onto another mount uses that actual target's attachment and
filesystem, allowing a link into the target mount and refusing one back into
the symlink's original mount.

Destination read-only admission precedes linking permissions. Source backend
read-only protection, managed-volume and directory refusal, protected-hardlink
policy, MAC, destination permissions, inode attributes and budget admission
remain enforced. The existing backend call, failure cleanup, created-node
commit and publication tail retain their order. Both path strings keep their
existing frees and every locked return releases the VFS lock. The contexts are
stack values; this change introduces no new owner, retained context address,
free or reference-count transition. Internal inode-only `fs.link` callers keep
their conservative fallback.

[Linux v6.12's `do_linkat`](https://github.com/torvalds/linux/blob/v6.12/fs/namei.c)
also follows the requested source before checking exact mount equality and
requires a writable destination mount before linking.

Use `--case links` or `lp-0` through `lp-9`. Native `all` and Linux
`move-reference` include the group. Route pairs run sixteen iterations each
with a regular source and a symlink followed to that regular source. Authorized
links must preserve inode/device identity, mode, UID/GID and contents through
both aliases, increment the actual link count by one, and leave the seed
symlink's count at one. Removing each new name restores the original count.
Read-only refusals preserve both names' absence, source link count and
source/parent metadata and timestamps.

Cross-alias attempts must return `EXDEV` for a writable destination and `EROFS`
for a read-only destination. A UID/GID 1000 child cannot link its own file into
the `0755` directory (`EACCES`) or through the read-only alias (`EROFS`). It
cannot link the root-owned `0600` marker into a `0777` directory (`EPERM`). Those
denials preserve destination absence, source count and directory metadata.
The group enables and reads back `fs.protected_hardlinks=1` in the owned Linux
VM; Vinix already protects foreign hard links and has no corresponding sysctl.
This changes only the reference guest's policy and retains every assertion.

| Case | Routes exercised |
| --- | --- |
| 0 | Directory descriptors, both bind-policy directions |
| 1 | Descriptors opened after a namespace copy, both directions |
| 2 | Chroot root and cwd through separate aliases, both directions |
| 3 | Absolute paths with invalid dirfds and symlinked parents, both directions |
| 4 | Read-only bind retained after lazy detach |
| 5 | Descriptors retained after a worker's private namespace retires |
| 6 | Read-only source/writable bind established before the first operation |
| 7 | Directory descriptions inherited across a namespace copy with unchanged flags |
| 8 | Writable bind/copy mount boundaries; valid links within one mount and through inherited or fresh descriptions |
| 9 | Source symlink resolving onto another tmpfs mount; dangling-source and directory refusal |

This qualification covers regular sources and followed source symlinks.
Non-followed symlink hard links still need backend qualification. `AT_EMPTY_PATH`,
invalid-flag/error-order coverage, divergent inherited-FD remount flags,
concurrent remount/setns/chdir, broader ACL/MAC/attribute combinations and
persistent/overlay backend integration remain open. Setup mounts and namespace
copies retain their existing ownership; no allocation-flatness or mount
reclamation claim is made. Rename, OCI/rootless acceptance and roadmap section
17 remain in progress.

Evidence from 2026-10-15 is retained under `build/development17-20261013`.

| States | Result |
| --- | --- |
| `mount-link-{arm,x86}-lp-0-before-b` | Previous kernels falsely return `EROFS` through writable aliases. |
| `mount-link-arm-lp-5-before-b`, `mount-link-arm-lp-6-before-c`, `mount-link-x86-lp-{5,6}-before-b` | Previous kernels create hard links through retired and live read-only routes. |
| `mount-link-{arm,x86}-lp-8-before-b` | Previous kernels allow a hard link between separate writable bind mounts. |
| `mount-link-{arm,x86}-lp-9-before-b` | Previous kernels falsely return `EXDEV` when a followed source resolves into the destination filesystem. |
| `mount-link-{arm,x86}-links-after-a` | All ten corrected native hard-link cases pass. |
| `mount-link-arm-all-after-c` | The cumulative native mount suite passes, including all ten hard-link cases. |
| `mount-link-{arm,x86}-linux-b` | The same final probe ELFs pass the portable Linux 6.12.51 suite. |

| Architecture | Final kernel SHA-256 | Shared native/Linux probe SHA-256 |
| --- | --- | --- |
| aarch64 | `00f600378aee46553b49d51cf528bc7ba8eae210adc221dd696f9377583b2ba5` | `03fe52b4879b226fac024942c58fa5d66a811ac127d5948fcd1975be5afa64c1` |
| x86_64 | `fb7065e8f0c4a36208de9d2b826edeb81022ebfbde5295dce785431f119ff8dc` | `694a6602a1be35a843b3bfc459e0599c1e954099328e9bde54d9b93f80241637` |

Both isolated builds start from the qualified removal inputs and change only
`syscall_linkat` in `vfs.v`. The other session's staged pointer-return spelling
edits, the pre-existing open-created descriptor hunks and later checkout
changes are excluded. Each `mount-link-{arm,x86}-input` retains its complete
kernel source manifest, changed source, generated C, ELF and hashes. Builds use
V source `f6358ecff9cffbf2d8b03e6a09269aac7707e26c`, compiler SHA-256
`f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39`
and link seed 17. Native ARM uses HVF/four CPUs; x86 uses TCG/two. Networking
is disabled. Focused native timeouts are 300/900 seconds; the cumulative ARM
suite and Linux references use 600 seconds. A new cumulative native x86 suite
and persistent/overlay integration run are outside this qualification.

The assertion-enabled source/C audit compares the complete generated `linkat`
function to the prior function after only the two stack contexts, route-aware
capture/walking, source-follow relocation and nil guard, destination admission,
exact mount/actual-source filesystem comparison and source backend guard.
Generated temporary numbers are normalized; all other generated operations,
including cleanup, must match. Unchanged route, policy, authorization, budget
and publication helpers are compared too. Per-architecture `link-c-audit.txt`
and `mount-link-source-evidence-b.log` retain those results. The final evidence
audit in `mount-link-evidence-a.log` additionally verifies all seventeen fixture
hashes, copied probe/C identity, receipts, boot-image hashes and positive markers.
A post-commit audit
compares the committed syscall with both isolated inputs and accounts for the
same excluded pre-existing descriptor hunks in the parent commit.

Initial `before-a` probes lacked the explicit Linux protected-hardlink policy
precondition. The first Linux reference exposed its bare kernel's disabled
default. Final `before-b` probes and `linux-b` runs enable and verify the policy
inside that owned reference VM, retaining all denial checks.

Disk pressure interrupted artifact writes for `arm-lp-6-before-b` and the
cumulative ARM `all-after-a`/`all-after-b` states. Those incomplete states are
retained; fresh runs supply the qualification receipts. Completed mount-test
images are losslessly archived as `test.iso.gz`. Every decompression hash is
verified against the original receipt before the uncompressed copy is removed;
adjacent `test.iso.archive.txt` records give the hash and restoration command.
Sources, probes, kernels, logs and receipts remain available. Identical immutable
kernel copies use independent APFS copy-on-write clones with unchanged hashes.
