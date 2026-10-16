# Captured publisher profile staging

The native SDK, SQLite, FFmpeg, Wine and Apple publisher profiles capture
no-follow descriptors and identities for their staging parent, private root,
payload inventory and catalog lock. All five recheck after creation, every
imported package and readiness. Source admission, copied-payload validation,
license notices, runtime bounds, target coverage and canonical pins retain their
existing checks.

Cleanup first checks the named inventory and unpublished lock against their
captured directories. A changed child preserves the entire private root; a
changed root preserves its replacement and recovery tree. Otherwise the existing
bounded retirement walker inventories directories owned by the publishing account
on the same filesystem and removes entries without following leaf aliases. It resolves
through the held parent even if that parent moved. Errors include both the
original failure and a path for retained recovery data.

Only `lock` is published. Exclusive rename uses the held private root and output
parent descriptors. The catalog directory is flushed before rename, and the
parent after it. Private inventory retirement happens separately; successful
retirement is followed by another parent flush. Once rename succeeds, failures
report publication and preserve the canonical catalog. Inspect saved output
before retrying, including after a moved-parent or cleanup-refusal diagnostic.

The [fixture](../../tools/packages/pkgcore/profile_export_test.v) reproduces
replacement-directory deletion in all five original profile builders. Its 320
substitution cases exercise outer roots at creation/import/readiness, inventory
roots after import and lock roots at readiness. Cases include ordinary and
byte-identical replacement directories, aliases, FIFOs, and outer dangling,
file, absent and parent replacements, with callback success and failure.
Assertions retain exact recovery file snapshots and root identity, outside
content/modes, source pins and canonical output after fresh retry under a
32-descriptor limit.

Fifteen further cases inject final directory-flush failures, parent replacement
after rename and inventory replacement before successful-return cleanup. Each
retains a complete canonical lock matching a clean build, reports the saved
output and permits a fresh independent retry. Only structural ELF, PE and Mach-O
fixtures are used for publisher admission; these bytes are never executed.
FFmpeg publication additionally uses the complete previously reviewed 8.0.1
source archive and its production digest/size check.

Run [the host controller](profile-export-check.v) with `V` set to a reviewed
compiler, `VINIX_PROFILE_EXPORT_SOURCE` naming that retained FFmpeg source
archive and a new work directory. It runs eighteen build/test checks: the new
fixture normally and with clang ASan/UBSan, all five existing profile suites,
atomic metadata tests and captured-export retirement tests. Host C builds use
`-O1`, including the sanitizer fixture. Sanitizer leak
detection is disabled; these checks do not establish complete-profile allocation
freedom. Existing profile suites cover signing, offline lifecycle, declarations,
license/host refusals, destination collisions and source changes.

The [native image controller](native-catalog-check.v) accepts `--profiles` with
the same source archive environment and ordinary pinned native inputs,
sandbox, compilers, kernel and fresh short state directory. It boots production
staging, runs four separate sixteen-case fixture processes for each profile,
then maintains real native SDK applications. The first process also checks the
baseline and three saved-output failures for its profile. On Vinix, six-second
waits separate test phases, allowing the kernel's five-second removed-node
grace period to expire. The complete image checks all 320 substitutions and
fifteen saved-output cases with a 900-second functional deadline. It records both
the fixture executable and source archive hashes. Software scenarios are
qualified separately.

This binds the exercised checkpoint boundaries, canonical output and target
syscall behavior. It does not freeze arbitrary simultaneous administrator
writes, recover profile processes after a kill, qualify media power loss or
execute the structural compatibility payloads. Production catalog migration,
graphical sessions and broader foreign-runtime qualification remain open under
roadmap section 14.

## Stress limits observed during qualification

The original combined guest fixture failed on AArch64 while reading a prepared
payload; an instrumented replay exited with signal 11. A subsequent run with
one process per profile reached native substitution case 58 before a read was
refused. Its retained `/proc/kernel-resources` observation identifies an owner
reservation denial: **57,933,458 bytes** were charged to that owner against a
**58,059,776-byte** allowance, and the next read requested **131,200 bytes** of
scratch. Global charge was below its limit, memory pressure was zero, and the
post-failure descriptor listing contained only 0–3. Six-second waits alone did
not retire the process's retained mappings. Both corresponding x86 runs were
interrupted during investigation and do not count as passes.

The final guest fixture uses fresh processes for sixteen-case cohorts and keeps
all 64 substitutions per profile. The publisher implementation remained unchanged
while the fixture was split. This qualifies directory ownership, failure cleanup
and saved publication at those bounded call counts; it does not establish
allocation freedom for repeated whole-profile construction in a persistent
process. The original failures, measured denial, executable/C artifacts and
interrupted x86 logs are retained. The first unoptimized host controller was
also stopped; the final host controller uses `-O1` and a new work directory.

## Recorded results, 2026-10-17

All **43 final host build/test checks** passed: the eighteen-check focused
controller and the existing 25-check composition ownership regression. The
new fixture passed normally and under clang ASan/UBSan. Existing signing,
profile/architecture/license, literal CLI, catalog/composition and tracked
planning checks also passed. The tracked planning components retained zero
bytes; that measurement excludes complete profile construction/publication.
The baseline reports replacement loss for all five original exporters; final
fixtures preserve each replacement and recovery tree.

Fresh QEMU TCG native image runs passed on AArch64 (**494.9 seconds**) and
x86_64 (**550.0 seconds**), each with all twenty profile cohort processes and
the five sets of saved-output checks. Each then maintained real Hello, Counter
and Memo applications through update, rollback, uninstall and cached reinstall
with retained ordinary-user data. The unchanged qualification kernels, pinned
native inputs and exact FFmpeg source archive were used. Receipts bind kernels,
init/fixture executables, staged service, trust, application declarations,
native payloads, source archive and serial/QMP output. Full staging/build logs,
including generated-C compiler warnings, are retained and hash-pinned. Headless
native window protocols do not qualify graphical login or compositor display.
The four verbatim baseline/AArch64 failure reports retain framework blank lines
and spaces on quoted empty lines; whitespace checks exclude those raw reports.

- [baseline](results/2026-10-17/profile-export-baseline.txt), [focused receipt](results/2026-10-17/profile-export-host.json), [summary](results/2026-10-17/profile-export-host.txt), [fixture](results/2026-10-17/profile-export-core.txt), [sanitizers](results/2026-10-17/profile-export-asan.txt)
- [broader receipt](results/2026-10-17/profile-export-regression.json), [summary](results/2026-10-17/profile-export-regression.txt), [signed CLI](results/2026-10-17/profile-export-cli.txt), [tracked planning](results/2026-10-17/profile-export-tracked.txt)
- [AArch64 receipt](results/2026-10-17/profile-export-aarch64.json), [report](results/2026-10-17/profile-export-aarch64.txt), [serial](results/2026-10-17/profile-export-aarch64.serial.txt), [QMP](results/2026-10-17/profile-export-aarch64.qmp.txt), [staging summary](results/2026-10-17/profile-export-aarch64.stage.txt)
- [x86_64 receipt](results/2026-10-17/profile-export-x86_64.json), [report](results/2026-10-17/profile-export-x86_64.txt), [serial](results/2026-10-17/profile-export-x86_64.serial.txt), [QMP](results/2026-10-17/profile-export-x86_64.qmp.txt), [staging summary](results/2026-10-17/profile-export-x86_64.stage.txt)
- Original combined AArch64 [report](results/2026-10-17/profile-export-attempt-aarch64.txt), [serial](results/2026-10-17/profile-export-attempt-aarch64.serial.txt), [QMP](results/2026-10-17/profile-export-attempt-aarch64.qmp.txt); diagnostic replay [report](results/2026-10-17/profile-export-diagnostic-aarch64.txt), [serial](results/2026-10-17/profile-export-diagnostic-aarch64.serial.txt), [QMP](results/2026-10-17/profile-export-diagnostic-aarch64.qmp.txt)
- Measured AArch64 owner-limit [report](results/2026-10-17/profile-export-cohort-aarch64.txt), [serial](results/2026-10-17/profile-export-cohort-aarch64.serial.txt), [QMP](results/2026-10-17/profile-export-cohort-aarch64.qmp.txt)
- Interrupted x86 [original report](results/2026-10-17/profile-export-attempt-x86_64.txt), [serial](results/2026-10-17/profile-export-attempt-x86_64.serial.txt), [QMP](results/2026-10-17/profile-export-attempt-x86_64.qmp.txt); [profile-process report](results/2026-10-17/profile-export-cohort-x86_64.txt), [serial](results/2026-10-17/profile-export-cohort-x86_64.serial.txt), [QMP](results/2026-10-17/profile-export-cohort-x86_64.qmp.txt)
- [source, compiler and artifact ledger](results/2026-10-17/profile-export-toolchain.json)
