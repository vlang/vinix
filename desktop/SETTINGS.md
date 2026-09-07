# Settings / Display

Open **Settings** from its wallpaper shortcut or taskbar launcher, then select
**Display**.

## Scale

Display scale has two integer choices: **100%** and **200%**. Changing it takes
effect immediately for the whole desktop. At 200%, the compositor lays the UI
out on a half-size logical canvas and the framebuffer presenter expands each
logical pixel to a 2x2 physical block. Windows, text, icons, the cursor and hit
targets therefore stay in one coordinate space instead of carrying separate
per-widget scale factors.

Vinix's simple framebuffer currently reports pixel geometry but no useful panel
DPI or model name to desktop userspace. Native Retina MacBook modes are therefore
treated as HiDPI by geometry: framebuffers at least **2300x1400** default to
200%; lower modes default to 100%. This includes current native MacBook modes
while leaving the normal QEMU and low-density modes at 100%. The setting can
always be changed manually.

When scale changes, pointer and window positions are mapped to the new logical
screen, maximized windows are refit, and old hit targets are discarded before
the next frame. Oversized windows are kept at the top-left so Settings remains
reachable even after manually selecting 200% on a small framebuffer.

## Brightness

The click-to-set bar has 5% steps; **- 5%** and **+ 5%** adjust the current
requested level (or the actual level before the first request). **Refresh**
rereads the device without changing anything. A visible Settings window also
refreshes at most once per second using the desktop's clock repaint.

The percentage is a linear position in the device's advertised writable nit
range: 0% selects `min_nits`, 100% selects `max_nits`. **0% does not turn off the
panel.** No M1 panel maximum is hardcoded, and there is no software-dimming
fallback. The requested and actual nit values are displayed separately;
`pending=1` is shown as pending, not as proof the display changed. An unknown
level is not silently replaced by a default: the bar can select an explicit
level, but relative +/- controls remain disabled until a level is known.

### Current hardware limitation

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

`settings.v` implements `HostedApp`; `app.v` registers the launcher. `scale.v`
owns the requested/applied integer scale and default policy. `scale_wm.v` swaps
the compositor's logical canvas between physical size and half size, remaps
window/pointer positions and invalidates stale hit targets. `framebuffer.v`
keeps its existing 100% fast path and expands the half-size canvas at 200%.

`backlight_client.v` owns brightness parsing, native
`BacklightState`/`BacklightResult`, percentage calculations and bounded command
I/O. `device_io.v` is the V interface used by both the production POSIX backend
(`platform.c.v`) and V test doubles. There are no handwritten C client or test
files.

Dynamic brightness labels are cached and replaced only when readback changes.
Disabled controls use `enabled=false`; event handling independently rechecks
availability. Scale controls are desktop-wide globals, so multiple Settings
windows display and update the same requested value.

```sh
V=/path/to/v sh tools/apple-backlight/test.sh
V=/path/to/v sh desktop/tools/test-settings.sh
# Without ui2, explicitly select only the client and POSIX tests:
CLIENTS_ONLY=1 V=/path/to/v sh desktop/tools/test-settings.sh
```

The runner requires V and, for UI tests, `third_party/ui2`; it does not silently
skip missing dependencies. `VFLAGS` can select the compiler/backend or
sanitizers. Settings regression cases cover both scale choices, stale scale hit
targets, MacBook/low-density defaults, odd-size logical extents, explicit
brightness writes, stale brightness hit targets, unknown readback, failed
writes, category switching, refresh and narrow layouts. The client tests cover
strict snapshots, arithmetic limits, permissions, offline and missing devices,
short writes, bounded interruptions, exact descriptor cleanup, and a round-trip
with the actual **V kernel backlight core**. The POSIX tests exercise real files,
shared mapping, directories, `/dev/null`, monotonic clocks and a PTY, including
restoration of both terminal attributes and descriptor flags.

The DCP transport/backend is still missing: desktop scaling does not change the
status of physical brightness adjustment.
