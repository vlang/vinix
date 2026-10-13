// SPDX-License-Identifier: MIT
module appsdk

import json2
import os
import encoding.utf8

#include <unistd.h>

fn C.read(int, voidptr, usize) isize
fn C.write(int, voidptr, usize) isize

pub const window_protocol = 1
pub const window_text_protocol = 2
pub const window_prefix = 'VINIX-WINDOW-FRAME '
pub const window_frame_limit = 65536
pub const window_event_limit = 512
pub const window_text_event_limit = 2048
pub const window_input_limit = 256

// A bounded display list, with no executable actions, paths or resource URLs.
pub struct WindowElement {
pub:
	kind string @[required] // label, button, rect; protocol 2 also input
	id string @[required] // button/input identity only
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
	kind string // click, close; protocol 2 also text
	sequence u64 // displayed frame, zero when closing before the first frame
	id string
	text string @[omitempty] // protocol 1 serialization stays unchanged
}

// Protocol 2 always carries text, including an empty field replacement.
struct WindowTextEvent {
	format int
	kind string
	sequence u64
	id string
	text string
}

pub fn validate_window_input(text string) ! {
	if !window_text(text, window_input_limit) { return error('native window input needs valid single-line UTF-8, at most 256 bytes') }
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
	if frame.format !in [window_protocol, window_text_protocol] || frame.sequence == 0 || frame.title == ''
		|| !window_text(frame.title, 128) || frame.width < 64 || frame.height < 64
		|| frame.width > 2048 || frame.height > 2048 || frame.background > 0xffffff || frame.elements.len > 128 {
		return error('invalid native window frame')
	}
	mut ids := map[string]bool{}
	defer { unsafe { ids.free() } }
	for element in frame.elements {
		if element.kind !in ['label', 'button', 'rect', 'input'] || !window_text(element.text, 2048)
			|| element.x < 0 || element.y < 0 || element.width < 1 || element.height < 1
			|| element.x > frame.width || element.y > frame.height
			|| element.width > frame.width - element.x || element.height > frame.height - element.y
			|| element.color > 0xffffff || element.background > 0xffffff {
			return error('invalid native window element')
		}
		if element.kind in ['button', 'input'] {
			if element.kind == 'input' {
				if frame.format != window_text_protocol { return error('native window inputs require protocol 2') }
				validate_window_input(element.text)!
			}
			if !identifier(element.id) || element.id.len > 64 || element.id in ids { return error('invalid native window control identity') }
			ids[element.id] = true
		} else if element.id != '' || (element.kind == 'rect' && element.text != '') {
			return error('native window decorative elements cannot request actions')
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
	if event.format !in [window_protocol, window_text_protocol] || event.kind !in ['click', 'close', 'text']
		|| (event.kind in ['click', 'text'] && (event.sequence == 0 || !identifier(event.id) || event.id.len > 64))
		|| (event.kind == 'close' && event.id != '') { return error('invalid native window event') }
	if event.kind == 'text' {
		if event.format != window_text_protocol { return error('native window text events require protocol 2') }
		validate_window_input(event.text)!
	} else if event.text != '' { return error('native window button/close events cannot carry text') }
}

// Applications must bind input to the exact frame and control they published.
// EOF's synthetic close (sequence zero) is also accepted for clean retirement.
pub fn (frame &WindowFrame) accepts(event &WindowEvent) bool {
	event.validate() or { unsafe { err.free() }; return false }
	if event.format != frame.format { return false }
	if event.kind == 'close' { return event.sequence == 0 || event.sequence == frame.sequence }
	if event.sequence != frame.sequence { return false }
	kind := if event.kind == 'text' { 'input' } else { 'button' }
	return frame.elements.any(it.kind == kind && it.id == event.id)
}

pub fn (event &WindowEvent) encode() !string {
	event.validate()!
	mut bytes := []u8{cap: 512}
	unsafe { bytes.flags |= .noslices }
	defer { unsafe { bytes.free() } }
	if event.format == window_protocol { json2.encode_append(event, mut bytes) }
	else { json2.encode_append(WindowTextEvent{ format: event.format, kind: event.kind,
		sequence: event.sequence, id: event.id, text: event.text }, mut bytes) }
	text := bytes.bytestr()
	limit := if event.format == window_protocol { window_event_limit } else { window_text_event_limit }
	if text.len >= limit { unsafe { text.free() }; return error('native window event exceeds its size limit') }
	return text
}

pub fn decode_window_event(text string) !WindowEvent {
	if text.len >= window_text_event_limit { return error('native window event exceeds its size limit') }
	window_nesting(text, 1)!
	mut event := read_window_event_json(text)!
	if event.format == window_protocol && text.len >= window_event_limit {
		event.close(); return error('native window event exceeds its size limit')
	}
	return event
}

pub fn (mut event WindowEvent) close() {
	unsafe { event.kind.free(); event.id.free(); event.text.free() }
	event = WindowEvent{}
}

pub fn publish_window_frame(frame WindowFrame) ! {
	protocol := os.getenv('VINIX_WINDOW_PROTOCOL')
	defer { unsafe { protocol.free() } }
	if (frame.format == window_protocol && protocol != '1') || (frame.format == window_text_protocol && protocol != '2') {
		return error('launch this application with its declared native window broker protocol')
	}
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
	return read_window_event_for(window_protocol)
}

// Explicit negotiation preserves the protocol-1 reader and its 512-byte limit.
pub fn read_window_event_for(protocol int) !WindowEvent {
	if protocol !in [window_protocol, window_text_protocol] { return error('unsupported native window input protocol') }
	limit := if protocol == window_protocol { window_event_limit } else { window_text_event_limit }
	mut bytes := [window_text_event_limit]u8{}
	mut used := 0
	for used < limit {
		count := C.read(0, unsafe { &bytes[used] }, 1)
		if count < 0 && C.errno == C.EINTR { continue }
		if count < 0 { return error('native window input is unavailable') }
		if count == 0 {
			if used > 0 { return error('incomplete native window event') }
			return WindowEvent{ format: protocol, kind: 'close'.clone(), id: ''.clone(), text: ''.clone() }
		}
		if bytes[used] == `\n` {
			mut event := decode_window_event(unsafe { tos(&bytes[0], used) })!
			if event.format != protocol { event.close(); return error('native window input protocol differs from the declared protocol') }
			return event
		}
		used++
	}
	return error('native window event exceeds its size limit')
}
