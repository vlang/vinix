# Unmount with retained file mappings

Ordinary unmount returns `EBUSY` while a published process address space has a
file mapping that retains the target attachment's open description. The check
covers read-only, private writable and executable protections, including views
whose last descriptor has closed. It runs in the existing process-table scan,
before writer admission and filesystem shutdown; capability checks remain first.
Lazy detach keeps its existing behavior.

The process-table lock keeps each process and its current page-map pointer
alive across exec/exit. A page-map try-lock protects the range list and the local
references keeping each global range and handle alive. Contention conservatively
refuses unmount instead of skipping an owner. The file module identifies its
own retained handle using both exact callback addresses before interpreting the
opaque pointer. No callback is invoked, no reference count changes and no
allocation or freeing is added. Other resource-specific mapping handles remain
opaque to this check.

A mapping selects the actual mount recorded by its original description,
including after fork or a namespace copy. Sibling bind aliases and copied mount
objects do not inherit that busy state. Anonymous mappings ignore a supplied
file descriptor and do not retain its attachment.

Run the [V controller](README.md) with `--case unmount-mappings`, or select
`uv-0` through `uv-9`. Native `all` and the same-executable Linux `move-reference`
suite require all ten cases and their group verdict.

| Case | Qualified behavior |
| --- | --- |
| `uv-0`, `uv-1` | Private and shared read-only mappings keep the mount busy after descriptor closure. Final unmap permits ordinary removal. |
| `uv-2` | A writable private mapping made from a read-only descriptor retains its attachment. A private write leaves the file unchanged. |
| `uv-3` | An arbitrary executable file mapping pins its attachment independently of the process's main image. |
| `uv-4` | Protection splits and partial unmaps retain the busy state through the final remaining fragment. |
| `uv-5` | A child's inherited mapping alone pins the mount after the parent unmaps. Ordinary-account unmount still returns `EPERM`. Exit releases the mapping before the zombie is reaped. |
| `uv-6` | A copied namespace's mount can unmount while an inherited mapping pins its original attachment. Child exit releases the original before reaping. |
| `uv-7` | A mapping through either bind alias pins that attachment while its sibling can unmount. |
| `uv-8` | Lazy detach permits retained mapping reads. A fresh replacement mount can unmount ordinarily. |
| `uv-9` | An anonymous mapping made with a valid file descriptor does not pin the file's mount. |

The fixture closes every source/writer descriptor before busy checks and keeps
cwd/root outside the selected mount. Each busy stage repeats 200 refusals with
unchanged mount identity and marker contents. Pipes synchronize inherited-view
holders. The exit cases use `waitid(WNOWAIT)` and verify the proc entry remains
before unmounting, then reap the child.

Evidence is retained under `build/development-unmount-mappings-20261015`.
The isolated `e42b3946c` worktree contains the saved typed-null adaptation and
seven mount/file sources matching this change; other sessions' kernel edits are
excluded. Builds use V `be2eb40`, clang, LLD and `KERNEL_LINK_RANDOMIZE=0`.
Source snapshots, generated C, compiler hashes and independently checked
receipts are retained with the evidence.

| Architecture | Kernel SHA-256 |
| --- | --- |
| AArch64 | `808b3bc57659eeedfa863263cbd60a418f071330c6c663b0833d6cbeb849e293` |
| x86_64 | `2a7b7570e2380461b1d6744817e3953e86e65222f5c43ee8d31c1821d48bde79` |

`before-arm` and `before-x86` reproduce premature unmount success with the
previous kernels at site 3200. `after-arm` runs the new group. `all-arm` and
`all-x86` run the full native suite with a 3600-second limit; `linux-arm` and
`linux-x86` run the portable suite with identical native probe executables on
Linux 6.12.51-0-virt. `cold-arm` and `cold-x86` retain three persistent Services
cold boots with immediate unmount attempts and bounded backend-busy retries.
`single-arm` selects `uv-4`, and `stale-cache` refuses a pre-change cached probe
before image construction or boot. The early `prepare-before.log` records a
host invocation before its generated build script existed; the subsequent
`prepare.log` records both successful builds.

Both architectures pass 345 native verdicts and 315 portable Linux verdicts.
Each architecture also passes three independent persistent Services cold boots,
eleven validated job/service/shutdown receipts and three clean read-only
filesystem checks. The artifact audit checks executable identity across control,
corrected and Linux runs, all fixture source hashes and the generated guards'
lack of heap allocation or mapping callback invocation. Single-case selection
and refusal of a pre-change cached probe pass as well.

This observes mappings already published in current process address spaces.
Concurrent mapping/exec publication and detached page maps pending destruction
remain unqualified. Descriptions held only by descriptors, in-flight operations,
queued descriptor passing, resource-specific opaque mappings and loader-owned
views without a retained file handle need complete mount ownership accounting.
Mount reclamation and full OCI/rootless acceptance remain open.
