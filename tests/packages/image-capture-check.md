# Owned release-image repository captures

Release-image repository preparation retains no-follow descriptors and the
parent/root identities of its private authenticated capture. The capture path
borrows its guard's storage; the plan transfers that owner exactly once.
Preflight, application declarations and publication reject a replaced capture,
including a byte-identical clone. Preparation rechecks contents and identity
after its capture checkpoint. Publication checks again after copying and its
staging checkpoint before admitting or publishing the complete image bundle.

Both capture and output cleanup use the existing bounded-descriptor retirement
walker through held parents. Replaced roots, unsafe modes and foreign directories
refuse deletion; leaf aliases/special files are unlinked without opening their
targets. A renamed parent does not redirect cleanup into its replacement.
Failure diagnostics retain the primary error and identify refused cleanup.
Exclusive publication and its final directory flush use the captured parent;
an error after rename retains the complete saved bundle.

`ImageRepositories.retire()!` performs checked cleanup and always closes the
owned descriptors, decoded metadata and strings, including on refusal.
`close()` retains its best-effort contract and both operations are repeatable.
The production staging command uses checked retirement before printing a check
report or final success. Existing published image output is retained when private
capture cleanup refuses. Independently owned application reviews remain usable
after repository metadata retires.

The [repository fixture](../../tools/packages/pkgcore/image_repositories_test.v)
reproduces the original loss of replacement data in both close and failed output
cleanup. It adds 80 substitutions across captured/prepared/output boundaries,
both architecture configurations, and ordinary, cloned, aliased, dangling,
FIFO, file, missing and parent replacements. Callback success/error cases bind
the checks independently of error handling. Assertions preserve inputs,
configuration bytes, outside contents/modes and moved recovery trees, require no
consumer state or partial bundle, and exercise checked retirement and retry under
a 32-descriptor limit. Additional cases replace a valid capture after output
copying, inject a final flush failure and refuse unsafe capture retirement.

The [application fixture](../../tools/packages/pkgcore/image_applications_test.v)
checks that identical replaced captures refuse new reports and release
declarations on both hosts, while existing image bundles and independent reviews
survive. The [focused controller](image-capture-check.v) runs the repository
fixture normally and both fixtures under clang ASan/UBSan. Set `V` to a reviewed
compiler and supply a new work directory. The existing
[image export controller](image-export-check.v) covers the staging CLI, shared
image/package behavior and signed consumer maintenance. The
[native image controller](native-catalog-check.v) requires the new fixture markers
before real SDK application maintenance; run `--image` with the normal pinned
native inputs, sandbox, cross-toolchains, kernel and a fresh short state directory.

This qualifies the exercised identities and checkpoint boundaries. Arbitrary
simultaneous administrator edits, complete-service allocation rates, media
power loss, production catalog migration, graphical login/presentation and wider
foreign runtimes remain outside this change. Roadmap section 14 remains open.

## Recorded results, 2026-10-17

The baseline reports `replacement-preserved=false` for both private capture
close and failed output cleanup. All **38 final host build/test checks** passed:
six focused checks and the existing 32-check image export regression, including
the real staging CLI and signed package lifecycle. ASan/UBSan cover both new
fixtures; leak detection is disabled and undefined behavior is fatal. The
32-descriptor fixture completed every substitution and retry. No whole-service
allocation-retirement claim is made.

Initial host attempts caught mistakes in the new application fixture: reuse of
a pre-publication configuration plan, an assertion confusing explicit roots with
their dependency closure, and an intermediate mistyped closure field. The final
fixture reopens published configuration, checks exact capture refusal, and
separately verifies the retained root and complete lock. Production code stayed
unchanged during those fixture retries; failed diagnostics remain recorded.

Fresh QEMU TCG native image runs passed on AArch64 (**41.2 seconds**) and x86_64
(**34.6 seconds**). Both build the production staging command, seed authenticated
image repositories/configuration/application declarations, require all new
repository assertions, and maintain real Hello, Counter and Memo applications
through upgrade, rollback, uninstall and offline cached reinstall. Ordinary
private data and native window protocols 1/2 remain required. The runs use the
unchanged qualification kernels and pinned native inputs; headless protocols do
not qualify compositor presentation. Cross-compilers emitted generated-C
warnings; full staging/build logs are retained and hash-pinned with the tested
source, compiler, guest init/fixture C and executables.

- [baseline](results/2026-10-17/image-capture-baseline.txt)
- [focused receipt](results/2026-10-17/image-capture-host.json), [summary](results/2026-10-17/image-capture-host.txt), [core fixture](results/2026-10-17/image-capture-core.txt)
- [repository sanitizers](results/2026-10-17/image-capture-asan-repositories.txt), [application sanitizers](results/2026-10-17/image-capture-asan-applications.txt)
- [broader receipt](results/2026-10-17/image-capture-regression.json), [summary](results/2026-10-17/image-capture-regression.txt), [signed CLI](results/2026-10-17/image-capture-cli.txt)
- [initial host diagnostics](results/2026-10-17/image-capture-attempts.txt)
- [AArch64 receipt](results/2026-10-17/image-capture-aarch64.json), [report](results/2026-10-17/image-capture-aarch64.txt), [serial](results/2026-10-17/image-capture-aarch64.serial.txt), [QMP](results/2026-10-17/image-capture-aarch64.qmp.txt), [staging summary](results/2026-10-17/image-capture-aarch64.stage.txt)
- [x86_64 receipt](results/2026-10-17/image-capture-x86_64.json), [report](results/2026-10-17/image-capture-x86_64.txt), [serial](results/2026-10-17/image-capture-x86_64.serial.txt), [QMP](results/2026-10-17/image-capture-x86_64.qmp.txt), [staging summary](results/2026-10-17/image-capture-x86_64.stage.txt)
- [source, compiler and artifact ledger](results/2026-10-17/image-capture-toolchain.json)
