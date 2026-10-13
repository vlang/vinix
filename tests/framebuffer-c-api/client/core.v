// SPDX-License-Identifier: MIT
// A foreign ABI consumer: no V runtime, strings, arrays or client-module import.
@[translated]
module client

#include "vinix_window.h"
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <poll.h>

@[typedef]
struct C.vinix_window {}

@[typedef]
struct C.vinix_framebuffer {
mut:
	pixels &u32
	width  u32
	height u32
	stride u32
	format u32
}

@[typedef]
struct C.vinix_window_event {
mut:
	kind    u32
	x       i32
	y       i32
	value   i32
	length  u32
	payload [4096]u8
}

@[typedef]
struct C.vinix_window_error {
mut:
	message [256]char
}

struct C.pollfd {
mut:
	fd      i32
	events  i16
	revents i16
}

fn C.vinix_window_api_version() u32
fn C.vinix_window_open(&char, i32, i32, &C.vinix_window_error) &C.vinix_window
fn C.vinix_window_open_at(&char, &char, i32, i32, &C.vinix_window_error) &C.vinix_window
fn C.vinix_window_close(&C.vinix_window)
fn C.vinix_window_event_fd(&C.vinix_window) i32
fn C.vinix_window_get_framebuffer(&C.vinix_window, &C.vinix_framebuffer) i32
fn C.vinix_window_frame_pending(&C.vinix_window) i32
fn C.vinix_window_wants_write(&C.vinix_window) i32
fn C.vinix_window_present(&C.vinix_window, &C.vinix_window_error) i32
fn C.vinix_window_set_title(&C.vinix_window, &char, &C.vinix_window_error) i32
fn C.vinix_window_next_event(&C.vinix_window, &C.vinix_window_event, &C.vinix_window_error) i32
fn C.vinix_window_wait(&C.vinix_window, i32, &C.vinix_window_error) i32
fn C._Static_assert(bool, &char)
fn C.poll(&C.pollfd, usize, i32) i32
fn C.puts(&char) i32
fn C.exit(i32)
fn C.strstr(&char, &char) &char
fn C.strcmp(&char, &char) i32
fn C.setenv(&char, &char, i32) i32
fn C.memset(voidptr, i32, usize) voidptr

fn check(ok bool, message &char) {
	if !ok {
		C.puts(message)
		C.exit(1)
	}
}

@[export: 'main']
pub fn entry(argc i32, argv &&char) i32 {
	C._Static_assert(sizeof(C.vinix_window_event) == 4116, c'event ABI size')
	C._Static_assert(sizeof(C.vinix_framebuffer) == 24, c'framebuffer ABI size')
	C._Static_assert(sizeof(C.vinix_window_error) == 256, c'error ABI size')
	check(argc == 3, c'expected window socket and open mode arguments')
	check(C.vinix_window_api_version() == 2, c'API version')
	mut error := C.vinix_window_error{}
	mut event := C.vinix_window_event{ kind: 777 }
	mut buffer := C.vinix_framebuffer{}
	check(C.vinix_window_event_fd(nil) == -1, c'null descriptor')
	check(C.vinix_window_get_framebuffer(nil, unsafe { &buffer }) == -1, c'null framebuffer')
	check(C.vinix_window_frame_pending(nil) == -1, c'null pending')
	check(C.vinix_window_wants_write(nil) == -1, c'null output readiness')
	check(C.vinix_window_present(nil, unsafe { &error }) == -1 && error.message[0] != 0, c'null present')
	check(C.vinix_window_next_event(nil, unsafe { &event }, unsafe { &error }) == -1 && event.kind == 777, c'null event leaves output untouched')
	check(C.vinix_window_open(nil, 128, 96, unsafe { &error }) == nil && error.message[0] != 0, c'null title')
	check(C.vinix_window_open_at(nil, c'test', 128, 96, nil) == nil, c'null explicit socket')
	check(C.vinix_window_present(nil, nil) == -1, c'optional error output')
	check(C.vinix_window_set_title(nil, c'title', unsafe { &error }) == -1, c'null title handle')
	check(C.vinix_window_open(c'invalid', 0, 96, unsafe { &error }) == nil, c'invalid dimensions')
	mut long_title := [130]char{}
	C.memset(unsafe { &long_title[0] }, 65, 129)
	check(C.vinix_window_open(unsafe { &long_title[0] }, 128, 96, unsafe { &error }) == nil, c'oversized title')
	check(C.setenv(c'VINIX_WINDOW_SOCKET', unsafe { argv[1] }, 1) == 0, c'socket environment')
	window := if C.strcmp(unsafe { argv[2] }, c'explicit') == 0 {
		C.vinix_window_open_at(unsafe { argv[1] }, c'Foreign client', 128, 96, unsafe { &error })
	} else {
		C.vinix_window_open(c'Foreign client', 128, 96, unsafe { &error })
	}
	check(window != nil && error.message[0] == 0, c'open window')
	check(C.vinix_window_get_framebuffer(window, unsafe { &buffer }) == 0, c'get framebuffer')
	check(C.vinix_window_wants_write(window) == 0, c'initial output queue')
	check(buffer.width == 128 && buffer.height == 96 && buffer.stride == 512 && buffer.format == 1 && buffer.pixels != nil, c'framebuffer fields')
	check(C.vinix_window_get_framebuffer(window, nil) == -1, c'null framebuffer output')
	check(C.vinix_window_next_event(window, unsafe { &event }, unsafe { &error }) == 0 && event.kind == 777, c'nonblocking empty receive')
	check(C.vinix_window_wait(window, -2, unsafe { &error }) == -1, c'invalid wait timeout')
	check(C.vinix_window_wait(window, 0, unsafe { &error }) == 0 && error.message[0] == 0, c'empty wait')
	check(C.vinix_window_set_title(window, nil, unsafe { &error }) == -1, c'null new title')
	check(C.vinix_window_set_title(window, c'bad\ntitle', unsafe { &error }) == -1, c'control in title')
	check(C.vinix_window_set_title(window, c'Ardent terminal', unsafe { &error }) == 0, c'update title')
	unsafe {
		buffer.pixels[0] = 0x123456
		buffer.pixels[128 * 96 - 1] = 0xabcdef
	}
	check(C.vinix_window_present(window, unsafe { &error }) == 0, c'present')
	check(C.vinix_window_frame_pending(window) == 1, c'pending frame')
	check(C.vinix_window_present(window, unsafe { &error }) == -1 && C.strstr(unsafe { &error.message[0] }, c'frame_done') != nil, c'double present')
	mut poll := C.pollfd{ fd: C.vinix_window_event_fd(window), events: i16(C.POLLIN) }
	check(C.poll(unsafe { &poll }, 1, 5000) == 1, c'external poll on event fd')
	mut seen := u32(0)
	mut attempts := 0
	for seen != 15 && attempts < 512 {
		attempts++
		check(C.vinix_window_wait(window, 1000, unsafe { &error }) >= 0, c'wait for events')
		mut status := C.vinix_window_next_event(window, unsafe { &event }, unsafe { &error })
		for status == 1 {
			if event.kind == 11 {
				check(event.x == 160 && event.y == 112 && event.value == 1 && event.length > 0, c'resize offer')
				check(C.vinix_window_get_framebuffer(window, unsafe { &buffer }) == 0 && buffer.width == 160 && buffer.height == 112 && buffer.stride == 640, c'automatic resized mapping')
				check(C.vinix_window_frame_pending(window) == 1, c'old frame remains pending across resize')
				seen |= 8
			} else if event.kind == 4 {
				seen |= 1
			} else if event.kind == 5 {
				check(event.x == -12 && event.y == 34 && event.value == 3, c'signed event fields')
				seen |= 2
			} else if event.kind == 8 {
				check(event.length == 3 && event.payload[0] == 97 && event.payload[1] == 0 && event.payload[2] == 98, c'binary event payload')
				seen |= 4
			} else {
				check(false, c'unexpected event')
			}
			status = C.vinix_window_next_event(window, unsafe { &event }, unsafe { &error })
		}
		check(status == 0, c'event stream drain')
	}
	check(seen == 15 && C.vinix_window_frame_pending(window) == 0, c'acknowledgement releases framebuffer')
	unsafe { buffer.pixels[160 * 112 - 1] = 0x654321 }
	check(C.vinix_window_present(window, unsafe { &error }) == 0, c'present resized frame')
	for C.vinix_window_frame_pending(window) == 1 {
		check(C.vinix_window_wait(window, 5000, unsafe { &error }) >= 0, c'wait for resized frame')
		status := C.vinix_window_next_event(window, unsafe { &event }, unsafe { &error })
		check(status >= 0, c'resized frame event')
		if status == 1 { check(event.kind == 4 && event.value == 1, c'resized frame generation') }
	}
	C.vinix_window_close(window)
	C.vinix_window_close(nil)
	C.puts(c'WINDOW C ABI PASS')
	return 0
}
