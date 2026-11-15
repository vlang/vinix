# V source-generation host boundary

Bridge, native guest and package CLI source generation now run the selected V
compiler with a complete replacement environment. PATH, locale, timezone and
source epoch are fixed. HOME, TMPDIR and VMODULES point to separate canonical
directories in the build logs namespace, created with mode 0700. VEXE and V's
caller-executable fields name the selected canonical ordinary compiler file;
automatic compiler fallback is disabled. Parent VFLAGS, module search paths,
credentials and loader-injection settings are excluded.

A before-command `-version` probe records the selected compiler's observed
image UUIDs and canonical ordinary non-system image bytes. Discovery and actual
C generation each retain their argv, exact environment, raw dyld observations
and decoded image identities. Final producer admission, native before/after
boot verification, the independent producer checker and full retainer require
those records in addition to the existing parsed-source and C/header/linker
checks. The compiler must match its previously captured input hash. Copied
graphs preserve ordinary records and the original environment namespace.

`wine-host-images-snapshot` now admits and preserves selected V images as well
as Clang/LLD images, deduplicated by bytes and mode. Native before-boot output
maps and producer output maps bind all twelve new records. The full retainer's
artifact map includes the selected ordinary V image paths.

The optional module control uses `VINIX_V_HOST_TEST_COMPILER` and a fresh
`VINIX_V_HOST_TEST_STATE`. It poisons parent VFLAGS, VMODULES, VEXE and
DYLD_INSERT_LIBRARIES, then requires real discovery and C generation to succeed
with matching parsed source lists. Adding VFLAGS to the recorded child
environment must refuse. The full retention runner has forty-four mutation
cases, including five V host cases: omitted baseline images, altered child
environment, omitted raw observations, changed image hashes and linked receipts.
Real and unchanged copied baselines must pass first; every mutation must refuse
at its named check without retained output.
The module checks now use [explicit production-active conditions](wine-helper-controls-check.md)
because the pinned compiler omits `assert` under `-prod`. Their requalification
supersedes earlier assertion-dependent module results; full-retainer controls
already use explicit errors.

This covers the selected V-to-C processes. Compiler source/bootstrap provenance,
controller/producer executable builds, other host tools, unreported inputs and
search absence remain separate gates. macOS system images remain explicitly
metadata-only: shared-cache and loader bytes are unadmitted. This is not a
complete hermetic toolchain qualification. Historical complete inputs and
original verifiers remain required. Product defaults, owned ARM/GUI and broader
roadmap 14 acceptance are unchanged.

The x86 checkpoint is `/Users/alex/.cache/vwvcompiler-20261115-01`, from isolated
base `333a49ad3`. Production/manual-free module controls, fresh PE/runtime and
independent producer admission pass. The signed holder-death/collection run
passes in 107.24 seconds with post-run V image/environment verification. All 32
owned-receipt controls pass. Final `controls-02` passes real and unchanged copied
baselines plus all forty-four exact refusals in `controls-run-02`. The initial
copy-fixture refusal is preserved; its fix copies V argv receipts as ordinary
files without relaxing production admission. Observed C bytes/modes, selected
V/Clang/LLD image bytes/modes and the selected resource-header tree are retained.
