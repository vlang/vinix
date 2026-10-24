# Native zombie priority retention

2026-10-24; native ELF64 musl, AArch64 and x86-64. Linux 6.12.51 runs
the identical probe ELF on each architecture.

| Run, per architecture | Checks | Failures |
| --- | ---: | ---: |
| Original kernel | 1,728 | 1,656 |
| Revised production kernel | 1,728 | 0 |
| Linux reference | 1,728 | 0 |

All eight maintained suites pass on both revised kernels: priozombie,
priochange, prioquery, threadnice, groupabi, grouptid, groupzombie and waitabi.

PRIO_PROCESS, PRIO_PGRP and PRIO_USER can query and update the retained
leader priority after exit, until wait reaps the process. The probe uses
waitid with WNOWAIT before querying each zombie. It covers single-thread
exit_group, a leader's raw thread exit followed by worker exit_group, and
a worker's exit_group while its leader is paused. Leader nice is -1 or 7;
worker nice is 17, making accidental worker-priority substitution visible.
Actual musl getpriority returns the valid -1 with errno zero. Raw calls
check the Linux 20-minus-nice encoding and three upper-word forms. Setters
cover signed32 extremes and clamping, permitted effective-UID matches,
EACCES when lowering without capability or sufficient target RLIMIT_NICE,
and EPERM for another owner. All three selectors return ESRCH after reap.

The isolated candidate cdd5b77daf0927030cc955b71a5d68a255f4f7e4 is based
directly on 941c2ac85be2518ee0d0c58a6ed6b5012a9c7105. Only
kernel/proc/nice.v, kernel/proc/proc.v and kernel/userland/exit.v change.
Their SHA-256 values, in that order, are:

```
94ce3aff1b64d411e91434e2bd9fea7f4b17f320fa3d317c019af47f23c10894
4b0d32a42761165508654326c5b826d1e06eddc53a1fe8a7bb4baf4e06f4e713
02cdc29fa382f5c367ba2ebb6aa3c1892fe1e72129d699a6ad0ab930fc0d7ad4
```

The existing process record retains two scalars under the process table
lock. Leader retirement captures nice once; later retirement cannot
overwrite intervening updates. Exit detachment and lookup/update use the
same lock. Rebinding a live leader during exec clears the retired flag.
Permission checks use the retained process credentials, capabilities and
limit rules already used for live tasks. Production build receipts pin
source, commands, tools, dependencies and outputs with unchanged inputs
before and after each build. Both generated C reviews check locked borrowed
access, scalar returns, explicit address identity and no new allocation or
free. Surrounding release, bind and exit code is unchanged apart from the
new calls and scalar reset. This is not a measured storage-retention claim.

Retained initial attempts include a reserved V identifier in the fixture,
and a Linux failure caused by changing the parent's real UID so PRIO_USER
also selected the parent. The final fixture changes only effective UID.
The initial evidence-preparation helper also needed a V option-handling
correction. The first maintained runs were interrupted before controller
completion; their partial artifacts remain retained without an invented
exit status. Fresh second runs complete all eight suites per architecture.

manifest.json hashes kernels, generated C, probe ELFs, serial logs,
commands, statuses and reviews. Identical bytes use relative symlinks;
copies use APFS clones. Large boot media are omitted with explicit SHA-256
pins, including completed private media hash-recorded before removal.
External dependencies are pinned. completion/receipt.json binds the
manifest, checker and successful audit to current repository sources.

Audit without -prod:

```
v run tests/linux-compat/priozombie-evidence.v --self-test
v run tests/linux-compat/priozombie-evidence.v check tests/linux-compat/results/2026-10-24/priozombie-evidence
```

The audit checks exact summaries and capped baseline mismatch counts,
identical Linux/baseline/candidate probe ELFs, kernel/source identity and
all eight maintained suites. Its eleven negative controls and the reference
parser's two positive/nine negative controls pass. The retained reference
parser output uses its predecessor's cosmetic "Priority change" label.
Upstream Linux v6.12 kernel/sys.c is retained for semantic comparison.

Scope is stable zombies in the initial PID namespace with unmapped UIDs
and unrestricted MAC policy. Live-to-retired transition races, concurrent
credential/limit changes, mapped namespaces, mixed-error traversal,
restricted security configurations, GNU libc and translated/ELF32 paths
remain unqualified. Zombie nice in procfs and scheduler syscall views is
also unqualified. The broad libc, installation/sandbox and foreign-app
acceptance gates remain open.

This directory contains the retained evidence. Run the audit from the repository root.
