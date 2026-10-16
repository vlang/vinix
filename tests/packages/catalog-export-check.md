# Captured catalog workspace and composition publication

`pack-catalog`, `compose-catalog` and `compose-catalog-for` now retain no-follow
descriptors and the identities of their staging parent/root. Construction
rechecks after creation, each imported package and the final readiness checkpoint.
Composition rechecks after creation and readiness. Existing pinned manifests,
payload hashes, canonical recipe/provenance bytes, host coverage and dependency
checks still run before publication.

Failure cleanup uses the existing retirement walker through the held parent.
It admits the root identity, inventories owned directories on the same filesystem
and removes entries without following leaf aliases or changing outside targets.
Changed roots or unsafe ownership/modes refuse deletion and retain recovery data;
the diagnostic preserves the original error and identifies cleanup refusal.
Moving the parent does not redirect deletion into the replacement directory.
Descriptor use is independent of tree depth.

Exclusive publication and its final directory flush use the captured parent.
Once rename succeeds, cleanup never removes the published artifact. Flush
failure or a subsequently changed visible parent reports that publication
occurred; inspect the saved directory before retrying. Successful public replies
remain independent of the retired plan. Canonical formats, input provenance,
space accounting and publisher sequence rules are unchanged.

The [fixture](../../tools/packages/pkgcore/catalog_export_test.v) reproduces
replacement-directory deletion by both original exporters. It exercises 144
substitutions across workspace creation/import/readiness and creation/readiness
of strict, AArch64 and x86_64 compositions. Each uses ordinary, aliased,
dangling, FIFO, file, missing, cloned and parent replacements with both callback
success and callback error. Assertions preserve exact recovery file snapshots,
root identity, outside content/modes and source pins. Fresh retry leaves those
trees unchanged and succeeds under a 32-descriptor limit.

Additional checks inject directory-flush and post-rename parent changes in all
four modes. Complete canonical artifacts remain saved and match fresh builds.
An ordinary composed workspace then feeds signed release publication and offline
install/remove on both consumer architectures. The maintained catalog and
composition suites cover complete application/runtime closures, destination
races, source capture, license/firmware rules and reproducible signatures.

Run the [focused host controller](catalog-export-check.v) with a reviewed `V`
and a new work directory. It runs the new fixture normally and under clang
ASan/UBSan, plus catalog/composition sanitizer suites. The existing
[composition ownership controller](composition-ownership-check.v) covers the
publisher/profile/CLI regressions and tracked planning lifetimes. The
[native image controller](native-catalog-check.v) requires the new assertions
before real SDK application maintenance; use `--image`, the normal pinned native
inputs, sandbox, cross-toolchains and kernel, and a fresh short state directory.

These checks bind exercised checkpoint boundaries and identities. They do not
freeze arbitrary simultaneous administrator writes, qualify media power loss,
measure whole-export allocation rates or extend the separate profile builders'
staging guarantees. Production catalog migration, graphical sessions and broader
foreign-runtime qualification remain open under roadmap section 14.

## Recorded results, 2026-10-17

The baseline reports `replacement-preserved=false` for both workspace and
composition cleanup. All **33 final host build/test checks** passed: eight
focused checks and the existing 25-check composition ownership regression,
including publisher/profile assertions, literal CLI paths, signed lifecycle,
tracked planning and sanitizer checks. ASan/UBSan cover the new fixture and
existing catalog/composition suites; leak detection is disabled and undefined
behavior is fatal. Existing tracked planning components still retain zero bytes;
that measurement excludes complete construction/publication calls.

The first integration fixture incorrectly called `State.close()` on a transaction
result that borrows caller/catalog fields. ASan reported a double free of the
shared publisher key. The corrected fixture follows the documented ownership
contract: transaction results are observed, while independently owned public
catalog/composition replies are closed. The initial diagnostic and binaries are
retained; production code stayed unchanged during this fixture correction.

Fresh QEMU TCG native image runs passed on AArch64 (**46.9 seconds**) and x86_64
(**36.7 seconds**). Each boots production-staged tools, requires the 144-case
fixture, saved-output and signed offline-consumption markers, and maintains
real Hello, Counter and Memo applications through update, rollback, uninstall
and cached reinstall with retained ordinary-user data. Receipts bind kernels,
tools, native inputs, signed bundles, configuration, declarations, fixture and
serial/QMP output. The unchanged qualification kernels and pinned native inputs
are used. Full staging logs, including generated-C compiler warnings, are
hash-pinned alongside source, init/fixture C and executables. Headless native
window protocols do not qualify compositor presentation or graphical login.

- [baseline regression](results/2026-10-17/catalog-export-baseline.txt), [initial fixture diagnostic](results/2026-10-17/catalog-export-diagnostic.txt)
- [focused receipt](results/2026-10-17/catalog-export-host.json), [summary](results/2026-10-17/catalog-export-host.txt), [fixture](results/2026-10-17/catalog-export-core.txt)
- [export sanitizers](results/2026-10-17/catalog-export-asan-exports.txt), [catalog sanitizers](results/2026-10-17/catalog-export-asan-catalog.txt), [composition sanitizers](results/2026-10-17/catalog-export-asan-composition.txt)
- [broader receipt](results/2026-10-17/catalog-export-regression.json), [summary](results/2026-10-17/catalog-export-regression.txt), [signed CLI](results/2026-10-17/catalog-export-cli.txt), [tracked planning](results/2026-10-17/catalog-export-tracked.txt)
- [AArch64 receipt](results/2026-10-17/catalog-export-aarch64.json), [report](results/2026-10-17/catalog-export-aarch64.txt), [serial](results/2026-10-17/catalog-export-aarch64.serial.txt), [QMP](results/2026-10-17/catalog-export-aarch64.qmp.txt), [staging summary](results/2026-10-17/catalog-export-aarch64.stage.txt)
- [x86_64 receipt](results/2026-10-17/catalog-export-x86_64.json), [report](results/2026-10-17/catalog-export-x86_64.txt), [serial](results/2026-10-17/catalog-export-x86_64.serial.txt), [QMP](results/2026-10-17/catalog-export-x86_64.qmp.txt), [staging summary](results/2026-10-17/catalog-export-x86_64.stage.txt)
- [source, compiler and artifact ledger](results/2026-10-17/catalog-export-toolchain.json)
