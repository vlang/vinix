# Deferred Bundle parcel regression365

Framework365 adds strong Binder reference handling to the deferred Bundle fix.
The host proof, complete framework build and same-APK ART regression passed.
The fixture is sealed; complete root and independent peer readbacks passed.
The subsequent Maps replay is separate.

[Experiment363](bundle-parcel363-regression.md) reproduced the old eager-decoding
class-loader failure, then failed the new framework's shared assertion in its
first post-copy `putAll` decode. Inspection separately established that generic
Parcel tag21 wrote no Binder payload and created a new Binder when reading it.
Fix `f5f7ce38c5fe58cc7683fcbc552c9d9f67368cb5` now accepts `IBinder` and calls the
existing `writeStrongBinder` and `readStrongBinder` methods. The original363
failed bundle remains sealed; the fixture is unchanged.

The underlying deferred decode change addresses [Maps360](maps360-permission-metadata-replay.md),
which reached a live map and search suggestions before an application Parcelable
failed to load through a framework-only loader. Bundle values now remain deferred
until access, allowing callers to set their application loader. Independent
Parcel snapshots preserve local Binder references. Copy and write preserve
deferred state; clear releases it without decoding. Explicit monitor cleanup
protects snapshot ownership. Loader-aware CREATOR dispatch is included.

## Source and host proof

Fixture `2082297e21b003d63df2cf17a584c781aa903627` exercises default and explicit
loaders, inherited BaseBundle access, copy/clone and deferred `putAll`, creator
dispatch, Parcelable arrays and nested Bundles, Binder identity, round trips,
empty/null values, cursor alignment and malformed framing. It generates four
probe classes plus Main.

Checker `02d31e93d9faadbf0347b62a09435d8788284b73` passed seven malformed guards,
duplicate rejection without input mutation, and twelve-class API28 assembly and
disassembly. The complete host proof is
`/Users/alex/.local/state/vinix/android/bundle-parcel-source-attempt4-2026-10-26`,
manifest `29291fde31a878075393157d5f86a9f656ed515feac522c0377381274d5339e2`.
Recorded and root complete readbacks exited 0 for all 736 files and the exact
file set. Independent source review found no blocking issue.

Builder `081a9a10796a344f9f4dd17375d62e308c986a2b` and fresh ART harness
`db44da3f513498223b13a21a84a740223f56c239` use the frozen353 compiler and explicit
private VROOT, retaining source, generated C, actual command exits, host tool
identities and equal 270-input source closures before and after compilation.
The harness bootstrap additionally retains the actual363 old trace and checks
its exact Dalvik exception and nested Bundle frame shape. Synthetic mutation
checks reject altered messages, frames and marker sequences.

The complete 658-file harness bootstrap is
`/Users/alex/.local/state/vinix/android/bundle-parcel365-run-bootstrap-build-2026-10-26`,
manifest `5c12507437c2930b0c266e83c9e3d4f4e5967670a8cc90bb3963af3a476d5adc`.
Compilation and both self-test commands exited 0. Recorded and root complete
readbacks exited 0 for every hash and the exact file set.

## Complete framework build

The sealed build is
`/Users/alex/.local/state/vinix/android/bundle-parcel365-framework-build-2026-10-26`.
It retains the complete qualified361 baseline and its complete359 and353 inputs.
Source and DEX comparisons change only `android/os/BaseBundle`, `Bundle`,
`Parcel` and `Parcelable$ClassLoaderCreator`, add only `android/os/VinixBundleCreator`,
and remove no classes: 2,074 become 2,075. Only `classes.dex` changes among the
three regular JAR members. Recorded, root and independent peer complete
readbacks exited 0 for all 32,872 files and the exact file set. Separate peer
filesystem inspection confirmed the source/DEX delta, all 413 frozen closure
inputs, 32 command exits and retained361 qualification chain. The adjacent peer
receipt is `bundle-parcel365-framework-peer-readback-2026-10-26.json`, SHA-256
`59ebf2f2e72bc4afec01267ad4ce54a0510724220aee076a6b5e30c9cf74ba8d`.
Its `-command.json` and `-inspection.json` retain the actual checker exit and
separate inspection.

| Input or result | SHA-256 |
| --- | --- |
| Provider source | `30d5778f28a5558d8fd330a12a3cc62c46ae4e2f6f50d4d4f6d8c935b1b583c2` |
| Fixture source | `ea61bf298f17589252fda8612b616c463c7cdf01bdc7d3816402dc4462f1bfb5` |
| Source checker | `02c1f5fc775f95d68a21e6ca35c03de9d91944052311b0e10e3182cb877aa934` |
| Framework builder source | `d8408a2f70c737698d533c17d9f47148976ffc8fc232587e6c9adc075cc70028` |
| Fresh365 harness source | `fa2775bec1140ea0b72d33879d70a688499a1e721b91cd6300fa956fff293b35` |
| Harness bootstrap executable | `dbe17651d7a02ec14604e2f177991623bf26f7786d6ac22fcbd2e2f152d857d7` |
| Qualified361 complete manifest | `9649ab0f596dcd44ce5979a2e129548ca550d2ad54b4d2995fd3c714e125f8e9` |
| Old361 framework JAR | `077bb9f1784e2945accebc9043e0d8d54617bb0e01725e97824807d8cc57b10a` |
| Framework365 complete manifest | `b07a32393f8a3e546819b5053516d3cce8c68238ad9ed27f0ce789e76a6d2d99` |
| New365 framework JAR | `b8b9351c39e28566ba5856bd3b71268e621587c866020d245cd2d738683668aa` |
| Native351 SO | `d3da7eefd58c8f1faf7a88dd0b6fa0839cebdba145d236bd5fe1ecc185e257a1` |
| Launcher353 | `406b187bb0ef8f42c57cc26532abae6599b837b5b0226da7afd23fcda8ca67a0` |
| Frozen V compiler | `109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e` |

## Same-APK ART validation

Fresh preparation exited 0 at
`/Users/alex/.local/state/vinix/android/bundle-parcel365-fixture-2026-10-26`.
Its signed APK is
`deafe7867599ccab25c5f286b21227d73a9e21d3903a30b16afc720205b10d9f`, and the
prepared checked runner is
`8a9bd02103260f35568b95cecc0d9c8397e897402bdbfe46d8d35f7f74f111f6`.

The fresh APK hash differs from363 because of ZIP timestamps and the APK signing
block. Read-only comparator `1491aafa9afd7f115e1ee4ed84b2f061439781db` found
all 27 retained fixture source, Smali, resource, tool and keystore inputs
identical. The 6,492-byte DEX is identical,
SHA-256 `49dbae1228844e556e8706023792f5fd6691ba14e45072246408258b35809e38`.
All six APK compressed member payloads, including v1 signature files, match.
The full 12,713-byte APKs match after masking only ZIP DOS/UT timestamps and the
APK signing block. The classes.dex UTC timestamp changed from 00:39:01 to
01:11:11 on 2026-10-26. The comparison receipt is external alongside the bundles
as `bundle-parcel363-365-apk-content-comparison-r2-2026-10-26.json`, SHA-256
`55bfa7255230284ece77bdd9c3291fe24924362e735c73c6c3cb7aae961a1261`.
Compilation and actual comparison exited 0; independent source review passed.
This comparison covers the listed inputs and APK bytes; it excludes the compiler
closure, which the separate recorded harness bootstrap authenticates.

The same fresh365 APK ran against old361 and new365 with identical native351,
launcher353 and frozen base runtime; only the framework JAR differed.
Preparation and execution retained the 1,024/768 MiB capacity gates. Both suite
commands exited 0. Old361 reproduced the exact framework-loader exception and
expected nested Parcel/fixture frames. New365 emitted `BEGIN`, `DEFERRED-PASS`,
`COPY-PASS`, `ROUNDTRIP-PASS`, `EMPTY-PASS` and `PASS` with the `BUNDLE-PARCEL-`
prefix in order, exactly once. The actual result records `window_observed`,
35 observation seconds, an alive QEMU, no process exit and no failure markers.
The retry suite ran from 01:32:14 to 01:33:02 UTC on 2026-10-26. The unmodified
checked runner exited 0, and subsequent original qualification exited 0 for both
expected results.

The first new host invocation exited 1 without a suite result or completed
observation receipt, despite producing the six probe markers. It is retained as
an interrupted attempt, with no passing result attributed to it. Recovery helper
`b3ac3ad8838704f6a3a6426f7889c2fa3945d857` preserved all seven original paths
and their bytes/modes under `interrupted-new-01` before the unmodified runner
retried. Its external receipt
is `bundle-parcel365-recovery-receipt-2026-10-26.json`, SHA-256
`8a2081266c21e52861020cd4444062b97985b50acc801ff95ef41a437663fa39`.

| Retained runtime evidence | SHA-256 |
| --- | --- |
| Old raw result | `6817becd0f480cb5f1e847f446b645f946e2bc8e462ffbfc82d9fe4b6361d39f` |
| Old serial log | `f245f4f91e4b144d2ce72ded0fa28b758c98921e8acf44c66f69278ca079a483` |
| New raw result | `4f96de316e3fb5797bb47c02f0a814a85b6d24617f0901388e2eb692097435cf` |
| New serial log | `6c9133219ffdbfdffa6c89f00e656d1349858ac36de129b71705ec1dfc264579` |
| Old semantic receipt | `ed743de38ac77fb56bff8a87e81d9f97706892ef8ebd089288e5755049fcb25b` |
| New semantic receipt | `e4ab9ab6b47faa706ea4f3a42fa7ceac71ad22105c430582dc7c97448d4d54f4` |

## Sealed evidence

Original qualification and sealing commands exited 0. The sealed fixture retains
34,163 files, including the interrupted attempt, under the fixture root above.
Its complete manifest is
`ad2947b2bdae595fe9c801cd295ca647d761f0b7cf55f8f19b3e8d74c4dce10e`.
Before sealing, reviewed helper `64ae3b2ebfd869d2c8f0af081ad9cf7614068fcf`
consolidated two identical retained module APKs into APFS clones, preserving
their hashes, paths and modes. Its actual exit was 0; receipts remain outside the
fixture at `bundle-parcel365-apk-clone-2026-10-26`.

External V recorder source/binary and actual qualification/seal command receipts
are retained alongside the fixture, using the prefix
`bundle-parcel365-fixture-finalize-recorder-2026-10-26` and
`bundle-parcel365-fixture-{qualify,seal}-2026-10-26-command.json`.
The original checked-runner hash remained unchanged before and after both calls.
Root and independent peer complete checker290 calls exited 0 for all 34,163
hashes and the exact file set.
The adjacent root receipt `bundle-parcel365-fixture-root-readback-2026-10-26.json`
has SHA-256 `da29878c24cb1bc62be4848f4163ce25ef2c4bd5024430e39d40be36ab176a7b`;
its `-command.json` records the actual argv, timestamps, checker identity before
and after, and actual exit 0. The peer receipt
`bundle-parcel365-fixture-peer-readback-2026-10-26.json` has SHA-256
`0dfa350d3ab5f936cdad2b4ed1dc0b8fd874ad7d317f1e761a7c2c6d289a264e`.
Its separate inspection replayed the exact semantic predicates read-only,
validated the full365→361→359→353 qualification and unchanged shared closures,
and matched archived bytes/modes to the interrupted plan and recovery receipt.
A separate Maps replay is required to establish the corresponding application behavior.
