// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import os
import guestvalidation

#include <stdlib.h>
#include <string.h>

fn C.malloc(usize) voidptr
fn C.free(voidptr)
fn C.strcmp(&char, &char) int

__global live_allocations int
__global displays int

fn allocated(data []u8) voidptr {
	pointer := C.malloc(usize(data.len))
	if pointer == unsafe { nil } { panic('mock allocation') }
	unsafe {
		for index, byte in data { (&u8(pointer))[index] = byte }
	}
	live_allocations++
	return pointer
}

@[export:'XOpenDisplay']
pub fn x_open(name &char) voidptr {
	if unsafe { name.vstring() } == 'absent' { return unsafe { nil } }
	displays++
	return voidptr(1)
}

@[export:'XCloseDisplay']
pub fn x_close(_ voidptr) i32 {
	displays--
	return 0
}

@[export:'XDefaultRootWindow']
pub fn x_root(_ voidptr) u64 { return 1 }

@[export:'XQueryTree']
pub fn x_tree(_ voidptr, window u64, root &u64, parent &u64, children &&u64, count &u32) i32 {
	mut values := []u64{}
	if window == 1 {
		values = [u64(2), 3]
	} else if window >= 3 && window < 14 {
		values = [window + 1]
	}
	unsafe {
		*root = 1
		*parent = 0
		*count = u32(values.len)
		*children = nil
		if values.len > 0 {
			*children = &u64(allocated(values.data.vbytes(values.len * int(sizeof(u64))).clone()))
		}
	}
	return if os.getenv('VINIX_XMOCK_MODE') == 'tree-error' { 0 } else { 1 }
}

@[export:'XGetWindowAttributes']
pub fn x_attributes(_ voidptr, window u64, attributes &guestvalidation.WindowAttributes) i32 {
	unsafe { attributes.map_state = if window == 2 { 0 } else { 2 } }
	return 1
}

@[export:'XFetchName']
pub fn x_fetch(_ voidptr, window u64, title &&char) i32 {
	mode := os.getenv('VINIX_XMOCK_MODE')
	text := if window == 2 {
		'Target hidden'
	} else if mode == 'legacy' && window == 3 {
		'Legacy Target'
	} else if mode == 'deep' && window == 14 {
		'Deep Target'
	} else {
		''
	}
	if text == '' {
		unsafe { *title = nil }
		return 0
	}
	mut bytes := text.bytes()
	bytes << u8(0)
	unsafe { *title = &char(allocated(bytes)) }
	return 1
}

@[export:'XInternAtom']
pub fn x_atom(_ voidptr, name &char, only_existing i32) u64 {
	assert only_existing == 1
	return if C.strcmp(name, c'_NET_WM_NAME') == 0 {
		1
	} else if C.strcmp(name, c'UTF8_STRING') == 0 {
		2
	} else {
		0
	}
}

@[export:'XGetWindowProperty']
pub fn x_property(_ voidptr, window u64, atom u64, offset i64, length i64, delete i32, requested u64, actual &u64, format &i32, items &u64, remaining &u64, data &&u8) i32 {
	assert atom == 1 && offset == 0 && length == 1024 && delete == 0 && requested == 2
	text := if window == 3 && os.getenv('VINIX_XMOCK_MODE') in ['utf8', 'nested', 'property-error'] {
		'Target\xff'.bytes()
	} else if window == 5 && os.getenv('VINIX_XMOCK_MODE') == 'nested' {
		'Nested Target'.bytes()
	} else {
		[]u8{}
	}
	unsafe {
		*actual = 2
		*format = 8
		*items = u64(text.len)
		*remaining = 0
		*data = nil
		if text.len > 0 { *data = &u8(allocated(text)) }
	}
	return if os.getenv('VINIX_XMOCK_MODE') == 'property-error' { 1 } else { 0 }
}

@[export:'XFree']
pub fn x_free(pointer voidptr) i32 {
	assert pointer != unsafe { nil }
	live_allocations--
	assert live_allocations >= 0
	C.free(pointer)
	return 0
}

@[export:'vinix_xfixture_live']
pub fn x_live() int { return live_allocations + displays }
