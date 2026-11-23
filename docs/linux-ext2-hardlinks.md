# Persisted ext2 hard-link lifetime

When ext2 or VJFS builds a mounted directory tree, all persisted names for
the same non-directory inode share one resource. Each name retains a
reference. The aliases see the same link count, permissions, length, and
mapped data. The inode and its blocks remain allocated after the final
unlink while an open handle, mapping, or running executable depends on them.
[Linux ext2 inode lookup](https://github.com/gregkh/linux/blob/v6.12.51/fs/ext2/inode.c)

The mount walk keeps a temporary inode index across directory recursion.
The index borrows from the detached tree and is freed when the walk returns.
New hard links continue to take a resource reference from their source name.
Multiple names now use the same opportunistic close-writeback policy as
hard links created at runtime. The normal writeback and explicit sync paths
remain available for durability.

The shared lifetime applies to one mounted tree, including its bind mounts.
Separately mounted views of the same block device still build separate trees
and have independent inode state. Their executable write claims are shared
when the views use the same registered backend. [Executable write exclusion](linux-etxtbsy.md)

## Qualification

Run `build-support/run-v-tool.sh tests/linux-compat/run-mount.v --case textbusy`
with `--arch`, `--kernel-dir`, and a fresh `--state-dir`. Add `--journal` for
VJFS. The probe creates hard links in different directories before remount.
It checks that a write through one link updates an already faulted mapping
through the other. It also checks shared mode, size, link count, and
executable write exclusion. The executable's inode remains unavailable for
reuse after both names are removed and the pathname grace period expires.
It becomes reusable after the executable exits.

Both disk formats passed on AArch64 and x86-64 with production kernels built
from `fd4053c19` plus this change. The x86-64 baseline failed at mapped data
coherence. The original mount regression passed on both final kernels.
`e2fsck -fn` passed for both ext2 volumes and for separate, clean ext2 exports
of the VJFS volumes. The allocation checker found one fewer allocation site
per architecture and still reports the existing allow-list failures.

| Architecture | Probe ELF | Vinix kernel |
| --- | --- | --- |
| AArch64 | `a7b165fb70b36c3f` | `c21324deb9ba756d` |
| x86-64 | `27cfc3140a5466df` | `257be92ebc96f6e5` |

Hashes are SHA-256 prefixes. The receipts, checksum manifests and disk check
logs are under `~/.cache/vinix-r15/ext2-alias/{arm,x86}-{ext2,vjfs}`. The
existing mount regression and allocation reports are in the same parent
directory.
