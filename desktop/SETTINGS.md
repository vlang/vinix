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

`settings.v` implements `HostedApp`; `app.v` registers the launcher.
`backlight_client.v` owns parsing, native `BacklightState`/`BacklightResult`,
percentage calculations and bounded command I/O. `device_io.v` is the V
interface used by both the production POSIX backend (`platform.c.v`) and
V test doubles. There are no handwritten C client or test files.

Dynamic labels are cached and replaced only when readback changes. Disabled
controls use `enabled=false`; event handling independently rechecks availability.

```sh
V=/path/to/v sh tools/apple-backlight/test.sh
V=/path/to/v sh desktop/tools/test-settings.sh
# Without ui2, explicitly select only the client and POSIX tests:
CLIENTS_ONLY=1 V=/path/to/v sh desktop/tools/test-settings.sh
```

The runner requires V and, for UI tests, `third_party/ui2`; it does not silently
skip missing dependencies. `VFLAGS` can select a compiler/backend or sanitizers.
The tests cover strict snapshots, arithmetic limits, permissions, offline and
missing devices, short writes, bounded interruptions, exact descriptor cleanup,
and a round-trip with the actual **V kernel backlight core**. Settings tests
cover explicit writes, stale hit targets, unknown readback, failed writes,
category switching, refresh and narrow layouts. The POSIX tests exercise real
files, shared mapping, directories, `/dev/null`, monotonic clocks and a PTY,
including restoration of both terminal attributes and descriptor flags.

Host tests and a complete native desktop build have been run. The ARM64 kernel
also passes V-to-C generation; a linked boot image and real M1 display behavior
still require validation. The DCP transport/backend is still missing: the port
to V does not make physical brightness adjustment operational.
