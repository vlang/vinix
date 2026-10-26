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
The state container must be new and have an existing canonical ordinary parent.
Copied/extracted kernels stay in `state/work`; the harness uses `state/run`.
Failures retain their work. This assumes a trusted namespace without concurrent
replacement of its parents.

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
That initial result covered discovery only.

### Retained state and ARM execution, 2026-10-26

Source base `b61d1175611b2604cdee643c075074bb5e8a2bc9`, with the maintained
controller/state fixture/supervisor changes retained in each bundle's
`qualified-source`, passed the real AArch64 guest scenario in 10.2 seconds.
The controller and supervisor both exited 0. All twelve exact serial markers
occur once, including all four public consumers and the 45 early refusals/nine
valid controls; the guest powered off cleanly. Six built/staged native ELFs
match, and the kernel extracted from the retained boot medium matches its input.

`sdk-contract-state-check.v` exercises normal and production real controllers:
nine exact refusals leave the private tree unchanged, and a malformed-kernel
control retains its exact copy in `work/kernel` before host discovery. A separate
production controller with changed source refuses before writing state.
The first host attempt correctly failed its stale-source control: development
`$embed_file` reloads the file. That attempt remains complete; the corrected
profile uses an independently compiled production control.

The fixed `sdk-contract-supervise.v` profile clears the environment, selects the
qualified wait-width V overlay for V/VEXE and caller markers, uses private
temporary/module directories, and checks selected compiler libraries, thirdparty,
headers, sysroot, tools, firmware, kernel, repository sources and controller
before/after. The full selected ARM input map is unchanged (SHA-256
`d9ecfa2701d378b0aa8b4a3780b4d8102910a531afa3a9404c4844383c5b619a`).
Retained generated C for the bootstrap and all six target programs identifies
only the selected overlay vlib root. This adds input observations beyond the
standalone controller receipt's narrower toolchain statement; it does not claim
a hermetic build, strict target warnings or target `-nocache` execution.

The inherited controller group was observed, reaped and empty; its final wait
returned -1/ECHILD, with no kill needed. The sampled namespace charge was
191,107,072 bytes under a 512 MiB cap, including both host attempts and the
worktree. Admission/floor checks use actual `df` (2 GiB/1 GiB). Sampling is not
a filesystem quota and does not track escaped daemons. Bootstrap execution is
recorded separately and occurred outside the native guard.

Complete quiescent bundles are outside Git. For each directory below, the
adjacent `-seal/inventory.json` has the listed SHA-256 and passes the complete
state checker; do not substitute a partial bundle:

| Bundle under `/Users/alex/.cache/` | Result | Complete inventory SHA-256 |
| --- | --- | --- |
| `vinix-sdk-arm-20261026-02` | Retained failed host control | `655189843a757b982952958679450f8410f8ce9708bd4ffbd701d979ed919d50` |
| `vinix-sdk-arm-20261026-03` | Normal/prod state and stale-source controls pass | `41c95be52135081324b7c74cba29739bcf91fc930d5b6f6da835b5ffa33dd56a` |
| `vinix-sdk-arm-20261026-04` | Native ARM scenario and supervisor pass | `07e2b192ca2cf893520dfa36b09ee1a8a3e2227e152a3bd04e5212c38b68e0b7` |

Selected ARM artifact SHA-256 values (the full receipt is `04/s/qualification.json`):

| Artifact | SHA-256 |
| --- | --- |
| V executable | `ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5` |
| Production controller | `b28d7ca7199a22e7bddf0a20d4a157ec45410c00a75db90fa90150a662dde902` |
| Input/extracted kernel | `66fda62176a422dbcc891e3f10e95d3a15add95b97beceb9c4451ca1775651d9` |
| Boot medium | `409461780f1e1f08628cb031db54b012cc2a889a9f8b66d7c97e792ca8c378c6` |
| Package CLI | `f5e55305364b8a84aa417795c34fcc11dc6200f03527bc105035ed6e49798a72` |
| Serial log | `88d6f11aeadf7d412cd4c91292209d94c452a3dcd234b5b9ab70c4884739578e` |

Native x86_64 execution remains pending. The broader SDK release gate stays open.
