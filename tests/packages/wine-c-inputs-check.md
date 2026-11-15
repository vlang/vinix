# Observed C inputs for Wine builds

The bridge, native guest and package C builds now run a discovery command with
`-H -fsyntax-only` before the actual `-H` compilation. Discovery preserves the
target, sysroot, GCC/resource selection, optimization, definitions and source
arguments from the real command; only the syntax-only flag and removal of the
link/output tail differ. The retainer continues checking the entire actual C
command exactly.

`c-inputs-before.json` captures both translation units and every ordered include
observation, preserving repetitions and paths containing spaces. Each file
records its observed spelling, resolved ordinary target and SHA-256. This also
captures non-header files the selected Clang reports, such as SDK metadata.
Relative/control-byte paths, empty traces, nonregular targets and linked or
oversized evidence records refuse.

The real compilation must report the same observations, targets and hashes;
only then is `c-inputs-verified.json` written. The producer and native controller
recheck the proof before their final receipts. Native checks also run before
boot and after the guest. Independent producer admission and full retention
require both receipts, discovery output/argv, the real compile trace and matching
commands. Observed C input paths join the retained byte-bearing artifact map.
The helper source is embedded and pinned by producers and the retainer.

`wine-c-inputs-snapshot BUILD_DIRECTORY LOG_DIRECTORY FRESH_OUTPUT` admits the
proof before and after copying every observed resolved target, preserving its
bytes and mode in a content-addressed file store. Its manifest records observed
spellings and resolved targets; the original namespaces and complete dependency
bundles remain independently required. It does not reconstruct alias chains or
claim a self-contained toolchain. Build the snapshot tool with `-prod` and the
repository on V's module path.

These receipts supplement the existing parsed V source capture, complete
selected resource-header trees, sysroot/GCC inventories, generated output,
private runtime/layout, PE, signature/launch and ISO checks. Historical bundles
still require their original complete inputs and original verifiers.

The module controls build a real two-unit C fixture with an absolute header
outside manual seed directories, including a space in its name. They verify
matching real/discovery traces, changed header bytes, a changed resolved target
with identical bytes, omitted observations, omitted receipt entries, linked
receipts and malformed trace input. Run with the repository on V's module path
and Clang available:

```text
v -prod -gc none -manualfree -path '@vlib|REPOSITORY|@vmodules' test tests/packages/winecsource
```

The full owned retainer controls require twenty-nine refusals after real and
unchanged copied baselines pass. Five new resealed cases remove a bridge compile
observation, omit a bridge receipt entry, change a guest input hash, change a
package discovery command and link a guest receipt. Each must fail at its named
check without retained output. Native evidence readers' ordinary-file records
remain ordinary in copied graphs, and mutations detach before writing.

This admits **observed C file inputs** under the existing stable local-input
contract. Include-search absence, inputs not reported by Clang, linker inputs,
compiler/dynamic-library closure and host controller builds are not fully
admitted by this C-input check; the additional
[linker archive/replay check](wine-link-inputs-check.md) now covers selected
static linker files and identical replay. This is not a hermetic build. Default activation, owned ARM/GUI,
redistribution and broader roadmap 14 acceptance remain open.

The x86 checkpoint is `/Users/alex/.cache/vwcclosure-20261115-01`, from
isolated source base `47460a42f`. Fresh PE/runtime production, independent
producer admission and all 32 owned-receipt controls pass. `native-01` passes
signed holder-death/collection in 146.666 seconds with post-run C input checks.
The real and unchanged copied graphs pass full retention. All twenty-nine
resealed mutations refuse at their named checks without retained output.
All three observed target-byte/mode snapshots pass. Production/manual-free
module controls pass after correcting an initial fixture assertion that omitted
Clang's additional SDK metadata observations. The initial assertion failure and
control-runner compile refusal remain recorded failures. Original distribution,
notices, toolchain and qualified kernel bundles remain independently required.
