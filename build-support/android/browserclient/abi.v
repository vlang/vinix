// SPDX-License-Identifier: GPL-2.0-or-later
module browserclient

import browseripc

// These functions are the only boundary used by the freestanding Android
// runtime. A successful open takes ownership of the authenticated descriptor.
@[export: 'vinix_android_browser_open']
pub fn abi_open(fd i32) voidptr {
	return open(int(fd)) or { return unsafe { nil } }
}

@[export: 'vinix_android_browser_submit']
pub fn abi_submit(handle voidptr, op u16, view u64, generation u64, navigation u64,
	payload &u8, length u32) u64 {
	if handle == unsafe { nil } || length > browseripc.max_payload
		|| (length != 0 && payload == unsafe { nil }) {
		return 0
	}
	mut c := unsafe { &Client(handle) }
	bytes := if length == 0 { []u8{} } else { unsafe { payload.vbytes(int(length)) } }
	return c.submit(unsafe { browseripc.Op(op) }, view, generation, navigation, bytes) or { return 0 }
}

// The returned payload remains valid until the next read or close. The caller
// serializes read+copy across JNI threads before invoking any Java callback.
@[export: 'vinix_android_browser_read']
pub fn abi_read(handle voidptr, request u64, header &u8, payload &&u8, length &u32,
	timeout i32) i32 {
	if handle == unsafe { nil } || header == unsafe { nil } || payload == unsafe { nil }
		|| length == unsafe { nil } {
		return -1
	}
	mut c := unsafe { &Client(handle) }
	event := c.read(request, int(timeout)) or { return -1 }
	if !event.available { return 0 }
	wire := browseripc.encode_header(event.header, .engine_to_client) or {
		unsafe { event.payload.free() }
		return -1
	}
	unsafe {
		c.current.payload.free()
		c.current = event
		C.memcpy(header, wire.data, usize(wire.len))
		*payload = event.payload.data
		*length = u32(event.payload.len)
		wire.free()
	}
	return 1
}

@[export: 'vinix_android_browser_close']
pub fn abi_close(handle voidptr) {
	if handle == unsafe { nil } { return }
	mut c := unsafe { &Client(handle) }
	c.close()
	unsafe { free(c) }
}
