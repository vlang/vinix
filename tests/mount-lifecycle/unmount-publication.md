# Descriptor publication during unmount

Ordinary unmount closes descriptor admission before scanning existing process
tables. Single and paired insertion check the description's actual attachment
while holding the destination descriptor-table lock. If admission succeeds,
unmount must observe the published descriptor or refuse on table contention.
If unmount closes admission first, insertion returns `EBUSY` without changing a
slot. The existing failure paths release the caller-owned description.

The admission callback is installed by the VFS module initializer before process
execution. It takes the mount lock only while reading the shutdown gate; unmount
releases that lock before inspecting process tables. No new reference counts,
allocations, frees or resource ownership are introduced. Failed unmount attempts
reopen admission, including refusals from descriptor/cwd/mapping/image checks.
Lazy detach leaves admission open. Bind aliases and copied namespaces use their
own actual attachment; authorization still precedes shutdown admission.
New cwd/root path walks first resolve saved directory contexts to the calling
namespace's mount copies. Missing identities remain foreign routes. Inherited
descriptor contexts retain their original attachments.

This prevents a blocked filesystem open from publishing a descriptor after its
attachment unmounts ordinarily. It does not yet keep the mount busy for the
entire blocked open: Linux does, and that stronger ownership accounting remains
open. The two late-completion cases are therefore native-only. The other eight
cases compare the identical probe executable with Linux.

Run the [V controller](README.md) with `--case unmount-publication`, or select
`uo-0` through `uo-9`. Native `all` requires all ten cases and Linux
`move-reference` requires the eight portable cases.

| Case | Qualified behavior |
| --- | --- |
| `uo-0`, `uo-1` | A blocked FIFO reader/writer cannot publish after successful ordinary unmount; it returns `EBUSY`. Native-only. |
| `uo-2`, `uo-3` | Lazy detach permits a blocked reader/writer to complete. A replacement mount unmounts independently. |
| `uo-4` | Descriptor-busy refusal reopens admission; a pending open completes and its new descriptor keeps the mount busy until close. |
| `uo-5` | Unmounting a sibling bind alias does not refuse publication on the original attachment. |
| `uo-6` | Removing the parent's original mount does not close admission to a child's copied mount. The new descriptor pins the copy until close. |
| `uo-7` | Ordinary-account unmount returns `EPERM` without closing admission for an existing blocked open. |
| `uo-8` | A new relative-cwd open uses the copied namespace's mount after the original unmounts. Leaving that cwd exposes the new descriptor as the copy's sole busy holder. |
| `uo-9` | A new absolute-root open succeeds from the copied namespace's retained root after the original mount unmounts. Process exit releases the root and descriptor. |

A sibling bind keeps the same FIFO reachable after detach. A pipe synchronizes
the child's entry, and `/proc/<pid>/stat` must report its single thread sleeping
before unmount. Only then does opening the opposite FIFO end release the wait.
The counterpart stays open until the child's result is acknowledged. Published
description checks repeat 200 refusals with stable identity and marker contents.

Evidence is retained under `build/development-unmount-publication-20261016`.
The isolated `e42b3946c` worktree contains eleven matching mount/file sources
and the saved typed-null adaptation; other sessions' kernel edits are excluded.
Builds use V `be2eb40`, clang, LLD and `KERNEL_LINK_RANDOMIZE=0`. Source snapshots,
generated C, compiler hashes and independently checked receipts are retained.

| Architecture | Kernel SHA-256 |
| --- | --- |
| AArch64 | `2fd08851961b2001b383d36f29598cb8e0cc1485af301ed46b6955f50c73a5d3` |
| x86_64 | `92e7824cd381ae343bfc0459519b7774fd7916a6ee68a687cbcd5809fef6c75c` |

`before-arm-c` and `before-x86-c` reproduce a descriptor returned after ordinary
unmount on the previous kernels, at site 3400. `all-arm-c` and `all-x86-c` run
the full corrected native suite with a 3600-second limit; `linux-arm-c` and
`linux-x86-c` run the portable suite using the identical probe executables on
Linux 6.12.51-0-virt. `cold-arm-b` and `cold-x86-b` retain three persistent
Services cold boots with immediate unmount attempts, backend-busy retries and
writer-admission rollback checks. `single-arm-c` selects `uo-4`; `stale-cache`
refuses a pre-change probe before image construction or boot.

Both architectures pass 367 native verdicts and 336 portable Linux verdicts.
Each also passes three independent persistent Services cold boots, eleven
validated job/service/shutdown receipts and three clean read-only filesystem
checks. The artifact audit checks probe identity, captured sources, compiler and
artifact hashes, startup callback registration, gate-before-scan ordering,
single/pair insertion checks under table locks and absence of new heap scratch.
The private `linux-control` V controller selects `uo-0`/`uo-1` with the same
probe executables: `linux-inflight-{arm,x86}-{0,1}` all refuse ordinary unmount
with `EBUSY` at site 3404 before releasing the FIFO rendezvous. These controls
confirm the documented difference from native late-publication refusal.

Earlier evidence remains separate: `all-arm` exposed the copied-directory
context regression at site 3013; its initial kernels/sources are retained.
The `linux-*-b` root test used a foreign escape descriptor and reached the old
namespace's unmounted path. The corrected root case checks reads before exit.
`all-arm-b` encountered `ENOMEM` in the existing `ef-8` exec test. Its cause
is not established. The identical final probe's isolated `ef-8` passes on both
previous and corrected kernels (`exec8-old`/`exec8-new`), and the final full ARM64
suite passes. These earlier failures are retained in the artifact audit.

The subsequent [description lifetime checks](unmount-handles.md) cover published
descriptions retained by in-flight operations after descriptor removal, mappings
and queued descriptor passing. Unpublished blocking opens, executable and
cwd/root publication, mount reclamation and full OCI/rootless acceptance remain
open.
