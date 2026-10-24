# Maps interaction driver

The driver sends QMP input and captures a 1024×768 Maps guest. Its white/black
onboarding and cyan map pixel probes choose when to interact; retained screenshots
need visual review. A matching probe does not qualify Maps functionality.

Build and run from the repository root:

```sh
v -nocache -cc cc -o build/android-maps/maps-interact-bounded tests/native-android-ws/maps-interact.v
build/android-maps/maps-interact-bounded /external/guest-run onboarding
build/android-maps/maps-interact-bounded /external/guest-run map
build/android-maps/maps-interact-bounded /external/guest-run capture after-skip
build/android-maps/maps-interact-bounded /external/guest-run input click 556 134
```

The guest run directory supplies `serial.log` and `qmp.sock`; `build/android-run`
must exist. Screen waits allow 600 seconds. Each input or screenshot subprocess
has a monotonic 30-second deadline, fair draining of both output pipes to separate
files, and kill/wait cleanup. `interaction.log` records command boundaries, output
paths, exit status and timeout state. Deadline, command failure or capped residual
output draining fails the action.

The controlled V fixture runs without a guest or QMP server:

```sh
v -nocache -cc cc -o build/android-maps/maps-interact-check tests/native-android-ws/maps-interact-check.v
build/android-maps/maps-interact-check build/android-maps/maps-interact-bounded /external/fresh-driver-check
```

Two runs passed exact preservation of 262,155 bytes including binary tails on
each stream, exit-7 propagation, and termination/reaping of a hung command:

| External evidence directory under `/Users/alex/.local/state/vinix/android/` | Flood / failure / timeout (ms) | `sha256.json` SHA256 |
| --- | --- | --- |
| `maps-interact-bounded-2026-10-24` | 551 / 22 / 30019 | `9a6f6ab0bcca8da2a15c9856bfb6f923295c8be21390ef7566487fc11561b17d` |
| `maps-interact-root-check-2026-10-24` | 261 / 21 / 30028 | `dfb107549a752c8b6bc6aea4ad2b6b249c09ede174014374a64524ed0b112c4c` |

Source base: `94decdcab3cdee19099dcdbbca4babff9abac5e4` plus the bounded driver
change. Both directories retain complete tested driver/checker source snapshots,
binaries, raw fixture logs, and an original-to-bounded `source/maps-interact.diff`
(SHA256 `42e5d8fb829bb469f1184eff7d6ae025c73aea06a3773d4834e8f1b706f252dd`).
Each inventory pins all 25 evidence files; its own digest is pinned above.
The original script and `build/android-maps/maps-interact` binary used by
Maps250 remain preserved under the sibling `maps250-251-2026-10-24/inputs/`.
These fixture results qualify subprocess handling;
they do not qualify the screenshot probes or a complete Maps workflow.
