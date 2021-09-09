#flag -lwayland-server

#include <wayland-server-core.h>

struct C.wl_display {}
fn C.wl_display_create() &C.wl_display
fn C.wl_display_destroy(&C.wl_display)
fn C.wl_display_run(&C.wl_display)
fn C.wl_display_add_socket_auto(&C.wl_display) &char

fn main() {
	mut dsp := C.wl_display_create()
	if dsp == voidptr(0) {
		println('couldn\'t create display')
		return
	}
	defer { C.wl_display_destroy(dsp) }
	println('created display')

	sock := C.wl_display_add_socket_auto(dsp)
	if sock == voidptr(0) {
		println('couldn\'t create socket')
		return
	}

	println('created socket: ' + unsafe{ sock.vstring() })

	C.wl_display_run(dsp)
}
