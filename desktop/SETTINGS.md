# Settings

## Saved desktop preferences

All desktop preferences use **one file**, `/root/.vinix-desktop-settings`:
window-button side, taskbar grouping, taskbar clock format, seconds, date and
weekday, theme, system language, wallpaper colour and image, keyboard layouts,
and scale. It is a versioned, human-readable snapshot, for example:

```ini
version=1
scale=2
button_side=left
taskbar_mode=combined
theme=macos
language=ru
clock_24_hour=false
clock_show_seconds=false
clock_show_date=false
clock_show_weekday=false
wallpaper_color=4
wallpaper_image=2
keyboard_layouts=us,ru
keyboard_layout=ru
```

`scale` is `auto`, `1` (100%) or `2` (200%). The other choices are `right`/`left`,
`standard`/`combined` and `default`/`macos`. `language` is `en` (the default),
`ru` or `es`; see [the system language](#system-language) below. Clock choices are `true`/`false`;
all four default to `true`, preserving the historical 24-hour clock with
seconds, date and weekday when an older version-1 snapshot omits the new keys.
Wallpaper values are the same zero-based catalogue indices used by Settings;
image `-1` selects the colour. If an image is not available in the current
build, the renderer uses the saved colour instead. `keyboard_layouts` lists the
enabled input sources in Settings' order, using `us`, `ru`, `es`, `fr`, `de`
and `pt`, and `keyboard_layout` is the one typing uses; it must be among them.
A record with only `keyboard_layout` enables that layout beside `us`, and one
with only `keyboard_layouts` types with the first listed. Both default to `us`.

The compositor loads the snapshot before allocating its canvas or launching
applications. After accepting Settings changes and applying any scale change,
it atomically saves the **whole** snapshot. A theme-, clock- or wallpaper-only
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

To verify in QEMU, change each appearance option, switch the clock to 12-hour
time without seconds, hide the date or weekday, choose a wallpaper and switch
scale to 200%. Inspect `cat /root/.vinix-desktop-settings`, shut down cleanly,
and relaunch with the same volume. All choices should be restored. Change only
the theme, clock or wallpaper and repeat to verify the scale and other values
survive. Also check 100%, resetting the file, and migration from a legacy `2\n`
record.

## Date & Time

Select **Date & Time** to control the compact taskbar clock. **Time format**
switches between a 24-hour clock and a 12-hour clock with AM/PM. **Seconds** can
be shown or hidden independently. **Date line** independently controls the
calendar date and abbreviated weekday, so it can show `Thu 1 Jan`, `1 Jan`,
`Thu`, or nothing. These settings affect the taskbar clock only; the standalone
Clock application keeps its own full clock presentation.

All four choices take effect immediately. The Settings pane is built with ui2
labels and buttons, and the Settings process returns the changed preference
state over the desktop application protocol. The compositor invalidates its
cached taskbar clock text and the next frame uses the new format. The choices
are part of the same atomic preference snapshot described above, so they
survive restart and older version-1 files continue to use the old full clock
default.

## Keyboard

Select **Keyboard** to choose input sources. **Input sources** turns layouts on
and off: English (US), Russian, Spanish, French, German and Portuguese
(Portugal). At least one stays on. **Typing with** picks the current one among
those that are on, and the pane shows what its top letter row, Option key and
accent keys type. **Ctrl-Space** moves to the next input source that is on and
briefly shows its name in the middle of the screen; with a single source, it
reaches applications as NUL (Ctrl-@) as before. The current source is saved
like every other preference, so a switch survives a restart.

While more than one input source is on, the taskbar shows the current one's
short name (`EN`, `RU`, ...) just left of the clock, as Windows' language bar
and the Mac input menu do. Clicking it lists the sources that are on, with a
tick beside the current one; picking one switches to it. **Keyboard settings**
at the bottom opens this pane. The badge sits against the clock's text in the
room its box leaves free, so the window buttons lose width only for a clock
wide enough to fill it, such as a 12-hour clock with seconds.

The layouts are the standard PC ones (xkb `ru`, `es`, `fr`, `de`, `pt`):
ЙЦУКЕН, QWERTZ, AZERTY and the Spanish and Portuguese QWERTY layouts, with
their dead accent keys. An accent key waits for the next letter (`´` then `e`
types `é`); Space or the same accent key again types the accent itself, and
Backspace cancels it. **Option (Alt)** types the characters printed on the
right of the keycaps, which PC keyboards type with AltGr: `@ € { [ ] } \ ~ | µ
² ³` on German, `` ~ # { [ | ` \ ^ @ ] } € ¤ `` on French, `\ | @ # ~ ¬ € [ ] { }` on
Spanish and `@ £ § { [ ] } € ¨ \` on Portuguese. The ISO key between left
Shift and Z types `<` and `>` (and `|` with Option on German).

Shortcuts do not move with the layout. Ctrl, Cmd and Option chords a layout has
no character for still name the key printed on a US keyboard, so Ctrl-C,
Cmd-W, Cmd-Tab and Alt-b keep working while typing Russian. DOOM and the nested
Vinix in QEMU receive the US keys whatever the input source, because game
controls and a virtual machine's own keyboard layout are positional.

### How it works

The console keyboard drivers still speak the US layout. `keyboard_layout.v`
re-types each read before anything else in the compositor sees it, the way an
X server's keymap turns keycodes into characters: every printable US byte names
a key and a Shift level, and the layout's table says what that key types. The
result reaches the Start menu, Quick Launch and applications as UTF-8. Escape
sequences pass through untouched, including one a short read split in two.
`ESC [` is both Option-`[` and the start of every CSI, so for Spanish and
Portuguese it is decided by the byte that follows, waiting at most one frame.

The kernel gives the desktop what the US byte stream would otherwise lose:
Option as an escape before the key on every keyboard (the Apple SPI keyboard
already sent it), Ctrl-Space as NUL, and the ISO key as `§` and `±`, which is
what Apple's US layout prints on it. It also answers the Linux `KDGETLED`
ioctl on the console. The US drivers apply Caps Lock only to US letters, so the
desktop asks for Caps Lock when a key is a letter in just one of the two
layouts, such as `ж` on the US `;` key or `,` on the French US-`m` key.

The desktop font carries the Latin-1 and Russian letters, `€`, `№` and `Œ œ Ÿ`
(`desktop/tools/genfont.py`). Terminal keeps one Unicode character per cell,
the editor edits UTF-8 by character, and hosted X11 applications receive
non-ASCII characters through a keysym borrowed for them.

Two limits remain. Apple's ISO keyboards report the key left of 1 and the key
left of Z the other way round from PC keyboards, as Linux `hid_apple` does
without `iso_layout`, so on those keyboards the two keys' characters are
swapped. And because Option and Alt are the same byte, Option chords that a
layout gives a character no longer reach applications as Meta (Alt-q, for
example, types `@` in German).

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

`keyboard_layout.v` owns the layout tables, dead keys, the typing
translation and the taskbar's input menu, and `settings_keyboard.v` the
Keyboard pane; the input-source names and preference codes are in
`settings_model.v`.
`settings_app.v` implements `NativeApp`; its categories and controls are ui2
elements (`ui2.view`, `ui2.label`, `ui2.button` and friends). `app.v` registers
the launcher, and `settings_model.v` holds the shared preference data while
`settings.v` holds the themes. `preferences.v` owns the complete file schema and
`preferences.c.v` its vlib file I/O, durability bridge and legacy migration.
`scale.v` owns the requested/applied integer scale and default policy.
`scale_wm.v` swaps the compositor's logical canvas between physical size and
half size, remaps window/pointer positions and invalidates stale hit targets.
`framebuffer.v` keeps its existing 100% fast path and expands the half-size
canvas at 200%. `clock.v` formats the taskbar clock according to the saved clock
preferences; `app_process.v` carries those preferences between the separate
Settings process and the compositor.

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
targets, MacBook/low-density defaults, odd-size logical extents, taskbar clock
format/seconds/date/weekday, explicit brightness writes, stale brightness hit
targets, unknown readback, failed writes, category switching, Wi-Fi radio and
scan actions, network sorting, refresh and narrow layouts. The client tests
cover strict snapshots and ioctl records, arithmetic and parser limits,
permissions, offline and missing devices, short writes, bounded interruptions,
exact descriptor cleanup, and a round-trip with the actual **V kernel backlight
core**. The POSIX tests exercise real files, shared mapping, directories,
`/dev/null`, monotonic clocks and a PTY, including restoration of both terminal
attributes and descriptor flags. Preference tests also run with `CLIENTS_ONLY=1`
and use temporary homes, never `/root`. They cover every saved field, both
scale overrides, auto-scale preservation, defaults, strict bounded parsing,
legacy migration and precedence, commit-before-save ordering, atomic
replacement through `os.File`, failed saves and cleanup, and pre-read rejection
of existing FIFOs and symlinks. They also check that a dangling unified-file
symlink does not trigger legacy migration and that a legacy directory is not
removed. The full UI suite additionally exercises actual Settings actions,
clock formatting and date-line combinations, application-protocol state, and
compositor scale application before saving and restoring the complete snapshot.

Desktop scaling is independent of the DCP backlight transport and never changes
the status of physical brightness adjustment.

## System language

Settings → Language chooses the language of the desktop and of the Vinix
applications it runs: English, Russian (Русский) or Spanish (Español). Each is
listed in its own name. The choice takes effect on the next frame everywhere,
including windows that are already open, and is saved as `language=` above.
Applications that are not part of Vinix (Firefox, LibreOffice, Wine...) choose
their language themselves.

Every string the desktop shows is looked up by key with `tr()`
([translations.v](translations.v)) from `translations/<code>.tr`, in the
format of V's `i18n` module. See [translations/README.md](translations/README.md)
for the format and for adding a language. Window and application titles stay
English internally, since the window manager identifies windows by them, and
are translated only where they are shown.

The native applications run as separate processes, so the language is part of
the settings every application request carries (`app_process.v`), the same way
the clock and theme preferences are.
