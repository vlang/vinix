# Framebuffer windows

An executable written in any language can open a normal Vinix desktop window
without ui2, X11, or Wayland. Connect to the desktop's Unix stream socket,
request a pixel buffer, map it with `mmap(MAP_SHARED)`, and draw XRGB pixels.
The same socket is a waitable event descriptor for `poll`, `select`, or `epoll`.

The default socket is `/run/vinix-session.<uid>/windows`. Both client and desktop
honor `VINIX_WINDOW_SOCKET`; `VINIX_SESSION_RUNTIME` changes the `/run` base.
The desktop starts the service after user registration. Connections must belong
to its user. A process can open multiple connections, one per window, and can
start from a shell or any other launcher.

For C and other-language bindings, use the [C API and SDK](windowfb/capi/README.md)
with [`vinix_window.h`](windowfb/capi/vinix_window.h), a shared/static library,
opaque window handles, mapped pixel pointers, and a waitable event FD.

The V client module is `desktop.windowfb`. It has no ui2 dependency:

```v
import desktop.windowfb

mut window := windowfb.open('My window', 640, 480)!
defer { window.close() }
unsafe { window.surface.back[0] = 0x00ff0000 }
window.present()!

// Or put window.event_fd() into your application's own poll/select/epoll set.
window.connection.wait(-1)!
mut event := windowfb.Message{}
for window.receive(unsafe { &event })! {
    // event.kind, event.x, event.y, event.value, event.text()
}
```

See [the runnable example](../examples/framebuffer/main.v). Its event loop paints
a gradient and follows the pointer, waiting for acknowledgement before redrawing.

## Wire format

Every message has a 24-byte header followed by `length` payload bytes. Integers
are fixed-width, little endian, with no padding. Stream reads and writes can
split or combine messages: accumulate the whole header and then its payload.

| Offset | Type | Meaning |
| --- | --- | --- |
| 0 | u32 | Magic `0x31465756` (bytes `VWF1`), protocol version 1 |
| 4 | u32 | Message kind |
| 8 | i32 | x |
| 12 | i32 | y |
| 16 | i32 | value |
| 20 | u32 | Payload length, at most 4096 |

| Kind | Direction | Fields and payload |
| --- | --- | --- |
| 1 CREATE | app → desktop | x = pixel width, y = pixel height, value = 0; title payload, 1–128 bytes, no control characters |
| 2 CREATED | desktop → app | x = pixel width, y = pixel height, value = stride in bytes; absolute framebuffer pathname payload |
| 3 PRESENT | app → desktop | All fields zero, no payload; publish the back buffer |
| 4 FRAME_DONE | desktop → app | All fields zero, no payload; back buffer may be reused |
| 5 MOTION | desktop → app | x/y = framebuffer coordinates; value = pointer button (usually 0) |
| 6 BUTTON_DOWN | desktop → app | x/y = framebuffer coordinates; value = button |
| 7 BUTTON_UP | desktop → app | x/y = framebuffer coordinates; value = button |
| 8 KEYS | desktop → app | All fields zero; UTF-8 text or terminal escape-sequence payload |
| 9 WHEEL | desktop → app | x/y = framebuffer coordinates; value = signed vertical scroll steps |
| 10 HORIZONTAL_WHEEL | desktop → app | x/y = framebuffer coordinates; value = signed horizontal scroll steps |
| 11 CONFIGURE | desktop → app | x/y = current window content width/height in logical desktop pixels; value = 0, no payload |
| 12 FOCUS | desktop → app | value = 1 when focused, 0 otherwise; x/y = 0, no payload |
| 13 CLOSE | either | All fields zero, no payload; close the window |

Buttons are 0 = none, 1 = left, 2 = middle, 3 = right, 4 = back.
Keyboard payloads use the desktop's existing UTF-8/terminal input, including
CSI-u sequences where available. This version does not promise separate physical
key-down/key-up events. Global window-management shortcuts remain with the desktop.

Send CREATE first and wait for CREATED. The desktop then sends initial CONFIGURE
and FOCUS events. Only PRESENT and CLOSE are valid app messages after creation.
Unknown kinds, bad lengths, or invalid requests disconnect the client.

## Pixel buffer and frame ownership

Open the returned pathname read/write, verify its size, and map the entire file.
Dimensions must be 64–8192 on each axis, with total mapping size at most 128 MiB.
The stride is `width * 4`; the file size is `48 + 2 * stride * height`.

The first 48 bytes are the compositor's existing VSF1 header, followed by a front
buffer and a back buffer. The app must only write the back buffer, starting at
byte `48 + stride * height`. Each pixel is a little-endian u32 `0x00RRGGBB`
(bytes blue, green, red, unused). Alpha is ignored.

After finishing the pixels, send PRESENT and leave the back buffer untouched
until FRAME_DONE. The compositor copies the back buffer into its front buffer
before acknowledging it, and schedules window damage. FRAME_DONE means copied;
it is not a vsync or physical-display fence. Apps may skip frames while waiting
and should drain all available events before drawing their next frame.

The allocation stays at its requested pixel size for the window's lifetime.
Resizing/maximizing scales it to the new content area; CONFIGURE reports that
area and pointer events are scaled back to framebuffer coordinates. A later
protocol can negotiate replacement buffers without changing this ownership rule.

Each connection owns one window and mapping. Closing the socket removes the
window and unlinks its file; an app must then unmap its copy. Closing from the
title bar sends CLOSE and closes the socket. EOF/hangup also means close, even
if no complete CLOSE message arrives. Never keep a pathname for a future session.

The desktop limits the service to 32 active/pending clients, expires incomplete
handshakes after five seconds, and bounds outgoing event queues. A client that
stops reading is disconnected when its queue fills. The desktop polls the listener
and client sockets alongside input devices, so PRESENT wakes an idle desktop.

## Validation

```sh
v -new-compiler desktop/windowfb/protocol_test.v
v run desktop/tools/test-framebuffer-windows.v
VINIX_FRAMEBUFFER_KEEP=1 v run desktop/tools/test-framebuffer-windows.v --cross
v -new-compiler -path '@vlib|@vmodules|.' -o framebuffer-demo examples/framebuffer
```

The host integration test covers shared pixels through the real compositor
reader, input, resize/focus, close/disconnect, slot reuse, invalid requests, and a
stalled handshake. Its temporary snapshot isolates unrelated checkout edits.
`--cross` also builds the desktop, demo, and a guest smoke-test init for ARM64 and
x86_64 against the existing musl SDKs. `VINIX_FRAMEBUFFER_KEEP=1` retains those
artifacts at the path printed by the runner. The guest init opens ten windows,
publishes thirty frames, waits for their acknowledgements, and closes each
mapping before printing `FRAMEBUFFER GUEST PASS`.
