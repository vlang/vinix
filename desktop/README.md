# vinix-desktop

A small desktop environment for Vinix, written in V and built on
[ui2](https://github.com/vlang/ui2)'s declarative element tree.

![The desktop running under QEMU](screenshot.png)

It maps `/dev/fb0`, reads the pointer from `/dev/pointer` and the keyboard from
its controlling terminal, and composes every frame itself: there is no display
server, no GPU and no toolkit underneath it.

What it does:

- a wallpaper, and a taskbar along the bottom listing every open window
- a clock in the bottom right corner — time above, date below
- windows with a title bar, a close, a maximise/restore and a minimise button
- dragging a window by its title bar, clicking one to bring it to the front
- a **New window** button, so the taskbar list can be seen growing and shrinking
- **hosted ui2 applications**: the taskbar's launchers open ui2's own examples
  in windows of their own, several at a time, each with its own state

Keys: `Esc` or `q` leaves the desktop, `n` opens a window, `c` a calculator.

## How it fits together

    main.v         the event loop: poll input, rebuild, render, present
    wm.v           the window manager — window list, the ui2 tree, hit routing
    window.v       the Window model and the pages windows show
    app.v          hosting ui2 applications in windows
    render.v       a ui2 backend that draws an element tree into a framebuffer
    canvas.v       the software renderer: spans, rounded rects, clipping, blend
    font.v         text, from the coverage atlases in font_data.v
    framebuffer.v  /dev/fb0: geometry over ioctl, pixels over mmap
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
the target has no `gg`, no Sokol and no OpenGL, so `-d ui2_headless` compiles
ui2's declarative core without its renderer, and this program supplies the
renderer instead.

Two conventions extend ui2 for this backend, both documented at the top of
`render.v`: an `image_path` of `builtin:<name>` draws a vector glyph the
renderer carries itself, since the target has no image files; and a rounded
view at the top level of the tree is a floating surface, so it gets a drop
shadow and a hairline edge.

## Hosting ui2 applications

A ui2 application normally calls `run_qml`, which opens a platform window and
blocks until it closes. There is no platform here to ask — the desktop *is* the
window system — so it uses ui2's `QmlApp` instead: the application hands over an
element tree for a content area of whatever size its window happens to be, and
gets back the id of whatever the user hit. Because the size is passed in rather
than taken from a display, an application re-lays-out when its window is
resized or maximised, which is how the calculator recentres itself.

The applications are ui2's own examples, and they are not copied into this
repository. `tools/stage_app.py` takes each example's source straight from the
ui2 checkout at build time and removes exactly one thing: its `fn main()`,
which exists to open a platform window and block. Everything the application
is — its model, its methods, its QML document — compiles unmodified, so what
runs on Vinix is the example rather than a retelling of it. Both it and the
desktop are `module main`, so they share a directory and V builds them as one
program.

Hosted event ids are ui2's own, prefixed `__qml_`, so the window manager can
tell them from its own without parsing them. It routes one by which window the
click landed in, which is also what decides it between two open copies of the
same application.

Add an application by listing its example directory in
`build-desktop-aarch64.sh` and adding an `AppFactory` to `available_apps` in
`app.v`.

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
ones the desktop's chrome uses plus those hosted applications ask for.

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
V's module path. The `ui2_headless` build this needs is upstream, so a plain
clone will do:

    git clone https://github.com/vlang/ui2 third_party/ui2

Then, from the repository root, with Homebrew `llvm`, `lld` and `qemu`
installed:

    ./build-desktop-aarch64.sh

That translates the V to C, compiles it for `aarch64-linux-musl` against the
static sysroot taken from the userland image, and stages
`build-support/init-aarch64/initramfs-desktop.tar` — an image whose `/sbin/init`
starts the desktop directly.

    VINIX_INITRAMFS="$PWD/build-support/init-aarch64/initramfs-desktop.tar" \
        ./run-aarch64.sh

Options the desktop itself takes:

    --fb=PATH         framebuffer device (default /dev/fb0)
    --pointer=PATH    pointer device (default /dev/pointer)
    --tz=HOURS        hours east of UTC; Vinix has no time zone database
    --frame-ms=N      target milliseconds per frame (default 16)
    --stats           report frame timings to the console

## Driving it from a script

Start the VM with a monitor and a QMP socket, and the two tools under `tools/`
can drive and photograph it without a human at the keyboard:

    VINIX_QEMU_EXTRA="-monitor unix:/tmp/vinix-monitor,server,nowait \
                      -qmp unix:/tmp/vinix-qmp,server,nowait" \
    VINIX_INITRAMFS="$PWD/build-support/init-aarch64/initramfs-desktop.tar" \
        ./run-aarch64.sh --no-build

    python3 desktop/tools/input.py drag 200 90 620 480
    ./desktop/tools/screenshot.sh /tmp/shot.png

`input.py` speaks QMP to the virtio tablet, which takes absolute coordinates,
so a click lands where it is aimed regardless of where the cursor was.

## What it needs from the kernel

`/dev/fb0` at 32bpp, and `/dev/pointer` — a character device added for this,
which reports the pointer's position, button levels, the press and release
edges since the last read, and any wheel movement. It never blocks: a
compositor redraws from the latest position anyway, and a queue it drained too
slowly would only make the cursor lag the hardware.
