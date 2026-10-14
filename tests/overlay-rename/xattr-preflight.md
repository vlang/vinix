# Overlay xattr authorization before copy-up

An xattr setter previously copied a lower inode to the upper before checking
its protections. Copy-up did not preserve the immutable flag, allowing UID 1000
to change an attribute on an immutable lower file. Both saved native kernels
reproduce that bypass. Refused owner, permission and namespace requests could
also leave unwanted upper files.

The shared setter now validates the value and ACL format and checks the
original resource before copy-up. The remover likewise checks the original
resource first. Overlay requests check the selected upper resource again before
the backend mutation. An overlay lower without xattr storage may still copy
into a capable upper. Existing MAC, mount, capability and DAC checks remain
active; notifications still follow successful mutations only.

The maintained V fixture prepares nine lower-only tmpfs regular files beneath
an ext2 upper. Root sets ownership, permissions and one immutable inode flag,
then the worker clears supplementary groups and runs as UID/GID 1000. It checks:

- Immutable `user.*` set/remove: `EPERM`.
- Nonowner access-ACL set/remove: `EPERM`.
- `user.*` set/remove without write permission: `EACCES`.
- `trusted.*` and file-capability set/remove without privilege: `EPERM`.
- Unsupported ACL version: `ENOTSUP`; malformed version-2 ACL: `EINVAL`.
- Invalid value pointer: `EFAULT`; unsupported flags: `EINVAL`.

After every case, the raw upper path must be absent and the lower file's
`COPYDATA` bytes and `user.keep=OLD` must remain readable through the merged
path. Each of two batches repeats all nine cases 200 times. After sampling,
an authorized setter must install `user.guard=YES` in the upper while the
attribute stays absent from the lower.

Root separately mounts a private procfs-lower/ext2-upper overlay: its lower
`version` file must refuse xattrs with `ENOTSUP`, while a setter through the
merged path must install `user.guard=ROOT` in the upper and leave the lower
unsupported.

Results from 14 October 2026 are retained in `build/development17-20261013`:

| State | Result |
| --- | --- |
| `xattrpre-arm-lower-before-a` | The preliminary early-storage check fails assertion 645 with `ENOTSUP`; this attempt is separate from final qualification. |
| `xattrpre2-arm-before-a`, `xattrpre2-x86-before-a` | Previous kernels fail assertion 635: the immutable-file setter returns success instead of `EPERM`. |
| `xattrpre2-arm-basic-a`, `xattrpre2-x86-basic-a` | Existing native tmpfs socket and pathname-xattr probe passes. |
| `xattrpre2-arm-linux-a`, `xattrpre2-x86-linux-a` | The identical corresponding basic probe ELF passes Linux 6.12.51-0-virt; this checks the existing portable socket probe, not the new overlay cases. |
| `xattrpre2-arm-after-a`, `xattrpre2-x86-after-a` | New preflight cases and authorized copy-up pass alongside persistent socket/xattr, ACL, creation-mask and read-only remount checks. |
| `xattrpre2-arm-all-a`, `xattrpre2-x86-all-a` | New preflight cases and the existing replacement, failure, retention, whiteout, opacity and persistence regressions pass. |

Phases 50/51 compare the preflight batches. The socket phases 40/41 and full
overlay phases 30/31 remain active. All 18 ARM slab classes plus the large count
and all 14 x86 classes plus the large count match, with zero writes after free.
The four final ext2 volumes pass read-only `e2fsck -f -n`. The global allocation
audit retains exactly the same 182 baseline file/kind findings; its existing
failures and allowlist remain unchanged.

The isolated `kernel-xattrpre2-{arm,x86}-tree` worktrees copy the previously
qualified [ACL wire-format kernels](acl-wire.md) and change only `fs/xattr.v`.
The first final-build attempt used an incorrect linker path and failed at the
link step; retrying with the established linker succeeded. An initial host
controller compile also failed; its logged retry passed. These attempts and the
preliminary runs remain separate from final evidence. The pinned compiler and
link seed 17 remain unchanged; x86 reuses its previously qualified generated
sampler. Independent source and generated-C lifetime review
approved the payload's extended lifetime across copy-up and existing resource
guards. It adds no allocation or owned reference, though overlapping the
payload buffer with a successful copy-up can increase peak memory.

`xattrpre2-evidence.v` checks the kernel/source/generated-C and fixture hashes,
saved controls, receipts, exact allocation samples, filesystem checks and
basic-probe identity with Linux. The assertion-enabled record is
`xattrpre2-evidence-final.log`; the allocation audit is
`xattrpre2-allocation-audit-a.log` and the hash-bound review is
`xattrpre2-lifetime-review.md`. Repeat with [the maintained controller](README.md).

This qualifies preflight authorization and input refusals on regular files.
Authorized requests that later fail backend existence, space or I/O checks may
still leave an upper copy. Concurrent metadata authorization, generic inode-flag
preservation in other copy-up paths, read-only lower and namespace/capability/MAC
matrices, crash recovery and OCI/rootless-runtime acceptance remain open. The
existing 25-second retirement waits remain in the fixture.
