// SPDX-License-Identifier: MIT
module appsdk

import json2
import os
import encoding.utf8

#include <unistd.h>

fn C.read(int, voidptr, usize) isize
fn C.write(int, voidptr, usize) isize

pub const window_protocol = 1
pub const window_prefix = 'VINIX-WINDOW-FRAME '
pub const window_frame_limit = 65536
pub const window_event_limit = 512

// A bounded display list, with no executable actions, paths or resource URLs.
pub struct WindowElement {
pub:
	kind string @[required] // label, button, rect
	id string @[required] // button identity only
	text string @[required]
	x int @[required]
	y int @[required]
	width int @[required]
	height int @[required]
	color u32 @[required]
	background u32 @[required]
}

pub struct WindowFrame {
pub:
	format int = 1
	sequence u64
	title string
	width int
	height int
	background u32
	elements []WindowElement
}

pub struct WindowEvent {
pub:
	format int = 1
	kind string // click, close
	sequence u64 // displayed frame, zero when closing before the first frame
	id string
}

fn window_text(text string, maximum int) bool {
	if text.len > maximum || !utf8.validate_str(text) { return false }
	for byte in text { if byte < 32 || byte == 127 { return false } }
	return true
}

fn window_nesting(text string, maximum int) ! {
	mut depth := 0
	mut quoted := false
	mut escaped := false
	for byte in text {
		if quoted {
			if escaped { escaped = false }
			else if byte == `\\` { escaped = true }
			else if byte == `"` { quoted = false }
		} else if byte == `"` { quoted = true }
		else if byte in [u8(`{`), `[`]! {
			depth++
			if depth > maximum { return error('native window message exceeds its nesting limit') }
		} else if byte in [u8(`}`), `]`]! { depth-- }
	}
}

pub fn (frame &WindowFrame) validate() ! {
	if frame.format != window_protocol || frame.sequence == 0 || frame.title == ''
		|| !window_text(frame.title, 128) || frame.width < 64 || frame.height < 64
		|| frame.width > 2048 || frame.height > 2048 || frame.background > 0xffffff || frame.elements.len > 128 {
		return error('invalid native window frame')
	}
	mut ids := map[string]bool{}
	defer { unsafe { ids.free() } }
	for element in frame.elements {
		if element.kind !in ['label', 'button', 'rect'] || !window_text(element.text, 2048)
			|| element.x < 0 || element.y < 0 || element.width < 1 || element.height < 1
			|| element.x > frame.width || element.y > frame.height
			|| element.width > frame.width - element.x || element.height > frame.height - element.y
			|| element.color > 0xffffff || element.background > 0xffffff {
			return error('invalid native window element')
		}
		if element.kind == 'button' {
			if !identifier(element.id) || element.id.len > 64 || element.id in ids { return error('invalid native window button identity') }
			ids[element.id] = true
		} else if element.id != '' || (element.kind == 'rect' && element.text != '') {
			return error('native window non-button elements cannot request actions')
		}
	}
}

pub fn decode_window_frame(text string) !WindowFrame {
	if text.len > window_frame_limit { return error('native window frame exceeds its size limit') }
	window_nesting(text, 3)!
	return read_window_frame(text)
}

pub fn (frame &WindowFrame) encode() !string {
	frame.validate()!
	mut bytes := []u8{cap: 2048}
	unsafe { bytes.flags |= .noslices }
	defer { unsafe { bytes.free() } }
	json2.encode_append(frame, mut bytes)
	text := bytes.bytestr()
	if text.len > window_frame_limit { unsafe { text.free() }; return error('native window frame exceeds its size limit') }
	return text
}

// Only decoded frames own these fields. Publisher-created frames borrow theirs.
pub fn (mut frame WindowFrame) close() {
	unsafe {
		frame.title.free()
		for element in frame.elements { element.kind.free(); element.id.free(); element.text.free() }
		(&array(&frame.elements)).free()
	}
	frame = WindowFrame{}
}

pub fn (event &WindowEvent) validate() ! {
	if event.format != window_protocol || event.kind !in ['click', 'close']
		|| (event.kind == 'click' && (event.sequence == 0 || !identifier(event.id) || event.id.len > 64))
		|| (event.kind == 'close' && event.id != '') { return error('invalid native window event') }
}

pub fn (event &WindowEvent) encode() !string {
	event.validate()!
	mut bytes := []u8{cap: 512}
	unsafe { bytes.flags |= .noslices }
	defer { unsafe { bytes.free() } }
	json2.encode_append(event, mut bytes)
	text := bytes.bytestr()
	if text.len >= window_event_limit { unsafe { text.free() }; return error('native window event exceeds its size limit') }
	return text
}

pub fn decode_window_event(text string) !WindowEvent {
	if text.len >= window_event_limit { return error('native window event exceeds its size limit') }
	window_nesting(text, 1)!
	return read_window_event_json(text)
}

pub fn (mut event WindowEvent) close() {
	unsafe { event.kind.free(); event.id.free() }
	event = WindowEvent{}
}

pub fn publish_window_frame(frame WindowFrame) ! {
	protocol := os.getenv('VINIX_WINDOW_PROTOCOL')
	defer { unsafe { protocol.free() } }
	if protocol != '1' { return error('launch this application with the native window broker') }
	text := frame.encode()!
	line := window_prefix + text + '\n'
	defer { unsafe { text.free(); line.free() } }
	mut sent := 0
	for sent < line.len {
		written := C.write(1, unsafe { line.str + sent }, usize(line.len - sent))
		if written < 0 && C.errno == C.EINTR { continue }
		if written <= 0 { return error('native window output is unavailable') }
		sent += int(written)
	}
}

// EOF is a close request, including forced broker retirement. Input is bounded
// before decoding; no application needs to link compositor internals.
pub fn read_window_event() !WindowEvent {
	mut bytes := [window_event_limit]u8{}
	mut used := 0
	for used < bytes.len {
		count := C.read(0, unsafe { &bytes[used] }, 1)
		if count < 0 && C.errno == C.EINTR { continue }
		if count < 0 { return error('native window input is unavailable') }
		if count == 0 {
			if used > 0 { return error('incomplete native window event') }
			return WindowEvent{ kind: 'close'.clone(), id: ''.clone() }
		}
		if bytes[used] == `\n` { return decode_window_event(unsafe { tos(&bytes[0], used) }) }
		used++
	}
	return error('native window event exceeds its size limit')
}
