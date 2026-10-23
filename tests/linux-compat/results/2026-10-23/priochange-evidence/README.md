# Native process-group and real-user priority updates

2026-10-23; native ELF64 musl, AArch64 with four virtual CPUs and x86-64
with two. Linux 6.12.51 runs the identical probe ELF on each architecture.

| Run, per architecture | Checks | Failures |
| --- | ---: | ---: |
| Original kernel | 23,508 | 5,077 |
| Revised production kernel | 23,508 | 0 |
| Linux reference | 23,508 | 0 |

All eight maintained suites pass on both revised kernels: priochange,
prioquery, threadnice, niceabi, niceadmit, attrnice, groupabi and grouptid.

PRIO_PGRP and PRIO_USER setpriority update every matching live task,
including nonleader pthreads. User selection uses real UID, even when an
unselected process shares the same effective UID. Zero selects the calling
process group or real UID. Nice clamps to -20..19 after signed low32
decoding. Upper-word variants of all three arguments, invalid selectors,
missing/reaped groups and users, worker TIDs used as groups and actual
musl errno behavior pass. The probe checks both raw and musl setters, then
reads each selected worker/leader and an unrelated task through both raw
and musl getters. It checks unprivileged group/user zero updates, EPERM
for another owner, EACCES for lowering nice without capability or sufficient
target RLIMIT_NICE, and successful partial updates despite an EPERM member.
It does not test every combination of multiple simultaneous refusal types.

The isolated candidate 4d5c21e0122b7eeee8e235f1154a9c701b5c7c9e is based
directly on ad2c4322bc23e230f46b3631ffc873a03057c09b. Only
kernel/proc/nice.v and kernel/syscall/table/linux_common.v change. Their
SHA-256 values are respectively:

```
067b32e970372e6e55950480081340fa9d0b2a2a7f25f28dd189401b1495f426
18e4b5f08cf61819f66b2b803e74f842d9f61bf5d327b73d94f1b61f21770a01
```

Production build receipts bind commands, source, tools, dependencies and
outputs, with unchanged inputs before and after each build. Both generated
C reviews confirm explicit process address identity, the process table lock
covering borrowed task/owner access and all apply_nice calls, scalar returns
and no new allocation/free or object lifetime. Existing query and namespace
identity helper bodies are unchanged.

Retained failed attempts include the initial fixture dereference syntax,
fixed-array code generation, and an attempted unprivileged effective-UID
change that failed setup on both Linux and Vinix. The fourth fixture regains
its saved root identity before changing effective UID and is the one used
for all reported results. The first kernel build rejected an inferred int
errno variable; the corrected variable is u64. The second build attempts
encountered stale empty build locks from the failed controllers; after
verifying no controller was running, the third builds passed. The first
generated-C checker mistook an indented call for a definition; the corrected
definition selector passed on both generated files. Failed/superseded logs,
fixture versions and the first kernel candidate remain retained.
The first maintained run stopped during niceadmit compilation when the host
disk filled; the first four suites had passed on each architecture. Fresh
second runs completed all eight suites after space was recovered. Partial
first-run artifacts and the available disk-exhaustion log remain retained.

manifest.json hashes retained kernels, generated C, probe ELFs, serial logs,
commands, statuses and reviews. Identical bytes use relative symlinks.
Large boot media are omitted with explicit SHA-256 pins; completed private
boot media are hash-recorded before removal to recover disk space. Evidence
copies use APFS clones. External dependencies are pinned.
completion/receipt.json binds the manifest, checker and successful audit to
the current repository source.

Audit without -prod:

```
v run tests/linux-compat/priochange-evidence.v --self-test
v run tests/linux-compat/priochange-evidence.v check tests/linux-compat/results/2026-10-23/priochange-evidence
```

The audit checks exact summaries and capped baseline mismatch counts,
identical Linux/baseline/candidate probe ELFs, kernel/source identities and
all eight maintained suites. Its eleven negative controls and the reference
parser controls (two positive/nine negative) pass. Upstream Linux v6.12
kernel/sys.c is retained under reference/ for semantic comparison.

Scope is live native ELF64 tasks in the initial PID namespace with unmapped
UIDs and unrestricted MAC policy. Zombie visibility, mapped namespaces,
concurrent credential/limit changes and teardown, mixed-error traversal,
restricted security configurations, GNU libc and translated/ELF32 paths
remain unqualified. No storage-retention qualification is claimed from
source inspection; this change adds no allocation or free. The broad libc,
installation/sandbox and foreign-application gates remain open.
