# Symlink creation attachment policy

`symlinkat` now preserves the destination directory's mount route while walking
the destination parent. Inode-only read-only inference could reject a writable
source when a read-only bind was newer, or accept creation through detached,
retired or live read-only routes when another alias was writable.

The syscall captures the starting directory and mount together using
`parent_and_mount_for`. The private creation helper walks with that stack
context and checks the final attachment plus backend read-only state. The
public helper used by initramfs and device setup initializes its inferred
context under the existing VFS lock and keeps the conservative inode fallback.
Name policy, directory attributes, access and linked-parent checks still precede
the existing budget reservation and backend call. Creation identity, failure
cleanup, publication and notification ordering stay unchanged. No new owned
allocation, retained context address or reference-count transition is introduced.

[Linux v6.12's `do_symlinkat` and `filename_create`](https://github.com/torvalds/linux/blob/v6.12/fs/namei.c)
also use the destination's mount for creation admission. Target text is passed
to the backend without resolving or normalizing it.

Use `--case symlinks` or `sp-0` through `sp-7`. Both native `all` and Linux
`move-reference` include the group. Each pair runs 32 iterations of two target
strings: `marker` and the dangling `missing/../literal//target`. Read-only
creation must return `EROFS`, leave the name absent through both aliases and
preserve the parent directory's identity, mode, ownership, size and timestamps.
Writable creation must produce the same symlink inode through both aliases,
with the exact target bytes, type, length and UID/GID 0. The marker's data and
identity remain intact. A UID/GID 1000 child must receive `EACCES` through the
writable directory and `EROFS` through the read-only route without creating a
name or changing parent metadata. Each pair explicitly sets the parent mode to
`0755` before those checks, including on Linux tmpfs roots.

| Case | Routes exercised |
| --- | --- |
| 0 | Directory descriptors and both bind-policy directions |
| 1 | Directory descriptors opened after a namespace copy, both directions |
| 2 | Chroot root and cwd through different aliases, both directions |
| 3 | Absolute destination paths with invalid dirfds, through symlinked parents, both directions |
| 4 | Read-only bind retained through directory descriptors after lazy detach |
| 5 | Descriptors retained after a worker's private namespace retires |
| 6 | Read-only source/writable bind established before the first call |
| 7 | Directory descriptions inherited across a namespace copy with unchanged flags |

Names are unique; these tests retain their created links until guest teardown.
They do not qualify unlink cleanup, mount reclamation or allocation-flat
creation/removal loops. Divergent inherited-FD remount flags, concurrent
remount/setns/chdir, persistent/overlay backend integration, the broader MAC and
attribute matrix and invalid-input error ordering remain open. Full OCI/rootless
acceptance and roadmap section 17 remain in progress.

Evidence from 2026-10-15 is retained under `build/development17-20261013`:

| States | Result |
| --- | --- |
| `mount-symlink-{arm,x86}-sp-{0,7}-before-d` | Previous kernels reject writable-source and inherited-description creation with `EROFS`. |
| `mount-symlink-{arm,x86}-sp-{4,5,6}-before-d` | Previous kernels create links through detached, retired and live read-only routes. |
| `mount-symlink-{arm,x86}-symlinks-after-a` | All eight corrected native cases pass. |
| `mount-symlink-arm-all-after-a` | The complete native mount suite passes, including inode flags and symlinks. |
| `mount-symlink-{arm,x86}-linux-b` | The same final probe ELFs pass the portable Linux 6.12.51 suite, including all eight symlink cases. |

| Architecture | Final kernel SHA-256 | Shared native/Linux probe SHA-256 |
| --- | --- | --- |
| aarch64 | `4f267d5e37d5ecadc1f6ce026b36f0d212653971421c52d2838dfab3e489c31f` | `d85299d098e9166a00a66b8968a65c30aa907cead09908bebc1b5ab256b4b567` |
| x86_64 | `20e02612180acccb76a95504b314b2827413767eed4c33e413ed554f47894843` | `388de994a8982b8679930ffcc3852fe18ff318108162a30f1a37d8f5f6b43893` |

Both isolated builds start from the qualified inode-flag inputs and change only
`vfs.v`. The other session's staged pointer-return edits and later checkout
changes are excluded. Each `mount-symlink-{arm,x86}-input` retains its complete
kernel source manifest, changed source, generated C, ELF and hashes. Builds use
V source `f6358ecff9cffbf2d8b03e6a09269aac7707e26c`, compiler SHA-256
`f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39`
and link seed 17. Native ARM uses HVF/four CPUs and x86 uses TCG/two. Networking
is disabled. Focused native timeouts are 300/900 seconds; the complete ARM suite
and Linux references use 600 seconds. No full native x86 cumulative suite or
new persistent/overlay backend integration run is claimed here.

The assertion-enabled source/C evidence audit verifies all fifteen fixture
sources, artifact and receipt hashes, controls and native/Linux ELF identity.
It compares the complete creation helper against the old helper after only
context initialization, route-aware walking and read-only policy substitutions;
generated return-temporary numbers are normalized for that comparison. It also
checks the complete syscall and internal wrapper, and unchanged walk, mount
policy, creation identity and publication helpers. Each architecture retains
`symlink-c-audit.txt`; `mount-symlink-source-evidence-c.log` and
`mount-symlink-evidence-a.log` retain the final audit results.

Initial `sp-0-before-a/b` states retain fixture C-declaration compilation
failures. The fixture now uses raw no-follow stat calls. The first Linux
`linux-a` comparisons exposed a missing test precondition: Linux tmpfs roots
are world-writable by default. The final fixture explicitly sets `0755` while
preserving every denial assertion. Native `symlinks-after-a`, Linux `linux-b`
and fresh `before-d` controls share that final probe; earlier `before-c` states
are superseded. An earlier x86 control sequence also retains a source-mismatch
refusal after the fixture changed. Old derived object caches were pruned and
completed identical kernel copies replaced with independent APFS copy-on-write
clones to recover disk space; retained source/C/ELF and receipt hashes are
unchanged.
