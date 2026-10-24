# Native shared-memory pending-removal status

Vinix now clears a shared-memory segment's key to IPC_PRIVATE and exposes
SHM_DEST in IPC_STAT after IPC_RMID. Attached segments retain their ID and
contents until their last attachment leaves. Repeated removal preserves
metadata; IPC_SET cannot clear SHM_DEST or restore the key. This follows
[Linux v6.12 ipc/shm.c](https://github.com/torvalds/linux/blob/v6.12/ipc/shm.c).

Identical static musl ELF64 probes run as root and UID 1000/GID 2000. Four
cohorts cover private, positive and negative keys and 0600/0660 modes. They
check creation and update flag filtering, removal with an ignored invalid
pointer, exact metadata preservation, continued access, key reuse with an
independent zeroed segment, failed-update preservation, read-only reattachment,
attachment counts, final detach and stale-ID EINVAL. Each cohort cleans up
before fork; inherited/split mapping accounting is outside this qualification.

| Result per architecture | Checks | Failures |
| --- | ---: | ---: |
| Linux 6.12.51 reference | 301 | 0 |
| Original Vinix production kernel | 301 | 60 |
| Corrected Vinix production kernel | 301 | 0 |

Native AArch64 uses 16 KiB pages. Native x86-64 and both Linux references use
4 KiB pages. Both production builds pass with unchanged before/after source
inventories. All eleven maintained suites (`shmremove`, `shmtime`, `shmset`,
`shmabi`, `shmflags`, `shmremap`, `sharedmem`, `runtime`, `mmap`, `namespace`,
`jit`) pass on both exact kernels.

The isolated candidate is `b3b2de5bb11c26233af0030a056771564ac131e3`, based on
`83223983bedfd84b1671457a8390722fcd6912e5`. Only sysvshm changes; the mapping
and exit sources are retained unchanged for comparison:

| Source | SHA-256 |
| --- | --- |
| kernel/sysvshm/sysvshm.v | `eafc91ba9f30a2a8bae48909da41b5b22d17bdb9e77226e63db629daa95a5766` |
| kernel/memory/mmap/mmap.v | `abe4c0ae22a64ce2bec71d9a886f5a663f522acf3e7a44cf77c9efd6078c8b2f` |
| kernel/userland/exit.v | `2d3fc96ee5a625a2176971e5a4689960df79a4e3ad34976199c571cb7324ffff` |

| Production kernel | SHA-256 |
| --- | --- |
| AArch64 | `4a5028dcc4407581595ab71e67d7d7f26cfedc24a2c3b492aa5c7d4964dbc3e0` |
| x86-64 | `621d97adf8ed1a054a1d8081197b5a98ece08690d46b6518b7e4aa42f85a703b` |

Generated C review on both architectures confirms exactly two scalar metadata
writes in shmctl under the existing segment lock, which also protects lookup
and permission checks. All other sysvshm function bodies and the inspected
mapping/exit paths are byte-identical to the baseline. No allocation, release,
reference-count operation or object lifetime changes. This scope review does
not claim a measured allocation-leak qualification.

Fork-inherited/split attachment counts and intermediate detach timestamps,
mremap metadata, removal/credential races, IPC namespace isolation and mapped
user namespaces remain separate work. This does not qualify full System V IPC,
GNU libc, translated/ELF32 applications or installation/service/sandbox/portal
acceptance. The three broad section 15 acceptance gates remain open.

The external bundle is
`/Users/alex/.cache/vinix-linux-compat/shmremove-20261024/evidence-final`.
It retains selected build/compile/reference/native/maintained inputs and
outputs, source inventories, generated C review and unsuccessful preparation
attempt receipts. The first ARM build invocation failed before creating its
state directory; its retry passes. Two generated C review helper attempts
failed parsing a declaration and reading a directory as a file; the corrected
helper passes. These diagnostic records do not claim separately qualified
complete input closures. Selected runs retain every pinned input, and the
original complete historical bundles remain required.

Compile checkers without `-prod` to preserve assertions:

```sh
v run tests/linux-compat/shmremove-reference.v --self-test
v run tests/linux-compat/shmremove-evidence.v self-test
v run tests/linux-compat/shmremove-evidence.v check /Users/alex/.cache/vinix-linux-compat/shmremove-20261024/evidence-final
```

The reference parser passes two positive and rejects nine negative controls.
The evidence checker passes five positive and rejects 23 negative controls.

The complete bundle passes the strict audit: 18,282 artifacts, zero omitted
selected input pins. Its `manifest.json` SHA-256 is
`be314530cab41f66682dcf683c4f8b451a1afa2425a3f8a6acb2f7016c9417da`.
