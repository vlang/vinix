# Settings / Display / Brightness

Open **Settings** from its wallpaper shortcut or taskbar launcher, then select
**Display**. The click-to-set bar has 5% steps; **- 5%** and **+ 5%** adjust the
current requested level (or the actual level before the first request).
**Refresh** rereads the device without changing anything. A visible Settings
window also refreshes at most once per second using the desktop's clock repaint.

The percentage is a linear position in the device's advertised writable nit
range: 0% selects `min_nits`, 100% selects `max_nits`. **0% does not turn off the
panel.** No M1 panel maximum is hardcoded, and there is no software-dimming
fallback. The requested and actual nit values are displayed separately;
`pending=1` is shown as pending, not as proof the display changed. An unknown
level is not silently replaced by a default: the bar can select an explicit
level, but relative +/- controls remain disabled until a level is known.

## Current hardware limitation

The experimental backlight core is not yet connected to a working DCP backend.
Consequently current Vinix boots do **not** create `/dev/apple-panel-bl`, and
Settings shows **Brightness driver not available** with disabled controls.
Adding this UI does not complete that driver integration. Do not enable the
experimental DCP boot option just to test the UI. See
[`../tools/apple-backlight/README.md`](../tools/apple-backlight/README.md) for
what the backend still needs.

The device is mode 0600. A process with read-only access can see the values but
cannot change them. Missing devices, permissions, offline state, malformed
responses and I/O failures are displayed; none causes a default brightness
write. Every action rereads status and bounds, including when an old hit target
was clicked after device loss. Writes are one whole decimal nit command; a
positive short write is an error and its suffix is never retried as a command.

## Implementation and tests

`settings.v` implements the existing `HostedApp` interface; `app.v` registers the
launcher. `backlight_client.h` is the header-only POSIX bridge, staged by the
existing `stage_app.py` and desktop build without additional build rules.
Dynamic labels are cached and replaced only when readback changes. The renderer
receives explicit `enabled=false` on disabled controls, and event handling also
checks availability independently of the last drawn frame.

Run from the repository root:

```sh
sh tools/apple-backlight/test.sh
sh desktop/tools/test-settings.sh
CC=clang CFLAGS='-O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer' \
    sh desktop/tools/test-settings.sh
# V UI tests additionally require V and the desktop's existing ui2 checkout:
REQUIRE_V_TESTS=1 V=/path/to/v sh desktop/tools/test-settings.sh
```

The C tests substitute POSIX operations, never access a real display, and include
an ABI round-trip with the actual kernel backlight core. The V tests inject a
fake device and exercise Display controls, explicit writes, stale hit targets,
missing/offline/read-only states, unknown readback, write errors and layout
bounds. The runner reports V tests as **SKIP**, or fails with `REQUIRE_V_TESTS=1`,
when their dependencies are absent; C test success is not a full desktop build.

Manual checks after building the desktop: open Settings in QEMU (disabled
brightness, no crash); maximise/restore it; open two Settings windows; test
read-only/offline/error states using a driver fixture. Physical changes and
firmware completion/readback must be tested on an M1 Air after backend
integration. Neither the UI nor the driver has been hardware-validated here.
