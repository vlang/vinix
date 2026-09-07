# vinix-desktop

A small desktop environment for Vinix, written in V and built on
[ui2](https://github.com/vlang/ui2)'s declarative element tree.

![The desktop running under QEMU](screenshot.png)

It maps `/dev/fb0`, reads the pointer from `/dev/pointer` and the keyboard from
its controlling terminal, and composes every frame itself without a display
server or toolkit underneath it. The normal binary is entirely software. An
M1 image that contains the Asahi Mesa runtime also carries a GPU-enabled binary
which uses AGX to scale and present that canvas when `/dev/dri/renderD128`
exists, with an automatic fallback to the static software binary.

What it does:

- a wallpaper, and a taskbar along the bottom listing every open window
- a clock in the bottom right corner — time above, date below
- windows with a title bar, a close, a maximise/restore and a minimise button
- dragging a window by its title bar, clicking one to bring it to the front
- a **New window** button, so the taskbar list can be seen growing and shrinking
- **shortcuts down the left edge of the wallpaper**, and matching taskbar
  launchers, for every application the desktop can open
- a **file browser** over the real filesystem: directories first, sizes, and a
  way back up
- an **activity monitor** listing every process on the machine with the share
  of a CPU and of RAM it is using, updated once a second
- a **text editor** for plain files, with an editable path, open/save controls,
  cursor navigation and keyboard shortcuts
- a **calendar** with month navigation, date selection and a jump back to today
- a **clock** with a large local-time display and a tenth-second stopwatch
- a **settings application**: window button side, taskbar style, theme,
  wallpaper, display, battery and experimental M1 Wi-Fi controls
- **native ui2 applications**: every Files, Calculator, Terminal, Settings and
  utility window is backed by its own OS process, PID and memory accounting
- **Cmd-Tab**, which switches windows on a tap and shows all of them in the
  middle of the screen when it is held

Keys: `Ctrl-Q` leaves the desktop, `Ctrl-N` opens a window, `Ctrl-K` the first
application. They are chords rather than bare letters because they fire
whenever no application holds the keyboard, which on a machine whose pointer
does not work is most of the time -- and `q` meaning "close the desktop" makes
typing any word with a q in it drop the user back to the console.

## How it fits together

    main.v         the event loop: poll input, rebuild, render, present
    wm.v           the window manager — window list, the ui2 tree, hit routing
    window.v       the Window model and the pages windows show
    app.v          native application metadata and factories
    app_process.v  compositor/client IPC, UI-tree encoding and lifecycle
    files.v        the file browser
    activity.v     the activity monitor, over /dev/processes
    editor.v       the plain-text editor and its keyboard editing model
    calendar.v     Gregorian month layout and the calendar application
    clock_app.v    the large clock and stopwatch application
    switcher.v     Cmd-Tab: the session it opens and the panel it shows
    settings.v     preferences shared by the desktop and Settings application
    settings_app.v the settings application
    settings_wifi.v the Wi-Fi pane: radio control, scan and network list
    wallpaper.v    loading and scaling a wallpaper photograph
    backlight_client.v / battery_client.v / wifi_client.v  V device clients
    platform.c.v   V POSIX bindings, terminal state, mmap, clocks and directories
    render.v       a ui2 backend that draws an element tree into a framebuffer
    canvas.v       the software renderer: spans, rounded rects, clipping, blend
    font.v         text, from the coverage atlases in font_data.v
    framebuffer.v  /dev/fb0: geometry over ioctl, pixels over mmap
    gpu_present.v / gpu_present_egl.c  optional M1 EGL/GLES presenter
    input.v        /dev/pointer, and the terminal in raw mode
    clock.v        CLOCK_REALTIME and the calendar arithmetic on top of it
    theme.v        every colour and measurement in one place

The interesting part is the split between `wm.v` and `render.v`. The window
manager never draws: it describes the whole screen as a `ui2.Element` tree —
views, labels and buttons with frames, box styles and text styles — and hands
that to the renderer. The renderer paints the tree and, in the same walk,
records every clickable and draggable element's absolute rectangle. Clicks are
routed by hit-testing those records. So what is on screen and what responds to
the pointer come from one description and cannot drift apart.

ui2's element tree is platform independent, which is what makes this possible:
the target has no `gg` or Sokol, so `-d ui2_headless` compiles ui2's
declarative core without its renderer, and this program supplies the renderer
instead. The optional EGL path is a presenter around that renderer rather than
a replacement for its element-tree rasterizer.

Two conventions extend ui2 for this backend, both documented at the top of
`render.v`: an `image_path` of `builtin:<name>` draws a vector glyph the
renderer carries itself, since the target has no image files; and a rounded
view at the top level of the tree is a floating surface, so it gets a drop
shadow and a hairline edge.

## Native ui2 applications

A ui2 application normally calls `run_qml`, which opens a platform window and
blocks until it closes. Here the desktop *is* the window system, but the app is
still a separate process. The compositor starts `vinix-files`,
`vinix-calculator`, `vinix-terminal`, and the other installed app names with
two private pipes. The app builds a ui2 element tree and sends the
renderer-relevant fields to the compositor; click actions and keyboard input
travel back over the request pipe. Because the compositor supplies the content
size, an app re-lays-out when its window is resized or maximised.

Only the compositor opens the framebuffer, pointer and raw keyboard. All
unrelated descriptors are closed before an app is exec'd, so the app processes
are ordinary display clients rather than competing display owners. Closing a
window asks its process to exit and reaps it; leaving the desktop closes every
remaining client. Settings returns its synchronized preference state with each
response, allowing theme, wallpaper and scale changes to cross the boundary
immediately.

The app names are relative symlinks to one static multicall executable. This
keeps the initramfs small, while each exec creates an independent address space
and Vinix records the per-app exec path as its process name. Consequently
`/dev/processes` reports truthful CPU and mapped-memory values for every app.

The applications are ui2's own examples, and they are not copied into this
repository. `tools/stage_app.py` takes each example's source straight from the
ui2 checkout at build time and removes exactly one thing: its `fn main()`,
which exists to open a platform window and block. Everything the application
is — its model, its methods, its QML document — compiles unmodified, so what
runs on Vinix is the example rather than a retelling of it. The multicall
executable selects the requested app factory before opening any display device.

The window manager owns four action prefixes — `taskbar.`, `task.`, `win.` and
`shortcut.` — and treats everything else as an application's, routing it to
whichever window the click landed in. That is also what decides it between two
open copies of the same application. Because the rule is "not mine", an
application names its events whatever suits it: ui2's `__qml_...` and the file
browser's `files.row.3` both arrive without the window manager parsing either.

Add an application by adding an `AppFactory` to `available_apps` in `app.v`;
it then has a wallpaper shortcut and a taskbar launcher. A ui2 example also
needs its directory listed in `build-desktop-aarch64.sh` so the staging step
compiles it in.

Firefox is the deliberately different case. It is an upstream X11/GTK
application rather than a native ui2 client. Its
`AppFactory` names `/usr/bin/run-firefox` as an exclusive command. At a frame
boundary the desktop restores the console and closes its framebuffer and
pointer descriptors, waits while Xorg and Firefox own them, then reopens the
devices and redraws when Firefox exits. This keeps GTK confined to Firefox's
packaged userspace runtime; `vinix-desktop` itself does not link or implement
GTK. The small `/usr/bin/vinix-xinput` bridge translates Vinix's native pointer
packets and console keyboard bytes into ordinary X11 input, avoiding an evdev
or udev compatibility layer. The desktop image builder refreshes this bridge,
the direct `startx` launcher, and Firefox's Vinix policy files even when its
base userland image is older. It refuses to publish an image with an incomplete
Firefox/Xorg runtime; the native error window remains as a runtime fallback.
Firefox's upstream graphics and GTK diagnostics are written to
`/var/log/firefox.log`. On an M1 image with the Asahi runtime, Xorg enables
glamor/DRI3 and Firefox enables WebRender over X11 EGL. Without the render node,
or with `VINIX_FORCE_SOFTWARE_GL=1`, both retain their software paths. Because
the display is still a firmware framebuffer rather than a DCP/KMS scanout,
hardware-rendered client buffers ultimately make one CPU-visible copy to
`/dev/fb0`.

## The file browser

`files.v` is not a ui2 example but Vinix's own, and it reads a real
filesystem — the listing comes from the kernel's `getdents64` through musl's
`readdir`, and each entry is `stat`ed for its size. It satisfies the same
`NativeApp` interface in its client process, so the window manager's protocol
proxy knows nothing about files.

Directories sort before files and both sort by name, because the order a
directory is read in is whatever the filesystem happens to store. Clicking a
directory descends, `Up` goes back, and `-`/`+` scroll when there are more
entries than the window has room for.

The image carries the desktop's own source at `/root/desktop`, so there is
something real to browse and so the machine holds the code it is running.

## Desktop utilities

The text editor reads and writes real files. Click the path in its toolbar to
edit it, press Return or **Open** to load it, and click the document to send
typing back to the page. The usual `Ctrl-N`, `Ctrl-O` and `Ctrl-S` shortcuts
create, open and save; arrows, Home, End, Backspace and Delete move or edit at
the insertion point. Files are limited to 64 KB so one accidental open cannot
consume the desktop on a small system image. New documents default to
`/root/notes.txt`.

The calendar uses the same local offset as the taskbar clock and lays out a
full six-week Gregorian month. Its arrow buttons cross year boundaries, a day
can be selected for a full date in the footer, and **Today** returns to the
current month. The Clock expands the same local time into an across-the-room
display and adds a start/stop/reset stopwatch with tenth-second updates.

Utility windows are sized for the logical MacBook desktop rather than the old
1024×768 QEMU screenshot. Shortcuts fill the available height and flow into a
second column when needed; taskbar launchers retain their full labels when
there is room and shrink only far enough to preserve an open-window entry and
the clock.

## The activity monitor

`activity.v` lists every process on the machine with the share of one CPU and
of RAM it is using. Native apps such as Calculator and Text Editor appear as
ordinary kernel records with their own PID and measured CPU and RAM. It maps
their stable executable names (`vinix-calculator`, `vinix-editor`, and so on)
to the labels shown elsewhere in the desktop. Like the file browser it is
Vinix's own rather than a ui2 example, and like it, it reads the real system.

Vinix has no procfs, so this needed a kernel interface. `/dev/processes`
answers a read with one snapshot of the whole table — a short header, then a
fixed-size record per process — taken under the process table's own lock, so a
list cannot be half of one moment and half of the next. The kernel side is
`kernel/modules/dev/procdev/procdev.v`, and the two halves share an ABI that
`ProcessTable.version` exists to catch drift in.

Everything in a snapshot is a running total or an absolute quantity, never a
rate: the kernel has no idea what interval anyone cares about. `cpu_time_ns` is
nanoseconds this process' threads have spent on a CPU since it started, and
turning that into a percentage is the monitor's job — it keeps the previous
sample and divides the difference by the wall clock between the two. Which is
also why every process reads 0% for the first second a window is open, and why
a process that appears between two samples is not credited with what it did
before anyone was watching.

The kernel counts those nanoseconds in the scheduler, charging a thread's turn
to its process at the moment it is switched away; `dequeue_and_die` charges the
last one, so a process that runs briefly and exits does not report nothing at
all. Memory is the sum of a process' mapped ranges, which on this kernel is
also what it has resident — every mapping is pre-faulted when it is made, so
there is no second number to report.

Sampling is once a second, not once a frame. A CPU percentage taken over 16 ms
is mostly noise: a process either did or did not get a timeslice in that
window, so every figure would read 0% or 100%.

The list sorts by CPU, memory or name, and rows are shown with the basename of
the program. The kernel stores a process' name as the path it ran with its pid
appended, and a fork appends again — the shell is `/bin/busybox[2]` and a loop
it starts is `/bin/busybox[2][3]` — so the monitor strips those suffixes. Every
number in them is an ancestor's pid, and this process' own has a column.

## The window switcher

`Cmd-Tab` moves to the window under the one on top, and pressing it again goes
back — which is what a tap is for. Holding Cmd down instead asks "what else is
open?", and after 400 ms the desktop answers: a translucent panel in the middle
of the screen with a tile for every window, the selection moving along it on
each further Tab, `Shift` walking back, the arrows moving it too, and the
window it lands on raised when Cmd is let go. A minimised window is in the
panel like any other and comes back rather than being switched to invisibly. A
click on a tile picks it; a click anywhere else puts the panel away.

The delay is the whole of the design. A tap is a gesture people make without
looking, and flashing a panel up for a tenth of a second would only be noise;
a hold is a question, and deserves an answer.

A terminal has no way to say "Cmd", so the keyboard drivers say it for it and
the desktop reads three sequences out of the byte stream before anything else
sees them:

    \e[9;9u        Cmd-Tab
    \e[9;10u       Cmd-Shift-Tab
    \e[57444;1:3u  Cmd let go

The first two are the CSI-u encoding of Tab — the key's own code point, then 1
plus a mask of the modifiers held with it, where super is 8 and shift is 1 —
which is what a terminal that reports modified keys at all uses. The third has
no precedent to follow, because no terminal has ever had a reason to report a
modifier being released; it is the same encoding's left Super key with an event
type of 3, "released". A driver only sends it when a chord was sent while Cmd
was down, so a bare Cmd press still costs a shell nothing.

They are taken out of the stream ahead of the focused application, which is the
one place the desktop overrules whoever is typing: Cmd-Tab belongs to the window
manager on the machine this borrows the gesture from, and a terminal that
swallowed it would strand a keyboard-only session in one window. A sequence
split across two reads is held back rather than handed over in halves — but
only from the second byte on, since a lone escape is a key someone pressed and
delaying it would be felt.

## Settings

Categories down the left, the chosen category's settings on the right.

**Appearance** puts the window buttons at either end of the title bar — right
as Windows does, left as macOS does, with the inner two swapping order to match
each convention — and switches the taskbar between one entry per window, as
Windows XP had, and one per application with a count, as Windows 7 had.

**Theme** chooses between the desktop's own look and *macOS*, as it looked from
Yosemite through Mojave: a menu bar across the top carrying the focused
window's name and the clock, light grey window chrome shaded down its height
with the title centred over it, three coloured discs at the leading edge, and a
dock — a rounded panel sized to its contents and centred clear of the bottom
edge — in place of the full-width taskbar.

The discs are grey until a window is focused and show their glyphs only while
the pointer is over the set, as macOS does. They also keep red-yellow-green
reading order at whichever end the Appearance setting puts them: that order is
the whole of what makes them recognisable, so reversing it when they move to
the right would defeat the point. Flat buttons have no such signature and
instead put close outermost, which is what both conventions do.

**Wallpaper** offers six colours and ten photographs.

**Display** reports and controls the experimental Apple panel backlight, while
**Battery** reports the Apple SMC battery device. **Wi-Fi** reads the optional
BCM4378 driver, controls its firmware radio, starts scans and lists the networks
found. Firmware loading and network credentials remain in `wifi-ctl`, and the
raw Ethernet device is not an IP stack. See `SETTINGS.md` for the exact device
and hardware limitations.

Settings is the one application that holds a pointer back to the `Desktop`. It
writes preferences straight into it, and since the window manager composes the
whole screen from those preferences on the next frame, a choice takes effect
immediately and everywhere without anything being told to refresh.

Everything that varies between themes is a field of `Theme` in `settings.v`;
anything that does not stays a plain constant in `theme.v`. Application
interiors deliberately do not follow the theme — an application draws its own
inside, as ui2's calculator plainly does — so they use the `app_*` constants.

## Wallpapers

Vinix has no JPEG or PNG decoder, and writing one to show a backdrop would be a
strange place to spend the effort. So `tools/fetch_wallpapers.py` downloads the
photographs at build time, decodes them, and writes each as a `.vwp`: a nine
byte header and packed RGB, stored at half the display's resolution and scaled
up when drawn. A photograph survives that at the size a wallpaper is looked at,
and it keeps ten of them to about six megabytes rather than twenty-three.

Downloads are cached, so a rebuild costs nothing and an offline build works
once the cache is warm. With neither network nor cache the build says so and
ships none; the desktop then offers only its colours.

The scaled result is kept in a buffer and blitted, because it only changes when
the setting does. Rescaling three quarters of a million pixels every frame to
paint a backdrop that has not moved would cost more than everything else the
compositor does put together.

The photographs come from [Lorem Picsum](https://picsum.photos), which serves
them from Unsplash under the [Unsplash License](https://unsplash.com/license).
The ids are pinned so a build is reproducible, and each image's source URL is
recorded in `SOURCES.txt` beside it on the image.

## Fonts

Vinix has no font files and no rasteriser, so the glyphs travel inside the
binary. `tools/genfont.py` rasterises several Roboto faces into 8-bit coverage
atlases and writes them to `font_data.v` as base64; `font.v` decodes them at
startup and blends the coverage, which is the same antialiasing a desktop
toolkit would give. Roboto is licensed under the SIL Open Font License 1.1 —
see `FONT-LICENSE.txt`.

Each face is a weight and a pixel size, and the renderer picks the closest one
to what a text style asks for rather than scaling, because a stretched bitmap
atlas looks far worse than one a couple of pixels off. The baked sizes are the
ones the desktop's chrome uses plus those native applications ask for.

Runs are decoded as UTF-8. Beyond printable ASCII each face carries the
supplemental code points in the generator's `EXTRA_RUNES` — `÷` and `±` among
them, which is what lets ui2's calculator label its keys properly. A candidate
rune the font has no glyph for is dropped at generation time rather than baked
as a `.notdef` box; the generator says which. Anything not baked draws as a
space.

Regenerate after changing a size, a face or the rune list:

    python3 desktop/tools/genfont.py

## Memory

The target has no garbage collector, and the element tree is rebuilt whenever
the screen changes. Two things keep that from growing the process without
bound: every element id a window needs is built once when the window opens and
reused, and `free_tree` releases each frame's child arrays after it has been
presented. The screen is also only recomposed when something it shows has
actually changed, so an idle desktop rebuilds once a second, when the clock
ticks.

## Building and running

ui2 is not vendored; check it out beside the sources, where the build points
V's module path:

    git clone https://github.com/vlang/ui2 third_party/ui2

Then, from the repository root, with Homebrew `llvm`, `lld` and `qemu`
installed, one command builds everything and boots into the desktop:

    ./run-desktop-aarch64.sh

It builds the kernel, builds the desktop, and starts QEMU on the result.
The desktop launcher uses its own `boot-image/boot-desktop.img` disk, created
as a sparse 2 GiB image on its first run. This leaves the ordinary
`boot-image/boot.img` available for the smaller shell image. Set
`VINIX_BOOT_DISK` (and, for a new disk, `VINIX_BOOT_DISK_SIZE_MB` or
`--disk=MB`) to choose another disk.

    --no-build      boot what is already built
    --no-kernel     skip the kernel build (the desktop is what you changed)
    --no-desktop    skip the desktop build (the kernel is what you changed)
    --monitor       expose a QEMU monitor and QMP socket (see below)
    --replace       stop a VM already using the boot disk

A second VM cannot share the boot disk: QEMU takes a write lock on it and
refuses to start without one. `--replace` stops the one already running.

Anything else is passed through to `run-aarch64.sh`: `--mem=MB`, `--serial`,
`--virtio-gpu`. The desktop launcher supplies 8 GiB of guest RAM by default:
the root filesystem is loaded into memory during boot. Use `--mem=MB` or
`VINIX_QEMU_MEM` to override it.

`build-desktop-aarch64.sh` is the build on its own, if that is all you want. It
translates the V to C, compiles it for `aarch64-linux-musl` against the static
sysroot taken from the userland image, and stages
`build-support/init-aarch64/initramfs-desktop.tar` — an image whose `/sbin/init`
starts the desktop directly. `run-aarch64.sh` boots any image named by
`VINIX_INITRAMFS`, and with none boots the ordinary shell.

Options the desktop itself takes:

    --fb=PATH         framebuffer device (default /dev/fb0)
    --pointer=PATH    pointer device (default /dev/pointer)
    --tz=HOURS        hours east of UTC; Vinix has no time zone database
    --frame-ms=N      target milliseconds per frame (default 16)
    --stats           report frame timings to the console

## Driving it from a script

`--monitor` starts the VM with a QEMU monitor and a QMP socket, and the two
tools under `tools/` then drive and photograph it without a human at the
keyboard:

    ./run-desktop-aarch64.sh --monitor

    python3 desktop/tools/input.py drag 200 90 620 480
    python3 desktop/tools/input.py click 344 412
    ./desktop/tools/screenshot.sh /tmp/shot.png

`input.py` speaks QMP to the virtio tablet, which takes absolute coordinates,
so a click lands where it is aimed regardless of where the cursor was.

## What it needs from the kernel

`/dev/fb0` at 32bpp, and `/dev/pointer` — a character device added for this,
which reports the pointer's position, button levels, the press and release
edges since the last read, and any wheel movement. It never blocks: a
compositor redraws from the latest position anyway, and a queue it drained too
slowly would only make the cursor lag the hardware.

From the keyboard it needs Cmd reported at all, which is new: the console used
to drop the key. All three keyboard paths now track it and send the three
sequences above — `dev/console` for PS/2, `aarch64/virtio_input` for QEMU, and
`c/apple_spi_keyboard.c` for the built-in keyboard on an M1, where Cmd is a key
someone actually has under a thumb.

Under QEMU on a Mac, `./run-desktop-aarch64.sh --grab-keys` is what lets the
chord through: macOS keeps Cmd-Tab for its own application switcher until QEMU
is allowed to capture every key. The price is that Cmd-Q no longer quits QEMU.

## Native V platform and device code

All handwritten desktop implementations and tests are V. `platform.c.v` is
V source using libc declarations and the target headers for constants and
ABI types; it contains no embedded C implementations. It replaces `shim.h`,
which previously wrapped framebuffer mapping, descriptors, raw terminal mode,
clocks and directory iteration. `backlight_client.v`, `battery_client.v` and
`wifi_client.v` replace the other header-only implementations and provide the
Wi-Fi ioctl client. Device parsers, percentage conversion, retry policies,
state and mocks are ordinary V.

Run `V=/path/to/v sh desktop/tools/test-settings.sh` with the existing
`third_party/ui2` checkout. All client, POSIX and UI tests run; missing V/ui2
is an error, not a silent C-only success. `CLIENTS_ONLY=1` explicitly selects
the portable client/POSIX suite without ui2. See `SETTINGS.md`, `BATTERY.md` and
`../tools/apple-backlight/README.md` for behavior and hardware limitations.
