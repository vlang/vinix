# Captured mirror and release staging

Mirror and publisher release exports now capture their parent and private staging
root through no-follow descriptors. Checkpoints recheck the visible parent,
ancestor permissions and captured root device/inode before subsequent export
work. Replacing a stage with an otherwise identical tree still refuses. Exclusive
publication renames relative to the captured parent and flushes that descriptor.
After rename, errors retain the published output and explicitly report its saved
state, including a changed visible parent or failed directory flush.

Failure cleanup admits the captured root name again and uses the existing
generation retirement walker through the held parent. It inventories ordinary,
administrator-owned directories on the same filesystem before unlinking any
entries, then reopens components without following aliases. Leaf aliases,
FIFOs and hard links are unlinked without opening or chmodding their targets.
Descriptor use is independent of depth. Unsafe or changed roots and foreign
directories refuse cleanup and retain recovery data; diagnostics preserve the
original export failure and identify the failed cleanup path. A replaced parent
does not redirect retirement into its replacement.

Previously, a failed export recursively removed the staging pathname without
checking the captured identity. The baseline checkpoint renames the private
stage away, creates a replacement containing `keep`, then returns an error.
The original implementation reports `replacement-preserved=false`. The revised
implementation retains both the replacement and renamed original stage.

The [mirror suite](../../tools/packages/pkgcore/mirror_test.v) adds 48 substitutions
across creation, copying and readiness; the
[release suite](../../tools/packages/pkgcore/release_test.v) adds 64 across
creation, copying, staging and sequence reservation. Each substitutes an ordinary
directory, alias, dangling alias, FIFO, file, missing root, cloned tree or parent,
with both a returned checkpoint error and a successful checkpoint return.
Refusal preserves replacement/outside contents and modes, recovery trees,
consumer trust/state/cache, signing inputs and publisher reservation timing.
Mirrors emit no completion and retry from verified cache with the upstream
removed. Releases retry exactly the reserved sequence and signed inputs.

The [guard fixture](../../tools/packages/pkgcore/export_stage_test.v) checks
1,000 complete create/check/retire/close cycles with zero tracked retained bytes,
128 retirements of 48-level trees under a 32-descriptor limit, special-leaf
handling, unsafe roots and root-only foreign ownership refusals before unlinking.
It injects a post-publication flush failure and verifies that complete output
survives; existing file/directory/alias/dangling/FIFO destinations remain intact.
The measured component excludes fixture setup and complete signing/export calls.
On Vinix the fixture allows the kernel's five-second unlinked-node grace period
between the flat allocation cycles and the 6,144-directory stress burst. It
records kernel-resource accounting around that interval. This keeps separate
component checks from exhausting one process's deferred kernel-resource budget;
cycle counts and the 32-descriptor limit are unchanged.

The [host controller](export-retirement-check.v) runs tracked guard and prior
mirror preparation assertions, generation recovery/collection regressions, and
clang ASan/UBSan for the guard and signed mirror/release suites. Set `V` to a
reviewed compiler and supply a new work directory. The existing
[image export controller](image-export-check.v) exercises shared package and
real CLI behavior. The expanded [mirror target controller](mirror-ownership-runtime-check.v)
runs both ownership fixtures and mirror/deployment/release suites on each target.
Use the normal cross-toolchain environment, `VINIX_HWTEST_TCG=1`, `--arch`,
`--kernel` and a new short `--state-dir`.

These checks bind exercised checkpoint boundaries and cleanup/publication
identities. They do not freeze arbitrary simultaneous administrator writes or
qualify media power loss, other catalog/profile exporters, full graphical
sessions or wider foreign runtimes. Section 14's release acceptance remains open.

## Recorded results, 2026-10-17

The baseline reproduces deletion of the replacement directory. All **46 host
build/test checks** passed: fourteen focused checks and the existing 32-check
image export regression, including signed CLI maintenance. ASan/UBSan cover
the guard, mirror and release suites; sanitizer leak detection is disabled and
undefined behavior is fatal. The separately tracked guard component retained
zero bytes over 1,000 complete cycles.

The first two x86_64 runs failed in the combined stress fixture. The diagnostic
retry reported `ENOMEM` at flat cycle 663 after deep-tree stress. Vinix defers
unlinked kernel nodes for five seconds and charges them to kernel-resource
budgets. The final fixture runs the flat cycles first, records resource usage
around a six-second grace interval, then performs the unchanged deep stress.
It keeps all cycle counts, the 32-descriptor limit and 1 GiB guest RAM. This
isolates the component checks; it does not qualify kernel memory or sustained
filesystem throughput. A subsequent host/guest attempt was interrupted by the
stopped CLI turn and has no complete result; its partial logs remain hash-pinned.

Fresh QEMU TCG runs passed on AArch64 (**118.1 seconds**) and x86_64
(**75.2 seconds**), including both tracked fixtures and signed mirror,
deployment and release suites. Each eight-artifact receipt binds the kernel,
init, five programs and serial output. Both guests exercise the root-only
foreign-ownership refusal. Kernel-resource charges decreased across the grace
interval, with no recorded budget denial in either final fixture. Compiler,
source, generated C, executable and evidence hashes are recorded in the ledger.

- [baseline regression](results/2026-10-17/export-retirement-baseline.txt)
- [focused host receipt](results/2026-10-17/export-retirement-host.json), [summary](results/2026-10-17/export-retirement-host.txt)
- [tracked measurements](results/2026-10-17/export-retirement-memory.txt), [sanitizers](results/2026-10-17/export-retirement-asan.txt)
- [broader regression receipt](results/2026-10-17/export-retirement-regression.json), [summary](results/2026-10-17/export-retirement-regression.txt), [signed CLI](results/2026-10-17/export-retirement-cli.txt)
- [first x86_64 failure](results/2026-10-17/export-retirement-attempts.txt), [serial](results/2026-10-17/export-retirement-attempt-x86.serial.txt), [QMP](results/2026-10-17/export-retirement-attempt-x86.qmp.txt)
- [diagnostic retry](results/2026-10-17/export-retirement-diagnostic-x86.txt), [serial](results/2026-10-17/export-retirement-diagnostic-x86.serial.txt), [QMP](results/2026-10-17/export-retirement-diagnostic-x86.qmp.txt)
- [AArch64 receipt](results/2026-10-17/export-retirement-aarch64.json), [report](results/2026-10-17/export-retirement-aarch64.txt), [serial](results/2026-10-17/export-retirement-aarch64.serial.txt), [QMP](results/2026-10-17/export-retirement-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-17/export-retirement-x86_64.json), [report](results/2026-10-17/export-retirement-x86_64.txt), [serial](results/2026-10-17/export-retirement-x86_64.serial.txt), [QMP](results/2026-10-17/export-retirement-x86_64.qmp.txt)
- [source, compiler, generated C, executable and evidence ledger](results/2026-10-17/export-retirement-toolchain.json)
