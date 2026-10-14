# UNIX socket pathname attributes

A bound UNIX socket replaces its namespace resource with a transport resource.
Although the transport retained the original inode, pathname xattr calls did
not reach its storage and returned `ENOTSUP`, hiding inherited access ACLs.

Pathname calls now borrow the inode through a dedicated resource interface.
They retain the resolved node and original resource until dispatch, backend
I/O, metadata refresh and notification finish. Cleanup runs after namespace
lookup unlocks. Successful set/remove refreshes the socket's mode and change
time from the backing inode; failed changes leave that view unchanged.

Projection preserves the existing pathname policy, MAC, owner/capability,
mount and overlay namespace checks, with additional read-only and immutable
checks on the projected backend. Descriptor calls keep their original resource:
a socket description cannot acquire filesystem ACL authority through its name.
All four descriptor xattr calls reject `O_PATH` with `EBADF` before reading user
pointers or touching output buffers.

The maintained V probe stages six inherited ACL fixtures per backend as root,
then runs as UID/GID 1000 with supplementary groups cleared. It checks:

- Pathname and no-follow ACL reads, size queries, listing and short-buffer
  `ERANGE`, including root updates on a live named socket.
- A nonowner's ACL set/remove refusal with `EPERM`; owner entry precedence
  over a named entry for the same UID; immediate connection denial/grant after
  ACL changes and matching mode bits.
- Access ACL removal and restoration, `ENODATA` after removal and preserved
  traffic on an established connection throughout the changes.
- Invalid ACL permission bits (`EINVAL`), a default ACL on a socket (`EACCES`),
  and unauthorized user/trusted/capability writes (`EPERM`). The capability
  request carries a valid version-2 payload so it tests authorization.
- Socket-description ACL get/set/remove refusal with `ENOTSUP`, and all four
  `O_PATH` descriptor calls with ordinary and invalid user pointers. The
  output buffer remains unchanged.
- Repeated direct-ext2 and ext2-upper updates, inode retirement, existing
  ownership rollback checks and read-only remount persistence of owner,
  mode, ACL and explicit timestamps.

On 14 October 2026, results were retained under
`build/development17-20261013`:

| State | Result |
| --- | --- |
| `socketxattr-arm-before-e`, `socketxattr-x86-before-e` | Previous backing-ACL kernels fail assertion 559: live pathname ACL read returns `ENOTSUP`. |
| `socketxattr-arm-basic-c`, `socketxattr-x86-basic-c` | Updated native tmpfs probe passes. |
| `socketxattr-arm-linux-d`, `socketxattr-x86-linux-d` | The exact corresponding native probe ELF passes in Linux 6.12.51-0-virt. |
| `socketxattr-arm-after-c`, `socketxattr-x86-after-c` | Tmpfs/direct-ext2/overlay ACL checks, two batches of 32 socket cycles per disk backend and read-only remount pass; the controller requires the xattr verdict. |
| `socketxattr-arm-all-b`, `socketxattr-x86-all-b` | Existing atomic replacement, backend failure, mixed lifetime, whiteout, opacity and persistence checks pass. |

All 18 ARM slab classes plus the large count and all 14 x86 classes plus the
large count are equal between batches, with zero writes after free. All four
final volumes pass read-only `e2fsck -f -n`. The allocation audit retains the
same 182 baseline file/kind findings without expanding the allowlist.

| Input | SHA-256 |
| --- | --- |
| Fixed ARM kernel | `bc9427a3451c46dfc5acf794421fe006657adb09d63964cd1409f63eecfdd2d4` |
| Fixed x86 kernel | `087e6039a3ff191b18aff5439a9f1c278ce7fd5f25e755fe361df0bc2643a7d7` |
| Xattr fixture | `b0bb17dc920611492451bea0cd4b2c32c7a43a378d5f82aeda52828c6c6e56da` |
| ACL fixture | `e8e96787a22fb3a595f36bd55741c3d48a658c8460b846dda46c6fba3731c71d` |
| Socket fixture | `ab8bf70e3b749689d9e3efd85d71484f9da915bdfe95c96f03c4efc753b43346` |
| Shared ARM native/Linux probe | `f446d5e8682ffad5cf7ceb17d59297f61941f65f6e7cea0011ffe4ee7885d551` |
| Shared x86 native/Linux probe | `f3c73487f937a40ad93e2f8eb98c7b89dda5be85728051e6b6f97c57895e6a74` |

Both isolated kernels use the pinned compiler described in
[the backing ACL qualification](socket-acl.md), with link seed 17. This patch
adds only `fs/xattr.v`, `resource/path_xattr.v` and the pathname callbacks in
`socket/unix/metadata.v` to the previously qualified source. The evidence
checker compares other reviewed filesystem/socket files with commit
`89d561213`, normalizing only the three documented per-open creation bookkeeping
differences in VFS. Concurrent checkout edits are excluded from these builds.

`socketxattr-evidence.v` checks receipts, source and artifact hashes, both old
kernel controls, all slab samples, four filesystem checks and identical native
and Linux probes. Its assertion-enabled run is `socketxattr-evidence-final.log`.
`socketxattr-lifetime-review.md` approves both source and generated C, including
caller-stack interface dispatch without heap boxing or temporary promotion.
The pinned allocation audit is `socketxattr-allocation-audit-a.log`. Repeat the
cases with [the controller instructions](README.md).

The subsequent ARM smoke run `socketxattr-desktop-perf-b` uses the same fixed
kernel, independently extracted from its running boot disk. All 36 batches of
200 syscall operations retain zero bytes per operation; all four 300-process
churn batches retain zero bytes with no additional slab pages. The cache test
writes 32 MiB and records 16 MiB cached. Desktop idle, application launch and
dragging pass their five-second and process-count checks. The complete report,
serial transcript and assertion-enabled verification are retained in
`socketxattr-desktop-perf-b.json`, `socketxattr-desktop-serial.log` and
`socketxattr-perf-evidence-final.log`.

This kernel regression uses a frozen prebuilt ARM desktop (SHA-256
`ff2ff6e838a04b4b9812f29aff1ab070e4e13a12f4a341a0b4a1ac9613446674`)
and private cached initramfs (SHA-256
`d491b349c45b1fb2b5052b4a41fbb90857cf68488c0e6b17caafbe1d879843a9`).
It does not qualify concurrent desktop changes. The initial preparation
`socketxattr-desktop-perf-a` started before that private image finished copying;
ISO construction refused its changing size and no guest booted. The fresh
passing run uses the completed, pinned inputs.

Earlier reference failures remain separate: the initial probe assumed a
creation ACL mask unaffected by umask, used an unsupported ACL wire version
and used a malformed capability payload. Final tests set the mask explicitly,
use supported ACL version 2 with invalid permission bits and a valid capability
payload. Native creation umask behavior and the unsupported-version errno
still differ from Linux; they are outside this qualification.

Lower-only socket copy-up still returns `EPERM`. The transport and pathname
still share metadata representation; full Linux sockfs separation, generic
metadata mutation/rollback concurrency, broader capability/MAC/namespace
matrices and OCI/rootless-runtime acceptance remain open. Ext2 cleanup retains
the existing 25-second final retirement wait; crash recovery with pending
cleanup and unmount draining remain unqualified.
