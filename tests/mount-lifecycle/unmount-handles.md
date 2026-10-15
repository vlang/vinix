# Description lifetime during unmount

Ordinary unmount returns `EBUSY` while a published file description retains the
selected actual attachment. This includes a blocked read/write after its
descriptor closes and `SCM_RIGHTS` waiting in a socket queue. Descriptor-table
and page-map scans alone miss descriptions held outside those tables.

The first admitted descriptor publication adds one count under the mount lock
and records its attachment in the existing `file.Handle`. Duplication, fork,
in-flight lookups, mappings and queued rights share that Handle and count.
Publication and shutdown admission use the same lock. Final Handle release
drops the count after resource, origin, writer and node close callbacks.
No new allocation, interface boxing or object freeing is introduced. Both
architectures' source and generated C received independent lifetime review.

Bind aliases have separate counts. Namespace copies start with zero counts;
inherited descriptions retain the original attachment. Lazy detach permits
retained descriptions to finish, and a replacement attachment remains
independent. Authorization still precedes ordinary-unmount admission.

Run the [V controller](README.md) with `--case unmount-handles`, or select
`uh-0` through `uh-9`. Native `all` and Linux `move-reference` require all ten.

| Case | Qualified behavior |
| --- | --- |
| `uh-0` | A blocked FIFO read keeps its mount busy after its descriptor closes; completion releases it. |
| `uh-1` | The same holds for a FIFO write blocked behind a full buffer. |
| `uh-2` | Queued read-only file rights keep the mount busy after source close and through receipt until the imported descriptor closes. |
| `uh-3`, `uh-4` | Queued `O_PATH` file/directory rights retain the same busy state. |
| `uh-5` | Receiving without ancillary space reports `MSG_CTRUNC`, discards the rights and releases the mount. |
| `uh-6` | Only the actual sending attachment is busy; each sibling bind unmounts independently in both directions. |
| `uh-7` | A copied namespace unmounts its own attachment while the original remains pinned; ordinary-account unmount still returns `EPERM`. |
| `uh-8` | Lazy detach preserves queued rights and their file data; a fresh replacement unmounts independently. |
| `uh-9` | Closing the receiving socket disposes queued rights and releases the busy state. |

Each busy stage repeats 200 ordinary-unmount refusals, checking unchanged mount
identity and marker contents. FIFO peers use a sibling bind, so their published
descriptors cannot make the selected attachment busy. A pipe delivers the worker
thread's TID; `/proc/self/task/<tid>/stat` must report it sleeping before its
descriptor closes. The main thread then unblocks and joins it before the final
successful unmount.

Evidence is retained under `build/development-unmount-handles-20261016`.
The isolated `e42b3946c` worktree contains eleven matching mount/file sources
and the saved typed-null adaptation; other sessions' kernel changes are excluded.
Builds use V `be2eb40`, clang, LLD and `KERNEL_LINK_RANDOMIZE=0`. Captured source,
generated C, compiler hashes and independently checked receipts are retained.

| Architecture | Kernel SHA-256 |
| --- | --- |
| AArch64 | `8a18af4946f80b94c78192063aa7c1d7cfed9caca3913b599fe887475edf4568` |
| x86_64 | `94a6477ba422b25d1f8c5c358e3f8cce293dee46658129f57131e6c9e3cc94a5` |

`before-arm-b` and `before-x86-b` reproduce premature successful ordinary unmount
on the previous kernels with an in-flight read after descriptor close (site
3500). `before-rights-arm` and `before-rights-x86` reproduce the same premature
success for queued `SCM_RIGHTS` using `uh-2`. `all-arm-b` and `all-x86-b` run
the corrected full native suite with a 3600-second limit. `linux-arm-b` and
`linux-x86-b` run the portable suite with the identical probe executables on
Linux 6.12.51-0-virt. `single-arm` selects `uh-5`; `stale-cache` refuses the
earlier probe before image construction.

Both architectures pass 378 native verdicts and 347 portable Linux verdicts.
`cold-arm` and `cold-x86` each pass three persistent Services cold boots, eleven
validated job/service/shutdown receipts and three clean read-only filesystem
checks, including immediate unmount attempts and backend writer-admission
rollback probes. The artifact audit checks the count gate, one-time admission,
final callback ordering, no heap scratch, matching probe artifacts and source
snapshots, plus cold-boot continuity and filesystem checks.

The initial `all-arm`/`all-x86` runs reached the existing `recvmsg(MSG_PEEK)`
limitation at site 3502 (`EOPNOTSUPP`) in the first version of `uh-5`.
The corresponding initial Linux runs pass. The maintained case qualifies
ancillary truncation/disposal without that unsupported flag; all final runs use
fresh matching probes. Those initial logs and artifacts remain available.

This pin begins at descriptor admission. Opens blocked before their first
publication still use the [late-publication refusal](unmount-publication.md),
which differs from Linux keeping that mount busy for the entire open. Such
unpublished opens, handles without attachment identity, cwd/root and executable
publication, mount reclamation and full OCI/rootless acceptance remain open.
