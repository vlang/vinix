# Native iOS UI host tests

The three commands use V directly:

```sh
./tests/ios/uikit
./tests/ios/game2048 --cycles 32
./tests/ios/desktop --app calculator --desktop build/vinix-desktop
./tests/ios/desktop --app 2048 --desktop build/vinix-desktop
```

UIKit retains the 27 calculator cases, resize bounds, keyboard check and 1,000
update cycles. The 2048 test retains the initial board, real swipe payloads,
0.32-second timer settlement, monotonic merge scores, alert handling and keyboard
arrow. Both execute the original Mach-O using `build/ios/run-ios-host`.

`iosui` owns the protocol pipes, copied state and decoded trees. SDK spawn
actions inherit only the two private protocol descriptors, capture both
diagnostic streams concurrently and keep the leader identity reserved until
private process-group retirement and the sole reap. Reads and writes retain
ten-second inactivity deadlines. Interrupts preserve their exit status. The
decoder checks every length and UTF-8 string, caps nesting at 512 and rejects
trailing bytes. Diagnostic streams and desktop logs have a 32 MiB bound.

The desktop command builds the unchanged C guest init for static AArch64,
stages the desktop and iOS installation with symlinks preserved, and writes
native USTAR. It keeps an idle stdin pipe and ordered stdout/stderr log, waits
for readiness and uses the original QMP click/swipe coordinates, rounding and
sleep intervals. Logs and screenshots remain in `build/ios`. A private short
socket directory prevents collision and path-length failures. Cleanup sends
TERM and waits ten seconds before forced group retirement; all temporary files
are removed after the process owner returns.

Cold ARM, x86 and ASan/UBSan qualification:

```sh
v -cc clang -o /tmp/qualify-ios-ui tests/native-ios-ui/qualify.v
/tmp/qualify-ios-ui /path/to/v /new/evidence/arm arm
/tmp/qualify-ios-ui /path/to/v /new/evidence/x86 x86
/tmp/qualify-ios-ui /path/to/v /new/evidence/san san
```

Each profile builds the command, protocol/process fixture, existing QMP suite
and existing launcher/reader suite from cold sources. Tests cover every
truncated element prefix, Unicode, nesting, split reads, malformed replies,
large concurrent diagnostics, EOF, exit/error handling, descendants, signals,
100 EOF/spawn retirement cycles, exact descriptor/PID cleanup, actual Unix QMP
exchanges and static guest-init/USTAR staging. They also run both real host app
workflows. Desktop QMP qualification uses a controlled emulator process; it does
not establish a new Vinix guest/compositor result. The host runner is a retained
external input; the sanitizer profile instruments the V controller and fixtures.

The independently edited main iOS controller (`tests/ios/run.py`) is outside
this closure. No Python is executed by these commands or their qualification.
