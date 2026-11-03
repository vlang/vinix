# Framework boot visibility SDK and native pair

The complete two-method SDK and a freshly coupled native library passed host
production and independent full readback. Core `992b426c3`, source qualification
`a8ceeefc0` and SDK producer `a16baf6c3` expose the framework API JAR
through ART's boot path while retaining system resource discovery. The
[source contract](framework-boot-source.md) records the platform-parent,
resource-only APK, ATLPaths and absolute JNI-load requirements. This host result
does not establish ART execution, GMS stability, Maps, authentication or imagery.

Paths use `S=/Users/alex/.local/state/vinix/android`. The SDK at
`S/combined-account-webview-framework-boot-framework-2026-11-03-r1` retains all
2,117 classes. Exactly Resources.getSystem and ATLLoadedApp.loadFromPath change
their loader source; all other 2,115 canonical classes, fields, methods and JNI
declarations remain intact. API-28 assembly/reassembly, complete class/JAR scope
checks and final input rechecks passed. The exact WebView predecessor remains
required at manifest
`c79d421bd385777aefd00b0be85a287af7907b1bb6dd55244d7546eb99ea958a`.

| SDK artifact | SHA-256 |
| --- | --- |
| SDK manifest | `af23c13d90f557c4f7f208ae75c39ad8bcf0efd86fc88fddfe399fe2e66a4e91` |
| SDK build receipt | `031a22b17d85b79adee0ca93776ead247fee47fa6f3b3d48376242969c7baee4` |
| Framework JAR | `d9633112327093e55d924ad658088f8dd3d0b712d5184bddcf7307bfc51bf974` |
| Framework DEX | `c59bc24f43fcd5c40a18b118872186795127fbe309cd1a523823f01136f6f30b` |

The SDK producer passed its first compile, self-test and production attempts.
Independent artifact review matched the focused proof's canonical class pair,
all preserved classes, the original predecessor, exact raw loader edits, the
JAR DEX stream and frozen/live input identities. Its note remains at
`S/framework-boot-framework-production-2026-11-03-r1/validation.md`, SHA-256
`a2df13165d5f6dd23a987f49b1ff5022cf95dfe3c2db38a15740fadfd20f0505`.

The first fresh native build at
`S/current-native-build-2026-11-03-framework-boot-r1` passed unchanged limits.
Its qualified Resource-lock r2 bootstrap and unchanged native producer retain
the original r5 build inputs, compiler-library provenance and strict AArch64
shared-link policy. Both SDK/native receipts record source revision
`a16baf6c3a361f3c27cc3368b8be2f795dedc222`. The original WebView native r2 remains
required at manifest
`1434754497efa741ddb2b378cbb693862ee96eb04cb304d9cbeeae5cc98b4dc0`.

| Native artifact | SHA-256 |
| --- | --- |
| Native manifest | `0a6d8126bd0842985123578550fc3fa60c0eb12543e8fcf680d1644f6b49f81f` |
| Native build receipt | `33608b8877f74c4d35b354d66b43a0401d219c712bbf9fa8a1e2282678afbbae` |
| Native DSO | `f3dafa843033f7fb5245cde6007e66eb603ae0fb747fdc1824a33f731ca7088d` |
| Generated C | `8321888455233a0a01c657182b79320733fc4ef8f02f4b65f236f122d7bcfff3` |
| Consumed C/header inventory | `df1b7598fdb9fe687f8db41b04c9a0e887b655e9dd3a38af4814e7977e953a3c` |
| Native production guard | `fad1888f69213a30bbfdd72c65a2aa87c7b6dcb94245decf779b776f0cf23c8d` |

The independent [V readback checker](framework-boot-native-readback.v) loads
and fully rehashes both SDKs and native bundles, applies strict receipt and ELF
checks, then repeats all four inventories before writing its result. It verifies
91 native source origins and 92 inputs with exactly the two committed
bootstrap/runtime source changes. Generated JNI, binding declarations and all
721 exports remain byte-identical. All 70 native-consumed raw class copies equal
the new SDK: Resources and ATLLoadedApp change semantically; WebView has only
the pinned source-to-canonical formatting pair. Canonical consumed differences
are exactly the two resource-loader classes. An independent whole-method oracle
checks each exact loader replacement, preserves quoted strings and control-flow
labels, and compares every other byte of both changed canonical classes.

The whole generated C file is byte-identical after isolating only ws_bootstrap,
ws_load_jni and the new ws_boot_classpath definition/prototype. The parser ignores
quoted and commented braces; the complete JNI function must equal its exact two
reviewed substitutions. Full function hashes are retained in the result. All 58
consumed C/header inputs are checked after exactly five owned-path rebases; only
the generated C value changes, with the other 57 values fixed. The restored
compiler-root inputs and complete 340-entry generator closure remain equal.
The builder closure is exactly 659 to 660: one framework registration change and
one new provider, with no other additions, changes or removals. Native compiler
arguments differ only by their owned output root. ELF dependencies, SONAME,
interpreter and search paths remain equal.

| Successful phase | Guard seconds | Sampled RSS bytes | Detailed RSS bytes | Shared growth bytes |
| --- | ---: | ---: | ---: | ---: |
| SDK producer compile | 1.818 | 414,416,896 | 436,469,760 | 3,010,560 |
| SDK producer self-tests | 0.514 | 9,043,968 | 14,614,528 | 102,400 |
| Full SDK production | 48.257 | 500,318,208 | 483,966,976 | 379,707,392 |
| Fresh native production | 22.134 | 561,725,440 | 380,846,080 | 103,034,880 |
| Readback checker compile r2 | 2.429 | 338,477,056 | 287,178,752 | 1,691,648 |
| C/SDK scope self-tests | 0.215 | 1,294,336 | 13,860,864 | 81,920 |
| Complete readback r2 | 3.163 | 48,447,488 | 62,980,096 | 28,672 |

Successful guards/children exited zero, reasons are empty, cleanup is complete
and detailed logs report zero swaps. The checker compile emitted one inherited
unused parse_pax notice. Limits remain 600 MiB sampled aggregate RSS, 300 seconds
for compilation/production, 900 seconds for full readback, 1 GiB reserve, 4 MiB
output and shell file cap 16777216. Growth limits remain 1 GiB for SDK/native
production and 512 MiB for checker compilation/readback. Compilers were serial.

Two actual checker failures remain preserved in the native controls. The first
compile exited 1/1 with complete cleanup after three Option/Result propagation
typos; its original source is readback-source.v. After correcting those three
lookups, fresh tools-r2 compilation and scope self-tests passed. The first full
readback reached its final write but its output parent did not exist; it exited
1/1 with complete cleanup. A fresh readback-r2 directory was created and the same
qualified binary reran every gate successfully under the original limits. No
native production failed, no result was overwritten and no audit was weakened.

Complete native/tool evidence remains in
`S/framework-boot-native-controls-2026-11-03-r1`, including both failed attempts,
both source snapshots, the executable, input before/after checks and receipts.
The final checker matches frozen readback-source-r2.v at SHA-256
`0ccc19ed4fe8e579762d62242e1be8d0d10954045f0c5ee63936f56e87a5519a`.
Its result is `readback-r2/result.json`, SHA-256
`39e02e7413d2844ebcfbb5e8cbb1ebb053e329063bfe00152cb82fcbaa75f5e7`,
and successful readback guard SHA-256 is
`0940dbcf0d6225cab43042021b8d09523752bac7f9d2635c278deb6d10c3cd33`.
The result retains every source, class, header, helper and C-function delta.
Independent final source/artifact review approved the checker and this report;
`validation.md` in that control root hashes to
`37e11cc72fdb2f19834084c6105e7c5c8125ce7ee9554f167f0c14601fe951b7`.
The native artifact and control roots are now closed.
All historical complete evidence and original auditors remain required.

The closed producers, predecessor evidence, primary source audits, fixture and
all failed checker attempts passed joint sealing and a separate fresh-process
readback: fifteen roots, 17,347 typed entries. The manifest at
`S/framework-boot-producers-sealed-2026-11-03-r1/sealed/manifest.json` hashes to
`97d2b432a3be23d570070e7be954a29dbe67c95984748e40037f5bbb14f669a7`.
Fourteen original roots and the separately retained complete caller readback log
are listed in roots.txt, SHA-256
`2e36f4a47bb7ec77033d2a6c258eed1d2416d904fb8f512fc3290c2929d79d51`.
Both guard/child pairs exited zero with complete cleanup, empty reasons and zero
swaps. Seal/readback took 2.950/0.953 seconds, sampled RSS
27,017,216/24,510,464 bytes, detailed RSS 27,213,824/23,298,048 bytes and observed
growth 8,273,920/1,540,096 bytes under the unchanged 600 MiB RSS, 900-second,
64 MiB growth and 1 GiB reserve limits. Original outputs were retained without
rewriting; seal and readback each passed on their first invocation. Image
qualification and signed ARM/GMS/Maps execution remain separate checks.
