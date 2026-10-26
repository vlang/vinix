# TimingLogger framework367 build

[Maps366](maps366-deferred-bundle-replay.md) reached a tiled map and search
suggestions. It later exited with a missing `android.util.TimingLogger` error
in a GMS Icing/AppIndexing worker. Provider fix
`dc2aa95c43f544e12ddfd403d746d3c852b1cf2a` implements its constructor, both
`reset` overloads, `addSplit` and `dumpToLog`, preserving disabled logging,
reused split lists, virtual reset calls and elapsed-time logging behavior.

Builder `2a35146cdebfd8cb588ef4ad7e6a091a03d54b90` produces the isolated
framework367 addition from the complete qualified365 build. Source and
disassembled DEX inventories add only `android/util/TimingLogger.smali`,
changing no existing class and removing none: 2,075 classes become 2,076.
Only `classes.dex` changes among the three regular JAR members. Existing
malformed destinations and duplicate application are rejected without changing
the corresponding input inventory. All six builder mutation self-tests passed.

The complete 644-file builder bootstrap is retained at
`/Users/alex/.local/state/vinix/android/timing-logger367-framework-builder-build-attempt2-2026-10-26`,
manifest `5cad7ba6fde6e528d5575112448fac5bea5f848bbad6dde7526a9bedcfb01cf3`.
Compilation and self-test exited 0; recorded and root complete readbacks passed.
The actual build retains its committed provider in a private VROOT, frozen
compiler, generated C, source closures, host tools and actual command receipts.
The complete365 baseline, including its complete361,359 and353 inputs, remains
inside the build and passed the original checker before and after use.

The sealed 41,884-file build is retained at
`/Users/alex/.local/state/vinix/android/timing-logger367-framework-build-2026-10-26`.
Its full invocation exited 0. The original complete checker exited 0, verifying
every file hash and the exact file set. The adjacent original receipt is
`timing-logger367-framework-build-2026-10-26-own-readback.json`, SHA-256
`35bf725e4340eab55ffcd7e55ba3216ed8d914495055641f930137546e53f1f2`.
Its `-own-readback-command.json` records the actual checker exit; the external
`-invocation.json` records the build command and actual exit.

Root's independent original checker call also exited 0 for all 41,884 files
and the exact file set. Its adjacent receipt is
`timing-logger367-framework-root-readback-2026-10-26.json`, SHA-256
`47c2fc2e8b186f201fea350eccc0fcdb7899330a92c3486801f3934e82b3b0c6`.

Independent peer qualification also exited 0 for every file hash and the exact
file set. Its separate semantic inspection checked the actual source and DEX
inventories, JAR members, all 32 recorded command exits, all 413 frozen closure
inputs, committed isolated provider, both rejection guards and the retained
baseline chain. The complete checker is committed as
`tests/native-android-ws/timing-logger367-framework-peer-check.v`, identical to
the executed external source, SHA-256
`2dbeb201e9e71478ec08ef4e65934663efa12d00e58db90513b6d57a56b8df60`.
The external receipt prefix is
`timing-logger367-framework-peer-readback-2026-10-26` beside the sealed build:

| Peer evidence | SHA-256 |
| --- | --- |
| Original complete readback `.json` | `1eb2ee77980d1cd3fcdae8ba0badafe9d18d9bf2e70f732cd7f04390a1e9dd77` |
| Actual checker `-command.json` | `70e191e28dfb71c8f66a116552957e13ed56aefe5d16e313fff31254876cbf84` |
| Semantic `-inspection.json` | `ef284d214764005fb1543f94ba8d8bff015960d45c454462b9167f67de0cb4a0` |

| Retained input or result | SHA-256 |
| --- | --- |
| Provider source | `9ad633613ab9108a3df262ffbeb4a372588f68a12bb21cfcf5a061ff34d175ef` |
| Builder source | `779059bdd4c1fb73e9c5300ad738bc7541e02e70adea33c78e6c750bc1d201ea` |
| Qualified365 manifest | `b07a32393f8a3e546819b5053516d3cce8c68238ad9ed27f0ce789e76a6d2d99` |
| Old365 JAR | `b8b9351c39e28566ba5856bd3b71268e621587c866020d245cd2d738683668aa` |
| Framework367 complete manifest | `933baf6da303aebaf262e280e41769c89b61c2f050b481dd4075900a533ad23b` |
| New367 JAR | `fece4cb639fb8745557032f872d13d45767768656ae879f065324696bbf99694` |
| Build validation receipt | `ecf0468dec8e078b94b9e6d43108aabd504aad4ea9b7a837b6bc00fc3897c345` |

This report establishes the framework build and retained-input integrity.
Same-APK ART behavior and the subsequent Maps replay require separate runtime
qualification.
