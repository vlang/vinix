# Native page-location queries

Native `move_pages` with a null `nodes` pointer reports the NUMA node
of each resident page. An unaligned address selects its containing page.
Each output is a signed 32-bit value. Addresses outside a mapping report
`-EFAULT`, and mappings without a resident page report `-ENOENT`.
The query leaves absent pages unpopulated. Previously committed pages
retain their node when protected with `PROT_NONE`. Device mappings
and physical pages with no known owner report `-ENOENT`.
[Linux 6.12.51 page-location implementation](https://github.com/gregkh/linux/blob/v6.12.51/mm/migrate.c)

`pid=0` selects the caller. An explicit PID or TID is resolved in the
caller's PID namespace and uses the real-credential process inspection
check. A missing target returns `ESRCH`. Access denied returns `EPERM`.
`MPOL_MF_MOVE_ALL` requires `CAP_SYS_NICE` even for an empty query.
Both user vectors are copied in batches of up to 16 entries, and earlier
results survive a copy fault in a later batch.

Page migration remains open. A nonempty request with a destination
node vector returns `EOPNOTSUPP` after flag and process validation.

## Qualification

The same native musl probe ELF on each architecture passed on Vinix and
Linux 6.12.51. The probe covers unmapped and unpopulated pages,
`PROT_NONE` residency, signed output and copy boundaries, earlier-batch
results after user-copy faults, child access, and credential checks.
Both operating systems passed again with two NUMA nodes on each
architecture. The probe allocated a page under each node's bind policy
and verified the results were 0 and 1. The previous Vinix kernels
returned `ENOSYS` at the first query.

Production builds used `841067921` plus the archived source patch.
The `processmadv`, `mmap`, `pidfdgetfd`, and `robustcreds` regressions
passed on both architectures. The `robustcreds` reruns used a 300-second
limit after the initial 120-second runs timed out. The allocation checker
reported the baseline failures with the same 306 AArch64 and 254 x86-64
allocation sites. Independent review found that child construction
needed a check before reading credentials or pinning a pagemap. The
final implementation includes that check.

Run the probe with `tests/linux-compat/run --arch ARCH --kernel-dir DIR
--state-dir FRESH-DIR --cases movepages`. The
[fixture](../tests/linux-compat/movepagesfixture/core.v) also runs on Linux
with the syscall reference controller. The two-node runs used four vCPUs
and two 1 GiB nodes. Their QEMU commands and serial logs are in the archive.

| Architecture | Probe ELF | Vinix kernel | Vinix two-node log | Linux two-node log |
| --- | --- | --- | --- | --- |
| AArch64 | `8b84c71eaf797605` | `f5b3e569e282067d` | `7ddaeadc3f198152` | `2f269cc02da9558d` |
| x86-64 | `5fc00f0baf370338` | `9facaddad051ea65` | `acd2c45c4d5620ff` | `4d681e1a150d040d` |

Hashes are SHA-256 prefixes. The complete archive was restored and verified.
It is stored at `~/.cache/vinix-r15/movepages/qualification.tar.zst` with
SHA-256 `c8fef00476b7f97bb04583ade7e68e93e61d8da73978785f1693b698648f5392`.
