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
then requires eighty-four exact refusals. Cases cover omitted parsed
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
Twelve more cover ordinary file-data capability replay: a weakened policy,
an added hidden-object permission with a consistently resealed policy, changed
execution/environment/exit records, unrelated allowed/denied read or hidden-link
results, altered output/member bytes, linked evidence and the old format 5.
Seven directory cases cover an added directory permission with a consistently
resealed policy/list, restored global directory permission, changed allowed or
denied enumeration results, changed control marker, old host format 6 and old
inner replay format 1.
Seven metadata cases cover an added metadata permission with a consistently
resealed policy/list, globally allowed metadata, forged image-alias evidence,
altered allowed/denied `stat` results, old host format 7 and old inner format 2.
Twelve query cases cover weakened permissions, an extra consistently resealed
execution permission, changed temporary-query declaration, partial policy and
attribute fixture, altered allowed/denied/isolation/output results, changed
temporary marker, old host format 8 and old inner replay format 3.

Ten native-content cases cover missing/added targets, forged values/declarations,
linked evidence, old outer/inner formats and live file/directory/additional-name
mutations on a newly built private fixture. Each native mutation restores
admission and preserves ordinary file bytes.

The [required host receipt boundary](wine-host-required-check.md) uses format 10
and shared `winehostbuild` admission. Qualification work in the producer,
controller and retainer requires the matching receipt beside the executable.
Native and prepared evidence bind the producer/controller host graphs; the full
retainer also retains its own graph. Original format-1/2/3/4/5/6/7/8/9 bundles and their original
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

Format 6 additionally requires `read-closed/receipt.json`, its policy, exact
capability map and complete replay/control graph. `winereadhost` recomputes the
capabilities from captured members, pinned ordinary images and the single derived
control response, including their original recorded paths when admitting copies.
The serialized map cannot grant another file even if the receipt and policy are
resealed consistently. A child applies the policy before LLD exec: captured replay
and unrestricted hidden-object linking must both match the original executable;
captured-object reading must succeed, while four external/SDK reads and restricted
hidden-object linking must reach their exact refusal gates. The temporary symlink
is removed after probing, preserving an ordinary retained evidence tree.
Both the host replay module and policy projector are embedded, pinned and retained.
All child commands, environments, exits, execution records, outputs and extracted
members are mandatory output rows and are checked at admission. Directory/metadata
reads, OS-root/device exceptions, writes, networking, helper startup and OS cache/
loader bytes retain the [standalone qualifier's narrow scope](wine-read-closed-replay.md).
Full library/ABI/search closure and hermetic admission remain unqualified.
Image hashes in this projection reuse the preceding mandatory Mach-O image
admission. The final host input and retained-blob pass still rehashes those bytes;
the new projection independently checks replay UUIDs and the exact permission set
without two additional reads of every large linker image.

Format 7 extends that same replay graph with inner receipt format 2. Directory
data reads require both directory type and an exact ancestor of an admitted
file; the sorted, bounded directory list and policy are recomputed together.
The `winedirclosure` source is embedded, pinned and retained. Enumeration of the
captured input directory must succeed; an unlisted marker directory must refuse
through direct, symlink and Data-volume paths after unrestricted enumeration
succeeds. Its marker and every child command/environment/exit/log are mandatory
output rows. Temporary aliases are removed before the ordinary evidence tree
is admitted. Copies continue to bind the original directory namespace.
Global metadata/name searches and the OS-root/device data exceptions remain
allowed; this does not establish full metadata/search or hermetic admission.

Format 8 extends this graph with inner receipt format 3. `winemetaclosure`
limits `file-read-metadata` to exact file/ancestor paths and bounded metadata-only
aliases of pinned ordinary images, retaining the explicit OS-root/device
exceptions. `winemetaimages` derives image aliases and their symlink targets;
`metadata-aliases.json`, the recomputed metadata list, policy and every new
control record are mandatory outputs and retained input rows. These modules
are embedded, pinned and retained too. Alias projection reuses the preceding
mandatory image-byte admission; the final input/blob pass still checks bytes.
Two captured file/directory `stat` controls succeed. Seven unlisted file,
directory and SDK `stat` controls require unrestricted ordinary types and exact
permission denials through direct, symlink and Data-volume paths. Copied bundles
keep their original namespaces. Other existence/search/metadata operations,
helper startup, OS loader/cache and complete hermetic admission remain open.

Format 9 adds inner receipt format 4 and shared `winequeryhost` evidence.
Existence and xattr queries use the exact admitted file/ancestor/alias set.
Three fixed execution/output paths and a temporary linker-output pattern with
exactly seven lowercase hex characters grant existence only. Three lookalike
temporary names must refuse. Two positive probes, eighteen unlisted query
refusals, three counterfactual/isolation probes and four temporary controls
record raw operation, target, result and error plus exact invocation evidence.
The fixture declaration, partial policies, ordinary temporary marker bytes and
all query records are mandatory. Builds seed and check known native attributes;
admission checks their serialized observations rather than requiring live
attributes to survive copying. Complete xattr content and the remaining
search, loader, bootstrap and hermetic boundaries remain open.

Format 10 adds inner replay format 5 and mandatory `read-closed/xattr-content.json`.
The exact canonical metadata target set is reconstructed independently; every
native attribute name/value returned with `XATTR_SHOWCOMPRESSION` is pinned,
including hidden compression metadata. Both capture and admission use two
matching bounded observations with the shared `winexattr` module. Its source is
embedded, pinned and retained. The host receipt is limited to 8 MiB.
Copies bind native content in the original recorded namespace; native attributes
on copied fixture files are not substituted for those original targets. Missing,
added or changed rows refuse even after resealing output hashes. These are
quiescent observations rather than an atomic snapshot: change-and-restore races,
OS-root/device exceptions and paths outside the metadata set remain unqualified.

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
