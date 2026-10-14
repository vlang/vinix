# Pivot root/cwd attachment identity

A pivot updates roots and cwd only when their inode and mount identity both
match the old root. Bind aliases can share the same inode while naming separate
attachments with different read-only policy. Comparing only the inode moved
unrelated alias paths into the new root, including another process's root and
the caller's cwd. Matching the stable mount ID also handles descriptions
inherited across mount-namespace copies. The comparison runs under each
existing filesystem-state lock and adds no allocations or ownership changes.
The original namespace root retains its boot-time empty-context compatibility;
this fallback is limited to a captured one-step root mount route.

This follows the attachment-and-dentry comparison in
[Linux v6.12 `replace_path` / `chroot_fs_refs`](https://github.com/torvalds/linux/blob/v6.12/fs/fs_struct.c).
The existing process traversal and the calling thread's private filesystem
state use the same predicate independently for root and cwd.

Run `--case pivot-alias`, or select `pa-0` through `pa-4`. Each case forks a
private mount namespace, mounts a tmpfs caller root and new root, and creates
a read-only sibling bind of the caller root. The bind and source have equal
device/inode numbers and distinct policies. Pipes synchronize holders so the
pivot occurs after their root/cwd are established and before their observations.

| Case | Root and cwd behavior |
| --- | --- |
| `pa-0` | Another process's root and cwd both use the bind alias and must retain the old inode. |
| `pa-1` | Another process's root uses the old-root attachment and moves to the new root; its cwd uses the alias and stays. |
| `pa-2` | Another process's root uses the alias and stays; its cwd uses the old-root attachment and moves. |
| `pa-3` | The caller's root moves while its cwd through the read-only alias stays. |
| `pa-4` | A sibling thread remains alive while the caller unshares `CLONE_FS`, ensuring Vinix creates private thread filesystem state. Both the caller's private view and the sibling's shared view get the new root while retaining the alias cwd. |

After the pivot, each holder repeats 200 root/cwd identity and writable-open
checks. Relative and absolute writable opens must follow their respective
attachment policies. A held alias descriptor also stays read-only. The parent
outside each private namespace retains its root identity. Every case requires
`MOUNT PIVOT ALIAS CASE: N PASS`, followed by `MOUNT PIVOT ALIASES: PASS` and the
suite verdict.

Qualification from 2026-10-14 is preserved under `build/development17-20261013`:

| States (both `arm` and `x86`) | Result |
| --- | --- |
| `mount-pivotalias-*-pa-0-before-c` through `pa-4-before-c` | Previous kernels incorrectly move alias roots in cases 0/2 and alias cwd in cases 1/3/4. Each prints the corresponding identity mismatch and fails. |
| `mount-pivotalias-*-all-after-a` | Patched kernels pass the complete native mount suite, including all five alias cases and the shared/private thread case. |
| `mount-pivotalias-*-linux-b` | Linux 6.12.51 passes all portable groups with the identical native probe ELF. |

The initial `pa-0-before-a` fixture attempted to create the new directory after
remounting its sibling inode alias read-only. An existing inode-based creation
check returned `EROFS` before the pivot. The corrected fixture completes setup
before remounting the alias. The `before-b` controls and `linux-a` runs preserve
the intermediate fixture, whose last case did not keep a sibling thread alive;
a single-thread `CLONE_FS` unshare does not create private ThreadFS on Vinix.
Only the final `before-c`, `all-after-a` and `linux-b` runs qualify that path.
These earlier attempts remain available as separate evidence.

| Architecture | Final kernel SHA-256 | Shared native/Linux probe SHA-256 |
| --- | --- | --- |
| aarch64 | `c755b8024921541e0dd3e1e5d5bc000c0a264ec9701f4bc6deb119f2577f80f5` | `2b677e3f8b06f9fa8eb5907556103ff8a0f6f42fd0df5d682f3e115190200203` |
| x86_64 | `6e93c0a5a94450916079b5330781ce6002382267f990cfb8f30bc5203ea073e9` | `c9e14591805950402594ca937c97d3380f7a0f4191e2001f4def9636ec0e6f11` |

The isolated worktrees reuse frozen `mount-pivotlife` sources, changing only
`kernel/fs/mount.v`; other sessions' live edits are excluded. The earlier VFS
baseline limitation described in [identities.md](identities.md) still applies.
Each `mount-pivotalias-{arm,x86}-input` freezes the ELF, generated C, mount source
and complete source manifest. Builds use V source
`f6358ecff9cffbf2d8b03e6a09269aac7707e26c`, compiler SHA-256
`f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39`
and link shuffle seed 17. The controller pins all seven fixture sources and
verifies them with ELF/C hashes before reusing the first `pa-0-before-c` probe.
ARM uses HVF and x86 uses TCG. Native ARM has four CPUs; native x86 and Linux
reference guests have two. Networking is disabled.
`mount-pivotalias-evidence.log` verifies controls, receipts, source/artifact hashes,
shared ELF identity, every positive marker, unchanged baseline sources and the
four generated predicate calls. The generated helper checks both node and
mount ID without allocating. No complete-operation allocation-flatness claim
is made; existing mounts and namespace copies remain permanently owned.

This qualifies the recorded process aliases and the calling thread's private
`CLONE_FS` view. Other threads' independently owned filesystem views are not yet
included in pivot's traversal. Multithreaded namespace switching, busy-reference
accounting, reclamation, general bind-alias isolation and the inode-based
creation check seen during setup remain open. Native bootstrap/self-root cases,
cursor-depth boundaries, same-directory stacking, full OCI/rootless acceptance
and the remaining roadmap section 17 work are also unqualified.

The subsequent [private thread qualification](pivot-threads.md) extends updates
to other threads' owned views, including across differing shared process namespaces.
