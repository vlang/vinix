# Overlay inode flag updates

`FS_IOC_SETFLAGS` previously changed the inode reached through the merged node
directly, modifying a lower layer instead of creating an upper copy. It now
validates the original argument, namespace, capability, mount and securelevel
before selecting the writable resource, then checks upper support, MAC and
securelevel before applying the flags. An authorized unchanged value remains
a no-op. This follows the upper-layer destination used by
[Linux v6.12 file-attribute updates](https://github.com/torvalds/linux/blob/v6.12/fs/overlayfs/inode.c).
Vinix retains its existing supported bits and backend flag storage.

Copy-up also refuses an orphaned or removed lower-only alias under
`overlay_lock`. A held descriptor after unlink or rename replacement must not
recreate its former name or overwrite a whiteout/new destination. Already-upper
aliases retain the existing early return and allow updates to their held inode.
The change adds no owned reference or allocation; the syscall descriptor and
existing overlay entry keep the original and selected upper resources alive.

Root prepares the lower tree before any merged lookup. It sets append-only
and immutable flags through an ext2-upper overlay, clears existing lower flags
through other merged names, and verifies both held-descriptor and direct-upper
results. Lower flags and bytes must remain unchanged. Invalid pointers,
unsupported flag bits and a valid unchanged value must create no upper file.

The ordinary-account worker clears supplementary groups and drops to UID/GID
1000. Two batches each repeat 200 cycles, refusing both changed and unchanged
flag values without privilege. No raw upper path may appear. The worker checks
append-only write/truncate/unlink restrictions, a permitted append, immutable
open/chmod/xattr/unlink refusals, writable cleared flags and append-only directory
creation without deletion. Final ext2 remounts preserve the upper flags; the
socket case additionally refuses root flag setters with `EROFS` on its read-only
remount. The [separate ext2 loading fix](ext2-flags.md) restores those on-disk bits.

A separate root tmpfs-upper probe holds lower-only descriptors across unlink
and rename replacement. Both setters must return `ENOENT`, preserve the removed
whiteout/replacement content and leave lower bytes/flags untouched after overlay
remount. An unlinked already-upper descriptor must still accept a flag update.

Final results are retained in `build/development17-20261013`:

| State | Result |
| --- | --- |
| `inodeflags3-arm-before-b`, `inodeflags3-x86-before-b` | Saved kernels fail assertion 654: setting an upper append flag changes the lower to `0x20`. |
| `inodeflags-arm-orphan-before-b`, `inodeflags-x86-orphan-before-b` | Preliminary routing patch without the lock-protected guard permits a removed lower-only descriptor's setter; assertion 670 fails. |
| `inodeflags3-{arm,x86}-basic-a` | Existing tmpfs socket and pathname-xattr probe passes. |
| `inodeflags3-{arm,x86}-linux-a` | Identical basic probe passes Linux 6.12.51-0-virt; this is the existing portable socket probe, not the new flag-storage cases. |
| `inodeflags3-{arm,x86}-after-a` | Flag, held-alias, xattr preflight and persistent socket regressions pass, including read-only remount. |
| `inodeflags3-{arm,x86}-all-a` | Flag and existing replacement, failure, retention, whiteout, opacity and persistence regressions pass. |

Flag refusal phases 60/61, xattr phases 50/51, socket phases 40/41 and overlay
phases 30/31 compare every live class and large-allocation count. All 19 ARM
counts and 15 x86 counts match with zero writes after free. Four final ext2
volumes pass read-only `e2fsck -f -n`; the global audit retains the same 182
baseline file/kind failures without allowlist changes.

The isolated `kernel-inodeflags3-{arm,x86}-tree` worktrees contain only the
three product changes above the qualified xattr preflight sources. The pinned
compiler, existing pointer-return normalization and link seed 17 remain fixed;
x86 reuses its qualified generated sampler. Initial fixture compilation/setup,
the unguarded routing and missing ext2-loading attempts remain separate from
final qualification. The independent review is `inodeflags3-lifetime-review.md`;
`inodeflags3-evidence.v` checks source/C hashes, controls, fixture receipts,
allocation samples, four filesystem checks and basic-probe identity with Linux.
Its assertion-enabled record is `inodeflags3-evidence-final.log`.
The combined probes contain the direct-ext2 fixture from commit `d6a33ce24`,
which these selected cases do not call. Its separate
[retirement-wait qualification](ext2-flags.md) uses the updated direct fixture
and its own frozen probe. The checker pins both fixture versions explicitly.

Generic protection-bit preservation during other authorized copy-up operations,
concurrent metadata authorization, lower-only anonymous copy-up after unlink,
broader capability/namespace/MAC and securelevel matrices, crash recovery and
OCI/rootless acceptance remain open. Authorized requests that later fail a
backend check can still leave an upper copy. Existing 25-second retirement
waits remain in the fixtures.
