# Ordinary unmount with child mounts

Ordinary `umount2(path, 0)` now returns `EBUSY` when the selected mount has an
active descendant in the caller's mount namespace. The check runs under the
existing mount-writer lock before backend unmount checks or attachment changes.
It follows current parent attachment identities under the mount-table lock:
inode ancestry cannot distinguish bind aliases, and saved routes can predate
a mount move. Detached records do not themselves make a mount busy.

Authorization and path admission retain their existing order. `MNT_DETACH`
continues to remove the selected attachment subtree recursively. After removing
children, ordinary unmount still performs the existing backend check, including
the ext2 orphan guard and flush. This change allocates no scratch storage and
adds no ownership, reference counts, freeing or mount reclamation.

Run the maintained V controller with `--case unmounts` or `--case um-0` through
`um-7`; see [README.md](README.md) for kernel and guest setup. Each case runs in
an owned private namespace. The busy checks repeat 200 times while checking
both mount identities and marker contents after every refusal.

| Case | Qualified behavior |
| --- | --- |
| `um-0` | A direct tmpfs child keeps its parent busy; UID/GID 1000 receives `EPERM` before the busy check. Child-first ordinary removal succeeds. |
| `um-1` | A three-level tree keeps both ancestors busy. Lazy removal of the child also removes the grandchild; ordinary removal of the parent then succeeds. |
| `um-2` | Moving a child and grandchild changes which parent is busy. The former parent can unmount immediately; the destination and moved child remain busy until child-first teardown. |
| `um-3` | A sibling bind alias sharing the parent's root inode can unmount even while the original attachment has a child. The original parent remains busy. |
| `um-4` | A bind child also keeps its containing tmpfs mount busy. |
| `um-5` | A child created only in a copied namespace does not block unmount in the original namespace. The copied parent's identity and contents survive, and it remains busy there. |
| `um-6` | Removing copied child/parent attachments does not clear the original namespace's busy state. |
| `um-7` | Lazy parent removal detaches the whole subtree, including a held child's route. A replacement mount can unmount ordinarily. |

Native `--case all` and the Linux `move-reference` suite require all eight
positive markers. Cached probe reuse also validates the new fixture's source
hash, preventing reuse of a probe built before these checks existed.

Evidence is retained under `build/development-child-unmount-20261015`.
The isolated build uses the existing `e42b3946c` worktree, the saved typed-null
declaration adaptation and the three unmount sources from `674c95eee`, with
only the new descendant guard added. Other sessions' kernel edits are excluded.
Builds use V `be2eb40`, clang, LLD and `KERNEL_LINK_RANDOMIZE=0`; source snapshots,
compiler/source hashes, generated C, probe ELFs, serial logs and receipts pin
the qualified inputs.

| Architecture | Corrected kernel SHA-256 |
| --- | --- |
| AArch64 | `868036af99f47d488d717ee1763c59d5d42e4151450a8a00a319f1e866288719` |
| x86_64 | `4ba65928118429628c4b6378bbded4428772b5f66a7c7f4467f72604c3e44496` |

The previous kernels in `before-arm` and `before-x86` reproduce premature
success at site 2802 on the first parent-unmount attempt. The corrected kernels
pass all 304 verdicts each in `all-arm` and `all-x86`; `linux-arm` and
`linux-x86` pass all 275 portable verdicts each with the identical native probe
executables on Linux 6.12.51-0-virt. Individual-case selection also passes, and
the pre-change cached probe is refused before image construction or boot.
`audit.log` records the verified results and input hashes.

This qualifies child-mount busy admission only. Linked open files, mappings,
cwd/root references, concurrent namespace switching, mount reclamation and full
OCI/rootless acceptance remain open. Existing permanent mount and filesystem
tree lifetimes are unchanged.
