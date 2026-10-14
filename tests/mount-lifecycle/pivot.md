# Pivot-root admission

`pivot_root` now preserves the identities of `new_root`, `put_old` and the
caller's current root. All three must have active attachments in the caller's
captured mount table. Both roots must name mount roots. A detached destination
returns `ENOENT`; foreign attachments, non-mount roots and unreachable routes
return `EINVAL`. Using the caller's old mount for the new root or destination
returns `EBUSY`. The mount capability and policy gates still precede lookup and
admission.

Inode ancestry alone cannot distinguish bind aliases. The new bounded helper
follows each mount's current namespace parent and covered node, then checks
inode ancestry within the matching mount. It verifies that `put_old` is below
the requested new root and that the new root is below the caller's current root.
Descriptors whose saved cursor predates a move do not supply the parent chain.
The VFS writer lock covers resolution, admission and existing publication.
The old-root record uses the validated old-root entry's type/source/flags and
the actual `put_old` context, including for a nested mounted destination.

The portable checks compare against
[Linux 6.12.51's pivot-root implementation](https://github.com/gregkh/linux/blob/v6.12.51/fs/namespace.c).
Its destination locking rejects an unmounted destination before root admission;
the detached error is consequently `ENOENT`. The same final ELF runs natively
and on Linux for each architecture.

Select all seven V fixture cases with `--case pivot`, or one with `pv-0` through
`pv-6`:

| Case | Request/check |
| --- | --- |
| `pv-0` | New root is an ordinary child directory inside another mounted filesystem: `EINVAL`. |
| `pv-1` | Detached read-only new root and old destination through a held fd, with a live replacement at its old path: `ENOENT`. |
| `pv-2` | New root/destination created only in a child's namespace, reached through a held fd: `EINVAL`; after child detachment/exit: `ENOENT`. |
| `pv-3` | Destination through a sibling bind alias shares the same inode as a descendant of the new root: `EINVAL`. |
| `pv-4` | Caller chroot is an ordinary directory rather than a mount root: `EINVAL`. |
| `pv-5` | Destination belongs to the caller's old-root mount: `EBUSY`. |
| `pv-6` | Valid tmpfs root, nested mounted destination and a directory bind root all pivot successfully. |

Each refusal verifies ordinary `O_PATH` lookup of both paths first, then repeats
the call 200 times while preserving root/cwd, source/destination/live inode
identities and marker contents. UID/GID 1000 with no supplementary groups must
receive `EPERM` before validation. Held read-only roots remain readable and
refuse creation, writable opens and truncation. Foreign descriptors retain
those properties after the source namespace detaches its root and exits.

Each refusal case then performs a valid pivot in that same namespace. The
ordinary-chroot case restores its original mount root using a held root fd
before that positive check. The fixture gives Linux's initramfs a pivotable
root by recursively binding `/` to a distinct directory and chrooting there.
Success changes `/`, cwd and `/..` to the new root, exposes the old root at the
requested directory, preserves old/new marker access and gives the correct
`..` from the old root. A nested destination checks its own mounted parent.
Each case runs in a child namespace; the parent's root identity stays intact.

Qualification from 2026-10-14 is retained under
`build/development17-20261013`:

| States (both `arm` and `x86`) | Result |
| --- | --- |
| `mount-pivot-*-pv-{0..5}-before-d` | Previous propagation-guard kernels accept the five invalid roots/routes, and return `EINVAL` rather than `EBUSY` for case 5. |
| `mount-pivot-*-all-after-d` | Final native kernels pass all pivot cases and every prior mount mode, move/depth, identity, admission and propagation validation check. |
| `mount-pivot-*-linux-d` | Linux 6.12.51 passes every portable check using the identical final native probe ELF. |

Earlier `before-a` states preserve a fixture pointer-sign compilation failure.
The `before-b`/`before-c` controls retain earlier fixture revisions and disk
exhaustion failures. `linux-a` exposed the fixture's unsuitable self-bind `/`
setup; `linux-c` established the detached-destination error. The final `d`
states use the corrected separate bind root and destination admission. Results
interrupted by disk exhaustion, including the x86 `all-after-c` run whose guest
printed PASS but whose receipt could not be written, are not qualification.

| Architecture | Final kernel SHA-256 | Shared native/Linux probe SHA-256 |
| --- | --- | --- |
| aarch64 | `df4e8e980eb7dcf70f6b322801e421a0d0b417816d6f8a38a65ecef36ff04533` | `53c3ff57e57f22e4a1b7386eba612c5159d4fb5fe0cca81bf179d0450c35116e` |
| x86_64 | `b42dc0400d88b4f9ee9afc0879912a7cb32af76cdb5fcaf43a1980a03c8dec00` | `407c588835daa9207a9c3cf837526ff3f03e1c7256a020f62355bb65a6439a3c` |

The isolated builds reuse frozen `mount-propagation` sources, changing only
`kernel/fs/mount.v`, and retain the VFS baseline limitation described in
[identities.md](identities.md). Other sessions' checkout changes are excluded.
Builds use V source `f6358ecff9cffbf2d8b03e6a09269aac7707e26c`, compiler SHA-256
`f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39`
and link shuffle seed 17. `mount-pivot2-{arm,x86}-input` freezes each final ELF,
generated C, mount source and complete kernel source manifest. The controller
pins all five fixture files and the cached ELF/C; controls and final native
runs reuse the first `before-d` probe. `mount-pivot-evidence.log` independently
checks receipts/artifacts, all case markers, shared ELF identity, unchanged
baseline sources and generated admission/publication ordering. The ancestry
helper contains no allocation calls. No new kernel ownership or freeing is
introduced; complete operations are not claimed allocation-flat.

This qualifies admission and the existing one-pivot publication path. Complete
mount reparenting, old-root detachment, repeated pivots, busy accounting, mount
reclamation, namespace switching/teardown and root/cwd updates across other bind
aliases remain unqualified. Propagation semantics, full OCI/rootless acceptance
and the remaining roadmap section 17 work remain open.
