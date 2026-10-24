# Native shared-memory integer ABI

Linux native System V shared-memory IDs, commands and flags use 32-bit `int`
arguments. Vinix now declares these syscall parameters as `i32`, ignoring the
upper register word while retaining 64-bit sizes and addresses. The existing
32-bit key handling remains intact. See [Linux v6.12 ipc/shm.c](https://github.com/torvalds/linux/blob/v6.12/ipc/shm.c).

Identical native musl ELF64 probes run as root and UID 1000/GID 2000. They
exercise decorated IDs, commands, keys and flags; IPC_STAT/IPC_SET metadata;
attachment counts, shared contents and removal; and retained EINVAL, EACCES
and EFAULT errors. Controls verify that invalid low-word IDs and commands
still fail, null SHM_REMAP still fails, and full-width sizes and buffers are
not truncated.

| Result per architecture | Checks | Failures |
| --- | ---: | ---: |
| Linux 6.12.51 reference | 243 | 0 |
| Original Vinix production kernel | 243 | 104 |
| Corrected Vinix production kernel | 243 | 0 |

The probe uses actual page sizes: 16 KiB on native AArch64, 4 KiB on native
x86-64 and both Linux references.

The isolated candidate is `1785e54fcd6441e24ff7d16f3ef036248f968b00`, based on
`640fcdafaaa5dd7ef9cfe1d6761a0907d74807fb`, with only
`kernel/sysvshm/sysvshm.v` changed. Its source SHA-256 is
`13fcab1f497261bab11552ad84b7c3c31a656cc305a470099fbe0ad1f271ca6e`.
Both production builds pass with unchanged before/after source inventories.
The generated C has the expected argument widths on both architectures;
all three function bodies are byte-identical to their originals. No
allocations, frees, locks, references or object lifetimes change.

| Production kernel | SHA-256 |
| --- | --- |
| AArch64 | `0c439f1e0ba10f22b7d402e244b9bb8d4781db6fde87153891a4d542d344e0ec` |
| x86-64 | `952a76a6a3058d6816b7c41b22855f102170d5642589e9445eb598bfd83325e9` |

All eight maintained suites (`shmabi`, `shmflags`, `shmremap`, `sharedmem`,
`runtime`, `mmap`, `namespace`, `jit`) pass on both exact production kernels.
The strict evidence checker's self-test passes five positive and rejects 23
negative controls; the Linux reference parser passes two positive and rejects
nine negative controls.

The complete external bundle is
`/Users/alex/.cache/vinix-linux-compat/shmabi-20261024/evidence-final`:
18,095 artifacts, zero omitted selected input pins. Its manifest SHA-256 is
`c390346c351b63f335d112720a41a60efba26db611605e20b259c25304d6abf5`.
The strict full-bundle audit passes, including all retained hashes, build
inventories, same-ELF comparisons and maintained suite receipts. Initial
unsuccessful compile attempts remain in the bundle.

Compile checkers without `-prod` to preserve assertions:

```sh
v run tests/linux-compat/shmabi-reference.v --self-test
v run tests/linux-compat/shmabi-evidence.v self-test
v run tests/linux-compat/shmabi-evidence.v check /Users/alex/.cache/vinix-linux-compat/shmabi-20261024/evidence-final
```

This qualifies native ELF64 shared-memory argument widths. Full System V IPC,
shared-memory namespace isolation, GNU libc, translated/ELF32 applications,
packaging and sandbox/portal integration remain separate qualifications.
