# Maps368 TimingLogger replay

Maps368 supplies `android.util.TimingLogger`, which was missing during
background GMS AppIndexing work in [Maps366](maps366-deferred-bundle-replay.md).
That fatal exception occurred after a place suggestion was selected.
Maps368 uses the qualified [Framework367](timing-logger367-framework-build.md),
which adds that class while preserving all 2,075 existing classes. Native351,
Loader357, the Maps and companion APKs, launcher, classifier and 600-second
observation contract remain pinned.

The generator is commit `93a869ae0`, dedicated replacement pin writer and
receipt wrapper `2463be949`, and independent prelaunch checker `c2349cac3`.
All generated source, binaries and complete evidence remain outside Git under
`/Users/alex/.local/state/vinix/android/`, except explicitly marked repository
paths below.

| Host input or result | SHA-256 |
| --- | --- |
| `timing-logger367-framework-build-2026-10-26/sha256.json` | `933baf6da303aebaf262e280e41769c89b61c2f050b481dd4075900a533ad23b` |
| Framework367 JAR | `fece4cb639fb8745557032f872d13d45767768656ae879f065324696bbf99694` |
| Native351 SO | `d3da7eefd58c8f1faf7a88dd0b6fa0839cebdba145d236bd5fe1ecc185e257a1` |
| Loader357 | `42c7ac8a276a7eb72a3844e94e182aef8ad7df4c2f8f7313f7061527d077b908` |
| `maps368-generation-2026-10-26/sha256.json` | `9aaf171bc4abdab25cd9d050d2a150a0f53651949999c74c8449c64d36274bc4` |
| Generated `maps368-run.v` | `86ec91f319502155d42fc8a1080e0bbacc7affff7045d1167d4b4762569b2509` |
| Repository `build/android-maps/maps368-run-recorded` | `e0d5ad5d9a3bea10e1923544fb8a36cbfdfd106dca1b8ee43e02e519f4fce5d6` |
| `maps368-recorded-build-peer-audit-2026-10-26.json` | `e0ae5ac6c1e612d65e5fd229c562533666fa77426a035e7dea02e4de2fa87dc5` |
| `maps368-prelaunch-review-build-2026-10-26/sha256.json` | `74f4d4871d4c93a26a1aee9d6da6fd9fc479bb7a204c3430fd4ff1e5fb2a2760` |
| `maps368-prelaunch-recorded-build-peer-audit-2026-10-26.json` | `4c2ab30c5a81a854ebb2cdb81530ad7de4d4ae8c008273496464965f8f12edda` |
| `maps368-replacement-pins-2026-10-26.json` | `280aa28d9f240e489377b4f15c622f81a78d23d749a81b25ebb63136d8693b1a` |
| Repository `build/android-maps/maps368/launch-pins.json` | `4c54cf37544469cfe4b9f1abf0f52c02136bf4c5a336516d7fd0738aa3d4e41a` |
| `maps368-2026-10-26/prelaunch-sha256.json` | `81533173be550bc2d4bc491fd5c1ec8721ad48c82e86426c169de608ceb12ce1` |
| `maps368-prepare-receipt-2026-10-26/sha256.json` | `7e3b5a94147a683b29331a8357aee238c47c0906a00f58e09f946888736d58f1` |
| `maps368-check-receipt-2026-10-26/sha256.json` | `3a48d100b109104834393778e9210465d33ae474d14623df009c67980b4ec3ae` |
| `maps368-independent-prelaunch-review-2026-10-26.json` | `ce4ac895728e04c4cb46cc689c21c78b27aa9df720b9935741096d8477254430` |

The original complete290 checker independently passed all 21 files in both
the original and retained generation bundles, and all 297 files in the
prelaunch checker build. Independent recorded-build audits at
02:24:28–02:24:29 UTC on 2026-10-26 checked each exact 272-input live and
retained compiler closure, command statuses and unchanged source, compiler,
C compiler and binary identities. The runner build is retained in
`maps368-run-build-c-2026-10-26`; it intentionally has no outer build-directory
seal. The checker build and self-test exited 0. These host audits do not
establish an ART or Maps runtime pass.

The dedicated wrapper accepts only the six exact Native351/Framework367
replacement identities, filters the inherited trace and location environment
keys, and records the actual child status separately from collection.
Preparation ran 02:22:18–02:25:58 UTC on 2026-10-26, exit 0, with unchanged
inputs, 50 clean environment entries and no forbidden keys. It retained the
complete framework baseline chain, prepared the exact three-file overlay,
and preserved the five original base boot members.
The recorded launch gate ran 02:26:29–02:30:30 UTC, exit 0, with the same
environment filtering and unchanged input identities.

Independent actual prelaunch review ran 02:27:20–02:31:17 UTC, exit 0. It
requalified the complete Framework367/365/361/359/353 chain and Native351 and
Loader357, checked both complete typed prelaunch trees, and confirmed exactly
three changed runtime files out of 109, with all other 106 unchanged. Modes,
links, APKs, launcher, identity settings, classifier, the 600-second setting,
all five original base boot members and the final three-member overlay passed.
Its external command/status receipt is
`maps368-independent-prelaunch-review-2026-10-26-command.json`; its SHA-256 is
`62693e8340e268b6a53f338789db2133771eb1c6c19cc1e4a1d7c4e9e6474984`.
