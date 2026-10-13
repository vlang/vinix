// SPDX-License-Identifier: MIT
// C ABI for the toolkit-independent client. Public layout: vinix_window.h.
module windowc

import desktop.windowfb

#include "../../libc_compat.h"

struct Framebuffer {
	pixels &u32
	width  u32
	height u32
	stride u32
	format u32
}

struct Event {
	kind    u32
	x       i32
	y       i32
	value   i32
	length  u32
	payload [4096]u8
}

struct ApiError {
	message [256]char
}

struct Handle {
mut:
	window windowfb.Window
}

fn report(out &ApiError, text string) {
	if out == unsafe { nil } { return }
	length := if text.len < 255 { text.len } else { 255 }
	unsafe {
		C.memcpy(&out.message[0], text.str, usize(length))
		out.message[length] = 0
	}
}

fn clear(out &ApiError) {
	if out != unsafe { nil } { unsafe { out.message[0] = 0 } }
}

// C strings are borrowed only during this call; cap before constructing a V
// string, so an oversized title/path does not allocate or scan without bound.
fn borrowed(ptr &char, maximum int) !string {
	if ptr == unsafe { nil } { return error('null C string') }
	unsafe {
		for length in 0 .. maximum + 1 {
			if ptr[length] == 0 { return tos(&u8(ptr), length) }
		}
	}
	return error('C string exceeds its size limit')
}

@[export: 'vinix_window_api_version']
pub fn c_api_version() u32 { return 1 }

@[export: 'vinix_window_open']
pub fn c_open(title &char, width i32, height i32, out &ApiError) voidptr {
	clear(out)
	text := borrowed(title, 128) or {
		report(out, err.msg())
		unsafe { err.free() }
		return unsafe { nil }
	}
	window := windowfb.open(text, int(width), int(height)) or {
		report(out, err.msg())
		unsafe { err.free() }
		return unsafe { nil }
	}
	return &Handle{ window: window }
}

@[export: 'vinix_window_open_at']
pub fn c_open_at(path &char, title &char, width i32, height i32, out &ApiError) voidptr {
	clear(out)
	socket := borrowed(path, 99) or {
		report(out, err.msg())
		unsafe { err.free() }
		return unsafe { nil }
	}
	text := borrowed(title, 128) or {
		report(out, err.msg())
		unsafe { err.free() }
		return unsafe { nil }
	}
	window := windowfb.open_at(socket, text, int(width), int(height)) or {
		report(out, err.msg())
		unsafe { err.free() }
		return unsafe { nil }
	}
	return &Handle{ window: window }
}

@[export: 'vinix_window_close']
pub fn c_close(opaque voidptr) {
	if opaque == unsafe { nil } { return }
	mut handle := unsafe { &Handle(opaque) }
	handle.window.close()
	unsafe { free(handle) }
}

@[export: 'vinix_window_event_fd']
pub fn c_event_fd(opaque voidptr) i32 {
	if opaque == unsafe { nil } { return -1 }
	handle := unsafe { &Handle(opaque) }
	return i32(handle.window.event_fd())
}

@[export: 'vinix_window_get_framebuffer']
pub fn c_get_framebuffer(opaque voidptr, out &Framebuffer) i32 {
	if opaque == unsafe { nil } || out == unsafe { nil } { return -1 }
	handle := unsafe { &Handle(opaque) }
	unsafe {
		*out = Framebuffer{
			pixels: handle.window.surface.back
			width:  u32(handle.window.surface.width)
			height: u32(handle.window.surface.height)
			stride: u32(handle.window.surface.stride)
			format: 1
		}
	}
	return 0
}

@[export: 'vinix_window_frame_pending']
pub fn c_frame_pending(opaque voidptr) i32 {
	if opaque == unsafe { nil } { return -1 }
	handle := unsafe { &Handle(opaque) }
	return if handle.window.frame_pending { 1 } else { 0 }
}

@[export: 'vinix_window_wants_write']
pub fn c_wants_write(opaque voidptr) i32 {
	if opaque == unsafe { nil } { return -1 }
	handle := unsafe { &Handle(opaque) }
	return if handle.window.connection.wants_write() { 1 } else { 0 }
}

@[export: 'vinix_window_present']
pub fn c_present(opaque voidptr, out &ApiError) i32 {
	clear(out)
	if opaque == unsafe { nil } {
		report(out, 'null window handle')
		return -1
	}
	mut handle := unsafe { &Handle(opaque) }
	handle.window.present() or {
		report(out, err.msg())
		unsafe { err.free() }
		return -1
	}
	return 0
}

@[export: 'vinix_window_next_event']
pub fn c_next_event(opaque voidptr, event &Event, out &ApiError) i32 {
	clear(out)
	if opaque == unsafe { nil } || event == unsafe { nil } {
		report(out, 'null window or event')
		return -1
	}
	mut handle := unsafe { &Handle(opaque) }
	mut message := windowfb.Message{}
	ready := handle.window.receive(unsafe { &message }) or {
		report(out, err.msg())
		unsafe { err.free() }
		return -1
	}
	if !ready { return 0 }
	unsafe {
		*event = Event{ kind: u32(message.kind), x: message.x, y: message.y, value: message.value, length: u32(message.length) }
		C.memcpy(&event.payload[0], &message.payload[0], usize(message.length))
	}
	return 1
}

@[export: 'vinix_window_wait']
pub fn c_wait(opaque voidptr, timeout_ms i32, out &ApiError) i32 {
	clear(out)
	if opaque == unsafe { nil } {
		report(out, 'null window handle')
		return -1
	}
	if timeout_ms < -1 {
		report(out, 'timeout must be -1 or nonnegative')
		return -1
	}
	mut handle := unsafe { &Handle(opaque) }
	ready := handle.window.connection.wait(int(timeout_ms)) or {
		report(out, err.msg())
		unsafe { err.free() }
		return -1
	}
	return if ready { 1 } else { 0 }
}
