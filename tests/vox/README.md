# Vox on the native Vinix desktop

The browser is built from `../vox2/main.v`, with its existing DOM, CSS, layout,
JavaScript, browser tabs and UI2 chrome. The module overlay in
`build-support/vox` supplies a CPU implementation of GG's drawing contract and
UI2's native desktop embedding API. Frames use Vinix's shared surface protocol;
keyboard and pointer events return through the desktop IPC connection.

Browser controls use Vinix UI2 buttons and builtin navigation symbols; window
management uses the desktop's outer title bar. Tab and bookmark favicons are
published from Vox's decoded image cache as small shared surfaces, preserving
their alpha against the control background. The desktop never opens arbitrary
PNG paths from the browser's cache.

Page text is sent as clipped UI2 labels to the same Roboto coverage renderer as
other Vinix apps. Line-box metrics are generated from `desktop/font_data.v`,
including its nearest-size and weight selection. The private fontconfig setup
uses the same bundled Roboto and Roboto Mono files for document layout.

The runtime dependency closure rejects X11, XCB, Wayland and GTK libraries.
EGL/GLES dispatch libraries are built with X11 and GLX disabled. No display
server or Sokol window is started. A WebGL vendor is not provided by this port.

## Build

Run from the repository root on an ARM64 Mac with Homebrew LLVM, GN, Ninja,
QEMU, Rust's `aarch64-unknown-linux-musl` target, the existing ARM64 musl SDK in
`build-aarch64-userland/staging`, and the fonts/certificates in
`build-aarch64-firefox/staging`. The builder uses the adjacent `v`, `ui2` and
`vox2` checkouts. It does not modify their sources or build the macOS bundle.

Keep generated files outside Git:

```sh
export VINIX_VOX_STATE="$HOME/.local/state/vinix-vox"
mkdir -p "$VINIX_VOX_STATE"
v -prod -path '.|build-support|@vlib|@vmodules' \
  -o "$VINIX_VOX_STATE/builder" build-support/vox/build.v
"$VINIX_VOX_STATE/builder" prepare
"$VINIX_VOX_STATE/builder" javascriptcore
"$VINIX_VOX_STATE/builder" runtime
"$VINIX_VOX_STATE/builder" glvnd
"$VINIX_VOX_STATE/builder" skia
"$VINIX_VOX_STATE/builder" extras
"$VINIX_VOX_STATE/builder" full
"$VINIX_VOX_STATE/builder" native
"$VINIX_VOX_STATE/builder" checks
```

`VINIX_VOX_SOURCE` can select a different Vox checkout; `V_BIN` selects its
compiler. Builds have a 12 GiB process-tree RSS guard and V has a 10 GiB limit.
Skia and libglvnd sources are pinned by revision/release and checksum. Skia's GN
helper and the orchestration are V; the upstream generated libglvnd release
files allow building without Python. Cached native objects must be removed
when changing their upstream source, SDK or compiler flags.

The browser uses Vox's scoped `-prealloc` arenas. The V builder stages the
bounded realloc and persistent closure metadata changes that Vox's production
build requires, in an isolated compiler/runtime copy with its own checksum
receipt. It does not execute Vox's Python staging tools. Cross-generated C
must contain the arena allocator: this compiler omits Boehm on cross-output
even when `-gc boehm` is specified.

The current Vox compiler uses 64-bit V `int`. The desktop still uses its pinned
32-bit-int compiler; set `VINIX_DESKTOP_V` to that compiler, not Vox's compiler:

```sh
"$VINIX_VOX_STATE/builder" guard "$VINIX_DESKTOP_V" -memory-limit 10G \
  -path '@vlib|.|desktop/tools|build-support|tests/linuxkpi|@vmodules' \
  -o "$VINIX_VOX_STATE/build-desktop" run tests/vox/build-desktop.v
"$VINIX_VOX_STATE/builder" guard "$VINIX_DESKTOP_V" -memory-limit 10G \
  -path '@vlib|.|tests/hardware-platform|build-support/source-tools|tests/linuxkpi|@vmodules' \
  -o "$VINIX_VOX_STATE/runner" tests/vox/run.v
```

## Check, package and capture

```sh
"$VINIX_VOX_STATE/builder" host-checks
"$VINIX_VOX_STATE/runner" package
"$VINIX_VOX_STATE/runner"
```

The package is `$VINIX_VOX_STATE/staging`. Install its contents into an ARM64
Vinix root filesystem with the updated desktop. `/usr/bin/vox` is a static V
launcher; it preserves the desktop descriptors and executes the browser using
Vinix's musl interpreter and the private libraries, fonts and certificates under
`/usr/libexec/vinix-vox/root`. Executing the browser ELF directly preserves its
executable identity when it starts script workers.

The test guest runs the original browser's `--headless-smoke` first, including
JavaScript DOM mutation, click listeners and wheel handling. It then opens Vox
from the desktop application factory. The VM uses the retained PTY kernel in
`build/pty-kernels/aarch64/vinix`, rather than building concurrent kernel edits.
Its QMP socket and serial log are in the external state directory.

From another terminal, after the Vox window appears:

```sh
"$VINIX_VOX_STATE/runner" key ctrl-l
"$VINIX_VOX_STATE/runner" type file:///usr/share/vinix/vox-welcome.html
"$VINIX_VOX_STATE/runner" key ret
"$VINIX_VOX_STATE/runner" shot
"$VINIX_VOX_STATE/runner" quit
```

The PNG is an actual QEMU framebuffer capture at
`$VINIX_VOX_STATE/vox-vinix-desktop.png`. Preserve screenshots, logs, binaries
and their checksums outside Git. Focused host tests cover clipping, alpha
composition, ellipse geometry, image cropping and compositor buffer ownership.
The same tests also check worker descriptor closure on the host and in Vinix.
Arena checks cover PNG's initial null realloc, decoded pixel ownership, cached
image records and fallback text surviving the document frame's reset. The
chrome checks also cover favicon alpha, cached surfaces, native button styles,
icon/caption spacing, clipping and monospaced text. The screenshot fixture
includes a generated PNG data-URL favicon so its tab icon works offline. The
builder invokes the staged compiler from its runtime root and checks for the
bounded realloc and closure helpers in generated C.
`full` selects the explicit compiler so failures are reported directly. If
generation is run separately for diagnostics, preserve its successful command
and log, copy its complete output to `$VINIX_VOX_STATE/vox.c`, then run
`builder finish-source` before `builder native`. That step applies the same
allocator, completeness and ABI-header checks as `full`.
The guest logs system memory and browser process status every 15 seconds for
interaction and idle measurements, including each browser's raw `statm` counters
and page size. The footer samples current process resident memory from
`/proc/self/statm` once per second, converting pages with the runtime page size.
Invalid or overflowing counters stay unavailable. The staged processmetrics
overlay leaves the shared Vox checkout unchanged; the receipt requires the
sampler's native test and five live process-counter samples.

Vox calls the Vinix UI2 setting `set_window_decorated(false)` before opening its
window. Its own tab strip supplies native window buttons and the drag target;
the compositor adds invisible resize targets. Other clients retain decorations.
The strip preserves Vox's classic curved tab outlines, gray background and
red/yellow/green window buttons, with window actions handled by Vinix. Toolbar
and bookmark buttons still use the native Vinix controls and font renderer.
The backward-compatible hello extension leaves protocol header sizes unchanged.
Run the frame/geometry regressions with the same guarded desktop builder command
above, appending `--host-tests`. This checks negotiation, all four themes,
recovery, raw-pointer coordinates, scoped controls and existing edge, window
action and title-bar behavior. Rebuild the compositor as well as Vox to exercise
this option in a fresh guest.

The portable chrome uses its existing state comparison to reuse unchanged
controls. Only the native UI tree has a recycled request lifetime; browser
callbacks retain their own state. CPU pixel buffers remain valid across those
requests and are reused between frames. The existing paint-command replay
arena is also enabled for this host, with portable shadow-cache records kept
in persistent storage. Document preparation and timer callbacks remain outside
that temporary arena. Polygon scanlines use a freed scratch buffer; the tests
verify that repeated draws do not advance the arena cursor.

`v -prod -o "$VINIX_VOX_STATE/receipt" tests/vox/receipt.v` builds the evidence
recorder. Run it with `VINIX_VOX_STATE` after capturing the guest. It requires
the smoke checks, at least 75 seconds of live browser samples, no guest failure
markers, and less than 128 MiB of system memory growth over the final 45 seconds.
It records the executable, generated source, runtime, headers, screenshot and
guest inventory, then preserves a compressed bundle and its checksum outside
Git. This is a functional memory guard, not a long-term leak qualification.

For a guest crash, `builder trace` builds an optional V signal tracer and test
launcher. The runner includes them only when `libvox-trace.so` exists in the
external state directory. This preserves the browser executable while printing
the fault PC, registers and frame addresses; use LLVM's symbolizer against the
recorded executable. Move the diagnostic library aside to run the normal
package again. The installable package does not include this tracer.

This initial CPU port does not yet implement the system clipboard, IME,
hardware graphics, detached process tabs, or the chrome's internal minimize
and zoom controls. Vinix's outer window controls provide window management.
The renderer is compiled without C optimization to keep this development
cross-build bounded; this workflow is a functional check, not a performance
qualification.
