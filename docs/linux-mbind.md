# Native NUMA policy on private anonymous mappings

`mbind` sets the policy for a page-aligned address range of private anonymous
memory. It rounds the length up to a page and splits the mapping at the
requested boundaries when needed. The calling thread's policy governs
ordinary allocations through `set_mempolicy`. `get_mempolicy(MPOL_F_ADDR)`
reports the explicit mapping policy. Adding `MPOL_F_NODE` returns the
page's physical node in the mode slot. [Linux 6.12.51 memory policy implementation](https://github.com/gregkh/linux/blob/v6.12.51/mm/mempolicy.c)

The supported policies are `MPOL_DEFAULT`, `MPOL_LOCAL`, `MPOL_PREFERRED`,
`MPOL_BIND`, `MPOL_INTERLEAVE`, `MPOL_PREFERRED_MANY`, and
`MPOL_WEIGHTED_INTERLEAVE`. See the separate qualification reports for
[preferred-many](linux-preferred-many.md) and
[weighted interleave](linux-weighted-interleave.md).
New pages and private copy-on-write faults use the mapping policy.
Interleave uses the anonymous page index, which survives splitting, fork
and moving remap. A strict
check returns `EIO` if a resident page lies outside the requested mask.
A failed interval check leaves the existing mapping policies in place.

`MPOL_DEFAULT` clears mapping policies and can span holes when the
interval includes a mapping. Other modes require a fully mapped interval.
Page migration and policy on shared or file-backed mappings and the reserved
`brk` arena remain open. The pager still chooses
the frames for swapped refaults. Vinix's existing
private moving remap copies resident data and can change its physical node.

## Qualification

The same native musl probe ELF passed on Vinix and Linux 6.12.51 on AArch64
and x86-64. Two-node guests verified range-specific fault placement,
strict rejection of a misplaced resident page, original placement after
ordinary binding, and page-index interleaving with out-of-order faults.
The probe also checked policy preservation across protection changes, fork
and moving remap. The previous Vinix kernels failed the policy query for
the last page of the first rounded binding.

Production builds used `6a9661e9e` plus the archived source patch. The
allocation checker reported the same existing failures and the same
306 AArch64 and 254 x86-64 allocation sites. The existing AArch64 NUMA
regression passed with its test program in the boot archive.

The `mempolicy`, `movepages`, `remapfile`, `mseal`, and `processmadv`
regressions passed on both architectures. After 200 seal-and-exit cycles
neither architecture showed growth in live slab classes or large pages.

Run the [fixture](../tests/linux-compat/mbindfixture/core.v) with
`tests/linux-compat/run --arch ARCH --kernel-dir DIR --state-dir FRESH-DIR
--cases mbind`.

| Architecture | Probe ELF | Vinix kernel | Vinix two-node log | Linux two-node log |
| --- | --- | --- | --- | --- |
| AArch64 | `21178d94aa2bae7f` | `702bec8edc9dde5f` | `ba3be6eec23dd20c` | `44894a02abb00787` |
| x86-64 | `ff9a3c824b2eca81` | `578ebd48349397dd` | `06209fce8ae4ee73` | `477c18419e324c79` |

Hashes are SHA-256 prefixes. The restored and verified archive is
`~/.cache/vinix-r15/mbind/qualification.tar.zst`, with SHA-256
`6a70a5184fc75aa4b78797affbb787aaf3197f91ebe7d5e64374f596361f81b6`.
