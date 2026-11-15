# Wine bridge Clang resource headers

The bridge producer queries its pinned Clang with `-print-resource-dir`,
requires one canonical absolute response, and passes that exact selection as
`-resource-dir=...` in the actual C compile/link command. Before compilation,
it captures the complete ordinary `include` tree, including empty directories,
in `clang-headers.json`, and puts every file hash in the producer input map.
After compilation it independently walks the tree again and requires identical
directory names, file names and bytes. Linked/special entries, empty trees and
oversized trees/files refuse. The shared helper's source is embedded and pinned.

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
nine cases, it requires fourteen refusals with no retained output, after real
and unchanged copied baselines pass.

This closes selected Clang resource-header coverage for **bridge production**
under the existing stable local-input contract.
It does not discover every actual C dependency, freeze compiler dynamic
libraries, admit native guest/controller resource headers, or establish a
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
