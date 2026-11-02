# Build ABI-width arrays and retained native

Core `0f443cf3b` adds Build.SUPPORTED_64_BIT_ABIS and SUPPORTED_32_BIT_ABIS for
the qualified AArch64 runtime. Its existing ARM property branch now seeds
`ro.product.cpu.abilist64=arm64-v8a`, empty `ro.product.cpu.abilist32` and empty
`ro.product.cpu.abi2`. The two new fields read those properties independently.
A private empty-aware list helper returns a fresh zero-length array for an
empty value, otherwise splitting with its separator argument. It uses the
two-argument property getter with an empty default, avoiding an unknown or
single-empty-string ABI entry. The
[source report](../native-android-tools/build-abis-source-check.md) records the
bounded API and property contract.

Producer `0d6272593` adds `--build-abis` over the exact EventLog SDK. Only the
Build and SystemProperties initializers change. Build adds two public static
final String-array fields and one private static helper; its 23 existing fields,
five other methods and metadata remain intact. SystemProperties preserves its
one field and six other methods. Its three new puts occur only after the old
AArch64 ABI-list assignment. The legacy x86 branch, SDK override, unrelated
properties, existing SUPPORTED_ABIS/CPU_ABI logic and all Build.VERSION bytes
remain unchanged. This does not qualify new x86 ABI behavior.

Independent raw/canonical oracles compare the complete old initializers with
only the exact insertions, preserving registers, instructions and branch
targets. Generic member/metadata/class/JAR gates remain unchanged. Class
membership stays 2,117; all 2,115 other canonical classes, including EventLog,
ComponentName and its creator, stay byte-identical. No classes or methods are
removed and the ordinary receipt has no Messenger removal keys. Independent
source and complete artifact review approved the full class delta, exact
focused-proof second-roundtrip output and streamed JAR DEX. Only classes.dex
changes inside the JAR.

| Admitted operation | Guard seconds | Sampled RSS bytes | Detailed RSS bytes |
| --- | ---: | ---: | ---: |
| Fresh quiet producer compile r2 | 3.231 | 392,609,792 | 425,902,080 |
| Complete producer self-tests r2 | 0.366 | 15,695,872 | 14,581,760 |
| Complete SDK production | 53.840 | 495,157,248 | 480,444,416 |
| Complete retained-native admission | 4.523 | 55,164,928 | 55,558,144 |

SDK production passed its first attempt. Producer r1 compile and self-tests
exited zero, but compilation emitted two local-variable shadowing notices; that
binary was not used for production. Only those two variable names and their
references changed before fresh quiet r2 qualification. The complete r1 sources,
binary and actual receipts remain retained. Admitted guards/children exit zero,
cleanup is complete and swaps are zero. Production observed 166,445,056 bytes
shared growth under unchanged 600 MiB aggregate RSS, 300-second build/test,
1 GiB reserve, 4 MiB output, file cap 16777216 and 512 MiB/1 GiB tool/SDK growth
limits.

Paths below use `S=/Users/alex/.local/state/vinix/android`. The SDK retains the
explicit output name `S/combined-account-webview-build-abis-framework-2026-11-02-r1`;
fresh source proof and producer controls use their actual November 3 date.

| Artifact | SHA-256 |
| --- | --- |
| Baseline EventLog SDK manifest | `56adef59b9210f72117709c26c5e008503379586407c70ab00297c32a70f5670` |
| New SDK manifest | `23c75e5be1445f177d7a6a801f907235d166b7a0f541c41bf0895f861bbed3e9` |
| SDK `build.json` | `b6e2cda589eca9ffcea15da9bb6e863e7b84908006829550890530c900d4ff73` |
| Framework JAR | `251753fdee85367880a9b0c48d1cb0058fd17a819e4651a8dc29f232673f531f` |
| Framework DEX | `f573bc91081977cc6fbeb2b5336962565bd9d057401254ccbbfa1c37ab1cb893` |
| Raw Build | `e85746ba3c04aea7e89785a58d34fe1c9e280b2254e791230992b62c8eb15d4c` |
| Canonical Build | `e51084623eaee7ca5e819af699497d6ddb9f9a6ea585cc1b42140c9c79b47166` |
| Raw SystemProperties | `d35c268b48d8f078bc416f88f9ee37dbca1c972f139637d3c753483bf7b2a84a` |
| Canonical SystemProperties | `2740259e2ff3260d0ab93dc040752b52b1daaae3c037b89e39ab2d35f6c85c34` |

The immutable receipt records source revision
`0d6272593dd7ef76d61853ac56a498b29c8615de`, containing core `0f443cf3b`.
Final input readback matched committed and frozen producer/provider/integration
pins; complete builder/provider source closures retain 271/143 entries.
Controls remain at `S/build-abis-framework-builder-2026-11-03-r1`, matching `r2`,
and `S/build-abis-framework-production-2026-11-03-r1`. Compiler, helper and
smali-tool inputs remain retained; host SDK and dynamic libraries remain
documented environmental dependencies.

Nine complete roots passed joint sealing and a separate fresh-process readback:
15,258 typed entries covering focused source proof, caller audit, both producer
attempts, SDK/production controls, fixture/controls and the complete EventLog
parent SDK. The list is
`S/build-abis-producers-sealed-2026-11-03-r1/roots.txt`; its
`sealed/manifest.json` hashes to
`bbee620d43a07d7aa0b25e599d3ad0d14fc95d2e692de20f4603fc6a981783fc`.
Seal/readback took 2.597/0.834 guard seconds, sampled 24,068,096/24,559,616 bytes
RSS and observed 4,739,072/1,327,104 bytes shared growth. Guards/children exit
zero with complete cleanup and zero swaps under unchanged 600 MiB RSS,
900-second, 64 MiB growth and 1 GiB reserve limits. Original r1 notices and
actual zero-exit receipts remain complete alongside the quiet r2 evidence.

The retained native bundle remains
`S/current-native-build-2026-11-02-broadcast-permission-r1`, manifest
`e371c8d365b78493f9f9d660ceceb1cb2b1382eaa60cae06bcbe4aad0c6c233b`,
DSO `29b2631c36a4a8c802e904e936c23e090fb2de3b5019ac93548df1b15de2a8f1`,
with original broadcast-SDK provenance
`49daffbfa9dc1dcc598e453eaae3611df7702963aa5b659022545149af7132d5`.
Its complete original native/source bundles remain required at twelve-root
seal `b755b2951d12e064f648b6baa872019aba414dfe61739c65197500382d9ef67d`.
The complete EventLog parent and source/backend history remain required at
nine-root seal `3d8a7308ea7cda0440dcd52484470502099028d8a42c69733c04518a6c0202c6`.
The prior sixteen-root Component/Messenger history remains required at seal
`4602a6e129564ff69905cc05a1ba619b5471b88ccfc5acbfdc99b5a0bb3b118a`;
historical prerequisite bundles and checks are unchanged.

Full SDK/native admission passed the exact two-class initializer/field/helper
scope with unchanged 2,117-class membership. Both changed classes remain outside
generated native membership. All 70 consumed classes stay canonically equal;
exactly two raw formatting pairs come from the canonical clone, with the other
68 raw classes equal. All 2,115 other classes remain unchanged, preserving
Build.VERSION, EventLog, ComponentName/creator and manual ContextImpl/native
theme/resource/loaded-app ABI. No native implementation, binding, linkage or
provenance change occurs.

| Consumed class | Original raw SHA-256 | Successor raw SHA-256 |
| --- | --- | --- |
| Context | `3819dd399a1ac9e8fba32ada045cc250f670f4fa012d765126ded7d1acbba0e8` | `60fdbab8aef10711d65afa9a0ddf5e64369ae21e0f9010291288109ebc305ab5` |
| ATLLoadedApp | `3e133e9cf9a3a2271bfef87917f2060c14b40a550dfb6f760c5b4278580b729f` | `6e8d9800711ae17e8b8a86de267590c2bb702d7d6fe8db870c57e6a599e5b0bd` |

The gate checks the original 91-origin/92-input native source map, 721 exports,
generated JNI/C, all 58 consumed C/header inputs and complete 650/340-entry
builder/generator helper closures. The retained native stays coupled to its
original broadcast SDK. Guard/child exits are zero, cleanup is complete, swaps
are zero and observed shared growth is 290,816 bytes under unchanged
600 MiB/900-second/512 MiB growth/1 GiB reserve limits.

Actual admission evidence is
`S/maps-build-abis-tools-2026-11-03-r1/framework-audit.guard.json`, SHA-256
`b2ad9b1844f4ddf34387c172988cbb5828009ecace5234820f11a4388d0caeb0`;
the complete log hashes to
`5be55a3afa87d7beb99c199de007b6b54d8ce8d0559e6f38c421beef8f6ce631`.
The admission executable used frozen source SHA-256
`034d266482bd0e4bccbf682cdfef2981b04e36b192ea4dc2b4bdd2c9029a91cc`.
Complete image-tool qualification is pending and reported separately. ARM,
live GMS/Maps behavior, authentication and imagery remain separate runtime
checks.
