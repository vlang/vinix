# Native move_mount

`move_mount` moves an existing attached mount within the caller's mount
namespace. Each endpoint can be a pathname relative to its directory
descriptor or an empty pathname paired with a descriptor and the matching
empty-path flag. Source and destination each have a final symlink flag.
The syscall applies Vinix's mount policy and confirms that both endpoints
belong to the current mount namespace before changing the table.
[Linux 6.12.51 implementation](https://github.com/gregkh/linux/blob/v6.12.51/fs/namespace.c)

The move preserves the attachment ID and its children. A retained descriptor
continues to name the same mount, and relative parent lookup follows its new
location. The move follows the current destination stack and publishes on top.
A detached source or unlinked destination is refused. A moved attachment and
any copied mount records hold a reference to its covered vnode. Replacing the
covered vnode releases that record's previous counted reference.

Cloned detached mounts, `MOVE_MOUNT_SET_GROUP`, and `MOVE_MOUNT_BENEATH` remain
unsupported. Automount flags are accepted in the existing VFS model, which has
no automount triggers. Mount redirects are keyed by vnode in Vinix, so bind
aliases of the same vnode can share redirects.

## Qualification

One unchanged probe executable per architecture passed on Vinix and Linux
6.12.51. It checks descriptor and pathname endpoints, the low 32-bit argument
words, flag and path error order, permission denial, foreign and detached
descriptors, and unlinked file targets. It also checks stable mount IDs,
child mounts, relative parent lookup, and the destination stack. The baseline
Vinix kernels returned `ENOSYS`.

Production builds used `9c1233b60` plus the archived source patch. Independent
review checked endpoint pins, covered vnode ownership, and lock ordering.
The allocation checker reported the same existing findings and the same
306 AArch64 and 254 x86-64 allocation sites as the baseline.
The legacy `MS_MOVE`, pivot-root lifecycle, `opentree`, `listmount`,
`statmount`, and namespace regressions passed on both architectures.

| Architecture | Probe ELF | Vinix kernel | Vinix serial log | Linux serial log |
| --- | --- | --- | --- | --- |
| AArch64 | `1d00c35195fc870a` | `020d777a2a2ac07e` | `4ee4b37043541807` | `2090b9ac089bf04b` |
| x86-64 | `7ccd9180897a8abf` | `07b7562763b20ec4` | `a359c1dec5932a2a` | `cdfdb930d432ada2` |

Hashes are SHA-256 prefixes. The restored and verified archive is
`~/.cache/vinix-r15/movemount/qualification.tar.zst`, with SHA-256
`bcae8fba6b2d124180a766ccca70087bc5b17b8246dd4620d7506ce66a445403`.
Decode it with `zstd --long=28 -dc` before extracting the tar stream.
