// SPDX-License-Identifier: GPL-2.0-or-later
// Read-only static HTML for APK help/changelog panels. Rendering uses the same
// native text layout as Android widgets. This is not a JavaScript web engine.
@[translated]
module atlframework

#include <strings.h>

fn C.strncasecmp(&char, &char, usize) i32

fn ws_html_name(text &char, length usize, name &char) bool {
	return length == C.strlen(name) && C.strncasecmp(text, name, length) == 0
}

fn ws_html_utf8(buffer &u8, code u32) usize {
	unsafe {
		if code < 128 {
			buffer[0] = u8(code)
			return 1
		}
		if code < 2048 {
			buffer[0] = u8(192 + (code >> 6))
			buffer[1] = u8(128 + (code & 63))
			return 2
		}
		if code < 65536 {
			buffer[0] = u8(224 + (code >> 12))
			buffer[1] = u8(128 + ((code >> 6) & 63))
			buffer[2] = u8(128 + (code & 63))
			return 3
		}
		buffer[0] = u8(240 + (code >> 18))
		buffer[1] = u8(128 + ((code >> 12) & 63))
		buffer[2] = u8(128 + ((code >> 6) & 63))
		buffer[3] = u8(128 + (code & 63))
		return 4
	}
}

fn ws_html_text(source &char) &char {
	unsafe {
		length := C.strlen(source)
		output := &u8(C.malloc(length + 1))
		mut used := usize(0)
		mut at := usize(0)
		mut skip := i32(0)
		for at < length {
			c := source[at]
			if c == `<` {
				mut end := at + 1
				for end < length && source[end] != `>` { end++ }
				if end == length { break }
				mut start := at + 1
				closing := source[start] == `/`
				if closing { start++ }
				finish := start
				mut name_end := finish
				for name_end < end && ((source[name_end] >= `a` && source[name_end] <= `z`) || (source[name_end] >= `A` && source[name_end] <= `Z`) || (source[name_end] >= `0` && source[name_end] <= `9`)) {
					name_end++
				}
				name := &source[start]
				size := name_end - start
				hidden := if ws_html_name(name, size, c'head') {
					1
				} else if ws_html_name(name, size, c'style') {
					2
				} else if ws_html_name(name, size, c'script') {
					3
				} else {
					0
				}
				if skip != 0 {
					if closing && hidden == skip { skip = 0 }
				} else if !closing && hidden != 0 {
					skip = hidden
				} else if ws_html_name(name, size, c'p') || ws_html_name(name, size, c'div') || ws_html_name(name, size, c'br') || ws_html_name(name, size, c'li') || ws_html_name(name, size, c'tr') || (size == 2 && (name[0] == `h` || name[0] == `H`) && name[1] >= `1` && name[1] <= `6`) {
					if used > 0 && output[used - 1] != 10 {
						output[used] = 10
						used++
					}
					if !closing && ws_html_name(name, size, c'li') {
						output[used] = `-`
						output[used + 1] = ` `
						used += 2
					}
				}
				at = end + 1
				continue
			}
			if skip != 0 {
				at++
				continue
			}
			if c == `&` {
				mut end := at + 1
				for end < length && end - at < 12 && source[end] != `;` { end++ }
				if end < length && source[end] == `;` {
					name := &source[at + 1]
					size := end - at - 1
					mut code := u32(0)
					if ws_html_name(name, size, c'amp') {
						code = `&`
					} else if ws_html_name(name, size, c'lt') {
						code = `<`
					} else if ws_html_name(name, size, c'gt') {
						code = `>`
					} else if ws_html_name(name, size, c'quot') {
						code = `"`
					} else if ws_html_name(name, size, c'apos') {
						code = 39
					} else if ws_html_name(name, size, c'nbsp') {
						code = 32
					} else if ws_html_name(name, size, c'copy') {
						code = 169
					} else if ws_html_name(name, size, c'ndash') {
						code = 0x2013
					} else if ws_html_name(name, size, c'mdash') {
						code = 0x2014
					} else if size > 1 && name[0] == `#` {
						mut index := usize(1)
						hex := name[1] == `x` || name[1] == `X`
						if hex { index++ }
						for index < size {
							digit := name[index]
							value := if digit >= `0` && digit <= `9` {
								i32(digit - `0`)
							} else if hex && digit >= `a` && digit <= `f` {
								i32(digit - `a` + 10)
							} else if hex && digit >= `A` && digit <= `F` {
								i32(digit - `A` + 10)
							} else {
								-1
							}
							if value < 0 {
								code = 0
								break
							}
							code = code * if hex { u32(16) } else { u32(10) } + u32(value)
							index++
						}
					}
					if code > 0 && code <= 0x10ffff && !(code >= 0xd800 && code <= 0xdfff) {
						used += ws_html_utf8(&output[used], code)
						at = end + 1
						continue
					}
				}
			}
			if u8(c) <= 32 {
				if used > 0 && output[used - 1] != 10 && output[used - 1] != 32 {
					output[used] = 32
					used++
				}
			} else {
				output[used] = u8(c)
				used++
			}
			at++
		}
		output[used] = 0
		return &char(output)
	}
}

fn ws_web_new(e voidptr, view voidptr) i64 {
	unsafe {
		PutBoolean(slot(e, 105))(e, view, field(e, c'android/view/View', c'haveCustomMeasure', c'Z'), 0)
		pointer := ws_view_new(6)
		(&WsView(pointer)).background = 0xffffffff
		(&WsView(pointer)).size = 16
		return pointer
	}
}

fn ws_web_data(e voidptr, view voidptr, base voidptr, data voidptr, mime voidptr) {
	unsafe {
		kind := ws_utf(e, mime)
		if mime != nil && !ws_html_name(kind, C.strlen(kind), c'text/html') && !ws_html_name(kind, C.strlen(kind), c'text/plain') {
			ws_release(e, mime, kind)
			ThrowNew(slot(e, 14))(e, cls(e, c'java/lang/UnsupportedOperationException'), c'Native WebView supports static text/html and text/plain data')
			return
		}
		plain := mime != nil && ws_html_name(kind, C.strlen(kind), c'text/plain')
		ws_release(e, mime, kind)
		source := ws_utf(e, data)
		text := if plain { C.strdup(source) } else { ws_html_text(source) }
		ws_release(e, data, source)
		widget := ws_view(e, view)
		C.free(widget.text)
		widget.text = text
		call(e, view, c'android/view/View', c'requestLayout', c'()V', nil)
		args := [Value{ i: 0 }, Value{ l: base }]!
		call(e, view, c'android/webkit/WebView', c'internalLoadChanged', c'(ILjava/lang/String;)V', &args[0])
		finished := [Value{ i: 3 }, Value{ l: base }]!
		call(e, view, c'android/webkit/WebView', c'internalLoadChanged', c'(ILjava/lang/String;)V', &finished[0])
		ws_mark()
	}
}
