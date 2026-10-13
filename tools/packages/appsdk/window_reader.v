// SPDX-License-Identifier: MIT
module appsdk

import encoding.utf8

const window_frame_keys = ['format', 'sequence', 'title', 'width', 'height', 'background', 'elements']
const window_element_keys = ['kind', 'id', 'text', 'x', 'y', 'width', 'height', 'color', 'background']
const window_event_keys = ['format', 'kind', 'sequence', 'id', 'text']

// This bounded schema has no recursive values. Owned JSON string parsing keeps
// escape/Unicode behavior without the pinned decoder's per-call allocation.
// Every partially decoded field is retired on failure.
struct WindowReader {
	text string
mut:
	position int
}

fn (mut r WindowReader) spaces() {
	for r.position < r.text.len && r.text[r.position] in [u8(` `), `\t`, `\r`, `\n`]! { r.position++ }
}

fn (mut r WindowReader) expect(byte u8) ! {
	r.spaces()
	if r.position >= r.text.len || r.text[r.position] != byte { return error('invalid native window JSON structure') }
	r.position++
}

fn (mut r WindowReader) next(first bool, end u8) !bool {
	r.spaces()
	if r.position < r.text.len && r.text[r.position] == end { r.position++; return false }
	if !first { r.expect(`,`)! }
	r.spaces()
	if r.position >= r.text.len || r.text[r.position] == end { return error('incomplete native window JSON member') }
	return true
}

fn (mut r WindowReader) quoted() !string {
	r.spaces()
	r.expect(`"`)!
	mut bytes := []u8{cap: 64}
	unsafe { bytes.flags |= .noslices }
	defer { unsafe { bytes.free() } }
	for r.position < r.text.len {
		byte := r.text[r.position]
		r.position++
		if byte == `"` {
			if !utf8.validate(bytes.data, bytes.len) { return error('invalid native window UTF-8 string') }
			return bytes.bytestr()
		}
		if byte < 32 { return error('unescaped native window JSON control character') }
		if byte != `\\` { bytes << byte; continue }
		if r.position >= r.text.len { return error('incomplete native window JSON escape') }
		escape := r.text[r.position]
		r.position++
		match escape {
			`"`, `\\`, `/` { bytes << escape }
			`n` { bytes << u8(10) }
			`r` { bytes << u8(13) }
			`t` { bytes << u8(9) }
			`b` { bytes << u8(8) }
			`f` { bytes << u8(12) }
			`u` {
				mut value := r.hex_unit()!
				if value >= 0xd800 && value <= 0xdbff {
					if r.position + 2 > r.text.len || r.text[r.position] != `\\` || r.text[r.position + 1] != `u` {
						return error('native window Unicode escape needs a low surrogate')
					}
					r.position += 2
					low := r.hex_unit()!
					if low < 0xdc00 || low > 0xdfff { return error('invalid native window low surrogate') }
					value = 0x10000 + ((value - 0xd800) << 10) + low - 0xdc00
				} else if value >= 0xdc00 && value <= 0xdfff { return error('unpaired native window low surrogate') }
				if value < 0x80 { bytes << u8(value) }
				else if value < 0x800 { bytes << u8(0xc0 | (value >> 6)); bytes << u8(0x80 | (value & 63)) }
				else if value < 0x10000 {
					bytes << u8(0xe0 | (value >> 12)); bytes << u8(0x80 | ((value >> 6) & 63)); bytes << u8(0x80 | (value & 63))
				} else {
					bytes << u8(0xf0 | (value >> 18)); bytes << u8(0x80 | ((value >> 12) & 63))
					bytes << u8(0x80 | ((value >> 6) & 63)); bytes << u8(0x80 | (value & 63))
				}
			}
			else { return error('invalid native window JSON escape') }
		}
	}
	return error('unterminated native window JSON string')
}

fn (mut r WindowReader) hex_unit() !u32 {
	if r.position + 4 > r.text.len { return error('incomplete native window Unicode escape') }
	mut value := u32(0)
	for _ in 0 .. 4 {
		byte := r.text[r.position]
		r.position++
		digit := if byte >= `0` && byte <= `9` { u32(byte - `0`) }
			else if byte >= `a` && byte <= `f` { u32(byte - `a` + 10) }
			else if byte >= `A` && byte <= `F` { u32(byte - `A` + 10) }
			else { return error('invalid native window Unicode hex digit') }
		value = (value << 4) | digit
	}
	return value
}

fn (mut r WindowReader) member(keys []string, seen u16) !int {
	key := r.quoted()!
	index := keys.index(key)
	unsafe { key.free() }
	if index < 0 { return error('unknown native window JSON field') }
	if seen & (u16(1) << index) != 0 { return error('duplicate native window JSON field') }
	r.expect(`:`)!
	return index
}

fn (mut r WindowReader) number(maximum u64) !u64 {
	r.spaces()
	start := r.position
	for r.position < r.text.len && r.text[r.position] >= `0` && r.text[r.position] <= `9` { r.position++ }
	if r.position == start { return error('native window JSON needs an unsigned integer') }
	text := unsafe { tos(r.text.str + start, r.position - start) }
	value := if text == '0' { u64(0) } else { counter(text)! }
	if value > maximum { return error('native window JSON integer exceeds its bound') }
	return value
}

fn close_window_elements(elements []WindowElement) {
	unsafe {
		for element in elements { element.kind.free(); element.id.free(); element.text.free() }
		(&array(&elements)).free()
	}
}

fn (mut r WindowReader) element() !WindowElement {
	r.expect(`{`)!
	mut element := WindowElement{ kind: '', id: '', text: '', x: 0, y: 0, width: 0, height: 0, color: 0, background: 0 }
	mut accepted := false
	defer { if !accepted { unsafe { element.kind.free(); element.id.free(); element.text.free() } } }
	mut seen := u16(0)
	mut first := true
	for r.next(first, `}`)! {
		first = false
		field := r.member(window_element_keys, seen)!
		seen |= u16(1) << field
		match field {
			0 { element = WindowElement{ ...element, kind: r.quoted()! } }
			1 { element = WindowElement{ ...element, id: r.quoted()! } }
			2 { element = WindowElement{ ...element, text: r.quoted()! } }
			3 { element = WindowElement{ ...element, x: int(r.number(2048)!) } }
			4 { element = WindowElement{ ...element, y: int(r.number(2048)!) } }
			5 { element = WindowElement{ ...element, width: int(r.number(2048)!) } }
			6 { element = WindowElement{ ...element, height: int(r.number(2048)!) } }
			7 { element = WindowElement{ ...element, color: u32(r.number(0xffffff)!) } }
			8 { element = WindowElement{ ...element, background: u32(r.number(0xffffff)!) } }
			else {}
		}
	}
	if seen != 0x1ff { return error('missing native window element field') }
	accepted = true
	return element
}

fn (mut r WindowReader) elements() ![]WindowElement {
	r.expect(`[` )!
	mut elements := []WindowElement{cap: 8}
	unsafe { elements.flags |= .noslices }
	mut accepted := false
	defer { if !accepted { close_window_elements(elements) } }
	mut first := true
	for r.next(first, `]`)! {
		first = false
		if elements.len == 128 { return error('native window element limit exceeded') }
		element := r.element()!
		unsafe { elements.push_many(&element, 1) }
	}
	accepted = true
	return elements
}

fn read_window_frame(text string) !WindowFrame {
	mut r := &WindowReader{ text: text }
	defer { unsafe { free(r) } }
	r.expect(`{`)!
	mut frame := WindowFrame{}
	mut accepted := false
	defer { if !accepted { frame.close() } }
	mut seen := u16(0)
	mut first := true
	for r.next(first, `}`)! {
		first = false
		field := r.member(window_frame_keys, seen)!
		seen |= u16(1) << field
		match field {
			0 { frame = WindowFrame{ ...frame, format: int(r.number(2)!) } }
			1 { frame = WindowFrame{ ...frame, sequence: r.number(~u64(0))! } }
			2 { frame = WindowFrame{ ...frame, title: r.quoted()! } }
			3 { frame = WindowFrame{ ...frame, width: int(r.number(2048)!) } }
			4 { frame = WindowFrame{ ...frame, height: int(r.number(2048)!) } }
			5 { frame = WindowFrame{ ...frame, background: u32(r.number(0xffffff)!) } }
			6 { frame = WindowFrame{ ...frame, elements: r.elements()! } }
			else {}
		}
	}
	r.spaces()
	if seen != 0x7f || r.position != text.len { return error('missing or trailing native window frame fields') }
	frame.validate()!
	accepted = true
	return frame
}

fn read_window_event_json(text string) !WindowEvent {
	mut r := &WindowReader{ text: text }
	defer { unsafe { free(r) } }
	r.expect(`{`)!
	mut event := WindowEvent{}
	mut accepted := false
	defer { if !accepted { event.close() } }
	mut seen := u16(0)
	mut first := true
	for r.next(first, `}`)! {
		first = false
		field := r.member(window_event_keys, seen)!
		seen |= u16(1) << field
		match field {
			0 { event = WindowEvent{ ...event, format: int(r.number(2)!) } }
			1 { event = WindowEvent{ ...event, kind: r.quoted()! } }
			2 { event = WindowEvent{ ...event, sequence: r.number(~u64(0))! } }
			3 { event = WindowEvent{ ...event, id: r.quoted()! } }
			4 { event = WindowEvent{ ...event, text: r.quoted()! } }
			else {}
		}
	}
	r.spaces()
	if seen != (if event.format == window_protocol { 15 } else { 31 }) || r.position != text.len {
		return error('missing or trailing native window event fields')
	}
	event.validate()!
	accepted = true
	return event
}
