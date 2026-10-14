# New filesystem and bind mount admission

New filesystem mounts, bind sources/targets and devpts targets now require an
active attachment in the caller's captured mount table. Ordinary path lookup
through a retained fd can still reach detached or foreign trees; that access
does not authorize attaching a filesystem there or binding that tree into the
local namespace. Previously all eight cases below succeeded on both native
architectures despite the existing remount/unmount/move guards.

The containing mount identity is checked after target resolution and before
filesystem construction, block-mount reservations or bind publication. New
mounts use that same table when publishing their record. Bind source admission
also requires a live identity before attaching or preparing origin strings.
Devpts validates its target under the VFS writer lock before preparing the
shared `pts` directory; backend preparation then releases the lock because
`internal_create` takes it itself. A detached destination returns `ENOENT`, an
active foreign destination returns `EINVAL`, and either inactive bind source
returns `EINVAL`. These results match
[Linux's namespace admission](https://github.com/torvalds/linux/blob/v6.12/fs/namespace.c).

The initial kernel boot mount can attach to the unmounted root sentinel only
when its context has no mount and the initial table has no entries. Binding or
devpts cannot use that exception. Detached entries stay in their tables, so
detaching existing mounts does not make a table qualify as a fresh boot table.
Both architecture kernel boots and the prior lifecycle suite pass.

The V fixture selects eight cases with `--case admission` or `ad-0` through
`ad-7`:

| Case | Held mount | Request |
| --- | --- | --- |
| `ad-0` | Detached read-only root, with a replacement at its old pathname | New tmpfs on its child directory. |
| `ad-1` | Same arrangement | Bind a local root onto its child directory. |
| `ad-2` | Same arrangement | Bind its child directory onto a local destination. |
| `ad-3` | Same arrangement | Devpts on its child directory. |
| `ad-4` | Read-only root created only in a child's mount namespace | New tmpfs on its child directory. |
| `ad-5` | Same arrangement | Bind a local root onto its child directory. |
| `ad-6` | Same arrangement | Bind its child directory onto a local destination. |
| `ad-7` | Same arrangement | Devpts on its child directory. |

Each target/source directory must open through its held fd before the request,
so lookup failure cannot masquerade as admission refusal. UID/GID 1000 with no
supplementary groups must receive `EPERM` before admission. Root repeats each
request 200 times, preserving the target, live pathname, local source and
destination device/inode identities and local marker contents. The retained
root still reads its marker and refuses creation/writable/truncating opens.
Relative cwd requests receive the same errors. Foreign cases repeat admission
and retained-data checks after the child detaches its root and exits.

Valid directory and file binds, new tmpfs and devpts mounts use local `O_PATH`
source/target fds and restore the original destination after unmount. The local
operations repeat after `unshare(CLONE_NEWNS)` with fds opened in that copied
namespace, and the parent's destination remains intact. The full native run
requires these cases plus every prior mode, move/depth and retained-identity
marker. Linux uses the identical ELF with the portable selector.

Qualification from 2026-10-14 is retained in
`build/development17-20261013`:

| States (both `arm` and `x86`) | Result |
| --- | --- |
| `mount-admission-*-ad-{0..7}-before-a` | Previous identity-guard kernels accept every request; result 0. |
| `mount-admission-*-all-after-a` | Patched native kernels pass the complete suite. |
| `mount-admission-*-linux-a` | Linux 6.12.51 passes all portable checks with the identical native probe ELF. |

| Architecture | Final kernel SHA-256 | Shared native/Linux probe SHA-256 |
| --- | --- | --- |
| aarch64 | `37cd0ff71e2c61b0313f82086f88221c4b00dd36fb1ab9318a17eabdaef7b5e8` | `66c467e1d3ad9db3c3eac2818a138fa1406d0c4d724f9f262f4e64a969ea95c1` |
| x86_64 | `94d85bb6e7980e8428adb4c617e3b6b86c598d30497c6b72f00fef479045acdc` | `bd195f7285bc6e7c49e34338ca83a210a259e56bac46cdf6ccd666e11971e099` |

The isolated worktrees reuse the frozen `mount-identities4` sources, changing
only `kernel/fs/mount.v` and `mount_policy.v`. They exclude other sessions'
checkout changes and retain the previous VFS baseline described in
[identities.md](identities.md). Builds use V source
`f6358ecff9cffbf2d8b03e6a09269aac7707e26c`, compiler SHA-256
`f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39`
and link shuffle seed 17. `mount-admission-{arm,x86}-input` preserves each ELF,
generated C, changed sources and complete prior source manifest with the two
updated hashes. The controller pins all three fixture files and verifies
source/artifact identity when reusing the first control's probe for later
controls and the passing run. The evidence checker independently verifies
every artifact and case marker, shared native/Linux ELF identity and unchanged
baseline sources. `mount-admission-evidence.log` also confirms the generated
admission helper allocates nothing, checks precede preparation, and each path
captures its table once. No new kernel ownership or freeing is introduced.

This qualifies admission before construction, not a complete mount transaction.
New filesystem/devpts preparation still releases the writer lock before
publication; concurrent detach/publication, namespace switching and teardown
remain open. Propagation, pivot-root admission, complete bind-alias isolation,
mount depth admission for every attachment, busy-reference accounting and
allocation-flat mount/namespace creation remain open. Devpts still shares its
existing backend: the `newinstance` option in the portable probe does not qualify
independent Vinix PTY namespaces. Full OCI/rootless acceptance and the remaining
roadmap section 17 work are incomplete.
