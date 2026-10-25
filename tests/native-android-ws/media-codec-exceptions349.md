# Media exception linkage for Google Maps

Maps347 reaches the map and place details, but embedded-player class `hwv`
cannot verify because superclass `hqa.V(long,long)` has an undefined register
at DEX PC `0x4CF`. The [actual caller proof](media-codec-exceptions349-callers.md)
traces that edge to missing media exception types. Fix revision
`732d7150e6d63b12e551ad1885d7f5185a5aca9d` adds `MediaCodec.CryptoException`,
`MediaCodec.CodecException`, and `MediaCryptoException`, plus the two nested
types' `MediaCodec` metadata. Their limited legacy API follows the
[official source contract](media-codec-exceptions349-contract.md).

One signed three-class fixture APK runs on native ART with each framework.
Its separate loader first initializes the original unchanged Maps APK's `hqa`
and `hwv` through `DexClassLoader`, checking their loader identities and
superclass relationship. API checks follow only after that succeeds. They cover
modifiers and nested metadata, constants, constructor visibility, messages and
nulls, exception hierarchy, independent error-code instances, signed diagnostic
strings including integer minimum, and transient/recoverable action semantics.

The old framework rejects original `hqa.V` exactly once with the same
`[0x4CF] copy1 v5<-v3 type=Undefined cat=1` VerifyError, before any API marker or
successful class-load marker. It exits during activity startup. The fixed
framework verifies both original classes, prints every ordered fixture success
marker, and remains alive for the 35-second observation with no failure markers.
Both semantic checks pass again during qualification. This establishes original
class verification and exception semantics; it does not establish native media
decoding, DRM, video playback or a subsequent Maps replay.

The runner freezes qualified346's compiler, V closure, C inputs and assets in
an isolated external tree. Its 642 V input pins match before and after runner
compilation. The original Maps APK is appended to a copy of qualified346's
base tar at `/opt/android-test/maps-application.apk`; retained extracted bytes
match the original hash, and both boots use that same base tar. The framework
JAR is the only guest runtime delta. Complete DEX comparison adds three classes,
increasing 2070 to 2073, and restores the exact original `MediaCodec` source and
disassembly after removing the two added metadata entries. The other 2069
existing classes are identical after disassembly. Duplicate application fails
without mutation.

Complete artifacts are retained at
`/Users/alex/.local/state/vinix/android/media-codec-exceptions349-2026-10-25`:

| Artifact | SHA-256 |
| --- | --- |
| Baseline346 framework JAR | `b33472257a59c9b8dffca155c2f1ecd77e0f10c3dae230a23a3afafee9e7c840` |
| Fixed349 framework JAR | `95aabc17c85a5cda0d643dfa5ef9e618955d422d960ffb3bbc2db74c86a9c37d` |
| Original unchanged Maps APK | `6218d72f48b184eb71f68879bce48cb9ebb2b510be7f7cff88217ea3fd592bb2` |
| Same signed fixture APK | `2dc11a3245ce979cc7a518ee390d6f860602f5bbb6c463653e7025e54181d673` |
| Executed checked runner | `7e285fceb087a7da38f7b14b172db16674d0fdce5eec861e88ac628df0a348ec` |
| Executed frozen runner source | `3c8bb20ab807006ed2ab49926284aa4f75d404d636f3e992164fac69f8895ca1` |
| Old raw serial | `a87cf0ad4666c916e92173fa7c47d53de407b178c10d265ece971e5c65929abd` |
| Fixed raw serial | `bd8ba48eff3c9f66dabd4c50d71dc11b1e98351c012395ec9299bf389c764ec0` |

The bundle contains 7,926 files. Its complete `sha256.json` manifest SHA-256 is
`0700318453dfb6373ea07587c3f42b09fbdb65930dffd35eda0664deddde8f88`.
Independent own, root and peer readbacks passed every file and the exact file
set. Their adjacent receipts are
`media-codec-exceptions349-own-readback-2026-10-25.json`,
`media-codec-exceptions349-root-readback-2026-10-25.json`, and
`media-codec-exceptions349-peer-readback-2026-10-25.json`.
The unchanged qualified346 bundle retains manifest SHA-256
`6d5205fce48faea0c406efb68ec9134c039aa106e591d20e4501f2826d65064b`.
