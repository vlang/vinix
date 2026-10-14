# Mount lifecycle qualification

The V controller boots an owned Vinix QEMU guest with private tmpfs mounts and
networking disabled. Fresh output directories retain the kernel, copied V
fixture, generated C, probe ELF, boot image, serial log and hash receipt.

Build each kernel in an isolated worktree, then run from the repository root:

```sh
V_C_ERROR_BUG_REPORT_DISABLED=1 USE_TCG=0 build-support/run-v-tool.sh \
  tests/mount-lifecycle/run.v --arch aarch64 \
  --kernel-dir /path/to/arm-worktree/kernel --state-dir /path/to/fresh-arm-result

V_C_ERROR_BUG_REPORT_DISABLED=1 USE_TCG=1 build-support/run-v-tool.sh \
  tests/mount-lifecycle/run.v --arch x86_64 \
  --kernel-dir /path/to/x86-worktree/kernel --state-dir /path/to/fresh-x86-result
```

The default `--case all` requires every positive marker. `--case flags`,
`--case move` and `--case identities` select a group; `--case id-0` through
`id-6` select one identity case. The timeout defaults to 180 seconds.
`--case admission` selects the new-filesystem/bind/devpts admission group;
`ad-0` through `ad-7` select its individual cases.

The [new mount admission checks](admission.md) cover detached and foreign
destinations and bind sources. Each case checks authorization, repeated
refusal and retained data/policy, then exercises valid fd-based directory/file
binds, tmpfs and devpts in the original and a copied namespace.

The [attachment identity checks](identities.md) cover detached and foreign
mounts reached through held descriptors or cwd. They also verify retained
read-only policy for creation, writable opens and truncation, including after
namespace retirement. Each of the seven cases runs 200 refusal/preservation
iterations, verifies capability denial and finishes with valid local operations.

Use `--probe-state /path/to/prior-native-result` to reuse its probe ELF and
generated C with a different kernel or case. The controller requires a matching
architecture and identical current/copied hashes of all three fixture files,
verifies both artifact hashes against the prior receipt and checks the ELF
architecture before boot.
The prior result may be a failed control; its receipt hash is pinned in the new
result. A changed source or artifact requires a fresh compilation.

`flags` repeats five unsupported unmount modes and five invalid flag sets 200
times each. `MNT_FORCE`, `MNT_EXPIRE`, force with detach, and either unsupported
mode with `UMOUNT_NOFOLLOW` must return `ENOTSUP`. Expiry with force or detach,
unknown bits and negative flags must return `EINVAL`. Every iteration preserves
the mount's device/inode identity and its marker contents. UID/GID 1000 must
receive `EPERM` before mode validation. A final symlink refuses unmount with
`UMOUNT_NOFOLLOW`; ordinary symlink-following unmount succeeds after descriptors
close. Lazy unmount with no-follow preserves an already open file description.

This explicitly refuses modes that Vinix does not implement. Linux's expiry
protocol checks usage and marks a mount before a subsequent expiry request can
detach it; its force path can call backend cancellation. See
[Linux v6.12 namespace implementation](https://github.com/torvalds/linux/blob/v6.12/fs/namespace.c).
The Vinix-specific `ENOTSUP` checks do not claim Linux force/expiry acceptance.

`move` repeats direct-descendant, nested-descendant and self moves 200 times in
both the original and a copied mount namespace. Each returns `ELOOP`, preserves
the source and nested marker, and leaves valid moves possible. A directory mount
cannot move onto a regular file (`EINVAL`). Valid moves preserve mount identity,
nested contents and the correct `..` destination through held `O_PATH`
descriptions and cwd; the child's namespace changes leave the parent intact.

The holder case opens a nested cwd/description before moving its ancestor under
another mount. Attempts to move that new ancestor below the retained cwd or a
`/proc/self/fd` destination must fail with `ELOOP` in 200 repetitions each. Moving
the nested destination out of that tree must then allow the previously refused
move, despite the holder's saved route. The check follows each mount's current
namespace parent by stable ID, under the existing mount-move writer lock.

Vinix also mounts 63 nested tmpfs roots beneath its boot root. Moving another
mount onto the resulting 64-step destination must return `ELOOP` before changing
either attachment: the moved mount needs one remaining cursor step. Moving the
whole nested tree onto a shallow mounted destination must also refuse a
65-step descendant. Removing one deepest mount makes that complete move fit
exactly 64 steps; it must succeed and preserve the deepest mount identity and
contents. The probe unmounts these roots in reverse order. Admission checks
every active attachment's current parent chain without allocating a snapshot.

The Linux reference executes the exact same probe ELF with `move-reference`
selected. It runs the portable cycle, type, namespace, holder, all seven
identity checks and all eight admission cases. Vinix's cursor limit and
unsupported unmount modes are excluded. Supply a matching Linux kernel and
the ELF preserved by a native run:

```sh
V_C_ERROR_BUG_REPORT_DISABLED=1 build-support/run-v-tool.sh \
  tests/mount-lifecycle/reference.v --arch aarch64 --kernel /path/to/linux-arm64 \
  --init /path/to/native-arm-result/init --state-dir /path/to/fresh-linux-result
```

Use `--arch x86_64` and matching artifacts for x86. The reference receipt pins
the shared ELF, Linux kernel, launcher source/C/ELF, archive, QEMU and serial log.
The launcher uses HVF on ARM, TCG on x86, two CPUs and no network devices.

The original mode/depth qualification from 2026-10-14 is retained under
`build/development17-20261013`; the subsequent identity/policy qualification
is recorded in [identities.md](identities.md):

| States (both `arm` and `x86`) | Result |
| --- | --- |
| `mount-lifecycle-*-flags-before-d` | Original kernels accept force unmount; site 13 fails with result 0. |
| `mount-lifecycle-*-move-before-d` | Original kernels accept a descendant move; site 32 fails with result 0. |
| `mount-lifecycle-*-flags-after-a` | Independently built unmount-only patch passes all mode checks. |
| `mount-lifecycle-*-subtree-before-a` | Root-only move admission passes holder checks but accepts the excessive-depth subtree; site 76 fails with result 0. |
| `mount-lifecycle-*-all-after-a` | Final native kernels pass both groups, including the exact 64-step subtree move. |
| `mount-lifecycle-*-linux-a` | Linux 6.12.51 reference passes portable checks with the identical final native ELF. |

The original controls and unmount-only runs preserve the earlier fixture
revision, before the subtree boundary was expanded. Their unmount, cycle,
holder and valid-move functions match the final fixture; the subtree controls
and final runs use their preserved complete source revision. Earlier fixture
compilation failures remain in the separate `before-a`/`before-b` states.

| Architecture | Final kernel SHA-256 | Shared native/Linux probe SHA-256 |
| --- | --- | --- |
| aarch64 | `62cb0aedfcefa51453113776216e1bddd0f861cb6d427a39a67980acda60aec3` | `65c691b1cc904436234e15e5f5ff53936026edf495d139c8ac818796bcb4aa27` |
| x86_64 | `2c6e85a4c1cc0cc53087f1df06aa82753c9a7b0e1ec6391bd92eef2bd4694c40` | `523929fddbe38e8cf18c5eb007b2d8c1f219756d46dae7e2e5caeac01ae649d9` |

The isolated kernels reuse the frozen `kernel-protected4` inputs from the
overlay qualification, replacing only `kernel/fs/mount.v`. Other sessions'
live checkout changes are excluded. Each `mount-lifecycle-{flags,move,move2}-*-input`
preserves its ELF, generated C, mount source and source manifest. Builds use
V source revision `f6358ecff9cffbf2d8b03e6a09269aac7707e26c`, compiler binary
SHA-256 `f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39`
and link shuffle seed 17. `mount-lifecycle-evidence.log` independently verifies
the receipts, source versions, controls, copied ELF identity, selected positive
markers and generated move/validation/parent functions without allocations.

These checks do not qualify busy-reference accounting, mount-object reclamation,
overlay cache teardown, concurrent mount publication/namespace switching,
propagation or complete bind-alias attachment isolation. Mount identities and
cached filesystem trees retain their existing permanent ownership; no allocation-flatness claim is
made for creating and removing mounts or namespace copies. Full OCI and rootless
qualification remains open.
