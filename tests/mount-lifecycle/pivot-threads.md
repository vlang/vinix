# Pivot updates to private thread views

A pivot now visits every thread's owned filesystem view in the caller's mount
namespace, as well as shared process state. It checks each private view's
namespace directly; a process's shared namespace cannot decide which of its
thread views participate. The existing mount-and-inode predicate independently
selects root and cwd, preserving other bind aliases and namespace copies.

Each successful pass holds the process-table lock, so a concurrent fork cannot
inherit an old root into a PID slot the traversal has already visited. The
thread-list lock protects ThreadFS publication and retirement. A busy list is
not waited for under the process-table lock: the traversal pins that process,
ends its partial pass, unlocks the table, waits for and releases the list lock,
and releases the process pin. It then restarts from PID 1. Earlier updates are
idempotent because the saved mount identity has already changed. Private
root/cwd updates hold the view's own lock. No new arrays, ownership objects,
heap promotions or direct frees are introduced.

This extends Vinix's traversal toward the all-task filesystem reference updates
in [Linux v6.12 `chroot_fs_refs`](https://github.com/torvalds/linux/blob/v6.12/fs/fs_struct.c).
Concurrent namespace switching is still outside the qualified scope.

Use `--case pivot-threads` or `pt-0` through `pt-6`. Each case runs in a child
with a private namespace and tmpfs caller/new roots. A read-only bind alias
shares the caller root's device/inode. Pipes gate the pivot until the worker's
private state and namespace are established, then gate observations until the
pivot has returned. Every case preserves the outer parent's root identity.

| Case | Expected result |
| --- | --- |
| `pt-0` | A sibling unshares `CLONE_FS`; both its old-root paths move to the new root. |
| `pt-1` | A sibling's private root and cwd through the bind alias stay on the old inode and remain read-only. |
| `pt-2` | Its private old-root attachment moves while its alias cwd stays read-only. |
| `pt-3` | Its alias root stays read-only while its old-root cwd attachment moves. |
| `pt-4` | A sibling unshares `CLONE_NEWNS` and remounts its copied caller root read-only. Its root/cwd and policy stay intact when the original namespace pivots. |
| `pt-5` | A helper process keeps a copied read-only namespace while its worker unshares `CLONE_FS` and joins the caller's namespace through an inherited namespace fd. The worker's root/cwd move; its process's shared root/cwd stay. |
| `pt-6` | A sibling repeatedly creates, joins and retires workers that unshare `CLONE_FS`, while the caller pivots. At least 20 private views have completed before the pivot starts. All observations name either the original or new mounted root; the final caller root/cwd name the new root. |

The first six cases repeat 200 root/cwd identity and writable-open policy checks
and preserve read-only policy through a held alias description. The group
requires all seven `MOUNT PIVOT THREAD CASE: N PASS` markers,
`MOUNT PIVOT THREADS: PASS` and the suite verdict. The churn case records its
completed count. It exercises concurrent thread publication and retirement;
it does not assert that a particular lock-retry branch was forced or claim
allocation-flat mount/namespace creation.

Evidence from 2026-10-14 is under `build/development17-20261013`:

| States (both `arm` and `x86`) | Result |
| --- | --- |
| `mount-pivotthreads-*-pt-{0,2,3,5}-before-e` | Previous kernels skip private views: root mismatches in cases 0/2/5, cwd mismatch in case 3. |
| `mount-pivotthreads-*-pt-{1,4,6}-before-e` | Previous kernels preserve the alias/copy and pass the unchanged thread churn control. |
| `mount-pivotthreads-*-all-after-b` | Patched kernels pass the complete native mount suite, including every private-view case and churn. Native timeout is 300 seconds. |
| `mount-pivotthreads-*-linux-b` | Linux 6.12.51 passes all portable groups using the identical final native probe ELF. |

Initial `build-a`/`before-a` attempts used V's reserved `thread` name. `before-b`
exposed a guest compiler promotion of a struct containing a fixed array; the
final worker state uses explicit stack storage and remains alive until join.
`before-c` predates the churn case. `before-d`, `all-after-a` and `linux-a` retain
the intermediate writable copied-root fixture. Native writable opens there
returned `EROFS` despite the copied source attachment being writable and its
sibling bind being read-only. The subsequent [bind policy checks](bind-policy.md)
qualify the correction to creation and writable opens through such aliases.
Final pivot preservation cases explicitly remount their copied roots
read-only, and retain all identity and read-only assertions. Final `before-e`,
`all-after-b` and `linux-b` qualify the complete current fixture.

| Architecture | Final kernel SHA-256 | Shared native/Linux probe SHA-256 |
| --- | --- | --- |
| aarch64 | `8d7a7ee0070598541cae23e5db3cb462e8e71a3d8b9fcb78387709b8afac37dc` | `a981c8704d2413182e65cbc335082442fca704fcb4bcb5db90675641ad68ddd0` |
| x86_64 | `a474513fe431ed83b5564a6bffd8860dfa3888fc30b52ea777d064000863d06c` | `8a7835fc58429d06c08a0b390f437c90392f8078ffadf494517bb16708d2e3bf` |

Isolated builds reuse the frozen `mount-pivotalias` baseline, changing only
`kernel/fs/mount.v`. Other sessions' checkout edits, including current proc and
VFS edits, are excluded; the earlier VFS baseline limitation in
[identities.md](identities.md) remains. Each `mount-pivotthreads-{arm,x86}-input`
preserves its ELF, generated C, mount source and complete source manifest.
Kernel builds use V source `f6358ecff9cffbf2d8b03e6a09269aac7707e26c`, compiler
SHA-256 `f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39`
and link shuffle seed 17. The maintained controller hashes all eight fixture
sources and verifies them with ELF/C hashes before reusing each first
`pt-0-before-e` probe. Native ARM uses HVF/four CPUs, x86 uses TCG/two CPUs;
Linux references have two CPUs. All guests have networking disabled.

`mount-pivotthreads-lifetime-review.md` records an independent review bound to
mount-source SHA-256 `16071634f8f1636cb2304f8c12e9456372715f337b00109d70ceabe71a001230`
and both generated C hashes. It verifies busy-process retention, no access after
unpin, ThreadFS list-lock protection and the successful-pass fork ordering.
`mount-pivotthreads-evidence.log` verifies that review, every receipt/artifact,
source manifests, all control outcomes/positive markers, shared ELF identity,
and generated retry ordering without new allocation/promotions. Completed test
artifacts retain their exact hashes after conversion to independent APFS clones;
`mount-pivotthreads-artifact-clones-a.json` records retained ISO/Linux artifacts.
Private worktree sparsification and derived object-cache removal are recorded
separately; kernel sources, generated C, binaries, logs and receipts remain.

Concurrent unshare/setns writes to a private view's namespace remain
unsynchronized with its lock. Broader fork/chroot/namespace stress,
bootstrap/self-root pivots, cursor-depth boundary
qualification, same-directory stacking, busy-reference accounting, reclamation,
propagation and full OCI/rootless acceptance remain open, along with the rest
of roadmap section 17.
