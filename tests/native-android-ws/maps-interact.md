# Maps interaction driver

The driver sends QMP input and captures a 1024×768 Maps guest. Its white/black
onboarding and cyan map pixel probes choose when to interact; retained screenshots
need visual review. A matching probe does not qualify Maps functionality.

Build and run from the repository root:

```sh
v -nocache -cc cc -o build/android-maps/maps-interact-bounded tests/native-android-ws/maps-interact.v
build/android-maps/maps-interact-bounded --self-test
build/android-maps/maps-interact-bounded /external/guest-run capture before-skip
build/android-maps/maps-interact-bounded /external/guest-run onboarding --client-rect 171 94 480 640
build/android-maps/maps-interact-bounded /external/guest-run map
build/android-maps/maps-interact-bounded /external/guest-run capture after-skip
build/android-maps/maps-interact-bounded /external/guest-run input click 575 148
```

Broker-launched Maps keeps runtime output in its private guest log, so its
`ANDROID-WS-READY` marker does not appear in host `serial.log`. Select
`--screen-only` explicitly for these waits:

```sh
build/android-maps/maps-interact-bounded /external/guest-run onboarding --client-rect 198 95 480 640 --screen-only
build/android-maps/maps-interact-bounded /external/guest-run map --screen-only
```

This mode requires the QMP endpoint and a matching screenshot probe, and rejects
any app-exit marker observed in UART. It does not claim runtime readiness or read
private logs. The default still requires the UART readiness marker as well as the
pixel probe. Both modes retain screenshots for visual review and log the selected
readiness mode. The map probe retains its original fixed screen regions.

`onboarding` requires the current client rectangle measured from the screenshot:
the left/top content origin and its visible width/height, excluding the window
frame and title bar. The example rectangle maps Skip's native `(404,54)` point
to screen `(575,148)`; replace it with the actual current rectangle. Desktop
windows cascade and can move or resize, so onboarding no longer assumes a fixed
screen position. All four values must be unsigned decimal integers, the dimensions
must be positive, and the rectangle must fit within the 1024×768 screenshot.
The driver transforms both onboarding probes and Skip into that rectangle and
records the selected geometry before waiting. Keep the window in place until the
click completes. `map`, `capture` and direct `input` retain their existing behavior;
the map probe still uses its original fixed screen regions.

The selftest checks rectangle rejection, translated and scaled click coordinates,
synthetic onboarding probes at several sizes, rejection of the stale probe
position, explicit readiness selection, missing QMP and observed app exits. It
needs no guest or QMP server.

The rectangle change (source base `f30d5acaf`, driver source SHA-256
`c7c6a4766bd9754c499d50a610b33b418940f68a513fcdf742ab8b61455d7d9f`)
passed the selftest and a real missing-rectangle CLI rejection. The bounded
production build peaked at 209,469,440 bytes RSS; selftest peaked at 12,140,544
bytes, both with zero swaps. Sources, executable, commands and logs remain at
`/Users/alex/.local/state/vinix/android/maps-interact-client-rect-2026-10-27-r1`;
its `sha256.txt` digest is
`585631000e1f4d4674331425cef0d455681860cf20dc0da2e8d139facd830213`.
These checks qualify geometry and parsing; no guest interaction was performed.

The guest run directory supplies `serial.log` and `qmp.sock`; `build/android-run`
must exist. Screen waits allow 600 seconds. Each input or screenshot subprocess
has a monotonic 30-second deadline, fair draining of both output pipes to separate
files, and kill/wait cleanup. `interaction.log` records command boundaries, output
paths, exit status and timeout state. Deadline, command failure or capped residual
output draining fails the action.

Command filenames include the driver PID, wall-clock nanoseconds and monotonic
time, and existing output paths are rejected. Darwin's process-relative monotonic
time alone can repeat across driver invocations and overwrite earlier streams.

The controlled V fixture runs without a guest or QMP server:

```sh
v -nocache -cc cc -o build/android-maps/maps-interact-check tests/native-android-ws/maps-interact-check.v
build/android-maps/maps-interact-check build/android-maps/maps-interact-bounded /external/fresh-driver-check
```

The fixture also supplies synthetic screenshots through a controlled command and
checks onboarding's transformed click plus map presentation without a UART
readiness marker. Add `--screen-only` to the checker invocation to run only these
two cases, without the output-flood and 30-second timeout regressions.

The screen-only change (base `d605dcda9`, driver source SHA-256
`b789c06739ce1ccd3f60b09a54552963e172c95ddfd5ca45770be041e71aef11`)
passed the selftest and both controlled screenshot cases. Sequential driver and
checker builds each stayed below 210 MB RSS; checks stayed below 13 MB, all with
zero swaps. Complete inputs, commands and results remain at
`/Users/alex/.local/state/vinix/android/maps-interact-screen-only-2026-10-27-r1`;
`sha256.txt` has digest
`2014f629db01ce23de5cead33883b7b9a1a267b1aae01a54925d27e993737eca`.
No live guest or QMP server was used for these checks.

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

Source revision `1114bb985ba4d3897e44b500e8e68bff5cbf8e19` fixes filename
collisions. The extended fixture passed 32 separate driver invocations into one
run directory, preserving
all 64 unique stdout/stderr streams and their tokens. Exact binary flood
preservation, exit-7 propagation and hung-command termination/reaping also passed
(85 / 26 / 30024 ms). Complete tested sources, binaries, compiler, raw logs and
commands recorded after execution are retained at
`/Users/alex/.local/state/vinix/android/maps-interact-unique258-2026-10-24`.
The 99-entry `sha256.json` SHA256 is
`ccf1c4eeff9011d560bef1bfc1e63929f78f7169d2ac697e98459a8975fb5d95`.

A read-only audit found no repeated command stream paths among Maps256's
22 commands. Maps257 reused `command-37333` for its `search-ready` and
`paris-query` captures: the earlier capture's stdout/stderr files were overwritten.
Its original interaction timeline and separate screenshots remain available.
Both historical runs retain their original frozen driver and artifacts.
