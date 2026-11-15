# Selected host executable build admission

`wine-host-build.v` builds the Wine native controller, bridge producer and full
retainer as arm64 Mach-O host programs. The builder also has a small fixture with
a transitive V import. It records V-to-C generation and the actual Clang
compile/link command separately, binding their selected inputs and outputs.

```sh
v -backend c -prod -gc none -manualfree -cflags -fno-lto \
  -path '@vlib|REPOSITORY|@vmodules' -o /external/host-build \
  tests/packages/wine-host-build.v
/external/host-build build controller /absolute/selected/v /external/new-controller
/external/host-build build producer /absolute/selected/v /external/new-producer
/external/host-build build retainer /absolute/selected/v /external/new-retainer
/external/host-build check /external/new-controller
```

The fixed profile selects macOS/arm64, production/manual-free C generation,
disabled default backtrace/segfault handling and explicit repository/module
paths. Discovery captures parsed V files and their hashes before generation;
the actual build must preserve that list and every pin. Both V children use
the existing closed environment and observed host-image admission. Their
private HOME/TMPDIR/VMODULES namespaces and original command locations remain
bound during independent checks and checks of copied evidence.

Clang receives the selected canonical Command Line Tools SDK explicitly through
`-isysroot`, its explicit resource directory, an arm64 target and a fixed command
with two translation units. SDK settings are pinned. The complete selected
Clang resource-header tree and the actual discovery/compile C include paths,
resolved targets, order, repetitions and hashes are checked. Existing closed
Clang environments and observed ordinary non-system image bytes are required.
Selected V, C, header and host-image bytes are retained in a content-addressed
input store. APFS clones avoid unnecessary physical copies; ordinary copies are
the fallback. A changed previously pinned input refuses when phases are merged.

Read-only `check` verifies the fixed profile and original namespace, source
dumps, V input pins, raw/decoded image records, environments, C command/include
proofs, complete resource-header snapshot, required input rows, all retained
input blobs, the exact output inventory and Mach-O executable header/mode.
Generated C outputs must match their compile-input pins even after resealing
the output map. Copied graphs still require the original input namespaces.

`wine-host-build-check.v HOST_BUILDER FIXTURE_BUILD FRESH_OUTPUT
[CONTROLLER_BUILD PRODUCER_BUILD]` requires real and unchanged copied baselines,
executes the fixture and optionally checks both real host program entrypoints,
then requires thirteen exact resealed refusals. Cases cover omitted parsed
imports and observed images, V/C environments and commands, omitted C include
records, linked receipts, changed retained input bytes, non-executable mode,
format/scope changes and changed generated C. Every mutation changes only a
private copy. Expected failures use explicit checks under `-prod`.

The [required host receipt boundary](wine-host-required-check.md) uses format 2
and shared `winehostbuild` admission. Qualification work in the producer,
controller and retainer requires the matching receipt beside the executable.
Native and prepared evidence bind the producer/controller host graphs; the full
retainer also retains its own graph. Original format-1 bundles and their original
checkers keep their historical contract. The builder's own bootstrap, complete
compiler provenance, unreported inputs/search
absence, full SDK content and Mach-O linker/library closure remain open. No
link replay or deterministic executable reproduction is claimed. macOS loader
and shared-cache bytes remain explicitly unadmitted. Local receipts are not
publisher authentication. Original prerequisite bundles and historical
verifiers remain required. No new guest execution, kernel/default change,
owned ARM/GUI or complete roadmap 14 acceptance is claimed.

The checkpoint is `/Users/alex/.cache/vwhostbuild-20261115-01`, based on
`d4dd87232`. Final `build-04` admits `fixture-02`, `controller-01` and
`producer-01`; the fixture executes successfully and both real programs pass
their embedded source guards and return the expected usage status. Final
`controls-02` passes real/copied baselines, both real build admissions/entrypoint
checks and all thirteen exact refusals in `controls-run-02`. Production/manual-
free host-image and real poisoned-parent V-generation module controls also pass.
The initial fixture's missing segfault-handler link failure and superseded
builder/control binaries remain diagnostic evidence. The explicit disabled-
handler profile passes without weakening an admission check.
