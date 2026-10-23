# Native semaphore permissions

2026-10-23. Bounded native ELF64 musl qualification on AArch64 and x86-64.

Semaphore sets now retain their creator/owner UID, GID, creation mode and
owning IPC namespace's user namespace ID. Existing-key semget requests,
read/query controls, write controls and operation vectors enforce access
permissions. IPC_RMID requires ownership or CAP_SYS_ADMIN; CAP_IPC_OWNER
overrides read/alter permission checks, not removal ownership checks. Effective
UID zero without effective capabilities receives no implicit override.

| Execution | AArch64 | x86-64 |
| --- | --- | --- |
| Original Vinix kernel, unchanged probe ELF | 256,552 checks, 95,772 failures | 256,552 checks, 95,772 failures |
| Candidate Vinix kernel, unchanged probe ELF | 256,552 checks, 0 failures | 256,552 checks, 0 failures |
| Linux 6.12.51, identical probe ELF | 256,552 checks, 0 failures | 256,552 checks, 0 failures |
| Maintained runner on candidate, four vCPUs | 256552/4200/457/261/276/175 checks, all pass | 256552/4200/457/261/276/175 checks, all pass |

The probe crosses all 512 permission modes with ten credential/capability
scenarios: effective owner, primary group, supplementary group, other user,
UID zero without capabilities, real-owner UID only, saved-owner UID/GID only,
CAP_IPC_OWNER only, CAP_SYS_ADMIN only and both capabilities. Each combination
has 50 checks, plus removal ownership and final state/cleanup checks. Existing
key requests fold each of the three requested permission columns. The probe
checks read versus alter operations, mixed vectors, GETVAL/GETPID/GETNCNT/
GETZCNT, GETALL/SETALL, invalid indices, bad array pointers, invalid values,
unknown commands and exclusive-create/count precedence. Unchanged final
values detect successful unauthorized alteration. Setup failures cannot pass.
Only the first twelve mismatches per child are printed: the baseline has 100
mismatch lines and 95,772 failed checks, not 100 failed checks.

Reference implementations are retained in `reference/linux-v6.12-sem.c` and
`reference/linux-v6.12-util.c`, from upstream
[ipc/sem.c](https://github.com/torvalds/linux/blob/v6.12/ipc/sem.c) and
[ipc/util.c](https://github.com/torvalds/linux/blob/v6.12/ipc/util.c).
Linux IPC access checks use effective UID and filesystem group membership.
Vinix currently has no independent filesystem IDs/setfsuid/setfsgid, so the
qualified subset uses effective GID and supplementary groups. A preliminary
AArch64 Linux run incorrectly assumed filesystem IDs never affected IPC
permissions; its 9,232 failures and the earlier fixture/compile attempts are
retained under `attempts/`. The final probe replaces that unsupported scenario
with saved-owner-ID checks; it does not claim filesystem-ID qualification.

The isolated candidate is `99b997a347ea535c66128ba7858ccfeab1a32827`, directly
based on `e5b423347e1aad8ef122316bb85602aab2d52e50`. Only the semaphore
source differs. Its SHA-256 is
`939e171c1d8f83e065208d99d7e60b25db032cbdbf8851ee055de72e835d43b6`.
Production build receipts pin tracked sources, dependencies, tools and outputs;
before/after input hashes match. Generated-C review confirms a stack credential
snapshot and inline set metadata. Allocation/destruction/evaluation/waiter
helpers, command bodies and the queued-operation tail match the baseline
(only compiler temporary numbers are normalized in the latter comparisons).
Access refusal unlocks and releases the existing timer. There is no new
allocation, borrowed namespace/group pointer or object lifetime.

`manifest.json` hashes retained artifacts, maps original paths to retained
files and explicitly pins omitted large media/external tools. Duplicate bytes
use relative symlinks. Commands, statuses, kernels, generated C, probe ELFs,
serial output and unsuccessful attempts remain inspectable. The mistyped
compile command's status is retained separately from the successful command.

Audit with the repository V compiler, without `-prod`:

```
v run tests/linux-compat/semperm-evidence.v --self-test
v run tests/linux-compat/semperm-evidence.v check tests/linux-compat/results/2026-10-23/semperm-evidence
```

The checker verifies artifacts, build identities, exact summaries, ELF
architectures, the identical probe on all three kernels and maintained
regressions. Its nine negative controls pass. The reference parser separately
passes two positive and nine negative controls. `completion/receipt.json`
binds the final audit, source identity and manifest.

IPC_SET/IPC_STAT and timestamp/owner mutation, IPC namespace isolation,
user-namespace mappings/ancestor capability traversal, independent filesystem
IDs, SEM_UNDO, larger sets/vectors, GNU libc and foreign/32-bit application
paths remain unqualified. Section 15's broad libc, installation/sandbox and
foreign application gates remain open.
