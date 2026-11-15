# Wine Clang resource headers

The bridge producer queries its pinned Clang with `-print-resource-dir`,
requires one canonical absolute response, and passes that exact selection as
`-resource-dir=...` in the actual C compile/link command. Before compilation,
it captures the complete ordinary `include` tree, including empty directories,
in `clang-headers.json`, and puts every file hash in the producer input map.
After compilation it independently walks the tree again and requires identical
directory names, file names and bytes. Linked/special entries, empty trees and
oversized trees/files refuse. The shared helper's source is embedded and pinned.

The native controller applies the same rules separately to its guest and
package C builds. Each `build-guest` / `build-package` directory contains its
own snapshot, resource discovery log/argv and explicit C selection. Header
hashes join the native input map before either actual build. The controller
re-enumerates both trees after compilation, before boot and after the guest
run. Header receipts and discovery records join the before-boot output map.

The producer checker and full retainer independently admit the snapshot,
discovery command/output, exact compile selection and input-map coverage.
The retainer also preserves its existing exact C argv and output bindings.
Recorded discovery and header receipts are required output artifacts. Copied
evidence preserves the original resource namespace; it cannot substitute a
different installation by editing an output receipt.

Run the module controls with the repository on V's module path:

```text
v -prod -gc none -manualfree -path '@vlib|REPOSITORY|@vmodules' test tests/packages/wineheaders
```

These controls cover unchanged snapshots, absent/changed input pins,
added/changed/removed headers, added empty directories, linked headers and
directories, ambiguous discovery output, mismatched/missing/duplicated compile
selection, changed compiler/discovery arguments and a linked snapshot receipt.
The full `wine-owned-retain-check.v` additionally requires five resealed
resource refusals: omitted manifest entry, omitted input pin, changed discovery
output, substituted compile flag and linked snapshot. Together with the prior
nine cases, those bridge controls require fourteen refusals. Ten more controls
exercise guest/package snapshots, input coverage, discovery output, C flags
and linked receipts. All twenty-four cases must refuse with no retained output,
after real and unchanged copied baselines pass. Native receipts checked as
ordinary files are copied as ordinary files in the unchanged copied baseline.

This closes selected Clang resource-header coverage for **bridge and native
guest/package production**
under the existing stable local-input contract.
It does not discover every actual C dependency, freeze compiler dynamic
libraries, admit host controller C resource headers, or establish a
hermetic toolchain. Existing sysroot/GCC/V source inventories remain required.
Historical checkpoints retain their original complete inputs and verifiers;
this change does not retroactively qualify them. Default activation, owned
ARM/GUI and broader roadmap 14 acceptance remain open.

The x86 checkpoint is `/Users/alex/.cache/vwheaders-20261115-01`, with
isolated source base `0481bafc4`. Fresh `pe-01` and `prepared-01` pass, as does
the independent producer checker. `native-02` passes signed holder-death and
collection in 140.651 seconds. `native-01` remains a failed guest link attempt
with a different compiler selected by the harness; the successful rerun sets
`V` to the same retained compiler used by the runtime producer. The initial
PE invocation's argument refusal is also preserved. The checkpoint includes
the selected resource-header bytes, independently compared with the original
directory. `controls-01` accepts the real and unchanged copied evidence graphs
and refuses all fourteen resealed mutations at their named checks without
creating retained output. The production/manual-free module controls also pass.
The selected original distribution, notices, compiler/toolchain
and qualified kernel remain independently required.

The native guest/package continuation is
`/Users/alex/.cache/vwnativeheaders-20261115-01`, from isolated base `d46c1d336`.
Fresh PE and owned runtime production and independent producer admission pass.
The signed holder-death/collection run `native-01` passes in 121.070 seconds,
including post-run verification of both native header trees. Production/manual-free
header controls and all 32 owned-receipt mutations pass. Source helper bytes
match the tested feature; selected header bytes are copied and independently
compared with the original resource tree. `controls-01` accepts the real and
unchanged copied evidence graphs, then refuses all twenty-four resealed
mutations at their named checks without retained output. The original distribution, notices,
compiler/toolchain and qualified kernel bundles remain separate prerequisites.
