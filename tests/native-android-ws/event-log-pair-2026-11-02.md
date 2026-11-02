# EventLog write preparation without a binary sink

GMS reached the absent EventLog class through `clgt.e` and exited. Core
`b87e5c134` adds the five API-28 write overloads, public constructor and private
UTF helper in one fieldless class. Static inspection of the installed host
liblog finds that its default binary path discards records while summing
positive vector lengths; no runtime delivery was measured. The Java adapter
returns `-ENODEV` (-19) after valid preparation for the unavailable sink.
No binary record bytes are stored or written, and no actual sink is qualified.
The [source report](../native-android-tools/event-log-source-check.md) records
the primary-source contract and focused proof.

The array overload preserves observable type/size preparation: null arrays and
items, String, Integer, Long and Float; at most 255 examined items; a two-byte
initial list position and 4,064-byte budget; five-byte int/float and nine-byte
long costs. Unsupported examined types throw the exact IllegalArgumentException
without coercion. String truncation retains the original logical position;
an earlier encoding failure returns `-EIO` (-5), suppresses later validation
and takes precedence over the unavailable sink. ART-28 counting uses two bytes
for NUL, four for paired surrogates and three for each unpaired surrogate,
bounded at 4,064 bytes without allocating encoded buffers. Reader/store APIs,
native declarations, output printing, identity changes and grants are absent.

Producer `460a026d5` adds `--event-log` over the exact Component SDK. A dedicated
class-only gate preserves generic narrow-profile strictness. All 2,116 old
canonical classes remain byte-identical; EventLog alone is added, yielding
2,117 classes. Raw input is the complete canonical clone, so the prior
ComponentName/creator provider formatting normalizes without code changes.
Independent metadata and seven-method body oracles surround full API-28 DEX
assembly, binding flags, registers, branch targets, types, UTF counting, limits,
exception ordering and negative statuses. The ordinary receipt lists no changed
classes, empty existing-member/field delta maps and no Messenger removal keys. Full independent
artifact review confirmed the complete tree delta, exact equality with the
focused proof's second-roundtrip EventLog and streamed JAR DEX. Only classes.dex
changes inside the JAR.

| Admitted operation | Guard seconds | Sampled RSS bytes | Detailed RSS bytes |
| --- | ---: | ---: | ---: |
| Fresh producer compile | 2.378 | 410,566,656 | 416,546,816 |
| Complete producer self-tests | 0.416 | 12,042,240 | 14,548,992 |
| Complete SDK production | 50.083 | 495,026,176 | 483,803,136 |
| Complete retained-native admission | 3.344 | 53,805,056 | 52,740,096 |

These producer steps passed their first attempts, with guard/child exits zero,
complete cleanup and zero swaps. Production observed 671,023,104 bytes shared
growth under unchanged 600 MiB aggregate RSS, 300-second build/test, 1 GiB
reserve, 4 MiB output, file cap 16777216 and 512 MiB/1 GiB tool/SDK growth limits.

Paths below use `S=/Users/alex/.local/state/vinix/android`; the complete SDK is
`S/combined-account-webview-event-log-framework-2026-11-02-r1`.

| Artifact | SHA-256 |
| --- | --- |
| Baseline Component SDK manifest | `79d78a512ac764807a2ecd3ca39317a5030e133f3749c0dd349c037482dcd512` |
| New SDK manifest | `56adef59b9210f72117709c26c5e008503379586407c70ab00297c32a70f5670` |
| SDK `build.json` | `173dbd5f3ccf8525656cee46571af827082bed97753aea7645821560ed847a03` |
| Framework JAR | `0a331f5595b4b6c1298dd0e944389cbeabe2b93f6e02e536c4d26d5d200967ad` |
| Framework DEX | `7137c2ddab3f670b0927170d09da059352bda1ba05e6a9f9d5b85f7b306c9531` |
| Raw EventLog | `9e76d83faf7b556e96823ab97cabfec568e83ebaf1732163cebf93492b70dd28` |
| Canonical EventLog | `914acd48f8b12fcbb54695f4497992f958a2658e6d34b93aabc032586b34093d` |

The immutable receipt records source revision
`460a026d54191e0a8c5e64fc35ea7022981fe2ec`, containing core `b87e5c134`.
Final input readback matched the committed and frozen producer/provider/
integration pins. Builder/provider source closures retain 271/143 entries.
Complete controls are
`S/event-log-framework-builder-2026-11-02-r1` and
`S/event-log-framework-production-2026-11-02-r1`. Compiler, helper and smali-tool
inputs stay retained; host SDK and dynamic libraries remain documented
environmental dependencies.

Nine complete roots passed joint sealing and a separate fresh-process readback:
15,311 typed entries covering source proof, primary caller audit, backend audit,
SDK/producer controls, fixture/controls and the complete Component parent SDK.
The list is `S/event-log-producers-sealed-2026-11-02-r1/roots.txt`; its
`sealed/manifest.json` hashes to
`3d8a7308ea7cda0440dcd52484470502099028d8a42c69733c04518a6c0202c6`.
Seal/readback took 2.693/0.864 guard seconds, sampled 28,295,168/24,510,464 bytes
RSS and observed 9,859,072/3,506,176 bytes shared growth. Guards/children exit
zero with complete cleanup and zero swaps under unchanged 600 MiB RSS,
900-second, 64 MiB growth and 1 GiB reserve limits. The prior complete
sixteen-root Component/Messenger history remains required at seal
`4602a6e129564ff69905cc05a1ba619b5471b88ccfc5acbfdc99b5a0bb3b118a`,
including all original failed attempts and the uncompiled proposal.

The complete backend evidence at `S/event-log-backend-audit-2026-11-02-r1`
retains the actual 67,280-byte liblog, ART origin inventory, ELF/disassembly,
commands and input/tool pins: 61 inventory entries, checksum
`e239e11d436bade327e33f86ba7e25c2619336a7724816a9d1c424c5abe24b7e`.
Its audit report hashes to
`dfe1879e55057a661d0d4e6f2a80131556ea97dc9ba0b8c2c29d77483eae25bf`.
The source proof retains 19 semantic controls and 132 interpreted input checks
on generated source and both API-28 DEX rounds; its receipt is
`df048c3ff4d18ebf7abcb82a5ff1de5dbb69a91db613682fc4c49c7bd8461b6e`.

The retained native bundle remains
`S/current-native-build-2026-11-02-broadcast-permission-r1`, manifest
`e371c8d365b78493f9f9d660ceceb1cb2b1382eaa60cae06bcbe4aad0c6c233b`,
DSO `29b2631c36a4a8c802e904e936c23e090fb2de3b5019ac93548df1b15de2a8f1`,
with original broadcast-SDK provenance
`49daffbfa9dc1dcc598e453eaae3611df7702963aa5b659022545149af7132d5`.
Its complete original native/source bundles remain required at the twelve-root
seal `b755b2951d12e064f648b6baa872019aba414dfe61739c65197500382d9ef67d`.

The full SDK/native admission passed its first attempt. EventLog remains outside
the generated native membership. All 70 consumed classes stay canonically
equal; exactly two raw formatting pairs come from the canonical clone, with
the remaining 68 raw classes equal. Complete old-class preservation also keeps
manual ComponentName constructor/getter/field ABI, its creator, ContextImpl
theme/resource/loaded-app ABI, Handler, Binder and Parcel unchanged. No native
implementation, binding, linkage or provenance change occurs.

| Consumed class | Original raw SHA-256 | Successor raw SHA-256 |
| --- | --- | --- |
| Context | `3819dd399a1ac9e8fba32ada045cc250f670f4fa012d765126ded7d1acbba0e8` | `60fdbab8aef10711d65afa9a0ddf5e64369ae21e0f9010291288109ebc305ab5` |
| ATLLoadedApp | `3e133e9cf9a3a2271bfef87917f2060c14b40a550dfb6f760c5b4278580b729f` | `6e8d9800711ae17e8b8a86de267590c2bb702d7d6fe8db870c57e6a599e5b0bd` |

The gate checks the original 91-origin/92-input native source map, 721 exports,
generated JNI/C, all 58 consumed C/header inputs and complete 650/340-entry
builder/generator helper closures. The retained native stays coupled to its
original broadcast SDK. Guard/child exits are zero, cleanup is complete, swaps
are zero and observed shared growth is 36,118,528 bytes under unchanged
600 MiB/900-second/512 MiB growth/1 GiB reserve limits.

Actual admission evidence is
`S/maps-event-log-tools-2026-11-02-r1/framework-audit.guard.json`, SHA-256
`16c766784156168dd8d79e40b3945151b5b95287782730f1983817f9aaca9952`;
the complete log hashes to
`31b0f289600a3fb1008f6dd9b88a682c6ebe436513bc22804b68b8b6207d238b`.
The admission executable used frozen source SHA-256
`9057e8ace0db0438436ef4f9ddc7e2d99a4f117d123836d536251232bf19939c`.
Complete image-tool qualification is pending and reported separately. ARM,
live GMS/Maps behavior, authentication and imagery remain separate runtime
checks.
