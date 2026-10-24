# Maps250/251 runtime comparison

Source base: `bdb9b81703656ca7885cb87ece2e967ed92d1795`, with the exact
compiled Compound247 worktree recorded by 125 framework and 83 native source
snapshots in the evidence bundle. Both runs use the same signed, unchanged
Maps `26.42.01.997557324`, Play Services and Play Store APKs.
The native build has frozen sources but no original command-output receipt.

| Run | Observed behavior | Original result |
| --- | --- | --- |
| Maps250 | Skip leaves onboarding and presents a detailed North America map, visually reviewed in retained `map.png`. The app remains running through the configured 180 seconds. | `startup_failed`: logged missing-class diagnostics; `process_exited=false`, native backend and Maps observed. |
| Maps251 | Real/effective/saved Unix UID and GID are 10000, supplementary groups and effective capabilities are empty, root regain is denied and data/home write probes pass. The original launcher then reports `Operation not permitted` before ART starts. | `startup_failed`, exit 1, native backend not observed. |

Search did not succeed: the first Paris input reached a blank search screen;
the retry occurred after QEMU stopped. Chips and search results are unqualified.
Maps250's packet capture is truncated because the host ran out of disk space.
The retained harness notes are labeled tool-output excerpts, not a continuous
stdout transcript. Neither run has an automatic functional pass.

Maps250's actual runtime archive contains 106 regular files, including 51 hidden
files; only the framework jar and native library differ from the original
image. Maps251 preserves all those bytes under the documented launcher/data
path mapping and adds its credential wrapper. Actual archive readback rejects
AppleDouble entries. The UID fixture also changes data permissions and does
not qualify production app isolation or notification behavior.

Complete ordinary raw outputs, screenshots, APKs, source/helper/config inputs,
staged payloads and post-run private boot/firmware state are retained outside
Git using independent APFS clones:

`/Users/alex/.local/state/vinix/android/maps250-251-2026-10-24`

The pinned `sha256.json` checksum is
`3083491f7d8046ea43cc14fa72afaffa611c2522e5ca479abb126cb0d26d7e3e`.
Maps250 inputs were frozen after its preflight began; Maps251 inputs were
frozen before launch. The copied boot media and UEFI variables are explicitly
post-run state. Closed QMP sockets are recorded as ephemeral endpoints.

Audit with `v -cc cc -cflags -O2 run tests/native-android-ws/maps-runtime-evidence.v check
/Users/alex/.local/state/vinix/android/maps250-251-2026-10-24
3083491f7d8046ea43cc14fa72afaffa611c2522e5ca479abb126cb0d26d7e3e`.
The checker verifies every retained file and independently extracts both
retained images to compare the actual runtime payloads, including hidden files.
Use optimization through `-cflags -O2`; this checkout's `-prod` removes assertions.
The earlier `-prod` audit runs did not validate assertions and are not counted.
Both maintained validation tools now refuse a `-prod` build with exit 2.

The assertion-enabled complete audit passed. The negative runner supplied the
authentic pinned manifest with all execution evidence omitted and verified the
expected 0-versus-288 inventory assertion. Both `-prod` guards returned exit 2.
Final validation receipts, including checker binary/source and output hashes:

| Receipt | SHA-256 |
| --- | --- |
| `/Users/alex/.local/state/vinix/android/maps250-251-2026-10-24-audit-checks/full-receipt.json` | `783f0b461952424cfbaf07088ccdb52242136be2637b6cabc72eabb316b8db3e` |
| `/Users/alex/.local/state/vinix/android/maps250-251-2026-10-24-negative-final-assertions/receipt.json` | `439f0def4ba7448aefc47764f34e1c2b66f0b4713bc9465543a30afb171e66c4` |

The audit directory also retains the initial manifests and the failed source
count check; only the archived auditor source changed during resealing.
