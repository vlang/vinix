# Native NUMA home nodes

`set_mempolicy_home_node` changes which node serves as the starting point
for allocation on an existing `MPOL_BIND` or `MPOL_PREFERRED_MANY` range.
It preserves the mode and mask. The home node can lie outside the mask.
An explicit `mbind` replacement clears the override. Existing pages keep
their physical placement, and fork inherits the range policy by value.
[Linux 6.12.51 memory policy implementation](https://github.com/gregkh/linux/blob/v6.12.51/mm/mempolicy.c)

The call rounds the length up to the native page size and skips holes and
ranges without explicit policies. A span containing only holes and default
policies returns `ENOENT`. An explicit unsupported policy returns
`EOPNOTSUPP` and leaves earlier updates in effect. Vinix applies the call
to the existing private anonymous `mbind` scope.

## Qualification

The probe checks argument width, length rounding and overflow, mode and
mask preservation, holes, and ordered partial updates. The two-node run
pins the faulting thread to node 0 and verifies that the override changes
only the intended pages' future placement. It also checks fork inheritance,
copy-on-write placement, resident pages, replacement by `mbind`, and a home
node outside a bind mask.

The same probe ELF per architecture passed on Vinix and Linux 6.12.51 in
single-node and two-node guests. Both production kernels were built from
`8342ea447` plus the archived source patch.

| Architecture | Probe ELF SHA-256 prefix | Vinix kernel SHA-256 prefix |
| --- | --- | --- |
| AArch64 | `ab2ea030ea7e2324` | `681ec0c076ebdc97` |
| x86-64 | `aa284a5f05c27955` | `94ca97c2e99fe6a6` |

The `taskpolicy`, `mbind`, `mempolicy`, and `prefmany` regressions passed on
both architectures. `taskpolicy` and `mbind` also passed in two-node guests.
The allocation checker reproduced the existing failures with the same site
counts. Independent review checked split failure cleanup and policy copies
through fork, remap, and fault installation. The separate native allocation
host tool still fails to build on both revisions because its `C.poll`
declaration conflicts with other modules.

Run `tests/linux-compat/run --arch ARCH --kernel-dir DIR --state-dir
FRESH-DIR --cases memhome --numa` for the Vinix two-node guest. The Linux
reference takes `--arch ARCH --case memhome --kernel LINUX --init
FRESH-DIR/memhome/init --state-dir LINUX-STATE --numa` using the
[syscall reference runner](../tests/linux-compat/syscall-reference.v).
Omit `--numa` for the single-node run.

The restored and verified archive is
`~/.cache/vinix-r15/memhome/qualification.tar.zst`, with SHA-256
`cba03499bc84bbb2b9bcbe1d0903f3a20f3d283bd4a3aa27dfa006590b218603`.
