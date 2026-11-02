# ComponentName parcel contract and retained native

The unchanged Messenger ARM fixture reaches ComponentName's missing parcel
implementation. Its inherited no-op writer and missing CREATOR cannot roundtrip
the component. The GMS reply Bundle also legitimately carries this value.
Core `eb467cd5a` supplies the API-28 contract; the
[source report](../native-android-tools/component-parcel-source-check.md)
records the focused proof and null/cursor controls.

ComponentName writes package then class as two Strings. Its public Parcel
constructor rejects a null package before reading the class, then rejects a
null class, with the exact NullPointerException messages. The static nullable
writer emits one null String for a null component; its nonnull path delegates
with flags zero. The nullable reader returns null after one null package read.
For a present package it deliberately uses the private String/Parcel constructor,
which reads the class without validation. Creator uses the public validating
constructor and creates actual ComponentName arrays. This preserves the API-28
distinction between Creator and the static nullable helper.

Producer `38a56c93a` adds `--component-parcel` over the exact Messenger SDK.
All 23 original methods, both private final String fields and other metadata
remain unchanged. Six methods and public static final CREATOR are appended;
the sole new fieldless VinixComponentNameCreator contains three methods.
Independent raw/canonical body oracles bind signatures, flags, registers,
String wire order, null branches, read order and the two constructor behaviors.
Generic member, complete class and JAR gates remain unchanged: 2,115 classes
become 2,116, with only ComponentName changed and its creator added. Intent,
Parcel and all Messenger/Message/Handler classes remain unchanged. The ordinary
receipt omits the previous Messenger profile's removal keys.
Independent source and complete artifact review confirmed the full class delta,
all original members, both changed/added class bodies and streamed JAR DEX.

| Admitted operation | Guard seconds | Sampled RSS bytes | Detailed RSS bytes |
| --- | ---: | ---: | ---: |
| Fresh producer compile | 2.009 | 388,071,424 | 427,802,624 |
| Complete producer self-tests | 0.375 | 15,548,416 | 14,483,456 |
| Complete SDK production | 44.728 | 494,731,264 | 480,591,872 |
| Complete retained-native admission | 2.567 | 52,346,880 | 52,183,040 |

Producer compile, self-tests and SDK production passed their first attempts,
with guard/child exits zero, complete cleanup and zero swaps. Production
observed 180,768,768 bytes shared growth under
unchanged 600 MiB aggregate RSS, 300-second build/test, 1 GiB reserve, 4 MiB
output, file cap 16777216 and 512 MiB/1 GiB tool/SDK growth limits.

Paths below use `S=/Users/alex/.local/state/vinix/android`; the complete SDK is
`S/combined-account-webview-component-parcel-framework-2026-11-02-r1`.

| Artifact | SHA-256 |
| --- | --- |
| Baseline Messenger SDK manifest | `e3d313ae3e51404da203344ef1a6db32a4aaf24fe01ac971a71fd69ae586aa85` |
| New SDK manifest | `79d78a512ac764807a2ecd3ca39317a5030e133f3749c0dd349c037482dcd512` |
| SDK `build.json` | `6bc973d61eb28427a11f7b08c1c5e493ddb2b0d54c5a41838cc15b55fa47c905` |
| Framework JAR | `329a45c23bd981b67733f36cde2828b2d890597a384acf1e0ce30f8f8fb582f4` |
| Framework DEX | `e1d9acbc41d653911ec59f1cd40243c4acd3ee1e5e1a3c97172d483ed1cf9625` |
| Raw ComponentName | `e0da33559da01d8f2323be046537eb2eeb35fe886d9c89e881df77116566295a` |
| Canonical ComponentName | `645ef164621fbc7a311a74ec3a997eb403231fa5b708e5b6c5645d864a96bfdb` |
| Raw creator | `5ef9c2b472f77ca6f0b0fa8220715b289e5818721644a6bec81c9c592c19fa9c` |
| Canonical creator | `9709ae9678ab2e0d393908087f2ab90f9259244e51db6e116689788e25933c64` |

The immutable receipt records source revision
`38a56c93ad5d97e2261c792736ea7864b2d05567`, containing core `eb467cd5a`.
Current, committed and frozen producer/provider/integration pins match;
complete builder/provider source closures retain 271/143 entries. Complete
controls remain at `S/component-parcel-framework-builder-2026-11-02-r1` and
`S/component-parcel-framework-production-2026-11-02-r1`. Only classes.dex changes
inside the JAR. Compiler, helper and smali-tool inputs stay retained; host SDK
and dynamic libraries remain documented environmental dependencies.

Delivery reuses the exact signed Messenger APK
`7295339e8b548f3d48091229eb31319be25bf7394a2091ebce6b26263693729a`
from `S/messenger-binder-fixture-2026-11-02-r2/probe.apk`, through the additive
`--messenger-binder-v2` runner profile and the same UID 10150. The payload is
unchanged. The complete original fixture, failures and producer bundles remain
required at the prior eleven-root seal
`8d21336afbaf8861710b6872390da77c5f2ec4ad0a9413b7588056d4e8b089d6`.

Sixteen complete roots passed joint sealing and a separate fresh-process
readback: 15,615 typed entries covering all five Component source/audit/SDK
roots plus all eleven original Messenger producer/fixture roots. Original
failed source proofs, fixture/producer attempts and the uncompiled proposal
remain complete. The list is
`S/component-parcel-producers-sealed-2026-11-02-r1/roots.txt`; its
`sealed/manifest.json` hashes to
`4602a6e129564ff69905cc05a1ba619b5471b88ccfc5acbfdc99b5a0bb3b118a`.
Seal/readback took 1.784/1.098 guard seconds, sampled 28,753,920/13,467,648 bytes
RSS and observed 4,939,776/1,462,272 bytes shared growth. Guards/children exit
zero with complete cleanup and zero swaps under unchanged 600 MiB RSS,
900-second, 64 MiB growth and 1 GiB reserve limits. Both prior complete seals
and historical prerequisites remain required.

The retained native bundle remains
`S/current-native-build-2026-11-02-broadcast-permission-r1`, manifest
`e371c8d365b78493f9f9d660ceceb1cb2b1382eaa60cae06bcbe4aad0c6c233b`,
DSO `29b2631c36a4a8c802e904e936c23e090fb2de3b5019ac93548df1b15de2a8f1`,
with its original broadcast-SDK provenance
`49daffbfa9dc1dcc598e453eaae3611df7702963aa5b659022545149af7132d5`.
The original complete native/source bundles remain required at their
twelve-root seal
`b755b2951d12e064f648b6baa872019aba414dfe61739c65197500382d9ef67d`.

The full SDK/native gate passes the exact 2,115-to-2,116 class delta and
preservation of all 23 original ComponentName methods, two String fields,
String/String constructor and getters used by manual native callers.
ComponentName is outside generated membership. All 70 consumed classes remain
canonically equal, with exactly two raw formatting pairs from the canonical
clone; the remaining 68 raw classes stay equal. Whole Handler, Binder, Parcel
and ContextImpl remain unchanged, including the latter's manually referenced
native theme/resource/loaded-app fields and methods. No native rebuild, binding
change or provenance relabel occurs.

| Consumed class | Original raw SHA-256 | Successor raw SHA-256 |
| --- | --- | --- |
| Context | `3819dd399a1ac9e8fba32ada045cc250f670f4fa012d765126ded7d1acbba0e8` | `60fdbab8aef10711d65afa9a0ddf5e64369ae21e0f9010291288109ebc305ab5` |
| ATLLoadedApp | `3e133e9cf9a3a2271bfef87917f2060c14b40a550dfb6f760c5b4278580b729f` | `6e8d9800711ae17e8b8a86de267590c2bb702d7d6fe8db870c57e6a599e5b0bd` |

The gate checks the complete original 91-origin/92-input native source map,
721 exports, generated JNI/C, all 58 consumed C/header inputs and 650/340-entry
builder/generator helper closures. The native bundle remains coupled to its
original broadcast SDK. Actual admission guard/child exits are zero, cleanup
is complete, swaps are zero and observed shared growth is 53,248 bytes under
unchanged 600 MiB/900-second/512 MiB growth/1 GiB reserve limits.

Actual admission evidence is
`S/maps-component-parcel-tools-2026-11-02-r1/framework-audit.guard.json`, SHA-256
`1e7093fdecf0d4bf80149bf90ed1391536c8ab4b38a76b40dde2e9b565db2959`;
the complete log hashes to
`22d4cd18dce00df6b3be4395c80ec901e12a1ad6b708a1f2af63819090c1b711`.
Current and frozen admission source both hash to
`f92cdf3f889e248af9f67ac4947dc5e50a862b3e6bf0285bf1ad673b63d2af4b`.
Complete image-tool qualification is pending and reported separately. ARM,
live GMS/Maps behavior, authentication and imagery remain separate runtime
checks.
