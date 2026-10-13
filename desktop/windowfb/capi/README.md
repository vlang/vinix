# C window API

Include [`vinix_window.h`](vinix_window.h) and link `libvinix-window`. The same
symbols can be called through another language's C FFI or dynamic loader.
The implementation is V, but the ABI contains only opaque pointers, fixed-width
integers, caller-owned structs and pixel pointers. No V compiler, toolkit, GC,
or runtime initialization is needed by the application.

Build a Vinix SDK from the repository root using the existing musl sysroot:

```sh
v run desktop/tools/build-window-capi.v --arch=arm64 --out=build/window-sdk-arm64
v run desktop/tools/build-window-capi.v --arch=amd64 --out=build/window-sdk-amd64
```

Each SDK contains `include/vinix_window.h`, `lib/libvinix-window.so` and
`lib/libvinix-window.a`. `--arch=host` builds a native library for developing
bindings and running the ABI tests; on macOS that shared library is a `.dylib`.
`V`, `LLVM_BIN`, `VINIX_AARCH64_SYSROOT` and `VINIX_AMD64_SYSROOT` can override the
compiler/toolchain locations. `CC` and `AR` select host tools. The library has
no ui2 dependency. Only the public `vinix_window_*` symbols are exported by the
shared library.

A C client can draw a first frame and wait for input like this:

```c
#include <vinix_window.h>

int main(void) {
    vinix_window_error error = {0};
    vinix_window *window = vinix_window_open("C framebuffer", 640, 480, &error);
    if (!window) return 1;

    vinix_framebuffer fb;
    if (vinix_window_get_framebuffer(window, &fb) != 0) {
        vinix_window_close(window);
        return 1;
    }
    for (uint32_t y = 0; y < fb.height; ++y)
        for (uint32_t x = 0; x < fb.width; ++x)
            fb.pixels[y * (fb.stride / 4) + x] = 0x00306090;
    if (vinix_window_present(window, &error) != 0) {
        vinix_window_close(window);
        return 1;
    }

    int running = 1;
    while (running) {
        if (vinix_window_wait(window, -1, &error) < 0) break;
        vinix_window_event event;
        int32_t status;
        while ((status = vinix_window_next_event(window, &event, &error)) == 1) {
            if (event.kind == VINIX_WINDOW_CLOSE) running = 0;
            /* FRAME_DONE permits the next draw/present. KEYS carries
               event.length bytes, including possible embedded NULs. */
        }
        if (status < 0) break;
    }
    vinix_window_close(window);
    return 0;
}
```

Use the guest's C compiler/sysroot to build the application, adding
`-I<SDK>/include -L<SDK>/lib -lvinix-window`. Deploy the shared library to the
guest's library path, or link the static archive with `-lpthread -lm`.

`vinix_window_open` reads `VINIX_WINDOW_SOCKET`, otherwise it connects to
`/run/vinix-session.<uid>/windows`. `vinix_window_open_at` takes an explicit
socket pathname. Creation returns a handle or NULL; other fallible calls return
-1 and optionally write a NUL-terminated message to the supplied error struct.
Passing NULL for error output is supported. Successful calls clear that message.

`vinix_window_next_event` returns 1 for an event, 0 for no complete event, and -1
for failure/disconnection. It accumulates split stream records internally and
leaves the output unchanged on 0/-1. Event structs and their payloads belong to
the caller; there is no event-free function. Keyboard payloads are byte arrays,
not C strings. The event kind and coordinate meanings match the
[wire protocol](../../FRAMEBUFFER.md).

For an existing event loop, get the borrowed descriptor with
`vinix_window_event_fd`. Poll for input/hangup and for output when
`vinix_window_wants_write` is 1. On output readiness call
`vinix_window_wait(window, 0, &error)` to flush queued bytes; drain input using
`vinix_window_next_event` until it returns 0. Keep decoding through the library,
so its partial-message state and frame acknowledgements remain synchronized.

The framebuffer pointer stays valid until `vinix_window_close`. It uses XRGB8888
pixels and a byte stride. Finish drawing, call `vinix_window_present`, then leave
the pixels untouched until a FRAME_DONE event is decoded and
`vinix_window_frame_pending` returns 0. FRAME_DONE acknowledges the copy into the
compositor, not vsync. Resizing scales the original allocation. Calls and drawing
on one handle must be serialized; separate handles have separate state.

Close each non-NULL handle exactly once and discard its pixel and descriptor
values afterwards. `vinix_window_close(NULL)` is harmless. Close all windows
before unloading the library. Check `vinix_window_api_version()` against
`VINIX_WINDOW_API_VERSION` before using a dynamically loaded library.

Run ABI qualification with:

```sh
v run tests/framebuffer-c-api/run.v
VINIX_CAPI_KEEP=1 v run tests/framebuffer-c-api/run.v --cross
```

The fixture includes the public C header and has no V runtime or client-module
import. It links and runs against both the shared library and static archive,
checks native struct sizes, paints the mapping, polls the descriptor, decodes
one-byte fragments and a binary keyboard payload, checks acknowledgement and
error handling, and closes the handle. `--cross` builds both guest SDKs and
static foreign-ABI consumers for ARM64 and x86_64.
