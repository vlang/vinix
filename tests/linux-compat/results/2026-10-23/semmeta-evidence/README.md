# Native semaphore metadata

2026-10-23. Bounded native ELF64 musl qualification on AArch64 and x86-64.

IPC_STAT now exports the native semid_ds layout, including creator/owner IDs,
key, mode, semaphore count and operation/change timestamps. IPC_SET imports
the complete native structure before lookup and authorization, preserves
immutable fields, masks modes to 0777 and rejects invalid UID/GID mappings.
Creators and current owners retain independent ownership rights. SETVAL,
SETALL and IPC_SET update change time; successful operation vectors update
operation time. Read permission and ownership failures follow Linux ordering.

| Execution | AArch64 | x86-64 |
| --- | --- | --- |
| Original Vinix kernel, unchanged probe ELF | 28,713 checks, 19,480 failures | 28,713 checks, 19,480 failures |
| Candidate Vinix kernel, unchanged probe ELF | 28,713 checks, 0 failures | 28,713 checks, 0 failures |
| Linux 6.12.51, identical probe ELF | 28,713 checks, 0 failures | 28,713 checks, 0 failures |
| Maintained runner on candidate | 28713/256552/4200/457/261/276/175 checks, all pass; four vCPUs | 28713/256552/4200/457/261/276/175 checks, all pass; two vCPUs |

The probe validates 104-byte x86-64 and 88-byte AArch64 metadata layouts,
field offsets, copy canaries, reserved fields, timestamp transitions and
ignored input fields. Runtime page sizes select protected buffer boundaries.
Bad pointers, full input import, negative/missing/stale IDs, invalid UID/GID,
unsupported IPC_64 commands and ignored indices check error precedence.
All 512 modes are crossed with seven scenarios: creator, current owner,
creator group, owner group, unrelated user, CAP_IPC_OWNER and CAP_SYS_ADMIN.
Each mode/scenario performs eight checks; 41 additional checks cover metadata.
Both creator and owner can assign arbitrary valid IDs without CAP_CHOWN;
CAP_IPC_OWNER grants read/alter access, while CAP_SYS_ADMIN grants ownership
operations. The permission suite separately covers ordinary vector access.

Reference implementations are retained in reference/linux-v6.12-sem.c and
reference/linux-v6.12-util.c, from upstream
[ipc/sem.c](https://github.com/torvalds/linux/blob/v6.12/ipc/sem.c) and
[ipc/util.c](https://github.com/torvalds/linux/blob/v6.12/ipc/util.c).
Earlier attempts remain under attempts/: compile/entry-point corrections,
a Linux coarse-clock boundary expectation, an incorrect 4 KiB guard-page
assumption on Vinix AArch64 and concurrent V-run controller executable
replacement. A later maintained run was interrupted without controller status;
its partial results are retained and a fresh full run supplies final results.
The final controllers use stable executables, the guard uses
getpagesize(), and timestamp checks wait for coarse realtime to advance.
Printed baseline mismatches are capped; the exact failing-check total comes
from the summary, rather than the number of diagnostic lines.

The isolated candidate is 09bf0cfff672c584c351642260bfe6a8a9513892, based
directly on d2283facaf4c5db67d48cae8194e3000f2689575. Only the semaphore
source differs; its SHA-256 is
29bed8c38a9de3b927c06b21ef25a956db52c5205b0410c3b5aa012026d2b3c1.
Production build receipts pin sources, dependencies, tools and outputs,
with unchanged before/after input hashes. Generated-C reviews on both
architectures confirm a zeroed stack metadata structure, inline scalar set
fields and no new allocation/free. IPC_SET imports before identity/locking;
IPC_STAT snapshots under lock and copies out after unlock without retaining
a set pointer. Existing destruction, waiter and evaluation helpers match the
baseline. No new object lifetime is introduced.

manifest.json hashes artifacts, maps original paths to retained files and
explicitly pins omitted large media/external tools. Duplicate bytes use
relative symlinks. Kernels, generated C, ELFs, serial logs, commands, statuses
and unsuccessful attempts remain inspectable. Audit without -prod:

```
v run tests/linux-compat/semmeta-evidence.v --self-test
v run tests/linux-compat/semmeta-evidence.v check tests/linux-compat/results/2026-10-23/semmeta-evidence
```

The checker validates build/source identity, architecture, exact summaries,
identical probe ELFs on all three kernels and all seven maintained suites.
Its nine negative controls and the reference parser's two positive/nine
negative controls pass. completion/receipt.json binds the final audit and
manifest to the current source.

IPC namespace isolation, mapped IDs and ancestor capability traversal,
independent filesystem IDs, SEM_UNDO, inventory commands, larger sets/vectors,
GNU libc and foreign/32-bit paths remain unqualified. Section 15's broad
libc, installation/sandbox and foreign application gates remain open.
