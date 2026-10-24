# Native shared-memory owner validation

Linux rejects an all-ones UID or GID in shmctl IPC_SET with EINVAL before
changing the object's owner, group or mode. Vinix now performs that validation
under the existing segment lock. See [Linux v6.12 ipc/util.c](https://github.com/torvalds/linux/blob/v6.12/ipc/util.c).

Identical musl ELF64 probes run as root and UID 1000/GID 2000. They check
valid large IDs, mode masking and ignored immutable fields; invalid UID/GID
combinations; unchanged metadata, contents and attachment counts after refusal;
and retained EFAULT, EINVAL and non-owner EPERM errors. Timestamp preservation
is checked on failed updates; successful timestamp updates remain unqualified.

| Result per architecture | Checks | Failures |
| --- | ---: | ---: |
| Linux 6.12.51 reference | 398 | 0 |
| Original Vinix production kernel | 398 | 180 |
| Corrected Vinix production kernel | 398 | 0 |

Native AArch64 uses 16 KiB pages. Native x86-64 and both Linux references use
4 KiB pages.

The isolated candidate is `f1d82411dd36b94c6ecb68f2cbf3e1653c7df64c`, based on
`12dd0cbd67873445a7c4e3f1ae0939e2471d4949`, with only
`kernel/sysvshm/sysvshm.v` changed. Its source SHA-256 is
`d4935c32ff65a2fc14101ce903274a2d828a7ea6e48ed1841f20c25dc253d9ef`.
Both production builds pass with unchanged before/after source inventories.
Generated C confirms byte-identical shmget/shmat functions and exactly one
shmctl validation branch. It reuses the existing operation-pin cleanup and
returns immediately; there is no new allocation, free or object lifetime.

| Production kernel | SHA-256 |
| --- | --- |
| AArch64 | `b68642cee0a8ca8a05ac9032774420bf5a4e3bc2c49a75a7edf8ed6d57aaa5df` |
| x86-64 | `4907b716bb1b8cb803148f34cac1c6e5ed1a17a28d62975709b6243c211afc82` |

All nine maintained suites (`shmset`, `shmabi`, `shmflags`, `shmremap`,
`sharedmem`, `runtime`, `mmap`, `namespace`, `jit`) pass on both exact kernels.
The evidence checker's self-test passes five positive and rejects 23 negative
controls; the reference parser passes two positive and rejects nine negative
controls.

The complete external bundle is
`/Users/alex/.cache/vinix-linux-compat/shmset-20261024/evidence-final`:
18,163 artifacts, zero omitted selected input pins. Its manifest SHA-256 is
`b1b56988a1ed0254c3368cab4486dff3d76dba191a7235db0b5d7bb754d23479`.
The strict full-bundle audit passes, checking all retained hashes, build
inventories, same-ELF results and maintained suite receipts. Initial unsuccessful
compile attempts and the incorrect initial parser argument remain retained.

Compile checkers without `-prod` to preserve assertions:

```sh
v run tests/linux-compat/shmset-reference.v --self-test
v run tests/linux-compat/shmset-evidence.v self-test
v run tests/linux-compat/shmset-evidence.v check /Users/alex/.cache/vinix-linux-compat/shmset-20261024/evidence-final
```

This qualifies native ELF64 owner validation with static credentials in the
initial IPC/user namespaces. Mixed lookup/copy-fault precedence, removal or
credential races, mapped namespaces, full System V IPC, shared-memory namespace
isolation, GNU libc, translated/ELF32 applications and installation/sandbox
acceptance remain separate qualifications.
