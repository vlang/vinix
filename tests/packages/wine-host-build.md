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

Format 3 selects `ld64.lld` for that same compile/link command and requires its
captured inputs, byte-identical replay and observed file-load coverage. The
archive, extracted members, replay executable, raw command/environment/image
records and `host-link.json` are mandatory output rows. The selected linker and
ordinary replay host images are mandatory retained input rows. Shared
`winemacholink` admission checks the fixed SDK/toolchain profile, the original
log namespace, captured member hashes, safe reported loads and both executable
hashes. The running role uses the executable verified by this replay.

Format 4 additionally requires `sdk-graph.json`, checking captured SDK stubs
against current resolved ordinary sources and declared library reexports across
all targets. The exact graph must match recomputation; source alias and resolved
target hashes belong to the input map and byte store. Linked graph records,
forged graphs, omitted SDK source pins and old format-3 receipts refuse. This is
the bounded declaration projection described in [the SDK audit](wine-sdk-check.md),
with symbols opaque and full ABI/search/loader admission still unqualified.

Read-only `check` verifies the fixed profile and original namespace, source
dumps, V input pins, raw/decoded image records, environments, C command/include
proofs, complete resource-header snapshot, required input rows, all retained
input blobs, the exact output inventory and Mach-O executable header/mode.
Generated C outputs must match their compile-input pins even after resealing
the output map. Copied graphs still require the original input namespaces.

`wine-host-build-check.v HOST_BUILDER FIXTURE_BUILD FRESH_OUTPUT
[CONTROLLER_BUILD PRODUCER_BUILD]` requires real and unchanged copied baselines,
executes the fixture and optionally checks both real host program entrypoints,
then requires thirty-six exact resealed refusals. Cases cover omitted parsed
imports and observed images, V/C environments and commands, omitted C include
records, linked receipts, changed retained input bytes, non-executable mode,
format/scope changes and changed generated C. Every mutation changes only a
private copy. Nine further cases cover old host format, changed replay output,
load map, replay environment/argv, extracted bytes, omitted linker input,
changed link namespace and a linked link receipt. Expected failures use explicit
checks under `-prod`. Four further cases cover changed/linked SDK graphs,
omitted resolved SDK source input and the old link-only host format.
Ten further cases cover the required SDK-denied replay: weakened policy,
disabled restriction in the execution record, added environment input, successful
negative-control exit, unrelated read/link failures, changed replay/member bytes,
a linked receipt and the old SDK-graph-only host format.

The [required host receipt boundary](wine-host-required-check.md) uses format 5
and shared `winehostbuild` admission. Qualification work in the producer,
controller and retainer requires the matching receipt beside the executable.
Native and prepared evidence bind the producer/controller host graphs; the full
retainer also retains its own graph. Original format-1/2/3/4 bundles and their original
checkers keep their historical contract. The builder's own bootstrap, complete
compiler provenance, unreported inputs/search
absence, full SDK content and complete Mach-O linker/library closure remain open.
Captured-link reproduction covers this local profile. macOS loader
and shared-cache bytes remain explicitly unadmitted. Local receipts are not
publisher authentication. Original prerequisite bundles and historical
verifiers remain required. Kernel/default changes, owned ARM/GUI and complete
roadmap 14 acceptance remain separate gates.

Format 5 additionally requires `sdk-denied/receipt.json` and every captured
member, executable, child command/environment/exit, raw log and LLD execution
record in that replay graph. The pinned builder dispatches a child that loads
the system sandbox API, denies reads under installed CLT SDK roots, then execs
LLD with a closed environment. Captured replay must match the original output;
three SDK path reads must fail with EPERM/EACCES, and an installed-SDK response
must link identically unrestricted and fail with the exact missing-library
diagnostics when restricted. The temporary symlink used by a read control is
removed after execution; its original path remains bound in the command log.
Admission rechecks these controls and observations from retained ordinary files,
including unchanged copied bundles with their original namespaces. The new
module is embedded, pinned and retained alongside existing admission sources.
The [historical standalone qualifier](wine-sdk-denied-replay.md) retains its
format-4 contract. This restriction covers LLD's installed CLT SDK reads;
other filesystem/network access, helper startup and OS library/cache bytes remain
outside that restriction's claim. Installed SDK source checks and unrestricted
controls still require the original SDK.

The historical optional-builder checkpoint is `/Users/alex/.cache/vwhostbuild-20261115-01`, based on
`d4dd87232`. Final `build-04` admits `fixture-02`, `controller-01` and
`producer-01`; the fixture executes successfully and both real programs pass
their embedded source guards and return the expected usage status. Final
`controls-02` passes real/copied baselines, both real build admissions/entrypoint
checks and all thirteen exact refusals in `controls-run-02`. Production/manual-
free host-image and real poisoned-parent V-generation module controls also pass.
The initial fixture's missing segfault-handler link failure and superseded
builder/control binaries remain diagnostic evidence. The explicit disabled-
handler profile passes without weakening an admission check.
