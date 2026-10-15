# Unmount with a running executable

Ordinary unmount returns `EBUSY` when a live process's recorded executable
belongs to the target attachment. The existing process-table scan reads
`exe_node` and `exe_mount` under the process's filesystem lock, before writer
admission or filesystem shutdown. Capability checks still run first. Nested
locks are tried without waiting; contention conservatively refuses this attempt.

The executable retains the loader's actual mount object. Its route is not
resolved against the process's current namespace: copying a namespace leaves
the original image attached to its original mount. A bind alias has independent
identity even when its executable inode is shared. Published zombies no longer
run an image and do not retain this busy state. No allocations, reference counts,
frees or object lifetimes change.

Run the [V controller](README.md) with `--case unmount-exec`, or select `ue-0`
through `ue-7`. Both native `all` and the same-executable Linux `move-reference`
suite require all eight cases and their group verdict.

| Case | Qualified behavior |
| --- | --- |
| `ue-0` | An ordinary-account executable pins its mount after the loader closes its file description. An unauthorized unmount still returns `EPERM` first. |
| `ue-1` | An unlinked ELF executed through `execveat(AT_EMPTY_PATH)` pins its mount after close-on-exec closes its descriptor. |
| `ue-2` | Copying the running process's namespace permits removal of its copied attachment while the original remains busy. |
| `ue-3`, `ue-4` | Execution through either bind alias pins that alias; the other attachment can unmount independently. |
| `ue-5` | Lazy detach permits continued execution and reading `/proc/self/exe`. A fresh replacement mount can unmount ordinarily. |
| `ue-6` | A published, unreaped zombie no longer pins the image's mount. |
| `ue-7` | Replacing the executable with an image on another mount releases the previous mount while the same process remains alive. |

The fixture copies its static native probe, closes all source/output descriptors
before execution and keeps cwd/root outside the image mount. Pipes establish
that the new image has started before each busy check. Refusals repeat 200 times
with mount identity and marker contents unchanged. The child continues executing
and verifies its image signature after the parent finishes checking. The zombie
case uses `waitid(WNOWAIT)` and verifies the proc entry remains before unmount;
the replacement case synchronizes both executable generations without an exit.

Evidence is retained under `build/development-unmount-exec-20261015`. Builds use
the isolated `e42b3946c` worktree, its saved typed-null adaptation and five
mount/unmount sources matching this change; other sessions' kernel edits are
excluded. Both architectures use V `be2eb40`, clang, LLD and
`KERNEL_LINK_RANDOMIZE=0`. Source snapshots, generated C, compiler hashes and
independently checked receipts are retained with the evidence.

| Architecture | Kernel SHA-256 |
| --- | --- |
| AArch64 | `e254baee8b183027c4797127099546654b6be2e1c04a5935339ce857fb720784` |
| x86_64 | `0926ad970ebf3ad6b1571ca74c005f08ccd0afd090a8a0ceaebace8d69b6532f` |

`before-arm-b` and `before-x86-b` reproduce premature unmount success on the
previous kernels at site 3104. The original `before-*` states also reproduce
that bug. The first Linux states and `after-arm` retain a fixture failure caused
by using a pipe helper that closed descriptors needed by the new handshake;
the corrected fixture keeps them open until the conversation completes.
`after-arm-b` runs the corrected complete group. `all-x86` retains a 900-second
timeout during the removal group, with no guest assertion failure. `all-arm`
and `all-x86-b` run the full native suite; the x86 retry permits 3600 seconds
without changing its kernel or probe. `linux-arm-b`/`linux-x86-b` run the portable
suite with identical probe executables on Linux 6.12.51-0-virt. `cold-arm` passes
the initial persistent Services shutdown regression. `cold-x86` retains a
second-boot broker-readiness failure at site 458, before the unmount exercise.
`cold-arm-b`/`cold-x86-b` use the
corrected listener-readiness gate. `single-arm` and `stale-cache` record individual
selection and refusal of a pre-change cached probe.

Both architectures pass 334 native verdicts and 304 portable Linux verdicts.
The corrected cold-boot gate passes three independent persistent boots, eleven
validated job/service/shutdown receipts and three clean read-only filesystem
checks per architecture. The ARM64 single-case selection passes `ue-7`, and a
pre-change cached probe is refused before image construction or boot. The
artifact audit verifies executable identity across control, corrected and Linux
runs, source hashes and the generated guards' lack of heap allocation.

These checks observe already published executable state. Concurrent loader
publication still needs mount admission and ownership accounting. Interpreter,
shared-library and arbitrary executable mappings, read-only descriptions and
mappings, mount reclamation and full OCI/rootless acceptance remain open.
