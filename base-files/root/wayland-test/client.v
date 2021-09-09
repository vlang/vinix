#flag -lwayland-client

#include <wayland-client-core.h>

struct C.wl_display {}
fn C.wl_display_connect(voidptr) &C.wl_display
fn C.wl_display_disconnect(&C.wl_display)

fn main() {
	mut dsp := C.wl_display_connect(voidptr(0))
	if dsp == voidptr(0) {
		println("couldn't connect to display")
		return
	}

	defer { C.wl_display_disconnect(dsp) }
	println("connected to display")
}
