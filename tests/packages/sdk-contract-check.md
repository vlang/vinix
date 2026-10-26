# Native package SDK contract qualification

The V controller `sdk-contract-runtime-check.v` reuses the hardware host harness
and four maintained public SDK consumers with one production `vinix-package`
executable. Its single scenario supports AArch64 and x86_64. The fixture
configuration remains `aarch64` on either native target: this checks the public
document/service contract, while the receipt separately records and validates
the architecture of every executed ELF.

The consumers check exact no-config capability discovery and eight refusals;
deployment formats 1/2 and five semantic/catalog refusals; 48 accepted URL
controls, 88 malformed refusals and two missing/corrupt controls; and three
policy reviews, canonical fingerprint equality and eight semantic refusals.
They use the existing public writers and decoders. Their proposals and fixture
trees must remain unchanged. The guest also checks 45 exact early operand
refusals and nine valid-operand controls against missing, corrupt and valid
configuration, with fixture tree comparisons after every outcome.

Each child is waited for and closed. Complete merged output reaches the serial
log; existing public PASS lines, process PASS lines, the native target marker
and clean shutdown are required. The controller additionally requires each
expected serial line exactly once. Repository import sources and the controller
are inventoried and hashed before and after execution. Receipts pin that source
inventory, V/controller executables, input and boot-medium kernel, staged init,
CLI, four consumers, initramfs, boot medium and serial log. Staged executable
hashes must equal build outputs; the copied kernel is rechecked after execution
and the retained medium's kernel must match it. Existing harness boot scripts
and configuration join the source inventory. Imported vlib/thirdparty, headers,
sysroots, linker, firmware and transitive tools are not frozen; this is not a
hermetic build claim.

Build the controller with the standard `tests/hardware-platform` module path,
then run with `--arch aarch64|x86_64`, a committed input `--kernel` and a fresh
`--state-dir`. `--list` lists the scenario without building target programs or
booting a guest. Passing artifacts must be retained; `--failures-only` is refused.

This is read-only SDK/CLI qualification. It grants no publisher authority,
applies no policy/deployment, accesses no network and does not qualify graphical
apps, runtime availability or the complete section 14 release.

## Results

On 2026-10-26, the controller compiled with `-prod -gc none -manualfree` against
source base `cc5ae2262ac91a4ff1e5a6d2391e8500428ef046`; `--list` passed for both
architectures. Independent source review found no remaining actionable issue.
Host evidence is retained at
`/Users/alex/Library/Caches/vinix-codex/section14/sdk-contract-20261026/host/`.
The controller SHA-256 is
`384017b289afeb7dcdd107007a852368815038fa632c9b6325b7bac93538b1a0`;
each architecture's list output hashes to
`76d96489779b88c6910b8ac3dd7a22cc06823d7814b8efe19d0e68ecc998d6e4`.
No target compilation, image staging or guest execution has run. Native
qualification remains pending both guest runs and review of their receipts.
