// SPDX-License-Identifier: GPL-2.0-or-later
module pkgadmin

// Only byte-exact encode() output is accepted. This fixed, nonrecursive
// envelope owns every decoded string and retires partial requests on refusal.
struct RequestReader {
	text string
mut:
	at int
}

fn (mut reader RequestReader) expect(value string) ! {
	if value.len > reader.text.len - reader.at { return error('administrator package request is not canonical') }
	for index, byte in value {
		if reader.text[reader.at + index] != byte { return error('administrator package request is not canonical') }
	}
	reader.at += value.len
}

fn (mut reader RequestReader) quoted(limit int) !string {
	reader.expect('"')!
	mut bytes := []u8{cap: 64}
	unsafe { bytes.flags |= .noslices }
	defer { unsafe { bytes.free() } }
	for reader.at < reader.text.len {
		byte := reader.text[reader.at]; reader.at++
		if byte == `"` { return bytes.bytestr() }
		if bytes.len == limit || byte < 32 { return error('invalid administrator package request string') }
		if byte != `\\` { bytes << byte; continue }
		if reader.at == reader.text.len { return error('incomplete administrator package request escape') }
		escape := reader.text[reader.at]; reader.at++
		match escape {
			`"`, `\\` { bytes << escape }
			`b` { bytes << u8(8) }
			`f` { bytes << u8(12) }
			`n` { bytes << u8(10) }
			`r` { bytes << u8(13) }
			`t` { bytes << u8(9) }
			`u` {
				// The encoder emits Unicode escapes only for ASCII controls.
				reader.expect('00')!
				mut value := 0
				for _ in 0 .. 2 {
					if reader.at == reader.text.len { return error('incomplete administrator package request escape') }
					digit := reader.text[reader.at]; reader.at++
					value = value * 16 + if digit >= `0` && digit <= `9` { int(digit - `0`) }
						else if digit >= `a` && digit <= `f` { int(digit - `a` + 10) }
						else { return error('invalid administrator package request escape') }
				}
				if value >= 32 { return error('noncanonical administrator package request escape') }
				bytes << u8(value)
			}
			else { return error('invalid administrator package request escape') }
		}
	}
	return error('unterminated administrator package request string')
}

fn decode_request(text string) !Request {
	mut reader := &RequestReader{ text: text }
	defer { unsafe { free(reader) } }
	reader.expect('{"format":1,"nonce":')!
	nonce := reader.quoted(32)!
	mut values := []string{cap: 69}
	unsafe { values.flags |= .noslices }
	mut accepted := false
	defer {
		if !accepted {
			unsafe { nonce.free(); for value in values { value.free() }; (&array(&values)).free() }
		}
	}
	if !hex(nonce, 32) { return error('invalid administrator package request identity') }
	reader.expect(',"arguments":[')!
	for reader.at < text.len && text[reader.at] != `]` {
		if values.len == 69 { return error('invalid administrator package argument count') }
		if values.len != 0 { reader.expect(',')! }
		value := reader.quoted(4096)!
		unsafe { values.push_many(&value, 1) }
	}
	reader.expect(']}')!
	if reader.at != text.len { return error('administrator package request is not canonical') }
	request := Request{ nonce: nonce, arguments: values }
	canonical := request.encode()!
	defer { unsafe { canonical.free() } }
	if text != canonical { return error('administrator package request is not canonical') }
	accepted = true
	return request
}
