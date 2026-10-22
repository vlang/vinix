// SPDX-License-Identifier: GPL-2.0-or-later
module pkglaunch

// The wire contract already requires byte-exact encode() output. Parse only
// that fixed, nonrecursive envelope, owning every accepted field and retiring
// partial arrays/strings on refusal. Argument bytes keep their existing Unix
// contract: they need not be UTF-8, but cannot contain NUL.
struct RequestReader {
	text string
mut:
	at int
}

fn (mut reader RequestReader) expect(value string) ! {
	if value.len > reader.text.len - reader.at { return error('isolated package request is not canonical') }
	for index, byte in value {
		if reader.text[reader.at + index] != byte { return error('isolated package request is not canonical') }
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
		if bytes.len == limit || byte < 32 { return error('invalid isolated package request string') }
		if byte != `\\` { bytes << byte; continue }
		if reader.at == reader.text.len { return error('incomplete isolated package request escape') }
		escape := reader.text[reader.at]; reader.at++
		match escape {
			`"`, `\\` { bytes << escape }
			`b` { bytes << u8(8) }
			`f` { bytes << u8(12) }
			`n` { bytes << u8(10) }
			`r` { bytes << u8(13) }
			`t` { bytes << u8(9) }
			`u` {
				// encode() emits Unicode escapes only for ASCII controls. Other
				// escapes (including alternate spellings) cannot be canonical.
				reader.expect('00')!
				mut value := 0
				for _ in 0 .. 2 {
					if reader.at == reader.text.len { return error('incomplete isolated package request escape') }
					digit := reader.text[reader.at]; reader.at++
					value = value * 16 + if digit >= `0` && digit <= `9` { int(digit - `0`) }
						else if digit >= `a` && digit <= `f` { int(digit - `a` + 10) }
						else { return error('invalid isolated package request escape') }
				}
				if value >= 32 { return error('noncanonical isolated package request escape') }
				bytes << u8(value)
			}
			else { return error('invalid isolated package request escape') }
		}
	}
	return error('unterminated isolated package request string')
}

fn decode_request(text string) !Request {
	mut reader := &RequestReader{ text: text }
	defer { unsafe { free(reader) } }
	format := if text.starts_with('{"format":2,') { 2 } else { 1 }
	if format == 2 { reader.expect('{"format":2,"nonce":')! }
	else { reader.expect('{"format":1,"nonce":')! }
	nonce := reader.quoted(32)!
	mut display := ''
	mut authority := ''
	mut values := []string{cap: 16}
	unsafe { values.flags |= .noslices }
	mut accepted := false
	defer {
		if !accepted {
			unsafe { nonce.free(); display.free(); authority.free(); for value in values { value.free() }; (&array(&values)).free() }
		}
	}
	if !valid_nonce(nonce) { return error('invalid isolated package request identity') }
	reader.expect(',"arguments":[')!
	for reader.at < text.len && text[reader.at] != `]` {
		if values.len == 772 { return error('invalid isolated package launch') }
		if values.len != 0 { reader.expect(',')! }
		values << reader.quoted(4096)!
	}
	reader.expect(']')!
	if format == 2 {
		reader.expect(',"display":')!
		display = reader.quoted(6)!
		reader.expect(',"authority":')!
		authority = reader.quoted(192)!
	}
	reader.expect('}')!
	if reader.at != text.len { return error('isolated package request is not canonical') }
	request := Request{ format: format, nonce: nonce, arguments: values, display: display, authority: authority }
	canonical := request.encode()!
	defer { unsafe { canonical.free() } }
	if text != canonical { return error('isolated package request is not canonical') }
	accepted = true
	return request
}
