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

### Retained x86 attempts, 2026-10-26

At source base `7594b84b387b46bed02df0b84cc35e813b82aecd`, with retained
`qualified-source`, the x86 `01` guest and controller passed the same native
contract scenario in 124.3 seconds. The supervisor then exited 1: its full-state
C scan treated two staged upstream Limine C source files as V-generated output.
Its input maps matched, all seven emitted V C files identified the qualified
vlib, and the controller group exited 0 and was reaped/empty (-1/ECHILD, no kill).
This is a retained supervisor refusal, not a passing complete qualification.
The complete `vinix-sdk-x86-20261026-01` bundle remains outside Git under
`/Users/alex/.cache/`; its adjacent `-seal/inventory.json` SHA-256 is
`8f163b47854ebbe165fe9cfccfe2b42e1104392a17c9ccf0ba40ce6100fdc3cb`.
The broader SDK release gate stays open.

The second x86 attempt was interrupted before program generation completed.
On continuation no supervisor/controller/QEMU process remained, and the bundle
had no serial guest log, qualification, final cleanup, after-map or budget receipt.
The terminating signal and exit status are unknown; this provides no passing
execution or cleanup result. Its complete interrupted namespace is retained at
`/Users/alex/.cache/vinix-sdk-x86-20261026-02`, with adjacent complete inventory
SHA-256 `c00c094000bbb597df6ef0b1c5ffd422f7ffb7e42baa45117811275bc1bef39f`.
An independent full-state check passed without altering that namespace.

### Native x86 execution, 2026-10-26

The shared supervisor now has a fixed `--x86` profile for
`/Users/alex/.cache/vinix-sdk-x86-20261026-03`, reusing the sealed ARM `03` production
controller. The retained ARM source and all sealed bundles remain unchanged.
Its kernel is the existing audio baseline kernel (SHA-256
`348b1204b78afe70f847b1cb5ebb1dd06dfac17add8dab672bb781baf5b6f78e`).
The selected C toolchain is `/opt/homebrew/Cellar/musl-cross/0.9.11`, including
its baked x86 musl sysroot, and the boot profile selects the existing x86 QEMU,
firmware, xorriso and complete cached Limine 12.9.3 tree. Fixed executable,
libc and cache hashes join complete selected before/after input maps. Host
shared libraries and system frameworks remain outside this observation.
The toolchain's three fixed target-loader links are recorded with their exact
`/lib/libc.so` literal target and required absence on the host; inventory does
not follow them into the host root. Other missing inputs remain refusals.

This profile requires the qualified V root's exact five top-level entries and
its complete overlay map and records both full input maps. It inventories the
V output directories `bootstrap-tmp` and `s/run/guest`, requiring one retained
supervisor C file and precisely the six expected target C files, each identifying
the selected vlib root. Cached bootloader C sources are outside these V output
directories.
The 768 MiB sampled charge includes ARM attempts `01`–`04` and their seals,
the SDK evidence directory/worktree, retained x86 `01`/`02` and seals, and fresh
`03`/seal. It keeps the 4 MiB receipt reserve, actual 2 GiB/1 GiB disk
admission/floor and 1,000 second controller guard.

At source base `7594b84b387b46bed02df0b84cc35e813b82aecd`, with retained
qualified supervisor source SHA-256
`7d7f86b887273747d25aae4b604b0c7db4e6809f3e977ebe4c8f3ff0de2038e5`
and supervisor executable SHA-256
`e3661b0ca135375a9a59e9b6ed7113b1947ee72f8124b2870829f3f01ce9fea5`,
the third attempt passed the native x86 scenario in 246.0 seconds. The controller
and supervisor both exited 0. All twelve exact serial markers occur once, six
built/staged native ELFs match, and the guest powered off cleanly. The retained
boot medium's extracted kernel matches the input.

Both complete input maps have SHA-256
`502cef3ea6a735feda2dad03a55a2fd9f90976d6d1a4f44b0347ed06d9d019dc`;
the after receipt reports no changed input. All seven emitted V C files identify
the qualified vlib. The inherited controller group was observed, reaped and
empty; final wait returned -1/ECHILD, with actual child exit 0 and no kill needed.
The final sample before its budget receipt was 542,724,096 bytes under the
805,306,368-byte cap, with 41,620,389,888 bytes actually available. Bootstrap ran
separately, outside the native guard. The sampled guard has the same escaped
daemon and filesystem quota limits described for ARM.

The complete quiescent `vinix-sdk-x86-20261026-03` bundle remains outside Git.
Its complete inventory is
`/Users/alex/.cache/vinix-sdk-x86-20261026-03-seal-02/inventory.json`, SHA-256
`ef08167c01d87ed06796b0a897cd7109ccaf57ddd56898d2b1a917ac4263adff`.
The first seal hit its 120-second bound during its final comparison; that
incomplete `-03-seal` directory remains intact. Its inventory passed a separate
complete check, and a fresh seal completed with the unchanged checker under a
240-second bound. Both inventories are identical. An independent complete check
of the final seal passed with the original unchanged checker (actual exit 0).
Post-seal `du` charged all
extant historical roots and both seal directories at 530,900 KiB before writing
its receipt, still below 768 MiB including the 4 MiB receipt reserve. That receipt
is retained at
`/Users/alex/Library/Caches/vinix-codex/section14/sdk-contract-20261026/host/x86-03-postseal-du.txt`.

Selected x86 artifact SHA-256 values (the full receipt is
`/Users/alex/.cache/vinix-sdk-x86-20261026-03/s/qualification.json`):

| Artifact | SHA-256 |
| --- | --- |
| Qualification receipt | `70fe579048b4b90d9f77a93e4fb04af034d642bf355129465a57501f2b1f5d6f` |
| V executable | `ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5` |
| Production controller | `b28d7ca7199a22e7bddf0a20d4a157ec45410c00a75db90fa90150a662dde902` |
| Input/extracted kernel | `348b1204b78afe70f847b1cb5ebb1dd06dfac17add8dab672bb781baf5b6f78e` |
| Boot medium | `c710b23b3a4a6b1028bc03a73373a6d0a3ac6f341bbab090dfdb15f2732c9516` |
| Package CLI | `dc15d93f94367189eed6b172eafa3322f3c7f024bdc52c8b6c4bf7f67edbec5e` |
| Serial log | `50389bd6ac21b83b37e05ba73a79ff1595e8e172f5559aefed05d04f78cc3c69` |
