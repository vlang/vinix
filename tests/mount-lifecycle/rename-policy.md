# Rename attachment policy

`renameat` and `renameat2` now capture each starting directory with its mount
route, then carry both routes through the rename walks. Read-only admission uses
the selected attachments and backend state instead of inferring policy from
inodes shared by bind aliases. Retained descriptions preserve their routes
after lazy detach or retirement of their original mount namespace.

Explicit routes must name the same mount object. Distinct writable bind mounts
and an inherited description versus a newly opened copied-namespace description
return `EXDEV`, even when their backing filesystem and stable mount IDs match.
Operations entirely through either inherited or newly opened descriptions remain
valid. The mount-boundary check follows the existing mounted-name refusal so a
mounted entry remains protected. Internal inode-only `fs.rename` callers infer
their contexts under the VFS lock and keep the conservative read-only fallback.

The complete existing rename body retains its flag checks, authorization,
immutable/append-only protection, permissions, filesystem/type/ancestor checks,
backend hooks, atomic map publication, reparenting, notifications, orphan pins
and deferred cleanup. The new contexts live on the stack. This change adds no
owned allocation, retained context address, release or reference-count transition.

[Linux v6.12's `do_renameat2`](https://github.com/torvalds/linux/blob/v6.12/fs/namei.c)
also requires matching source/destination mounts and a writable mount. Its
ordering differs from Vinix's retained validation order; combined failures such
as a cross-mount rename involving a read-only route remain unqualified here.

Use `--case renames` or `rp-0` through `rp-9`. Native `all` and Linux
`move-reference` include the group. Each route pair repeats sixteen rounds of
regular-file, literal-symlink and empty-directory operations through `renameat`,
zero-flag `renameat2`, `RENAME_NOREPLACE` with an absent destination, and
`RENAME_EXCHANGE` with an existing destination. Ordinary operations replace an
existing entry. Exchanges verify both resulting names; other successful moves
verify the old name disappears. Both aliases must expose the expected identities,
mode, ownership and size. Symlinks retain literal targets, including a dangling
target, and never rename their referents.

Read-only attempts must return `EROFS`, preserve both entries or the destination's
absence, and leave parent/source/destination metadata and timestamps unchanged.
A UID/GID 1000 child repeats the denials with `EACCES` through the `0755` writable
directory and `EROFS` through its read-only alias. Held descriptions retain their
inode, owner, mode and regular-file contents after replacement or exchange;
replaced nondirectory entries have zero links. Directory descriptions remain
stat-able. Cleanup happens after these retained-description checks.

| Case | Routes exercised |
| --- | --- |
| 0 | Directory descriptors, both bind-policy directions |
| 1 | Descriptors opened after a namespace copy, both directions |
| 2 | Chroot root and cwd through separate aliases, both directions |
| 3 | Absolute paths with invalid dirfds and symlinked parents, both directions |
| 4 | Read-only bind retained after lazy detach |
| 5 | Descriptors retained after a worker's private namespace retires |
| 6 | Read-only source/writable bind established before the first operation |
| 7 | Directory descriptions inherited across a namespace copy with unchanged flags |
| 8 | All four operations across writable bind/copied mount boundaries; valid moves through inherited and fresh descriptions |
| 9 | Repeated cross-directory moves preserve a held directory's `..`; mounted source/destination entries remain busy |

This qualifies the attachment checks on tmpfs. Divergent inherited-FD remount
flags, concurrent remount/setns/chdir, invalid flags and combined-error ordering,
broader sticky/ACL/MAC/attribute combinations and persistent/overlay backend
integration remain open. The existing mount/namespace ownership is unchanged;
no allocation-flatness or mount reclamation claim is made. Full OCI/rootless
acceptance and roadmap section 17 remain in progress.

Evidence from 2026-10-15 is retained under `build/development17-20261013`.

| States | Result |
| --- | --- |
| `mount-rename-{arm,x86}-rp-0-before-b` | Previous kernels falsely return `EROFS` through writable aliases. |
| `mount-rename-arm-rp-{5,6}-before-b`, `mount-rename-x86-rp-5-before-b`, `mount-rename-x86-rp-6-before-c` | Previous kernels rename entries through retired and live read-only routes. |
| `mount-rename-{arm,x86}-rp-8-before-b` | Previous kernels allow a rename between separate writable bind mounts. |
| `mount-rename-arm-renames-after-b`, `mount-rename-x86-renames-after-a` | All ten corrected native rename cases pass. |
| `mount-rename-arm-all-after-a` | The cumulative native mount suite passes, including all ten rename cases. |
| `mount-rename-{arm,x86}-linux-a` | The same final probe ELFs pass the portable Linux 6.12.51 suite. |

| Architecture | Final kernel SHA-256 | Shared native/Linux probe SHA-256 |
| --- | --- | --- |
| aarch64 | `d3421bf5946ff133110c0183f4a6e8c40ef3094e2f4c1eb09e9961e7a0b7344e` | `b3e8f94c4758f3ae5749877618d2ebde90fac9a90817a89ee95f606f8619a851` |
| x86_64 | `58232cc7fe940dce108d1c26ee586ab614f6ba7077db169cea64b403c4254e87` | `392f8ac8632b1bb85eb68fb91222431394c5002ed9a95157e9fdfe2bb4273a1e` |

Both isolated builds start from the qualified hard-link inputs and change only
the rename wrapper/helper and syscall in `vfs.v`. The other session's staged
pointer-return spelling edits, the pre-existing open-created descriptor hunks
and later checkout changes are excluded. Each `mount-rename-{arm,x86}-input`
retains its complete kernel source manifest, changed source, generated C, ELF
and hashes. Builds use V source `f6358ecff9cffbf2d8b03e6a09269aac7707e26c`,
compiler SHA-256 `f532f1b78b7f6f385bfa0bff05eb98a714d2355028748b3dfaa7d8e4025eee39`
and link seed 17. Native ARM uses HVF/four CPUs; x86 uses TCG/two. Networking
is disabled. Focused native timeouts are 300/900 seconds; the cumulative ARM
suite and Linux references use 600 seconds. A new cumulative native x86 suite,
desktop performance run and persistent/overlay integration are outside this
qualification.

The assertion-enabled source/C audit compares the entire generated rename
helper against the previous rename function after only its signature change,
internal route initialization, two route-aware walks, attachment read-only
checks with the conservative internal fallback, and exact mount-object admission
after mounted-name refusal. The complete generated syscall must match after
the two stack contexts, directory/route capture and helper dispatch. All other
operations, including every existing free, lock release and publication/cleanup
step, must match; generated temporary numbers are normalized. Common route,
policy, authorization, reparenting, overlay, orphan and cleanup helpers are
compared unchanged. Per-architecture `rename-c-audit.txt` and
`mount-rename-source-evidence-a.log` retain those results.

The final `mount-rename-evidence-a.log` audit verifies all eighteen fixture
hashes, artifacts, receipts, boot images, copied probe/C identity, controls and
positive native/Linux markers. A post-commit audit compares the committed
wrapper, helper and syscall with both isolated inputs and accounts for the same
excluded pre-existing descriptor hunks in the parent commit.

Initial `rp-0-before-a` probes failed C compilation because this V compiler
inferred unsigned-byte pointers for local C-string conditionals. Explicit
character-pointer casts fix the fixture without changing its assertions. Final
`rp-0-before-b` probes supply the shared ELF and generated C for every qualified
native control, corrected run and Linux reference.

Disk pressure interrupted the first corrected ARM state and the x86
`rp-6-before-b` control before usable artifact results were written. Those
incomplete states are retained; fresh states supply the qualification receipts.
Completed mount/overlay test images are losslessly archived as `test.iso.gz`.
Every completed archive's decompression hash is verified against its original
receipt before the uncompressed copy is removed. Adjacent `test.iso.archive.txt`
records give the hash and restoration command. Failed compression attempts
retain their original image. Sources, probes, kernels, logs and receipts remain
available; identical kernel copies can use independent APFS copy-on-write clones
without changing their hashes.
