# Native process-group and real-user priority queries

2026-10-23; native ELF64 musl, AArch64 with four virtual CPUs and x86-64
with two. Linux 6.12.51 runs the identical probe ELF on each architecture.

| Run, per architecture | Checks | Failures |
| --- | ---: | ---: |
| Original kernel | 6,199 | 403 |
| Revised production kernel | 6,199 | 0 |
| Linux reference | 6,199 | 0 |

All seven maintained suites pass on both revised kernels: prioquery,
threadnice, niceabi, niceadmit, attrnice, groupabi and grouptid.

PRIO_PGRP and PRIO_USER getpriority select the lowest nice value among
matching live tasks, including nonleader pthreads. The UID selector uses
the real UID. Zero uses the calling process group or real UID. Signed
low32 selectors and target IDs, invalid selectors, missing/empty selections,
changing task nice, sibling isolation and actual musl errno handling pass.
Raw successful results are 20 - nice; musl nice -1 succeeds with errno zero.
The 5,670 invalid-selector checks cross 63 selectors, five target IDs and
nine upper-word combinations through raw and musl entry points. The other
529 checks cover three processes with distinct real/effective UIDs, shared
and separate groups, workers and reaped selections.

The isolated candidate 730d43fb3d1505c4e7f8ad92c5292586d9c841db is based
directly on a544610c9f559e97e86c38dc931c0c8125e174c9. Its only source
changes are kernel/proc/nice.v and kernel/syscall/table/linux_common.v.
Their SHA-256 values are respectively:

```
950db21493f4edab4bf9be97407f4f546397ce82e65a6a263e076f5d9aaff8ae
f125c27895e9e28ea346207211907868a1d2f24cb61faa489c50d2189ffb33c7
```

Build receipts bind production commands, source, tools, dependencies and
outputs, with unchanged input hashes before and after the build. Generated
C review on both architectures confirms explicit address identity checks,
all borrowed task/process dereferences under the process table lock,
scalar-only returns and no new allocation/free or object lifetime. Existing
process lookup, nice and setpriority helpers remain byte-identical.

The first candidate passed the direct test but its V typed-pointer comparison
generated a deep struct comparison; the revised kernel uses voidptr identity.
First maintained ARM builds failed their old-directory compiler guard.
Later attempts exposed overlong QEMU socket paths and missing ARM Linux UAPI
headers. Superseded maintained runs were stopped and recorded with exit143;
the final m3arm/m4x86 runs use short paths and pin their extra header inputs.
The m3x86 run passed six suites, then disk exhaustion prevented preparing
the final suite. Its exit1 and partial receipt remain retained; m4x86 reruns
all seven suites on the same revised kernel.
Initial fixture compile corrections and all these attempts remain retained.

manifest.json hashes retained kernels, generated C, ELFs, serial logs,
commands, statuses and reviews. Identical bytes use relative symlinks.
Large boot media are omitted with explicit SHA-256 pins; superseded media
were pruned from the private cache after hashing to recover disk space.
Completed build objects are also hash-recorded before removal; kernels and
generated C remain retained. Evidence copies use APFS filesystem clones.
External tools/dependencies are pinned. completion/receipt.json binds the
manifest, final checker and successful audit to current repository source.

Audit without -prod:

```
v run tests/linux-compat/prioquery-evidence.v --self-test
v run tests/linux-compat/prioquery-evidence.v check tests/linux-compat/results/2026-10-23/prioquery-evidence
```

The audit checks exact summaries and capped baseline mismatch counts,
identical Linux/baseline/candidate probe ELFs, kernel/source identity and all
seven maintained suites. Its eleven negative controls and the reference
parser controls (two positive/nine negative) pass. Upstream Linux v6.12
kernel/sys.c is retained under reference/ for semantic comparison.

Scope is live tasks in the initial PID namespace with unmapped UIDs and
unrestricted MAC policy. Group/user setpriority still returns EINVAL.
Zombie priority visibility, mapped user namespaces, concurrent credential
changes/teardown, restricted security configurations, GNU libc and
translated/ELF32 paths remain unqualified. No new storage retention is
claimed from source inspection; this query adds no allocation or free.
The broad libc, installation/sandbox and foreign-application gates remain open.

The first evidence audit rejected duplicate suffix matches for the frozen
source and build worktree. The corrected checker selects the architecture
worktree explicitly and tests both ambiguity and missing-path refusals.
The failed audit is retained alongside the successful retry.
