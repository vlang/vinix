# Native shared-memory timestamps and last-operation PID

Vinix now reports creation/control, attachment and detach times through
shmctl IPC_STAT. New objects have zero attachment/detach times and last PID;
successful shmat records the calling process and attachment time. Successful
IPC_SET, including a no-op update, changes only the control timestamp and
mutable permission fields. Explicit detach and final mapping cleanup on exit
record the detach time and the responsible process PID. Rejected updates and
IPC_RMID preserve these fields. The reference behavior is
[Linux v6.12 ipc/shm.c](https://github.com/torvalds/linux/blob/v6.12/ipc/shm.c).

Identical static musl ELF64 probes run as root and UID 1000/GID 2000. They
check zero initial fields, whole-second timestamp transitions, immutable fields,
read/write contents, read-only child attachments, explicit detach and exit
cleanup. Null buffers and all-ones owner IDs retain EFAULT/EINVAL and leave
metadata unchanged. The child forks before attaching; inherited attachment
accounting is outside this qualification.

| Result per architecture | Checks | Failures |
| --- | ---: | ---: |
| Linux 6.12.51 reference | 175 | 0 |
| Original Vinix production kernel | 175 | 46 |
| First candidate | 175 | 6 |
| Corrected Vinix production kernel | 175 | 0 |

Native AArch64 uses 16 KiB pages. Native x86-64 and both Linux references use
4 KiB pages. Both production builds pass with unchanged before/after source
inventories. All ten maintained suites (`shmtime`, `shmset`, `shmabi`,
`shmflags`, `shmremap`, `sharedmem`, `runtime`, `mmap`, `namespace`, `jit`)
pass on both exact kernels.

The isolated candidate is `0be640e33d7f989d1041de6d794687609f6c1712`, based on
`8b3442d96949f737c7e9362d0f9e97a0a3dfc2bd`, with exactly these kernel changes:

| Source | SHA-256 |
| --- | --- |
| kernel/sysvshm/sysvshm.v | `4f96ac65d7bf96351475429ae0a7419ad49bb46e88e39f982ffa4e33b7f7bc25` |
| kernel/memory/mmap/mmap.v | `abe4c0ae22a64ce2bec71d9a886f5a663f522acf3e7a44cf77c9efd6078c8b2f` |
| kernel/userland/exit.v | `2d3fc96ee5a625a2176971e5a4689960df79a4e3ad34976199c571cb7324ffff` |

| Production kernel | SHA-256 |
| --- | --- |
| AArch64 | `bfc075e234e2e2bc1195652b452213aaeacd695b63974441ecf9f3a3fd473f26` |
| x86-64 | `2ae2f828446dcac2f54713f7daa2788363b702d73cdcf67adf1d16a744d6226f` |

Temporary page-fault and procfs inspection pins must not update detach time or
last PID. The first candidate incorrectly did so, and exit cleanup observed
the kernel process after the thread switched identity. The corrected code
notifies only when an actual global mapping is retired and passes the saved
exiting PID. The callback runs before the existing handle release, while that
pin is still held. It writes inline metadata under the existing segment lock.
Generated C review on both architectures confirms no new allocation, free or
reference-count operation in the new helpers and unchanged allocation/free/pin
call counts in the modified paths. This is a lifetime review, not a measured
allocation-leak qualification.

Fork-inherited and split VMAs share a global mapping. Their per-process
attachment counts and intermediate detach timestamps remain unqualified;
the new callback runs only at final global retirement. mremap metadata,
removal/credential races, IPC namespace isolation and mapped user namespaces
remain separate work. This does not qualify full System V IPC, GNU libc,
translated/ELF32 applications or installation/service/sandbox/portal acceptance.

The external bundle is
`/Users/alex/.cache/vinix-linux-compat/shmtime-20261024/evidence-final`.
It retains selected build/compile/reference/native/maintained inputs and
outputs, source inventories, generated C review, and unsuccessful attempt
receipts. The original complete historical bundles remain required. All
selected input pins are preserved; unsuccessful attempts are diagnostic
records rather than separately qualified complete input closures.

Compile checkers without `-prod` to preserve assertions:

```sh
v run tests/linux-compat/shmtime-reference.v --self-test
v run tests/linux-compat/shmtime-evidence.v self-test
v run tests/linux-compat/shmtime-evidence.v check /Users/alex/.cache/vinix-linux-compat/shmtime-20261024/evidence-final
```

The reference parser passes two positive and rejects nine negative controls.
The evidence checker passes five positive and rejects 23 negative controls.

The strict full-bundle audit passes: 19200 artifacts, zero omitted
selected input pins. Manifest SHA-256:
`a8bc9a885269b0585ee0fe0553bee2fab8bae2053371556b5041a9aa763e8db8`.
