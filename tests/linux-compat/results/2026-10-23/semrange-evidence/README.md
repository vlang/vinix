# Native semaphore SETVAL error order

2026-10-23. Bounded native ELF64 musl qualification on AArch64 and x86-64.

For semctl SETVAL, negative signed IDs return EINVAL first. For nonnegative
IDs, signed low-32 values outside 0–32767 return ERANGE before ID lookup or
semnum validation. Successful value/PID updates and queue progression retain
their existing behavior.

| Execution | AArch64 | x86-64 |
| --- | --- | --- |
| Original Vinix kernel, unchanged probe ELF | 4,200 checks, 240 failures | 4,200 checks, 240 failures |
| Candidate Vinix kernel, unchanged probe ELF | 4,200 checks, 0 failures | 4,200 checks, 0 failures |
| Linux 6.12.51, identical probe ELF | 4,200 checks, 0 failures | 4,200 checks, 0 failures |
| Maintained runner on candidate | 4,200/457/261/276/175 checks, all pass | 4,200/457/261/276/175 checks, all pass |

The probe crosses seven ID forms, six indices, ten union values and two
command forms (840 calls). Every call checks its return/errno and both
semaphore values/PIDs, for 4,200 checks. Coverage includes upper register
bits, negative IDs, stale/missing IDs, negative/excessive indices, negative
values, 32768, signed limits and legal 0/32767 values. Setup failures cannot
produce a passing summary. Linux reference semantics come from
`ksys_semctl`/`semctl_setval` in `reference/linux-v6.12-sem.c` (upstream
https://github.com/torvalds/linux/blob/v6.12/ipc/sem.c).

The isolated candidate is `7eb399c6e8da852729a04fa52943a848eb1b6c92`, directly
based on `f7db726bbba470e3b4746a90197a8b3958b62a78`. Only the semaphore
source differs. Its SHA-256 is
`0ee9007d431ac0f225a59e391af2d379dcbb6380c6d6da813f0f2f1fa9adaab1`.
Build receipts pin tracked sources, dependencies, tools and outputs with
matching input hashes before/after. Generated C confirms early scalar checks;
the rest of semctl matches baseline byte for byte after removing the former
range-error branch and its unlock. No allocation or object lifetime changes.

`manifest.json` hashes retained artifacts, maps original paths to those
artifacts and explicitly pins omitted large media/external tools. Duplicate
contents use relative symlinks. Receipts retain commands, serial output,
compiled probes, generated C and kernels. Unsuccessful compilation
attempts and the initial review-script assertion (which incorrectly expected
the removed error branch's unlock to remain) are visible in `attempts/`.
The corrected review checks that exact removal against the baseline.

Audit with the repository V compiler:

```
v run tests/linux-compat/semrange-evidence.v --self-test
v run tests/linux-compat/semrange-evidence.v check tests/linux-compat/results/2026-10-23/semrange-evidence
```

The checker includes nine negative controls for summaries, markers, failures
and ELF architecture. The Linux reference parser adds two positive and nine
negative controls. `completion/receipt.json` binds the final audit, source
identity and manifest.

This does not qualify SEM_UNDO, IPC permissions/namespaces, remaining
commands/timestamps, larger sets/vectors, GNU libc or foreign/32-bit paths.
Section 15's broad libc, installation/sandbox and foreign application gates
remain open.
