# Maps370 Intent URI replay

Maps370 uses the qualified [Framework369](intent-uri369-framework-build.md)
to address the missing `Intent.parseUri(String,int)` method that stopped
[Maps368](maps368-timing-logger-replay.md) during background GMS AppIndexing.
Framework369 changes only `android.content.Intent` among the 2,076 framework
classes. This report records the host gates; the Maps runtime observation is
pending.

The generator is commit `fb3b07283`, replacement pin writer and receipt wrapper
`1179973a5`, independent prelaunch checker `6d52f5ca0`, and its command recorder
`8cc2c4fdb`. The generator bootstrap peer is `9ba39485e`; the independent
recorded-build peer is `9dfc81593`. Complete generated source, binaries and
evidence remain outside Git under
`/Users/alex/.local/state/vinix/android/`, except repository build paths marked
below.

| Host input or result | SHA-256 |
| --- | --- |
| `intent-uri369-framework-build-2026-10-26/sha256.json` | `9f52eb8f69aaaa6d57f8ca3ce11dd20c870de8032bc821aff5e7527473334c93` |
| Framework369 JAR | `74e1d74b9ecf51e302f2802a2d291ff15f1d1793495d67c7c108d1d5350a884b` |
| Native351 SO | `d3da7eefd58c8f1faf7a88dd0b6fa0839cebdba145d236bd5fe1ecc185e257a1` |
| Loader357 | `42c7ac8a276a7eb72a3844e94e182aef8ad7df4c2f8f7313f7061527d077b908` |
| `maps370-generation-2026-10-26/sha256.json` | `f55ab450cce9db00eb601b03afc7c09efa8d6c5fe49ece0c452b77720be03823` |
| Generated `maps370-run.v` | `11ab2cd3ac79ec8c24810f127c4a163d267d998fc1ea03f60258ef9e33e84ac1` |
| Repository `build/android-maps/maps370-run-recorded` | `d8fb503f68deb073e351d3a292b08e03b80aa181395647dc18bb20d231526330` |
| `maps370-generator-build-2026-10-26/sha256.json` | `b4a46ea26a62c954470d3617a87cd3bfc593a81b8d4da82d03c4e8eaad78f3a5` |
| `maps370-generator-peer-readback-2026-10-26.json` | `a14c69044fc5a3062a3718c22b598b52184a312233bd0b248fe140e725d00bf8` |
| `maps370-recorded-build-peer-audit-2026-10-26.json` | `b7bdcfe7e6bf84d2a67b7c5d47ce02b6d7d4d41788c9d53ee1f42cbc84037147` |
| `maps370-prelaunch-review-build-2026-10-26/sha256.json` | `515cf9c83cf9c13c6957904a5bfc5458f452791de8854880fe682c214ecd396a` |
| `maps370-prelaunch-review-build-peer-readback-2026-10-26.json` | `033a6756fcc6b8d720472f2dac58f8ff21df98039e19f43efed18c2b2ca1ec3a` |
| `maps370-replay-receipt-build-2026-10-26/sha256.json` | `2f8c95cf4ef9aa299e134a6cdde04a5a4804e91371e9a4d22d08acf03fbb20f6` |
| `maps370-replacement-pins-2026-10-26.json` | `6ed5a463a2851ecbb3b31fba35c5030ae794409c152e001765a4648bed841c78` |
| Repository `build/android-maps/maps370/launch-pins.json` | `7807d9fabb153a6668b53ace2831cdf3ae01ca96f4a333e3bd9ef647b6d722f0` |
| `maps370-2026-10-26/prelaunch-sha256.json` | `d8522f2c3b318fffa90147bf68912833287d10d1e50b82e31680f0b8799cb605` |
| `maps370-prepare-receipt-2026-10-26/sha256.json` | `a472eb89262ee471c2b217ab1c0f840be5b6e378f62371f86358515aa1ea8c64` |
| `maps370-prepare-receipt-peer-readback-2026-10-26.json` | `a35c36b6795eec33ae60caae4bd8c3460ae8430aa2a7a33c1f8c87c29bb80043` |
| `maps370-check-receipt-2026-10-26/sha256.json` | `23756cc4635cb27d7a3dd9c191ddd2d3345566f8efe3ff388b1a957a9a733e69` |
| `maps370-check-receipt-peer-readback-2026-10-26.json` | `a278a5a3bad8c93694dbd00765fb9a1d1df0def4256628d49b147a0652d9fbc1` |
| `maps370-independent-prelaunch-review-2026-10-26.json` | `498afc747398e71ed96936b32aa81ca5b1ebc74dcf087ff9d12e1025c9eabf1b` |

The original complete290 checker independently passed both 21-file generation
bundles and the 297-file prelaunch checker build. The independent peers checked
the exact 272-input live and retained compiler closures for the generator,
runner and prelaunch checker, including build argv, actual command statuses,
self-tests and unchanged source, compiler, C compiler and binary identities.
The runner build is retained in `maps370-run-build-c-2026-10-26`; it has no
outer build-directory seal, matching the earlier replay build contract.

The dedicated wrapper accepts only the six exact Native351/Framework369
replacement identities, filters inherited trace and location environment
keys, and records the actual child status separately from collection.
Recorded identity, environment and nonzero-status self-tests passed, as did
the complete wrapper build, self-test and pin-writer bundle readbacks.
Native351, Loader357, Maps and companion APKs, launcher, classifier and the
600-second observation contract remain pinned. Host gates alone do not
establish a Maps runtime pass.

Preparation ran 03:19:26–03:24:12 UTC on 2026-10-26, actual exit 0, with
unchanged inputs, 50 clean environment entries and no forbidden keys.
It retained the complete framework baseline chain and prepared the exact
three-file runtime overlay while preserving the five original base boot
members.
The original complete290 checker independently passed all nine preparation
wrapper files, actual exit 0. Its exact argv, actual status, unchanged checker
and manifest identities and log hash are retained in the adjacent
`maps370-prepare-receipt-peer-readback-2026-10-26-command.json`; its SHA-256 is
`634255df2b8d93d3ae8e3eb20268b392acdf7b3d0296716dbeeeba3a68cdcfba`.
The dedicated wrapper peer recorder is committed in `51d271a57`.

The recorded launch gate ran 03:24:30–03:26:50 UTC, actual exit 0, with the
same environment filtering and unchanged input identities. The original
complete290 checker independently passed all nine launch-gate wrapper files,
actual exit 0. Its adjacent
`maps370-check-receipt-peer-readback-2026-10-26-command.json` has SHA-256
`c6053246d0765327e016e85e60224f8714fc28fb56e09fc0934f5777661a24e3`.

Independent actual prelaunch review ran 03:24:28–03:26:39 UTC, actual exit 0.
It requalified all 50,901 files of the Framework369 build and its complete
367/365/361/359/353 baseline chain, 2,404 Native351 files and 2,440 Loader357
files. Both complete typed prelaunch trees passed. Exactly three runtime
files changed among 109: the native library, framework JAR and loader; all
other 106 remained unchanged. Modes, links, APKs, launcher, identity settings,
classifier, the 600-second setting, all five original base boot members and
the final three-member overlay passed. The exact argv, actual child status
and unchanged checker identity are retained in
`maps370-independent-prelaunch-review-2026-10-26-command.json`, SHA-256
`a81c7dd9f9f05fd53b8203450616bb31a34fee60f875dcf4ca61c60cf04cc076`.
The adjacent recorder source and binary match their recorded identities.
