# Unmount with retained working and root directories

Ordinary unmount now returns `EBUSY` when existing process or private thread
working/root-directory state selects the target mount. The check runs after
child-mount validation and before writer admission and backend shutdown. A
refusal changes no attachment or directory state. Explicit lazy detach retains
its existing behavior.

The process table lock protects process objects. Each directory and saved route
is read under its owning filesystem lock; private thread views are also read
under the thread-list lock that protects their publication and retirement.
Nested locks, including mount-table lookup, are tried without waiting. A busy
owner conservatively refuses this attempt instead of being skipped. Published
zombies have already released their filesystem state and are excluded.

Saved mount IDs resolve to the owner's namespace copy, including a detached
record. If that namespace has no record for a foreign route, its original
permanent mount remains selected. Bind aliases have different IDs even when
they share a directory inode. Empty boot-root contexts use the existing root
inode fallback. No mount ownership, reference counts, allocation or freeing are
added; these checks borrow fields only while their existing locks protect them.

Run the [V mount controller](README.md) with `--case unmount-paths`, or select
`ud-0` through `ud-9`. Native `all` and the same-ELF Linux `move-reference`
suite require all ten positive markers.

| Case | Qualified behavior |
| --- | --- |
| `ud-0` | The caller's cwd inside the mount prevents ordinary unmount. Capability denial still returns `EPERM` first. |
| `ud-1` | A child's chroot root pins the mount while its cwd remains outside. Restoring the root and exiting releases the busy state. |
| `ud-2` | A cwd pins its selected bind attachment in both directions. The sibling alias can unmount independently. |
| `ud-3` | A child's inherited cwd resolves to its copied namespace's attachment. The original mount can detach; the copied mount remains busy until the cwd changes. |
| `ud-4`, `ud-5` | Private thread cwd and chroot views independently prevent ordinary unmount. Leaving those views permits removal. |
| `ud-6` | A private thread that joins the original mount namespace pins the target even when its process's shared namespace differs. |
| `ud-7` | A foreign cwd imported through a proc descriptor pins a mount created after the holder copied its namespace, absent from that copy's table. The descriptor closes before the busy check. |
| `ud-8` | Lazy detach permits a retained cwd to keep reading. A fresh replacement mount can unmount ordinarily. |
| `ud-9` | A published, unreaped zombie no longer retains its previous cwd/root busy state. |

Busy checks repeat 200 times while preserving directory identity and marker
contents. Pipes synchronize holders with the unmount attempts; thread views
restore their directories before joining. The zombie case uses `waitid` with
`WNOWAIT`, verifies the proc entry remains present and unmounts before reaping.

Evidence is retained under `build/development-unmount-paths-20261015`.
The isolated `e42b3946c` worktree keeps the saved typed-null adaptation and the
five mount/unmount sources matching this change; peers' kernel edits are
excluded. Builds use V `be2eb40`, clang, LLD and `KERNEL_LINK_RANDOMIZE=0`.
`source-pins.json` and `audit.log` record source snapshots, compiler hashes,
generated C, preserved executable identity and independently checked receipts.

| Architecture | Kernel SHA-256 |
| --- | --- |
| AArch64 | `b1709f319ac1d862d8f7958246387df59612fae00620f18a9b909b1836ac6ace` |
| x86_64 | `169e183402a4f6c881383c5a955fdbc21564f6f3dc286311a6ae705207a5f61d` |

`before-arm-b` and `before-x86-b` reproduce premature success with the previous
kernels at site 3001. The earlier `before-arm`/`before-x86` states retain a
fixture compilation failure before a reserved local name was corrected.
`after-arm`/`after-x86` run the complete new group; `all-arm`/`all-x86` run the
full native mount regression. `linux-arm`/`linux-x86` run the portable suite on
Linux 6.12.51-0-virt with the identical native probe executables.
`cold-arm`/`cold-x86` retain the persistent Services shutdown and clean-filesystem
regression. Individual-case selection and stale-cache refusal are recorded
separately.

Both architectures pass 325 native verdicts and 295 portable Linux verdicts.
Each persistent cold-boot regression passes three independent boots, eleven
validated job/service/shutdown receipts and three clean read-only filesystem
checks. The ARM64 single-case run passes `ud-6`; an older cached probe is refused
before image construction or boot. The artifact audit verifies these results
against the pinned executables, sources and generated C.

These checks observe existing retained directory state. A concurrent
chdir/chroot/fchdir or namespace change can publish a later reference and remains
unqualified. Generic read-only/O_PATH and
executable mapping ownership, mount reclamation, complete bind-alias isolation
and full OCI/rootless acceptance remain open. Mounts, namespaces and cached
filesystem trees retain their existing lifetimes.
