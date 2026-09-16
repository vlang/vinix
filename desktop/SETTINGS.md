# Settings

## Saved desktop preferences

All desktop preferences use **one file**, `/root/.vinix-desktop-settings`:
window-button side, taskbar grouping, theme, wallpaper colour and image, and
scale. It is a versioned, human-readable snapshot, for example:

```ini
version=1
scale=2
button_side=left
taskbar_mode=combined
theme=macos
wallpaper_color=4
wallpaper_image=2
```

`scale` is `auto`, `1` (100%) or `2` (200%). The other choices are `right`/`left`,
`standard`/`combined` and `default`/`macos`. Wallpaper values are the same
zero-based catalogue indices used by Settings; image `-1` selects the colour.
If an image is not available in the current build, the renderer uses the saved
colour instead.

The compositor loads the snapshot before allocating its canvas or launching
applications. After accepting Settings changes and applying any scale change,
it atomically saves the **whole** snapshot. A theme-only or wallpaper-only
change is saved too and does not discard other preferences. Until scale has
actually been changed, saves retain `scale=auto`, so appearance changes do not
pin the current display's automatic scale. Unchanged frames, device refreshes,
and unapplied or rejected scale requests do not trigger saves.

Missing keys use their defaults and unknown keys are ignored. Missing,
unreadable, malformed, unsupported-version or oversized files fall back to the
default settings and geometry policy. Known keys may occur only once; loading
never evaluates shell commands. A normal first boot does not create a file.
Remove the file to reset all preferences, or edit it while the desktop is
stopped; the next successful save rewrites the complete supported snapshot.

The earlier `/root/.vinix-desktop-scale` format is migrated only when the unified
file is absent. The old file is removed **after** the new snapshot is saved and
synced. An existing unified file always takes precedence, even if damaged, so
an old scale cannot unexpectedly override a reset or corrupt configuration.
No new scale-only file is written.

File I/O uses V's standard library: `os.lstat` and `os.read_file` for loading,
`io.util.temp_file` for a mode-0600 sibling, `os.File.write_string` for saving,
and `os.rename_dir`/`os.rm` for publication and cleanup. The exact-destination
rename deliberately rejects a directory at the settings path. Writes are
unbuffered so errors are reported before publication. A small `fsync` bridge
remains because `os.File.flush()` only flushes stdio, not persistent storage;
it syncs the file before rename and flushes the directory update afterwards.
Vinix's existing file-fsync fallback handles unsupported directory syncing.
Failed writes leave the previous file intact; save failures are reported on
stderr without undoing live changes. The next settings change retries the
complete current state, rather than retrying every frame.

Loading checks file type and size before `os.read_file`, then checks the
returned length and validates the record. Existing symlinks, special files
and records over 4 KiB are rejected. These are configuration-file checks, not
a race-free sandbox: the settings file is in the desktop's own home and should
not be replaced or grown concurrently with startup. In particular, `read_file`
allocates for the file it reads; the size checks are not a hard allocation cap
under concurrent modification.

The file lives in the desktop's writable home, not `/etc` in the initramfs.
On the AArch64 QEMU desktop launcher, reuse the same persistent `/root` volume
(`boot-image/desktop-root.ext2`). `--no-persist` uses RAM and `--ephemeral`
removes its private volume on exit; neither preserves settings for the next
launch. Continue to shut down writable ext2 guests cleanly.

Brightness and Wi-Fi controls operate on devices; their live/pending readbacks,
scan results and battery measurements are not desktop preferences and are not
serialized or replayed at startup.

To verify in QEMU, change each appearance option, choose a wallpaper and switch
scale to 200%. Inspect `cat /root/.vinix-desktop-settings`, shut down cleanly,
and relaunch with the same volume. All choices should be restored. Change only
the theme or wallpaper and repeat to verify the scale and other values survive.
Also check 100%, resetting the file, and migration from a legacy `2\n` record.

## Wi-Fi

Select **Wi-Fi** to inspect `/dev/wlan0`. After the experimental Apple Wi-Fi
driver has been enabled with the exact kernel argument `vinix.apple_wifi=1` and
matching BCM4378 firmware has been loaded, Settings can turn the firmware radio
on or off, start an asynchronous scan, and list the networks found. Results are
shown strongest first with security, channel and RSSI. **Refresh** rereads the
driver without starting a scan.

The normal `desktop` deployment enables Wi-Fi without the other optional Apple
drivers; `desktop-drivers` enables them all. The desktop image includes
`wifi-ctl`.

Firmware is not included, but a package created with `tools/m1-wifi/package.py`
can be staged and loaded before the desktop starts by building with
`--wifi-bundle=/path/to/wifi-bundle` (or the `VINIX_WIFI_BUNDLE` environment
variable). Firmware packaging/manual loading and WPA2 credential entry remain
in `wifi-ctl`; selecting a network in Settings does not join it. The
device currently provides raw Ethernet rather than IPv4/IPv6 sockets, so a
successful association is not yet ordinary Internet connectivity. See
[`../tests/m1-wifi/README.md`](../tests/m1-wifi/README.md) for bring-up and
hardware limitations.

The Wi-Fi client validates the fixed-size ioctl responses, bounds SSIDs and the
network count, retries interrupted calls, and falls back to read-only access for
displaying state. Mutating controls require write access and re-read device
state immediately before acting, so stale buttons cannot mutate a device that
has since disappeared or changed state.

## Display

Open **Settings** from its wallpaper shortcut or the Start menu, then select
**Display**.

### Scale

Display scale has two integer choices: **100%** and **200%**. Changing it takes
effect immediately for the whole desktop. At 200%, the compositor lays the UI
out in half-size logical coordinates backed by a native-resolution canvas.
Geometry still expands each logical pixel into a 2x2 physical block, while
text uses dedicated 2x font masks so its antialiased edges remain one physical
pixel wide. Windows, icons, the cursor and hit targets therefore stay in one
coordinate space without sacrificing sharp type.

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

### Brightness

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

The real t8103 internal-panel backend is opt-in with `vinix.apple_dcp=1` (or the
deployment script's `--apple-dcp` switch). After its RTKit/IOMFB handshake,
Vinix creates `/dev/apple-panel-bl` and Settings enables these controls. Without
that option, on unsupported firmware/topology, or after a transport fault,
Settings shows **Brightness driver not available** with disabled controls. See
[`../tools/apple-backlight/README.md`](../tools/apple-backlight/README.md) for
the hardware scope and diagnostic boot messages.

The device is mode 0600. A process with read-only access can see the values but
cannot change them. Missing devices, permissions, offline state, malformed
responses and I/O failures are displayed; none causes a default brightness
write. Every action rereads status and bounds, including when an old hit target
was clicked after device loss. Writes are one whole decimal nit command; a
positive short write is an error and its suffix is never retried as a command.

## Implementation and tests

`settings_app.v` implements `NativeApp`; `app.v` registers the launcher, and
`settings_model.v` holds the shared preference data while `settings.v` holds
the themes. `preferences.v` owns the complete file schema and
`preferences.c.v` its vlib file I/O, durability bridge and legacy migration. `scale.v`
owns the requested/applied integer scale and default policy. `scale_wm.v` swaps
the compositor's logical canvas between physical size and half size, remaps
window/pointer positions and invalidates stale hit targets. `framebuffer.v`
keeps its existing 100% fast path and expands the half-size canvas at 200%.

`backlight_client.v` owns brightness parsing, native
`BacklightState`/`BacklightResult`, percentage calculations and bounded command
I/O. `device_io.v` is the V interface used by both the production POSIX backend
(`platform.c.v`) and V test doubles. `wifi_client.v` owns the Wi-Fi ioctl parser
and actions, while `settings_wifi.v` owns the corresponding pane. There are no
handwritten C desktop client or test files.

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
writes, category switching, Wi-Fi radio and scan actions, network sorting,
refresh and narrow layouts. The client tests cover strict snapshots and ioctl
records, arithmetic and parser limits, permissions, offline and missing devices,
short writes, bounded interruptions, exact descriptor cleanup, and a round-trip
with the actual **V kernel backlight core**. The POSIX tests exercise real files,
shared mapping, directories, `/dev/null`, monotonic clocks and a PTY, including
restoration of both terminal attributes and descriptor flags. Preference tests
also run with `CLIENTS_ONLY=1` and use temporary homes, never `/root`. They cover
every saved field, both scale overrides, auto-scale preservation, defaults,
strict bounded parsing, legacy migration and precedence, commit-before-save
ordering, atomic replacement through `os.File`, failed saves and cleanup, and
pre-read rejection of existing FIFOs and symlinks. They also check that a
dangling unified-file symlink does not trigger legacy migration and that a
legacy directory is not removed. The full UI suite additionally exercises
actual Settings actions and compositor
scale application before saving and restoring the complete snapshot.

Desktop scaling is independent of the DCP backlight transport and never changes
the status of physical brightness adjustment.
