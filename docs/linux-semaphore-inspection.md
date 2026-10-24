# Native semaphore inspection

The 2026-10-24 qualification covers native musl ELF64 applications on AArch64
and x86-64. `semctl(IPC_INFO)`, `SEM_INFO`, `SEM_STAT` and `SEM_STAT_ANY` now
report semaphore limits, usage and metadata instead of returning `EINVAL`.
The [maintained probe](../tests/linux-compat/seminfofixture/core.v) uses raw
syscalls; the same executable runs on each Vinix candidate, its baseline and
Linux 6.12.51.

| Result per architecture | Checks | Failures |
| --- | ---: | ---: |
| Linux reference | 11,965 | 0 |
| Original Vinix kernel | 11,965 | 11,130 |
| Fixed production Vinix kernel | 11,965 | 0 |

The probe covers the 40-byte native `seminfo` layout, configured limits and
live set/semaphore counts; metadata matches `IPC_STAT` byte for byte (104 bytes
on x86-64, 88 on AArch64). Enumeration returns real IDs from stable indices,
including after unrelated deletion and 96 create/remove cycles. Tests exercise
all 512 permission modes with owner, group, other and `CAP_IPC_OWNER` roles.
`SEM_STAT` requires read permission; `SEM_STAT_ANY` permits inspection without
that check. Canary and protected-page boundaries check exact user copies.

Negative IDs fail before other validation. Information queries ignore other
nonnegative IDs and `semnum`; metadata queries ignore `semnum`. Scalar arguments
use their low signed 32 bits. Invalid indices, unsupported `IPC_64` command
variants, inaccessible user buffers and denied permissions return measured Linux
errors, including permission checks before metadata copy faults.

Both production builds pass. The maintained runner also passes all eight suites
on both candidate kernels: inspection 11,965, metadata 28,713, permissions
256,552, SETVAL error order 4,200, array controls 457, operation PIDs 261,
signed arguments 276 and operation ABI 175 checks. Reference parser controls
include two positive and nine negative cases; the evidence checker rejects nine
negative serial/architecture controls.

Builds used an isolated candidate `f92876f078f4c8c8847b92bbde87376ba986f978`,
with only `kernel/sysvsem/sysvsem.v` changed from
`04dc43da2c196e1d3e6ed2c9a139805e99b0d8ac`. The semaphore source SHA-256 is
`cdd7e4012ab55c05fb602c26959cfe5ae8b1e64bf08523162c5e6ccef77778be`.
The built kernel SHA-256 values are:

| Architecture | SHA-256 |
| --- | --- |
| AArch64 | `4fb6c16168f1e3eac43c9f8dabfcb01fc0704ab06c0139b07b926371a0648541` |
| x86-64 | `33a50d250c174934a428ad8b674df7778559b09515e8013a68bac325c61b3f52` |

Generated C from both builds was reviewed for the fixed stack index bitset,
explicit stack metadata snapshots, locked lookups and scalar capture before
unlock. No new allocation/free path appears in those inspected functions.
This qualification makes no measured storage claim.

The complete external bundle is retained at
`/Users/alex/.cache/vinix-linux-compat/seminfo-20261024/evidence-final`.
Its `manifest.json` SHA-256 is
`4ba8dc389dd3d61565728ab28fb59eac8948e1882f5281e1ebd11112f705a0ed`.
It includes source, binaries, generated C, boot media, build inventories,
receipts and logs; uncopied compiler dependencies have explicit hash pins.
Failed setup attempts are retained: initial fixture compilation, missing Linux
image, a build-directory race and generated-C excerpt selection. The enclosing
state directory also records an audit started before publishing finished and
an ambiguous source lookup corrected before the final audit.
Audit the complete bundle with:

```sh
v run tests/linux-compat/seminfo-reference.v --self-test
v run tests/linux-compat/seminfo-evidence.v --self-test
v run tests/linux-compat/seminfo-evidence.v check /Users/alex/.cache/vinix-linux-compat/seminfo-20261024/evidence-final
```

Vinix reports its own ceilings: 4,096 sets, 32 semaphores per set, 32 operations
per vector and a maximum value of 32,767. Live counts concern the initial IPC
namespace. `SEM_UNDO`, IPC namespace isolation/mapping, independent filesystem
IDs, concurrent credential/removal races, GNU libc, ELF32 and translated
application paths remain unqualified. This bounded result does not close the
broader libc, packaging or foreign-architecture roadmap gates.

The behavior and ABI are compared with
[Linux v6.12 semaphore implementation](https://github.com/torvalds/linux/blob/v6.12/ipc/sem.c),
[Linux semaphore definitions](https://github.com/torvalds/linux/blob/v6.12/include/uapi/linux/sem.h)
and [semctl documentation](https://man7.org/linux/man-pages/man2/semctl.2.html).
