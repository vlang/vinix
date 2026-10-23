import os

const root = '/Users/alex/code/vinix'
const area = '/Users/alex/.cache/vinix-linux-compat/priochange-20261023'

fn main() {
 report := '# Native process-group and real-user priority updates

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
'
 os.write_file(area + '/report.md', report)!
 path := root + '/docs/linux-posix-qualification.md'
 existing := os.read_file(path)!
 assert !existing.contains('## Native process-group and real-user priority updates')
 os.write_file(path, existing + '\n#' + report + '\n[Retained update evidence](../tests/linux-compat/results/2026-10-23/priochange-evidence).\n')!
 matrix := root + '/docs/linux-posix-compatibility.md'
 old_matrix := os.read_file(matrix)!
 mut lines := old_matrix.split_into_lines()
 mut output := ''
 for line in lines {
  if line.starts_with('| Native process-group and real-user priority queries |') {
   output += line.replace('Group/user setpriority, zombies,', 'See the following row for group/user setters. Zombies,') + '\n'
   output += '| Native process-group and real-user priority updates | qualified subset | qualified subset | PRIO_PGRP/PRIO_USER setpriority visits matching live threads by group or real UID, including zero selectors, signed32 argument decoding and nice clamping. Actual musl EPERM/EACCES/ESRCH and permitted partial updates pass 23,508 checks per architecture and identical Linux 6.12.51 ELFs; originals fail 5,077. Eight maintained suites pass. [Receipts and limits](linux-posix-qualification.md#native-process-group-and-real-user-priority-updates). Mapped namespaces, zombies, races, mixed-error traversal, restricted MAC and GNU/foreign/ELF32 remain separate. |\n'
  } else { output += line + '\n' }
 }
 os.write_file(matrix, output.trim_right('\n') + '\n')!
 readme := root + '/tests/linux-compat/README.md'
 original_readme := os.read_file(readme)!
 os.write_file(readme, original_readme.replace('maintained results. Group/user setpriority, zombies, mapped namespaces,', 'maintained results. The following priochange case qualifies group/user setters.\nZombies, mapped namespaces,') + '\n\nThe `priochange` case adds 23,508 native ELF64 checks for group/user\nsetpriority, nonleader threads, real UID selection, signed32 argument words,\nnice clamping, actual musl errors and permitted partial updates. Both native\nkernels and identical Linux 6.12.51 ELFs pass; originals fail 5,077 checks\neach. Run `--cases priochange,prioquery,threadnice,niceabi,niceadmit,attrnice,groupabi,grouptid`\nwith a fresh state directory. All eight maintained suites pass on both kernels.\n\n`priochange-reference.v` takes the same arguments as `semabi-reference.v`;\n`--self-test` runs two positive and nine negative parser controls. Compile\n`priochange-evidence.v` without `-prod`, run `--self-test`, then `check` on\nthe [retained update evidence](results/2026-10-23/priochange-evidence).\nThe audit checks source/build identities, same-ELF results, eight maintained\nsuites and eleven negative controls. Namespace, race, zombie, mixed-error,\nrestricted MAC and GNU/foreign/ELF32 qualifications remain open.\n')!
 roadmap := root + '/roadmap.md'
 original_roadmap := os.read_file(roadmap)!
 needle := '- [x] Enforce PRIO_PROCESS setpriority using effective CAP_SYS_NICE'
 assert original_roadmap.contains(needle)
 bullet := '- [x] Implement native PRIO_PGRP/PRIO_USER setpriority across live threads,\n  selecting by process group or real UID and preserving permitted partial\n  updates. Qualify signed32 words, clamping, actual musl permission/limit\n  errors and empty selections on both architectures and same-ELF Linux.\n  See [the priority-update receipts and limits](docs/linux-posix-qualification.md#native-process-group-and-real-user-priority-updates).\n\n'
 os.write_file(roadmap, original_roadmap.replace(needle, bullet + needle))!
 println('Prepared scoped priority-update report, matrix, README and roadmap')
}
