# UNIX socket creation masks

Pathname bind requested mode `0777` without applying the process umask. A
socket created under umask `0022` therefore remained writable by other users.
The bind path now masks its requested permission bits before the existing
filesystem ACL inheritance and publication. Abstract names return before this
filesystem operation and keep their existing permission behavior.

The V probe runs as UID/GID 1000 with supplementary groups cleared. Each
backend checks stream, record and datagram sockets under five masks, first
without a default ACL and then with an inherited ACL. The inherited template
has owner permissions 6, a named UID entry with permissions 2, group permissions
0, mask 2 and other permissions 2:

| Umask | Mode without an ACL | Mode with the template ACL |
| --- | --- | --- |
| `0000` | `0777` | `0622` |
| `0022` | `0755` | `0600` |
| `0077` | `0700` | `0600` |
| `0222` | `0555` | `0400` |
| `0777` | `0000` | `0000` |

The probe verifies pathname and O_PATH mode/owner metadata and the exact ACL
owner, group, mask and other fields. The named entry remains present as the
mask restricts it. Sockets without a default ACL have no access ACL attribute.
Actual connection attempts must fail with `EACCES` when owner write permission
is absent; otherwise a real stream/record connection or datagram transfer must
succeed. Tests restore the original process mask after each bind and retire
each temporary pathname and descriptor. Existing abstract-name checks still
connect under umask `0777` and descriptor mode zero.

The disk probe additionally leaves one UID/GID 1000 socket created under umask
`0077` on direct ext2 and the overlay upper. After transport close and read-only
volume remount, both retain mode `0600`, nlink 1, the named ACL entry and a zero
ACL mask/other entry. Existing live xattr, permission, ownership rollback,
descriptor and socket retirement checks remain active.

Results from 14 October 2026 are retained under
`build/development17-20261013`:

| State | Result |
| --- | --- |
| `socketumask-arm-before-b`, `socketumask-x86-before-b` | Previous pathname-xattr kernels fail assertion 603: actual mode `0777`, expected `0755`, umask `0022`. |
| `socketumask-arm-basic-a`, `socketumask-x86-basic-a` | Native tmpfs creation and operation matrix passes. |
| `socketumask-arm-linux-a`, `socketumask-x86-linux-a` | The exact same corresponding native probe ELF passes Linux 6.12.51-0-virt. |
| `socketumask-arm-after-a`, `socketumask-x86-after-a` | All 90 creation cases per architecture across tmpfs/direct-ext2/overlay, masked metadata persistence and repeated socket retirement pass. |
| `socketumask-arm-all-a`, `socketumask-x86-all-a` | Existing atomic replacement, backend failure, mixed lifetime, whiteout, opacity and persistence regression passes. |

The two batches of 32 socket cycles per disk backend retain equal live counts
across all 18 ARM slab classes plus the large count and all 14 x86 classes plus
the large count. Writes after free remain zero. All four final volumes pass
read-only `e2fsck -f -n`. The allocation audit matches the same 182 baseline
file/kind findings; the allowlist is unchanged.

| Input | SHA-256 |
| --- | --- |
| Fixed ARM kernel | `f7bd19dffcff3db9d93e9fc2f7825bf46a2743faab804677b0893bae81f5b37e` |
| Fixed x86 kernel | `10e9f1e8479c856407da07a4445a07d1cc344aa801e0ac0747e61f46f88fe45f` |
| Creation fixture | `ad41d32618c9cec74f5a3fc59494b7e23d6af2137113f9d4039605f396bc9ad6` |
| Core fixture | `039980c90daf7331569f544601e880cb007139f49bbce3e5f31f8913529b4e7f` |
| Socket fixture | `890f5bc1a9294b098d37ee976df9646b273d734780b085d263a759464ca03543` |
| Shared ARM native/Linux probe | `d3c91b4291a52023a64d4c408128832eb5dbc424057a41210ef04115ef4b5ea1` |
| Shared x86 native/Linux probe | `29100169334e3e3fcf3410798d1cae1f481d675be977ac6d051559fa4e5a8fdf` |

Separate `kernel-umask-arm-tree` and `kernel-umask-x86-tree` worktrees preserve
the earlier [pathname-xattr qualification](socket-xattrs.md). They copy its
qualified kernel sources and dependencies, adding only the scalar bind mode
calculation. Builds use its pinned `f6358ec` compiler and link seed 17. The x86
sampler host generator is compiled with `-gc none` and run with that compiler
selected explicitly through `V`; the final x86 build is
`kernel-umask-x86-tree/kernel-socketumask-x86-build-c.log`. Earlier failed
sampler builds and the first fixture C pointer-type failure remain separate
from passing results.

`socketumask-evidence.v` verifies all fixture/artifact receipts, exact kernel
source comparisons, generated C hashes and scalar mode calculation, both old
kernel controls, flat allocation samples, four filesystem checks and identical
native/Linux probe hashes. Its assertion-enabled run is
`socketumask-evidence-final.log`; the allocation audit is
`socketumask-allocation-audit-a.log`. Repeat with
[the maintained controller](README.md).

This qualifies the tested pathname bind masks and existing abstract behavior.
Full socket/path metadata separation, broader capability/MAC/user-namespace
matrices and OCI/rootless acceptance
remain open. The existing 25-second final retirement wait remains part of the
disk fixture; unmount draining and crash recovery with pending cleanup are
outside this qualification.

The subsequent [wire-format correction](acl-wire.md) qualifies unsupported
ACL-version and malformed-payload errno ordering.
