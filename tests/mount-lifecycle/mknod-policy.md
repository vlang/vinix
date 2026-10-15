# Node creation attachment policy

`mknodat` now captures its starting directory and mount route together, then
retains that route through lookup and read-only admission. The regular-file
branch also passes it to the existing resolved creation helper. A writable
bind alias remains usable when another alias of the same inode is read-only;
a retained read-only directory cannot authorize creation after lazy detach or
retirement of its mount namespace.

The change adds one stack cursor and uses the existing route-aware helpers.
It preserves the complete existing capability/MAC, policy, linked-parent,
attribute and directory-access checks, mode/umask handling, backend constructors,
publication, errors and cleanup. It introduces no heap owner, reference-count
transition or new free. Internal inode-only creation callers keep their existing
conservative fallback.

[Linux v6.12 `do_mknodat`](https://github.com/torvalds/linux/blob/v6.12/fs/namei.c)
likewise resolves a creation path with its mount and dispatches regular files
separately from device/FIFO creation. This qualification covers the supported
Vinix forms below; it does not change Vinix's refusal of socket placeholders or
claim Linux's complete invalid-mode and combined-error ordering.

Use `--case nodes` or `nd-0` through `nd-7`. Native `all` and Linux
`move-reference` include all eight cases:

| Case | Routes exercised |
| --- | --- |
| 0 | Directory descriptors, both writable/read-only bind directions |
| 1 | Descriptors opened after a namespace copy, both directions |
| 2 | Separate chroot root and cwd aliases, both directions |
| 3 | Absolute paths with invalid dirfds and symlinked parents, both directions |
| 4 | A read-only directory descriptor retained after lazy detach |
| 5 | Writable/read-only descriptors retained after a worker namespace retires |
| 6 | Read-only source and writable bind established before creation |
| 7 | Directory descriptors inherited across a namespace copy with unchanged flags |

Each route pair repeats sixteen rounds of typeless and explicit regular-file,
FIFO, character-device and block-device creation. A `0027` umask must produce
`0750` permissions from `0777`. Both aliases expose the same nonzero inode,
filesystem device, type, ownership and link count. Existing names return
`EEXIST`. Regular files and FIFOs pass actual write/read checks. Device nodes use
zero device numbers and are inspected without opening them; device backing and
I/O behavior are outside this test.

Every read-only attempt returns `EROFS`, preserves the name's absence and leaves
the parent metadata/timestamps unchanged. A UID/GID 1000 child checks `EACCES`
for regular/FIFO creation through a root-owned `0755` writable directory and
`EROFS` through its read-only alias. Separate device attempts in a `0777`
directory with nonzero device number `0x103` must return `EPERM`, isolating
capability denial from directory DAC and Linux's 0/0 whiteout exception.
Denied names remain absent and the original marker's identity/data is preserved.

Evidence from 2026-10-15 is retained under `build/development17-20261013`:

| States | Result |
| --- | --- |
| `mount-nodes-{arm,x86}-nd-{0,6}-before-b` | Previous kernels falsely refuse regular-file creation through writable aliases. |
| `mount-nodes-{arm,x86}-nd-{4,5}-before-b` | Previous kernels create files through detached and retired read-only routes. |
| `mount-nodes-{arm,x86}-nodes-after-a` | All eight corrected native cases pass. |
| `mount-nodes-arm-all-after-a` | The cumulative native mount suite passes, including inode flags, writer lifetimes and node creation. |
| `mount-nodes-{arm,x86}-linux-b` | The same final probe ELFs pass the portable Linux 6.12.51 suite. |

| Architecture | Kernel SHA-256 | Shared native/Linux probe SHA-256 |
| --- | --- | --- |
| aarch64 | `52e1967478d2559a86e872d8b64a9536199dea71428de70681c17dfef7c02eab` | `3572d2c3b5fff1ea8f3821b6769a6bdad5a7856fd80610174da872db23d73968` |
| x86_64 | `8485c82874677d185e7b0c95c878ef828c169646dddb0c623de2e6d5513a0e37` | `a771e4245dcc5383ac4966b5f8599251e57bd7acdf5d554b941cc942e2a35e7b` |

Both isolated builds start from the qualified writer inputs, changing only
`kernel/fs/mknod.v`. Complete source manifests, source copies, generated C,
kernels and hashes are preserved in `mount-nodes-{arm,x86}-input`. The complete
changed file matches the checkout. The unchanged frozen baseline still excludes
the pre-existing open-created VFS hunks, staged pointer-return spelling edits
and earlier fcntl/descriptor/lock changes described in
[the writer qualification](writer-policy.md). The complete current checkout
kernel was not built or booted.

Builds use V source `f6358ecff9cffbf2d8b03e6a09269aac7707e26c`, compiler SHA-256
`f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39`
and link seed 17. Native ARM uses HVF/four CPUs; x86 uses TCG/two, with
1024 MiB. Linux uses HVF/TCG, two CPUs and 512 MiB. Focused native timeouts are
300/900 seconds; the cumulative ARM suite and Linux use 600 seconds.

The assertion-enabled source/C audit compares all parsed namespace-qualified
generated functions with the writer baseline after temporary/discard number
normalization. Only `syscall_mknodat` changes. Its complete body must match after
the stack cursor, route-aware directory capture/walk/read-only check and resolved
regular-file dispatch. Per-architecture `nodes-c-audit.txt` and
`mount-nodes-source-evidence-a.log` retain that result. The final
`mount-nodes-evidence-a.log` verifies all twenty fixture hashes, artifacts,
receipts, boot images, shared probe/C identity, old-kernel controls and positive
native/Linux markers. A post-commit audit compares the complete committed
`mknod.v` with both isolated inputs and checks the commit's owned paths.

Initial `before-a` controls reproduced the kernel failures. The first Linux
reference states exposed a fixture precondition error: device requests through
the protected directory return `EACCES` before capability admission. The final
fixture uses the separate writable directory and nonzero device number above;
no kernel authorization check was weakened. The final `nd-0-before-b` ELFs/C are
reused for every qualified control and corrected run. Earlier attempts remain
retained. Completed older boot images may be losslessly archived as
`test.iso.gz`, with decompression hashes verified before removing originals.

Divergent inherited-FD remount flags, concurrent remount/namespace/cwd changes,
broader ACL/sticky/MAC/attribute combinations and persistent/overlay integration
remain open. There is no allocation-flatness or mount reclamation claim. A new
cumulative native x86 run and desktop performance scenarios are outside this
qualification. Full OCI/rootless acceptance and roadmap section 17 remain in
progress.
