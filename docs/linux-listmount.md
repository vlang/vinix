# Native listmount

`listmount` enumerates unique mount IDs from the calling mount namespace.
`LSMT_ROOT` starts at the caller's saved filesystem root. An explicit unique
ID selects the mount's descendants and excludes the selected mount itself.
Selecting a mount outside the caller's root requires `CAP_SYS_ADMIN` over
the mount namespace. The enumeration follows mount attachments, so two bind
aliases of an inode can have different descendants. Mount moves preserve IDs
and change ancestry. Lazy detach removes the attachment from enumeration.
[Linux 6.12.51 listmount implementation](https://github.com/gregkh/linux/blob/v6.12.51/fs/namespace.c#L5414)

Results are in ascending ID order unless `LISTMOUNT_REVERSE` is set. A cursor
continues strictly past its ID even after that mount detaches. The syscall
accepts the 24-byte and 32-byte request layouts and zero-filled extensions
up to one page. It copies only the IDs returned. Large output buffers use
the caller's kernel scratch budget. The mount table is unlocked before
copyout.

Vinix enumerates the active records in the caller's mount table. Existing
mount propagation approximations still apply. In particular, initial
namespace attachments reached only through fallback pathname lookup after
a namespace copy are outside that copy's enumeration. Foreign mount
namespace queries return `ENOENT`. `statmount` remains unavailable.

## Qualification

The same probe ELF per architecture passed on Vinix and Linux 6.12.51. It
checks request versions and error ordering, both scan directions, cursor
wrap, bind ancestry, mount moves, namespace copies, and a chroot whose root
is overmounted after entry. It verifies that an unprivileged caller cannot
query a mount outside that root, that detached mounts are excluded, and
that a detached ID is still a valid cursor. The previous Vinix kernels
returned `ENOSYS`.

Production builds used `c39228822` plus the archived source patch.
Independent review checked the mount-table lock order, scratch ownership,
and copyout. The allocation checker reported the same existing failures
and the same 306 AArch64 and 254 x86-64 allocation sites as the baseline.
The `namespace`, `statmntid`, `clonefsns`, and `open` regressions passed
on both architectures.

| Architecture | Probe ELF | Vinix kernel | Vinix serial log | Linux serial log |
| --- | --- | --- | --- | --- |
| AArch64 | `ea1cca238a26f5ef` | `0c088474cd339596` | `ec4bc9e721289545` | `cd027371e500e545` |
| x86-64 | `8995e500d333f938` | `1d1618dba525378a` | `5325d1eb17bc7a47` | `7157c6f5ce7881a1` |

Hashes are SHA-256 prefixes. The restored and verified archive is
`~/.cache/vinix-r15/listmount/qualification.tar.zst`, with SHA-256
`35bb08e442cd7457372f4f4b37823f9fcd9d5d16e114abde4aff3ec589a8408b`.
