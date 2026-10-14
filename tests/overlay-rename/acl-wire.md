# POSIX ACL wire-format errors

The public ACL setter returned `EINVAL` for every unsupported wire version.
It now checks a complete four-byte version header before validating entry
lengths or contents: an unsupported version returns `ENOTSUP`; a truncated
header or malformed version-2 ACL returns `EINVAL`. This follows
[Linux v6.12 ACL header decoding](https://github.com/torvalds/linux/blob/v6.12/fs/posix_acl.c#L691).

The classification reads a borrowed buffer and adds no allocation or lifetime.
Existing backend validation, disk version-1 conversion, authorization and
stored-ACL corruption checks retain their existing behavior. Rejected payloads
return before changing ACL storage or emitting its attribute notification.

The maintained ordinary-account V probe tries versions 0, 1, 3 and 255 with
lengths 4, 5, 43 and 44 through pathname and no-follow setters. A complete
unsupported header wins over a malformed entry length. Three-byte headers
return `EINVAL`; a nonzero high version byte returns `ENOTSUP`. Supported
version 2 with a five-byte payload or invalid permissions remains `EINVAL`.
The final read must match the original ACL exactly. Existing live mutation,
permission, descriptor, creation-mask and persistence checks remain active.

Results from 14 October 2026 are retained in `build/development17-20261013`:

| State | Result |
| --- | --- |
| `aclwire-arm-before-b`, `aclwire-x86-before-b` | Previous kernels fail assertion 621: errno 22 instead of 95. |
| `aclwire-arm-basic-a`, `aclwire-x86-basic-a` | Updated native tmpfs probe passes. |
| `aclwire-arm-linux-a`, `aclwire-x86-linux-a` | The identical corresponding native probe ELF passes Linux 6.12.51-0-virt. |
| `aclwire-arm-after-a`, `aclwire-x86-after-a` | Repeated tmpfs/direct-ext2/overlay attribute and socket checks, allocation samples and read-only remount pass. |
| `aclwire-arm-all-a`, `aclwire-x86-all-a` | Existing overlay replacement, failure, lifetime, whiteout, opacity and persistence regression passes. |

All 18 ARM slab classes plus the large count and all 14 x86 classes plus the
large count stay equal between batches, with zero writes after free. Four
final volumes pass read-only `e2fsck -f -n`. The allocation audit retains the
same 182 baseline file/kind findings without allowlist changes.

Separate `kernel-aclwire-arm-tree` and `kernel-aclwire-x86-tree` worktrees copy
the [creation-mask qualification](socket-umask.md) and change only
`fs/xattr.v` and `posix_acl/acl.v`. The pinned compiler and link seed 17 are
unchanged; x86 reuses the previously qualified generated sampler. The first
fixture build rejected a reused loop variable name; that failed attempt is
separate from the final controls and passing probes.

`aclwire-evidence.v` checks source and generated-C hashes, all fixture/artifact
receipts, controls, exact allocation samples, four filesystem checks and native
probe identity with Linux. The assertion-enabled record is
`aclwire-evidence-final.log`; complete kernel/probe/fixture hashes are retained
there and in the per-run receipts. The allocation audit is
`aclwire-allocation-audit-a.log`. Repeat using [the controller](README.md).

Broader capability/MAC/user-namespace matrices, socket/path metadata separation
and OCI/rootless acceptance remain open. The disk fixture keeps its existing
25-second retirement wait; pending-cleanup crash recovery and unmount draining
remain outside this qualification.
