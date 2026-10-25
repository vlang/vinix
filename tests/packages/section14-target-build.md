# Section 14 combined compositor target builds

Qualification date: 2026-10-26. Source base:
`42ebeef03945b5fa88f117bdb3e612e436154af4`, with exactly these five
production changes frozen together:

| Source under `desktop/` | SHA-256 |
| --- | --- |
| `app_selection_migration.v` | `7c8ffb0ef40942687ba482b8b0ca626bfb102224506ac4d3030e213043a52e60` |
| `packagecore/release.c.v` | `fd6de99dd94073e26a636f1f3c29b74626d1c8f63af95e0c6f1c1e02def788cd` |
| `session_hub.v` | `fbb722891c5de21a0f285dcf4fdedadac1f91f85102ce1dcd0b0b2eba4d5f2ec` |
| `software_policy_navigation.v` | `d2ddab4108ec4233e0079dc3a2e52d1b66bc5c83c0ade2eef191fa8adf290acc` |
| `software_snapshot.v` | `0c1283a83eb2e1361ddb62ba59ec57a1042cf233b734b42f375293c86198f805` |

The first bundle combines generic protected release-review routing, compact
unavailable-policy recovery, and the 320×240 Save installed form. It excludes later
repository-list recovery changes and unrelated dirty main-checkout kernel and
compatibility files. A separate six-source run adds repository-list recovery;
the first bundle remains unchanged.

The maintained V runner is `tests/packages/section14-target-build.v`. It reuses
`workflowbuild.stage` and `hosttest` to stage the full production compositor,
generate C with `-new-compiler -nocache -prod -gc none -manualfree`, and compile/link
with Clang `-O2 -static` against each target's musl sysroot. Frozen module lookup
precedes other project paths, including the modified `desktop.packagecore`.

The optional supplementary build stages every production `software_*.v`, the image
controller fixture, Terminal adapter, and shared fail-closed HostedX11App adapter.
Its hosted adapter SHA-256 is
`502d852d447240a982c8bef719415025f6f3a9846020d015fc863886e0904aaa`.
These are compile/link qualifications; fixture assertions and guest workflows were
not executed by this run.

Tools: V `0.5.2 fd996fc`, SHA-256
`ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5`;
Clang 23.1.0, SHA-256
`4e4fd968922cd634ebb6445325703a6276effde7b39337a6a9ff40b3b0c657b8`;
LLD 23.1.0, SHA-256
`745f1b0e8809caef992e6136402561787d951cafe3d0d1736bdc7c03be41e98b`.

The complete external bundle is at
`/Users/alex/Library/Caches/vinix-codex/section14/package-section14-combined-target-20261026/full-compositor`.
It retains the frozen project/UI sources, runner source/binary, actual V/Clang/LLD
executables, literal module/V/Clang commands and diagnostics, generated C, ELFs,
and source/tool/static-runtime/generated-C before/after hashes. Both full compositor
and supplementary image cross-links passed on both architectures. Its
`bundle.sha256` SHA-256 is
`7e98cfb73875518900862033874900fe55aee955872cf970892a2449ddff28de`.

| Five-source target output | SHA-256 |
| --- | --- |
| AArch64 compositor | `21b5a001c234db237eddc9e1823db03c0ea1d884ac347efaa9ebfb7e4daf797c` |
| AArch64 Software image | `74849095e6c568e7a5a5647fcab37f1dbe6a5c17e34c346afef645a67397b7a5` |
| x86-64 compositor | `03d4f2ec49105d86ecfb140722b3030c6f65f36d4b3e2b34e418e5524900711f` |
| x86-64 Software image | `5ab85da80cecdd2b9000afd473887a42e16b70728cc20b644b3f163ba2d73524` |

The separate six-source follow-up retains the same source base and five hashes
above, and adds `desktop/software_repository_navigation.v`, SHA-256
`ee4d66bddea22a513ca1b96f846dfa157f35ea8156b99efe8ca5446db049dbe4`.
Its complete frozen source tree differs from the first bundle only in that file.
Both compositors and both supplementary image cross-links passed again, with
six named production paths checked before and after. The complete bundle is at
`/Users/alex/Library/Caches/vinix-codex/section14/package-section14-combined-target-20261026/full-compositor-plus-repository`.
Its `bundle.sha256` SHA-256 is
`7742fb411cbf604613987331efd97ba33f60c34d7dafa83618b0fadf769d36e3`.

| Six-source target output | SHA-256 |
| --- | --- |
| AArch64 compositor | `2b7500de5eebd06e83d02fa73838503de6552a9eceba953dcb4c4ddab8295e0e` |
| AArch64 Software image | `659a1ed46a44db7e2d6352e018c2e6f1723a76ce45fad5cf7d01d7831df5d779` |
| x86-64 compositor | `259613b8f95ddde359a70f338baeca27bd96f0ae2b56391f6d6c3cc35de67a83` |
| x86-64 Software image | `2546514b294113794451e84fbe91c6c1729778499ae30667658c299128f2c631` |

The checker requires the complete bundle, verifies all manifest files and required
artifacts, compares before/after receipts, requires the exact named production
paths for the recorded five- or six-source scope, and checks ELF64 ET_EXEC architecture,
bounded program headers, PT_LOAD, and absence of PT_INTERP. Successful `-static`
link commands provide the static-link evidence. This does not establish complete
ELF structural correctness or guest behavior. V's full standard-library tree,
sysroot headers, compiler configuration files, and transitive toolchain libraries
were not fully frozen; this is not a hermetic-input qualification.

The checker rejected the five-source bundle with a withheld command log, then
passed again after the original file was restored. The logs remain outside the
sealed bundle at `checker-missing.log` and `checker-restored.log` in its parent
directory. The immutable first bundle predates `production-scope.txt`; its
five-source receipt remains supported by the maintained checker.

New builds select `--scope=release-save-policy` (five sources) or
`--scope=release-save-policy-repository` (six sources), and write the explicit
scope receipt. Both modes stage the complete compositor sources; the scope names
the changed production paths whose original and frozen bytes must match before
and after the run.

To validate the retained bundle using the maintained checker:

```sh
v -backend c -path '@vlib|.|desktop/tools|@vmodules' run tests/packages/section14-target-build.v --check=/Users/alex/Library/Caches/vinix-codex/section14/package-section14-combined-target-20261026/full-compositor
v -backend c -path '@vlib|.|desktop/tools|@vmodules' run tests/packages/section14-target-build.v --check=/Users/alex/Library/Caches/vinix-codex/section14/package-section14-combined-target-20261026/full-compositor-plus-repository
```

## Hosted Launch options target builds

The separate 2026-10-26 hosted-options qualification uses source base
`3770607e67052a3e179d8c27a19b1668993a440e`, the same six production hashes
above, and these five additional frozen production paths:

| Source | SHA-256 |
| --- | --- |
| `desktop/software_app.v` | `fbe37cc132d224b00d44c183ff76958ca0fb8100ce7cb63f8b12bd50162b4695` |
| `desktop/software_launch.v` | `11db058fe944789a19df91f2c8a3cb0b31a84d6bd5955913922a524d064e5719` |
| `desktop/software_hosted.v` | `8e366c7f1a1706e736b3982e8bb842d5cde02edec77f49959f9ffbf0ace6938d` |
| `build-support/xorg-server/winehost/core.v` | `bc31ff0dcb2746bf81e54c9e44e900cb0e33dbaa7037392b72277fa44d3ccedf` |
| `build-support/xorg-server/winehost/package.v` | `7ce47e4cacad1fc1acbcd7a91dc2bd25b5fd127407307785f5996a923bdcccb3` |

Its explicit scope is
`release-save-policy-repository-hosted-launch-options`: eleven named original
production paths must match their frozen source copies before and after building.
This scope requires the Software image fixtures and actual authenticated X11
bridge in addition to the complete compositor on both architectures. The bridge
freezes `winehost` and `x11auth`, generates C with the maintained raw-module recipe,
and links against the architecture's X11 musl sysroot. Its generated C contains
the new `package_command_allowed` call and parser. The compositor and image use
the static recipe described above; the bridge uses `-static-libgcc` and dynamic
musl linking with `-O2 -Wall -Wextra -Werror`.

The new scope inventories hidden entries, rejects bundle symlinks, and retains
bridge generated-C before/after receipts, a linker trace and map, plus hashes and
alias targets before and after for the X11 sysroot `lib`, `usr/lib`, and selected
GCC runtime directory. The checker requires static ET_EXEC compositor/image
outputs and ET_DYN bridge outputs with exactly the architecture's
`/lib/ld-musl-ARCH.so.1` interpreter, bounded segments, and PT_LOAD. Historical
five- and six-source bundle admission keeps its original inventory semantics;
both original seals passed again with the extended checker.

The complete external hosted-options bundle is at
`/Users/alex/Library/Caches/vinix-codex/section14/package-section14-hosted-options-target-20261026/full-compositor-hosted-options-v2`.
All six cross-links and the complete bundle checker passed. Its `bundle.sha256`
SHA-256 is
`c5b72beb336e451695c58094d8f77ed850014ee180fe609bf5d05582b267834d`.

| Eleven-source target output | SHA-256 |
| --- | --- |
| AArch64 compositor | `cb23ee2f37ecdde3703dfb6c0d4a2e02526499d0942685bacc0cf4c256d75d68` |
| AArch64 Software image | `81b551a3161fd5e11fa9efaa6e2f619beb3f2f76747434bb7632ed52c830b15b` |
| AArch64 X11 bridge | `7f3f29c0b40ff3a7d841386f7833a94f7d4cdfec4a5b98f1c7e5dd9e50fcc019` |
| x86-64 compositor | `60a2a6619403dd551f969445f3548d6fadd6f785303315377fb2043ca0d2b4a0` |
| x86-64 Software image | `1753a7906cb342c6bf2fb2ea1edede8562dc1ace1c7308696ce73b11d321606c` |
| x86-64 X11 bridge | `5d63f0d9fdc31b74b92f2658e5244320e46090c4ee344dcc9d2b183215e87c7e` |

The V, Clang and LLD executable hashes are the same as above. The bundle preserves
their executable copies, literal commands, diagnostics, frozen project/UI/ABI and
bridge sources, generated C, and ELFs. Runtime receipts hash the enumerated files;
they do not freeze the entire sysroot, headers, V library tree or transitive host
toolchain inputs. This qualification covers compilation and linking only; it does
not execute the fixture assertions, hosted application, or guest workflow.

```sh
v -backend c -path '@vlib|.|desktop/tools|@vmodules' run tests/packages/section14-target-build.v --check=/Users/alex/Library/Caches/vinix-codex/section14/package-section14-hosted-options-target-20261026/full-compositor-hosted-options-v2
```

The maintained `section14-target-build-controls.v` exercised seven resealed
negative controls on a complete disposable copy. It restored the original bytes
and manifest and passed a full check after every control. The original bundle
also passed before and after, retaining the same seal. All controls exited 1:

| Mutation | Refusal |
| --- | --- |
| AArch64 bridge ET_EXEC | `unexpected ELF64 executable architecture` |
| AArch64 wrong PT_INTERP bytes | `unexpected ELF interpreter` |
| AArch64 duplicate PT_INTERP | `missing or duplicate ELF interpreter` |
| Hidden source addition | `input count changed` |
| Hidden source removal | `input count changed` |
| Bundle file symlink | `unexpected bundle symlink` |
| Missing x86-64 bridge | `missing hosted bridge artifact: bridge/bridge` |

The external control directory is `negative-controls` beside the hosted-options
bundle. It retains the complete restored copy, helper source/executable, literal
checker commands, diagnostics, mutated manifests and ELF samples. Its exact
refusal receipt is `controls.json`, SHA-256
`77e87e02401bcd658ab06eba9477137d3207973751b6b23cc0532bb4a2f450a8`.
The receipt also binds the checker executable, helper source and mutated
manifest hashes. These controls leave the original five- and six-source bundles
and their admission unchanged.
