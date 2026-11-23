# Native memory policy address queries

`get_mempolicy(MPOL_F_ADDR)` looks up an address in the caller's mappings.
It returns `MPOL_DEFAULT` and an empty nodemask for Vinix's unbound mappings,
including `PROT_NONE` and demand-backed mappings. `MPOL_F_ADDR | MPOL_F_NODE`
reports the physical NUMA node of an accessible page. A readable absent
page can be faulted in by the node query. An unmapped address returns
`EFAULT` before any output copy.
[Linux 6.12.51 memory policy implementation](https://github.com/gregkh/linux/blob/v6.12.51/mm/mempolicy.c)

Native nodemask output uses whole 64-bit words for the `maxnode - 1` bits
and is limited to one native page. An undersized mask is rejected before
lookup. The scalar mode is written before the mask, and trailing words are
zeroed before copying the first word. `MPOL_F_MEMS_ALLOWED` reports mode zero
and the allowed nodes.

Vinix still stores memory policy on the process. Per-mapping `mbind`
policies, Linux's interleave-next result for `MPOL_F_NODE` without
`MPOL_F_ADDR`, and translated or 32-bit policy calls remain open.

## Qualification

The same native musl probe ELF for each architecture passed on Vinix and
Linux 6.12.51. It checked the mapping policy under a task binding, a resident
page's physical node, protected and unmapped addresses, demand faults, and
controlled nodemask copy faults. Two-node QEMU runs on each architecture
bound the test page to node 1, switched the task to node 0, and then verified
the address still reported node 1. The previous kernels returned the task
policy for the address query and failed the probe.

Production builds used `dfb5bd477` plus the archived source patch. The
allocation checker reported the existing failures with the same 306 AArch64
and 254 x86-64 allocation sites. Independent review checked the map lifetime
through lock release and demand faults. The page-in path rechecks permissions
under the pagemap lock before borrowing backing storage.

The `move_pages`, `mmap`, and `process_madvise` regressions passed on both
architectures. The existing AArch64 NUMA regression passed when supplied
with an initramfs containing its test program. With the harness's default
archive, both the old and new kernels failed to load init before the
regression began.

Run the [fixture](../tests/linux-compat/mempolicyfixture/core.v) with
`tests/linux-compat/run --arch ARCH --kernel-dir DIR --state-dir FRESH-DIR
--cases mempolicy`.

| Architecture | Probe ELF | Vinix kernel | Vinix two-node log | Linux two-node log |
| --- | --- | --- | --- | --- |
| AArch64 | `e5e394596c485a8d` | `5daee8d08221bc8d` | `b7f7276001fd2bf` | `ec7f4d34eafc429` |
| x86-64 | `1a91719327a0ac42` | `ce803876bfd1be6b` | `78bbee9fb094f608` | `5aeebfeab760df9` |

Hashes are SHA-256 prefixes. The restored and verified archive is
`~/.cache/vinix-r15/mempolicy/qualification.tar.zst`, with SHA-256
`b6dd77b3ff12a9da23f54cbd3ee2b4fc774361d0b3c00e57e22cb9ddce11b089`.
