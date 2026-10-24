# Native shared-memory remap validation

The 2026-10-24 qualification covers native musl ELF64 on AArch64 and x86-64.
`shmat` now returns `EINVAL` when `SHM_REMAP` has a null address, including
an address rounded to null by `SHM_RND`. Previously Vinix could choose an
automatic address and report success, or return an access error for an
inaccessible segment. The rejection now precedes segment lookup and access
checks, matching [Linux v6.12 ipc/shm.c](https://github.com/torvalds/linux/blob/v6.12/ipc/shm.c).

The [maintained probe](../tests/linux-compat/shmremapfixture/core.v) runs the
same executable on Linux 6.12.51, the original Vinix production kernel and
the corrected production kernel. Root and UID 1000 cover null/rounded-null
addresses, valid/removed/invalid IDs, RDONLY/EXEC combinations, inaccessible
segments, misalignment, and 200 repeated refusals. Refusals preserve metadata,
attachment counts and existing shared contents. Positive controls retain
ordinary automatic attachments and fixed RW, RO and RX replacements.

| Result per architecture | Checks | Failures |
| --- | ---: | ---: |
| Linux reference | 1,101 | 0 |
| Original Vinix production kernel | 1,101 | 876 |
| Corrected Vinix production kernel | 1,101 | 0 |

The probe obtains the actual page size with `sysconf(_SC_PAGESIZE)` and tests
the last byte below that boundary. Native AArch64 uses 16 KiB; Linux reference
and x86-64 runs use 4 KiB. Successful RWX mappings remain outside these
executable controls because Vinix deliberately restricts RWX mappings.

The isolated candidate is
`e20f59ab2806d8b9b31d918acea08ff6b8165a2d`, based on
`4ee3c398fa8fa5b065ae3af35a66a8fae645645f`, with only
`kernel/sysvshm/sysvshm.v` changed. Its SHA-256 is
`e8f7245dfb91530047cd6c9173e07e7d3325df295b9bfe40789db6e7ff315ced`.
Both production builds pass with identical before/after source inventories.
Generated C confirms the guard returns before acquiring the existing lock
and introduces no allocation, free or object lifetime.

| Production kernel | SHA-256 |
| --- | --- |
| AArch64 | `a6466b5d1145e799dfdc6a6ebe9167c73e8317c88efef364cba7ef5dd4e85593` |
| x86-64 | `e66c02a0811001087373a21b8991e09600980f6db09cd85b51be8f071349f1ad` |

All six maintained suites (`shmremap`, `sharedmem`, `runtime`, `mmap`,
`namespace`, `jit`) pass as one complete batch per architecture. The evidence
checker passes five positive and rejects 23 negative controls. The Linux
reference parser passes two positive and rejects nine negative controls.
The complete audit checks both builds, all selected inputs, matching probe
ELFs, original/native/Linux outcomes and maintained batch identities.

The retained bundle is
`/Users/alex/.cache/vinix-linux-compat/shmremap-20261024/evidence-final`;
its manifest SHA-256 is
`ce3f96f9b880b369247ff436794bcdb4914409417e8ffcf2f4cd8839f1ad5e28`.
The complete bundle preserves failed attempts. Compile checkers without
`-prod` to retain their assertions:

```sh
v run tests/linux-compat/shmremap-reference.v --self-test
v run tests/linux-compat/shmremap-evidence.v self-test
v run tests/linux-compat/shmremap-evidence.v check /Users/alex/.cache/vinix-linux-compat/shmremap-20261024/evidence-final
```

This qualifies the bounded native `shmat` validation path. Full System V IPC,
shared-memory namespace isolation, GNU libc, ELF32, translated applications,
packaging and sandbox integration remain separate qualifications. The three
broader roadmap gates remain open.
