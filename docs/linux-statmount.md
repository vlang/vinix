# Native statmount

`statmount` reads an attachment in the caller's mount namespace by its unique
ID, as returned by `statx` or `listmount`. It reports the attachment and parent
IDs, mount attributes, filesystem type, and the namespace ID. For recognized
filesystem types it reports the device, filesystem magic, and the backing
filesystem's read-only state. Each returned field group is marked in the result
mask.

The filesystem-relative root follows the bind source, including subsequent
renames. The mountpoint follows the attachment and is relative to the caller's
saved root. Moves keep the attachment ID and update its parent and mountpoint.
Detached and unknown IDs return `ENOENT`. A mount outside the caller's root
requires `CAP_SYS_ADMIN` over the namespace and yields an empty mountpoint.

The syscall accepts both Linux 6.12 request layouts. Its zero-initialized
512-byte result header can be truncated for numeric requests. String offsets
are relative to the end of the fixed header and follow a leading NUL. A short
string buffer returns `EOVERFLOW` before copyout. The kernel releases both
mount locks before copying the result to userspace.
[Linux 6.12.51 implementation](https://github.com/gregkh/linux/blob/v6.12.51/fs/namespace.c)

Foreign namespace queries return `ENOENT`. Propagation fields describe the
private mount model, with no peer or master groups. The mount-options string
is omitted. Combined strings use a bounded 12 KiB scratch buffer plus the
leading NUL, so sufficiently deep paths can return `EOVERFLOW`.

## Qualification

One unchanged probe ELF per architecture passed on Vinix and Linux 6.12.51.
The probe checks request versions, error ordering, exact-fit string output,
mount IDs and device numbers from `statx`, the namespace ID shared with
`listmount`, and bind sources and mountpoints containing spaces. It also
checks that the ID survives a move and that the reported paths follow a source
rename, chroot and lazy detach. The baseline Vinix kernels returned `ENOSYS`.

Production builds used `d9908a099` plus the archived source patch. Independent
review checked mount ancestry lifetimes, lock order, scratch ownership and
copyout on both architectures. The allocation checker reported the same
existing findings and the same 306 AArch64 and 254 x86-64 allocation sites as
the baseline. The `listmount`, `statmntid`, `namespace`, `clonefsns` and
`open` regressions passed on both architectures.

| Architecture | Probe ELF | Vinix kernel | Vinix serial log | Linux serial log |
| --- | --- | --- | --- | --- |
| AArch64 | `45d397ebea22c71d` | `564a893572644f05` | `48b6c56759e30d66` | `ae8854c4608fe4b7` |
| x86-64 | `6ee1d96eeb23c663` | `792d5ab631fa7867` | `9f5bfbed50bebc87` | `98b3f97a3850f817` |

Hashes are SHA-256 prefixes. The restored and verified archive is
`~/.cache/vinix-r15/statmount/qualification.tar.zst`, with SHA-256
`4773dc65c771e926ec975a9289f8b1230d770041bf8532c1657c795c5298f173`.
Decode it with `zstd --long=28 -dc` before extracting the tar stream.
