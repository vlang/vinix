# Unmount with retained descriptors

Ordinary unmount returns `EBUSY` while a live published process's descriptor
table retains an open description for the selected attachment. This covers
read-only files and `O_PATH` files and directories independently of writer,
mapping, executable and cwd/root checks. Authorization remains first; lazy
detach keeps its existing behavior.

The existing process-table lock protects process/table lifetime, and a descriptor
table try-lock protects each slot and its owned descriptor/handle against close,
replacement and growth. Contention conservatively refuses the attempt. The
handle's mount context is immutable after publication, so this adds no handle
lock, reference count changes, allocations or frees. Inherited descriptions
select their original attachment, including after a mount namespace copy.

Run the [V controller](README.md) with `--case unmount-descriptors`, or select
`uf-0` through `uf-9`. Native `all` and Linux `move-reference` require all ten
cases. `uw-8` now also requires retained-descriptor refusal on both systems;
its previous native-only stale-route behavior is historical evidence.

| Case | Qualified behavior |
| --- | --- |
| `uf-0`, `uf-1` | Read-only and O_PATH file descriptors prevent ordinary unmount until close. |
| `uf-2`, `uf-3` | Read-only and O_PATH directory descriptors prevent ordinary unmount while cwd/root stay outside. |
| `uf-4` | A duplicate alone keeps the attachment busy after the original closes. |
| `uf-5` | A child's inherited read-only descriptor alone pins the mount after the parent closes its copy. Ordinary-account unmount still returns `EPERM`; exit releases the descriptor before zombie reaping. |
| `uf-6` | A copied namespace's mount can unmount while an inherited descriptor still pins its original attachment. Child exit releases the original before reaping. |
| `uf-7` | A descriptor through either bind alias pins only that attachment; its sibling can unmount. |
| `uf-8` | Lazy detach preserves openat/read access through a retained O_PATH directory. A replacement mount can unmount ordinarily. |
| `uf-9` | Unlinking a read-only open file does not release its attachment; replacing its pathname does not change the retained description's data. |

Each busy stage repeats 200 refusals with unchanged mount identity and marker
contents. These cases retain no writable description, file mapping or cwd/root
inside the target. Pipes synchronize forked holders; `waitid(WNOWAIT)` and a
remaining proc entry establish that unmount succeeds before zombie reaping.

Evidence is retained under `build/development-unmount-descriptors-20261016`.
The isolated `e42b3946c` worktree contains the saved typed-null adaptation and
eight mount/file sources matching this change; other sessions' kernel edits are
excluded. Builds use V `be2eb40`, clang, LLD and `KERNEL_LINK_RANDOMIZE=0`.
Source snapshots, generated C and compiler hashes accompany the hash receipts.

| Architecture | Kernel SHA-256 |
| --- | --- |
| AArch64 | `d0269b81bdabf29736e2feb1824c4696cefeb37cda073b87caac87a1e4ba88e5` |
| x86_64 | `ed1ca62e40bb4c65c376859c68cdb82e32d16ebf0e37ee5ea998cf1c797a161a` |

`before-arm` and `before-x86` reproduce premature unmount success with the
previous kernels at site 3300. `all-arm` and `all-x86` run the full corrected
native suite with a 3600-second limit. `linux-arm` and `linux-x86` run the
portable suite with identical native probe executables on Linux 6.12.51-0-virt.
`cold-arm` and `cold-x86` retain three persistent Services cold boots, immediate
unmount attempts, bounded backend-busy retries and writer-admission rollback
checks. `single-arm` selects `uf-4`; `stale-cache` refuses a pre-change cached
probe before image construction or boot.

Both architectures pass 356 native verdicts and 327 portable Linux verdicts.
Each also passes three independent persistent Services cold boots, eleven
validated job/service/shutdown receipts and three clean read-only filesystem
checks. The artifact audit verifies identical probe executables across the
control, corrected and Linux runs, unchanged probe C between control/corrected
runs, fixture/controller hashes and persistent-volume continuity. It also checks
the descriptor guard's actual-attachment comparison, try-lock and lack of heap
allocation. Individual-case selection and
refusal of a pre-change cached probe pass as well.

This observes descriptors already published in process tables. Concurrent
publication, descriptions removed from tables but held by in-flight operations,
queued descriptor passing, detached page maps and opaque resource-specific
mappings still need complete mount admission and ownership accounting. Mount
reclamation and full OCI/rootless acceptance remain open.
