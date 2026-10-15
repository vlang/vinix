# Inode-flag attachment policy

`FS_IOC_SETFLAGS` now checks the descriptor's saved mount route before changing
immutable/append-only flags or copying up an overlay inode. The old inode-only
check could reject a writable source because a read-only bind was newer, or
accept changes through detached, retired or live read-only routes when another
alias was writable. Authorized unchanged values also require a writable route.

The ioctl dispatcher passes `&fd.handle.mount` to the existing flag helper while
its existing descriptor reference is held. The helper borrows it synchronously;
it does not retain the address, allocate an owner or change a reference count.
The dispatcher's deferred release and the helper's argument, capability, MAC,
backend support, securelevel and overlay checks remain in their previous order.
`FS_IOC_GETFLAGS` keeps its existing behavior through read-only descriptions.

The mount-write requirement also appears in
[Linux v6.12's inode-flag ioctl](https://github.com/torvalds/linux/blob/v6.12/fs/ioctl.c).
This change preserves Vinix's existing capability check before mount policy.
It does not qualify Linux-compatible error precedence for unprivileged setters.

Use `--case inode-flags` or `ip-0` through `ip-7`. The native `all` suite includes
the group. Each case has a private mount namespace and tmpfs marker. Regular
files and directories repeat sixteen cycles of append-only, immutable, both
bits and cleared flags. Getters through both aliases must see the same bits;
changed and unchanged setters through the read-only route must return `EROFS`
and preserve flags, identity, ownership, mode, size and timestamps. The final
file content must remain `MOUNT-OK`. UID/GID 1000 must receive `EPERM` from both
routes for changed and unchanged values, while getters remain available on its
inherited descriptors. Data descriptors are opened read-only.

| Case | Routes exercised |
| --- | --- |
| 0 | Directory bind in both read-only/writable flag directions |
| 1 | Descriptions opened after a namespace copy, both directions |
| 2 | Chroot root and cwd through different aliases, both directions |
| 3 | Regular-file bind, both directions |
| 4 | Read-only bind retained through directory descriptions after lazy detach |
| 5 | Descriptions retained after a worker's private namespace retires |
| 6 | Read-only source/writable bind established before the first call |
| 7 | File and directory descriptions inherited across copies with unchanged flags |

The flag payloads in this group are native-only. The same probe's Linux
`move-reference` suite exercises the existing portable mount cases and excludes
these flag setters; it must not be presented as Linux flag-ioctl qualification.
The [descriptor flag checks](descriptor-flags.md) separately cover inherited
descriptions whose original mount and namespace copy have divergent remount
flags. Filesystem-backed Linux flag comparisons, concurrent remount/setns and
the broader securelevel/MAC/capability matrix remain open. Full OCI/rootless
acceptance and roadmap section 17 remain in progress.

Evidence from 2026-10-15 is retained under `build/development17-20261013`:

| States | Result |
| --- | --- |
| `mount-inodeflags-{arm,x86}-ip-{0,7}-before-b` | Previous kernels reject writable-source and inherited-description setters with `EROFS`. |
| `mount-inodeflags-{arm,x86}-ip-{4,5,6}-before-b` | Previous kernels accept a flag change through detached, retired and live read-only routes. |
| `mount-inodeflags-{arm,x86}-flags-after-a` | All eight corrected native flag cases pass. |
| `mount-inodeflags-arm-all-after-a` | Complete native mount suite, including the new flag group, passes. |
| `mount-inodeflags-{arm,x86}-linux-a` | Same probe ELFs pass the existing portable Linux 6.12.51 suite; flag setters are excluded. |
| `mount-inodeflags-{arm,x86}-overlay-after-a` | Existing overlay/ext2 regressions, allocation gates, flag copy-up/retention/authorization/persistence and read-only remount refusals pass. |

| Architecture | Final kernel SHA-256 | Shared native/Linux probe SHA-256 |
| --- | --- | --- |
| aarch64 | `c24a57c262023bef36aa2225a3d9162bfd07fd602371f2bf9d48a301ba11ef9c` | `4a3b91957cd7a731a7938813c829dc36ea314bfaa337879f84779f6f7cbe9478` |
| x86_64 | `0bb119858148aa90d8d715306700c572bee254d9b5c301c3b5149737fe91255a` | `e24419b1dd5cf33fe3f85fe7df46632e6faeddbe9e29e4e8d30da61eb2c87cda` |

Both isolated builds start from the qualified xattr inputs and change only
`attributes.v` and the ioctl call site in `vfs.v`. The other session's staged
VFS pointer-return changes and later checkout changes are excluded. Each
`mount-inodeflags-{arm,x86}-input` retains source manifests, the two changed
sources, generated C, ELF and hashes. Builds use the existing V source
`f6358ecff9cffbf2d8b03e6a09269aac7707e26c`, compiler SHA-256
`f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39`
and link seed 17. ARM uses HVF/four CPUs; x86 uses TCG/two. Networking is disabled.
Focused native timeouts are 300/900 seconds, the full ARM suite uses 600, and
Linux references use 600 seconds. There is no new full native x86 cumulative
run in this qualification.

Overlay runs use fresh 128-MiB ext2 volumes and timeouts of 900 seconds on ARM
and 1200 on x86. Both final volumes pass `e2fsck -f -n` with exit status zero;
their SHA-256 hashes stay equal to the controller receipts after that read-only
check. `fsck.log` and `fsck.exit` retain those results. Existing retirement waits
and allocation gates are unchanged.

The source/C evidence audit verifies all fourteen native fixture sources,
controls, shared ELF identity, receipts and artifact hashes. It compares the
complete generated flag helper and ioctl dispatcher against the previous C
after just the argument and read-only-helper substitutions. Their existing
releases, authorization, no-op and copy-up ordering must remain identical.
The context parameter appears only in its declaration and synchronous policy
call; the policy helpers are unchanged. Per-architecture
`inode-flags-c-audit.txt` records the check.
`mount-inodeflags-evidence-a.log` records the assertion-enabled final audit.

Initial `ip-0-before-a` states preserve a V fixture compilation failure caused
by assigning through a function-call result. The corrected fixture stores the
errno pointer in a local first. Fresh `before-b` controls and corrected runs
use its pinned ELF and C without rebuilding or weakening assertions.
