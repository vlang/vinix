# Required Wine qualification host receipts

The producer, native controller and full retainer now admit format-12 host-build
receipts before qualification work. Build each with `wine-host-build.v`; launch
its `program` in the original build directory. A bare or relocated executable,
linked receipt, wrong role or unsupported format refuses before creating
qualification output. Existing non-production and embedded-source guards still
run; the controller's read-only owned-build preflight requires a host receipt.
Usage-only controller/retainer requests can still return their usage messages.

Shared `winehostbuild` admission checks the selected V/C/input/image contract,
requires the exact canonical running executable and original receipt namespace,
and checks its role and executable hash. The producer and controller must also
use the compiler bound by their host receipts for guest source generation.
The original bootstrap builder remains a separately pinned input.

Format 12 retains captured Mach-O link/replay/load evidence for the
actual running executable. Every archive member, replay artifact and receipt
belongs to the host output graph; the selected linker and observed ordinary
host images belong to its input graph and byte store. Missing rows cannot be
waived by the producer, controller or full retainer. Original format-2/3/4/5/6/7/8/9/10/11 checkers
and their complete historical bundles retain their earlier contract.

It also requires `sdk-graph.json`, recomputed SDK stub identities and declared
reexport coverage. Both alias and resolved source paths/hashes must appear in
the host input map and retained byte store. The SDK projector source is embedded
and pinned with the other admission modules. Every qualification role rechecks
the graph before work, and both producer/controller graphs are rechecked after
the guest. Full SDK/TAPI/ABI/search and loader admission remain separate gates.

It additionally requires an installed CLT SDK read-denied replay and its four
runtime denial controls in `sdk-denied/`. Captured output must match the running
executable; the installed-SDK baseline must also match before its restricted
counterpart fails. The graph's exact policy, commands, environments, exits,
observed loads/images and retained bytes are checked at every shared admission.
The restriction implementation is embedded and pinned with the host builder.
This covers installed SDK reads during LLD replay; other filesystem/network
access, bootstrap and OS loader/cache bytes remain unqualified.

It also requires ordinary file-data capability replay in `read-closed/`. Shared
admission reconstructs the exact literal permissions from captured members,
pinned ordinary images and one derived control response; an added permission
refuses even after resealing the policy and capability map. Both successful
links must reproduce the running executable. One allowed read, four denied reads
and a denied external-object link must reach their named gates. Policy/module
sources, all replay/control artifacts and execution records join the mandatory
graphs and byte stores. Inner receipt format 2 additionally requires exact
ancestor-directory permissions, reconstructed from the same admitted files.
Captured-directory enumeration succeeds; direct, symlink and Data-volume reads
of an unlisted directory must reach exact permission-denial gates. Its marker,
policy, directory list and all child records are mandatory and independently
checked. Inner format 3 additionally requires exact metadata permissions,
`metadata-aliases.json` with bounded aliases resolving to pinned ordinary images,
two allowed `stat` controls and seven permission-denied `stat` controls.
The metadata list, policy, alias graph and all child records are recomputed and
checked, including in unchanged copies. Inner format 4 adds exact existence and
xattr query permissions, three fixed existence-only execution paths and an
anchored temporary-output pattern with seven lowercase hexadecimal characters.
`query.json`, three partial policies, the attribute fixture declaration, four
temporary controls and 27 query child records are mandatory. Native builds seed
and check known xattrs; admission validates serialized observations and ordinary
fixture bytes, allowing unchanged copies whose filesystem drops native xattrs.
Inner format 5 additionally requires `xattr-content.json`, with all native
attribute names/values on the independently derived canonical metadata set.
`XATTR_SHOWCOMPRESSION` includes compression metadata hidden by default APIs.
The embedded/pinned shared reader bounds native reads, holds descriptors and
requires two matching complete observations. Admission compares the canonical
receipt to live original-namespace attributes; unchanged copied graphs still
require those original targets. A copy's native attributes cannot replace them.
These quiescent observations do not establish an atomic filesystem snapshot.
Inner format 6 additionally requires `link-xattr-content.json`. The independently
validated alias graph determines every canonical-parent symlink node and literal
body. Its names/values are read through held link descriptors without following
final targets. The shared reader/projection sources are embedded, pinned and
retained. Admission requires the canonical receipt and original namespace;
copies cannot substitute their own nodes. The host receipt has an 8 MiB bound.
Inner format 7 additionally requires `directory-content.json`, recomputed from
the independent directory capability projection using the pinned shared native
reader. Immediate names are captured only after all host output names exist,
including reserved proof/receipt names. All observed ancestor names must remain
stable; subsequent output belongs in a preexisting sibling namespace. No name
exceptions or added permissions are granted. Copied graphs still require the
original directory namespace. Quiescent observations do not establish complete
search/absence closure.
Remaining xattr coverage, other search/metadata operations, OS-root/device exceptions, writes/network,
helper startup and OS loader/cache bytes retain their previous scope.
Full ABI/library/search closure remains open.

Prepared builds contain `host-producer.json`; native runs contain
`host-controller.json`. Each binds the host receipt hash, directory, compiler,
source and executable. Their input maps include every admitted original host
input, retained input blob, output and receipt. Producer admission and native
post-guest checks re-admit these records. The full retainer independently checks
both graphs and their input-map coverage, requires the binding records in the
producer/native output pins, and adds its own admitted host graph to retained
artifacts. Copied graphs keep the original host namespaces and ordinary binding
records. Source pins for shared host admission and its CLI are embedded too.

`wine-host-required-check.v CONTROLLER PRODUCER RETAINER FRESH_OUTPUT [PREPARED]` checks
fifteen exact startup refusals across all three roles: missing, linked, moved,
wrong-role and unsupported-format receipts. Every case must refuse at its
named gate before creating the requested output.
With the prepared build supplied, three further cases link its producer binding,
alter its receipt hash or omit a host artifact input. The real controller must
refuse each before signing/build output; an empty requested directory is allowed.
Producer host admission runs before signing and is repeated after the guest.

The full owned-retention runner now requires sixty-nine refusals after real and
unchanged copied baselines. Five host-binding cases change producer/controller
binding hashes, omit host receipt rows from their input maps or link the native
binding record. All mutation writes target private copies. Existing 44 cases
retain their named gates and the original complete input requirements.
Two additional cases omit the producer's host-link receipt or the controller's
host-link archive from retained input maps. `wine-owned-retain-check.v` accepts
`--host-link-only` after its normal arguments to run those two cases with both
baselines, allowing an incremental check alongside a completed original matrix.
Two further cases omit the SDK graph from producer/controller input maps;
`--host-sdk-only` runs these with both baselines.
Two more omit `sdk-denied/receipt.json` from producer/controller retained input
maps; `--host-sdk-denied-only` runs these with both baselines.
Two more omit `read-closed/receipt.json` from those maps; `--host-read-only`
retains both baselines while selecting this pair.
Two further cases omit `read-closed/policy.sb` from producer/controller maps,
requiring the directory policy to remain in both retained host graphs.
Two further cases omit `read-closed/metadata-aliases.json` from those maps.
Two further cases omit `read-closed/query.json` from those maps.
Two further cases omit `read-closed/xattr-content.json` from those maps.
Two further cases omit `read-closed/link-xattr-content.json` from those maps.
Two further cases omit `read-closed/directory-content.json` from those maps.
Alternatively `--partition=0/4` through `--partition=3/4` divide all 69 cases
without weakening either baseline. Use a separate output directory for each;
`wine-retention-partitions-check.v PREFIX` verifies their exact assigned case
lists, both baselines and complete unique coverage from `PREFIX0` through `PREFIX3`.

This makes selected host build evidence mandatory in qualification tooling. It
does not activate owned runtime defaults or qualify the bootstrap builder,
complete compiler/SDK content, unreported inputs/search absence, Mach-O linker/
library closure or OS loader/shared-cache bytes. Historical bundles and their
original verifiers remain required. Owned ARM/GUI, redistribution and broader
roadmap 14 acceptance remain open.

The historical format-2 checkpoint is `/Users/alex/.cache/vwhostrequired-20261115-01`, with final
isolated source in `source-final` from base `a58e30385`. Final controller,
producer and retainer host builds pass. `prepared-02` and independent producer
admission pass; `native-02` passes signed x86 holder-death/collection in 104.796
seconds with both host bindings re-admitted afterward. All 32 receipt controls,
18 startup/pre-sign controls and 49 full-retainer refusals pass, including real
and unchanged copied retention baselines. Final observer is
`host-retainer-final-02/program`, with matrix results in `retention-controls-02`.
The earlier run and the failed diagnostic-order matrix remain preserved. Moving
controller coverage checks after guest header/C checks restores the original
header refusal without skipping host admission. No guest rerun was needed for
that observer-only change; the signed input maps do not contain retainer source.
