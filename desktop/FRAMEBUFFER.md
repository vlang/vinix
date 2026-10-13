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
| 1 CREATE | app → desktop | x = pixel width, y = pixel height, value = feature mask (see below); title payload, 1–128 bytes, no control characters |
| 2 CREATED | desktop → app | x = pixel width, y = pixel height, value = stride in bytes; absolute framebuffer pathname payload |
| 3 PRESENT | app → desktop | x/y = 0, value = buffer generation, no payload; publish the back buffer |
| 4 FRAME_DONE | desktop → app | x/y = 0, value = acknowledged buffer generation, no payload; back buffer may be reused |
| 5 MOTION | desktop → app | x/y = framebuffer coordinates; value = pointer button (usually 0) |
| 6 BUTTON_DOWN | desktop → app | x/y = framebuffer coordinates; value = button |
| 7 BUTTON_UP | desktop → app | x/y = framebuffer coordinates; value = button |
| 8 KEYS | desktop → app | All fields zero; Kitty keyboard protocol with flags 31 when requested, otherwise legacy UTF-8/terminal input |
| 9 WHEEL | desktop → app | x/y = framebuffer coordinates; value = signed vertical scroll steps |
| 10 HORIZONTAL_WHEEL | desktop → app | x/y = framebuffer coordinates; value = signed horizontal scroll steps |
| 11 CONFIGURE | desktop → app | x/y = content width/height, value = buffer generation; nonempty pathname payload offers a replacement mapping |
| 12 FOCUS | desktop → app | value = 1 when focused, 0 otherwise; x/y = 0, no payload |
| 13 CLOSE | either | All fields zero, no payload; close the window |
| 14 SET_TITLE | app → desktop | All fields zero; new title payload, 1–128 bytes, no control characters |
| 15 BUFFER_ACK | app → desktop | x/y = 0, value = offered generation, no payload; accept the replacement buffer |

Buttons are 0 = none, 1 = left, 2 = middle, 3 = right, 4 = back.
CREATE's feature mask is bit 0 (`1`) for replacement buffers and bit 1 (`2`)
for Kitty keyboard input. Use `value = 3` for both; the V and C clients do this
automatically. Zero preserves the original fixed-buffer, legacy-keyboard contract.
Unknown bits are rejected. Install the updated kernel and desktop together:
Kitty requests are rejected if the console lacks physical-key event support.

Kitty input follows the [keyboard protocol specification](https://sw.kovidgoyal.net/kitty/keyboard-protocol/)
with flags `31`: disambiguation, press/repeat/release, shifted and base-layout
alternates, every key as an escape sequence, and associated Unicode text.
For example, Ctrl-I is `CSI 105;5:1u`, Tab is `CSI 9;1:1u`, and releasing
Escape is `CSI 27;1:3u`. Navigation/function keys use the specification's
canonical CSI forms (for example `CSI 1;6:3A` for Ctrl-Shift-Up release).
Modifier keys, independent left/right state, Caps Lock and Num Lock are reported.
Paste/IME text with no physical key uses Kitty's key code zero and associated
text. Serial text cannot provide hardware modifiers or releases; physical PS/2,
USB, VirtIO and Apple SPI keyboards preserve them. Window-management chords
remain with the desktop; releases go back to the window that received the press,
including across focus changes. Clear held state when focus is lost or closed.

Send CREATE first and wait for CREATED. The desktop then sends initial CONFIGURE
and FOCUS events. PRESENT, CLOSE, SET_TITLE and a valid BUFFER_ACK are accepted
after creation.
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

With replacement buffers, resizing/maximizing sends CONFIGURE with the new
dimensions, a positive generation and the new pathname. Map and validate that
file exactly as for CREATED, stop using the old pixels, and send BUFFER_ACK
with that generation. Send subsequent PRESENTs with the new generation; the
initial generation is zero. Stream ordering lets a PRESENT already submitted
for the old buffer complete before BUFFER_ACK retires it. Its FRAME_DONE still
carries the old generation. Do not treat CONFIGURE as a frame acknowledgement.

The V/C clients map, acknowledge and retire the old client mapping while decoding
CONFIGURE. The C pixel pointer is invalidated by a CONFIGURE with a nonempty
payload: call `vinix_window_get_framebuffer` again and redraw at the new size
once `vinix_window_frame_pending` is zero. The desktop retains the old surface
until BUFFER_ACK, keeps its pixels at native size during handoff, and offers at
most one replacement at a time. Further resize motions are coalesced to the
latest dimensions after acknowledgement. Disconnect cleans up both mappings.
Pointer coordinates use the current content coordinate system.

An empty CONFIGURE is an informational size event and does not invalidate pixels.
Clients requesting no replacement buffers keep the original allocation and
scaled pointer coordinates, with generation zero throughout.

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
reader, pending-frame resize handoff/coalescing, Kitty encoding and key routing,
title/focus, close/disconnect, slot reuse, invalid requests, and a
stalled handshake. Its temporary snapshot isolates unrelated checkout edits.
`--cross` also builds the desktop, demo, and a guest smoke-test init for ARM64 and
x86_64 against the existing musl SDKs. `VINIX_FRAMEBUFFER_KEEP=1` retains those
artifacts at the path printed by the runner. The guest init opens ten windows,
publishes thirty frames, waits for their acknowledgements, and closes each
mapping before printing `FRAMEBUFFER GUEST PASS`.
