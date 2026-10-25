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
