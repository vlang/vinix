# Native shared-memory attachment flags

The 2026-10-24 qualification covers native musl ELF64 on AArch64 and x86-64.
`shmat` now ignores unused flag bits, matching
[Linux v6.12 ipc/shm.c](https://github.com/torvalds/linux/blob/v6.12/ipc/shm.c).
Previously Vinix rejected these calls with `EINVAL`, including otherwise
valid attachments. Active address and protection flags retain their meaning.

The [maintained probe](../tests/linux-compat/shmflagsfixture/core.v) runs the
same executable on Linux 6.12.51, the original Vinix production kernel and
the corrected production kernel. Root and UID 1000/GID 2000 exercise every
unused low-32 bit individually, their combined mask, an empty mask and two
upper-word masks. Ordinary, rounded, read-only and executable read-only
attachments preserve shared contents and attachment counts. Read-only mappings
reject writable protection changes. Invalid IDs, misaligned addresses,
null/rounded-null SHM_REMAP and inaccessible segments retain `EINVAL`/`EACCES`.

| Result per architecture | Checks | Failures |
| --- | ---: | ---: |
| Linux reference | 1,763 | 0 |
| Original Vinix production kernel | 1,763 | 1,085 |
| Corrected Vinix production kernel | 1,763 | 0 |

The probe uses the actual page size: 16 KiB on native AArch64 and 4 KiB on
native x86-64 and both Linux references. Executable controls use read-only
executable mappings, consistent with Vinix's restrictions on RWX mappings.

The isolated candidate is `9b39bfe4f774c0540281f442d47baa803812c69d`, based on
`a8e6f33b3ecfb1ba313ab1a7b7dd8ad6205239e7`, with only
`kernel/sysvshm/sysvshm.v` changed. Its source SHA-256 is
`a158f66e9701020ba08a21d7aeb1d77a9aa9fba9de75a2aad161fd86972d7b49`.
Both production builds pass with identical before/after source inventories.
Generated C confirms removal of the rejection without adding allocations,
frees or object lifetimes.

| Production kernel | SHA-256 |
| --- | --- |
| AArch64 | `6a4d08be3b74dfb9280b71bb476d33d831d3280bef0c195f44c04ce628031bac` |
| x86-64 | `62b04b4d2291a95f1afcca99d44e034d8b810237d837bef00dbbcfb56f523ff6` |

The evidence checker passes five positive and rejects 23 negative controls.
The Linux reference parser passes two positive and rejects nine negative
controls. All seven maintained suites (`shmflags`, `shmremap`, `sharedmem`,
`runtime`, `mmap`, `namespace`, `jit`) pass on both production kernels.

The complete audit bundle contains 18,073 artifacts with no omitted input
pins at `/Users/alex/.cache/vinix-linux-compat/shmflags-20261024/evidence-final`.
Its manifest SHA-256 is
`db74cfe828365a79a9b69a09d7454a471aeb27f6e5d76a9698f10fd24ab705d6`.
Compile checkers without `-prod` to preserve assertions:

```sh
v run tests/linux-compat/shmflags-reference.v --self-test
v run tests/linux-compat/shmflags-evidence.v self-test
v run tests/linux-compat/shmflags-evidence.v check /Users/alex/.cache/vinix-linux-compat/shmflags-20261024/evidence-final
```

This qualifies native ELF64 attachment flag handling. Full System V IPC,
shared-memory namespace isolation, GNU libc, translated/ELF32 applications,
packaging and sandbox/portal integration remain separate qualifications.
