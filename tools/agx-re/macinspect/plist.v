module macinspect

import math
import math.big
import strings
import traceanalysis as j

#flag -lexpat
#include <expat.h>

fn C.XML_ParserCreate(&char) voidptr
fn C.XML_ParserFree(voidptr)
fn C.XML_SetUserData(voidptr, voidptr)
fn C.XML_SetElementHandler(voidptr, fn (voidptr, &char, &&char), fn (voidptr, &char))
fn C.XML_SetCharacterDataHandler(voidptr, fn (voidptr, &char, i32))
fn C.XML_SetEntityDeclHandler(voidptr, fn (voidptr, &char, i32, &char, i32, &char, &char, &char, &char))
fn C.XML_Parse(voidptr, &char, i32, i32) i32
fn C.XML_GetCurrentLineNumber(voidptr) usize
fn C.XML_GetCurrentColumnNumber(voidptr) usize
fn C.XML_GetErrorCode(voidptr) i32
fn C.XML_ErrorString(i32) &char

struct PlistXmlFrame {
mut:
	value   Property
	key     string
	has_key bool
}

struct PlistXml {
	parser voidptr
mut:
	root    Property
	stack   []PlistXmlFrame
	data    strings.Builder
	failure string
}

fn (mut x PlistXml) add(p Property) ! {
	if x.stack.len == 0 {
		x.root = p
		return
	}
	mut frame := &x.stack[x.stack.len - 1]
	if frame.has_key {
		if frame.value.kind != .object {
			return error('unexpected element at line ${C.XML_GetCurrentLineNumber(x.parser)}')
		}
		frame.value.fields[frame.key] = p
		frame.key = ''
		frame.has_key = false
	} else {
		if frame.value.kind != .array {
			return error('unexpected element at line ${C.XML_GetCurrentLineNumber(x.parser)}')
		}
		frame.value.array << p
	}
}

fn plist_xml_start(pointer voidptr, name &char, _attributes &&char) {
	mut x := unsafe { &PlistXml(pointer) }
	if x.failure != '' { return }
	x.data.clear()
	tag := unsafe { cstring_to_vstring(name) }
	if tag in ['array', 'dict'] {
		x.stack << PlistXmlFrame{
			value: Property{
				kind: if tag == 'array' {
					.array
				} else {
					.object
				}
			}
		}
	}
}

fn plist_xml_text(pointer voidptr, data &char, count i32) {
	mut x := unsafe { &PlistXml(pointer) }
	if x.failure == '' { unsafe { x.data.write_ptr(data, int(count)) } }
}

fn plist_xml_entity(pointer voidptr, _name &char, _parameter i32, _data &char, _count i32, _base &char, _system_id &char, _public_id &char, _notation &char) {
	mut x := unsafe { &PlistXml(pointer) }
	x.failure = 'XML entity declarations are not supported in plist files'
}

fn python_space(r rune) bool {
	return r in [rune(9), 10, 11, 12, 13, 28, 29, 30, 31, 32, 0x85, 0xa0, 0x1680, 0x2000, 0x2001,
		0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200a, 0x2028, 0x2029,
		0x202f, 0x205f, 0x3000]
}

fn plist_integer(text string) !string {
	hex := text.starts_with('0x') || text.starts_with('0X')
	radix := if hex { u32(16) } else { u32(10) }
	mut runes := (if hex { text[2..] } else { text }).runes()
	for runes.len > 0 && python_space(runes[0]) { runes.delete(0) }
	for runes.len > 0 && python_space(runes.last()) { runes.pop() }
	mut negative := false
	if runes.len > 0 && runes[0] in [rune(`+`), `-`] {
		negative = runes[0] == `-`
		runes.delete(0)
	}
	if hex && runes.len > 0 && runes[0] == `_` { runes.delete(0) }
	mut digits := ''
	mut separator := false
	for r in runes {
		if r == `_` && digits != '' && !separator {
			separator = true
			continue
		}
		digit := decimal_digit(r)
		if digit >= 0 {
			digits += digit.str()
		} else if hex && r in [rune(`a`), `b`, `c`, `d`, `e`, `f`, `A`, `B`, `C`, `D`, `E`, `F`] {
			digits += r.str()
		} else {
			return error('invalid literal for int() with base ${radix}: ${j.quoted(text)}')
		}
		separator = false
	}
	if digits == '' || separator {
		return error('invalid literal for int() with base ${radix}: ${j.quoted(text)}')
	}
	n := big.integer_from_radix(digits, radix)!
	return if negative { n.neg().str() } else { n.str() }
}

fn decode_plist_base64(raw string) ![]u8 {
	mut output := []u8{}
	mut position := 0
	mut previous := 0
	mut padding := 0
	mut characters := 0
	for c in raw.bytes() {
		if c == `=` {
			if position >= 2 {
				padding++
				if position + padding >= 4 { return output }
			}
			continue
		}
		digit := if c >= `A` && c <= `Z` {
			int(c - `A`)
		} else if c >= `a` && c <= `z` {
			int(c - `a`) + 26
		} else if c >= `0` && c <= `9` {
			int(c - `0`) + 52
		} else if c == `+` {
			62
		} else if c == `/` {
			63
		} else {
			-1
		}
		if digit < 0 { continue }
		padding = 0
		characters++
		match position {
			0 { previous = digit }
			1 {
				output << u8((previous << 2) | (digit >> 4))
				previous = digit & 15
			}
			2 {
				output << u8((previous << 4) | (digit >> 2))
				previous = digit & 3
			}
			3 { output << u8((previous << 6) | digit) }
			else {}
		}
		position = (position + 1) & 3
	}
	if position == 1 {
		return error('Invalid base64-encoded string: number of data characters (${characters}) cannot be 1 more than a multiple of 4')
	}
	if position != 0 { return error('Incorrect padding') }
	return output
}

fn validate_date(raw string) ! {
	runes := raw.runes()
	mut fields := []int{}
	mut offset := 0
	for index, separator in ['', '-', '-', 'T', ':', ':'] {
		if index != 0 {
			if offset < runes.len && runes[offset] == `Z` { break }
			if offset >= runes.len || runes[offset].str() != separator {
				return error("'NoneType' object has no attribute 'groupdict'")
			}
			offset++
		}
		width := if index == 0 { 4 } else { 2 }
		mut n := 0
		for _ in 0 .. width {
			if offset >= runes.len {
				return error("'NoneType' object has no attribute 'groupdict'")
			}
			digit := decimal_digit(runes[offset])
			offset++
			if digit < 0 { return error("'NoneType' object has no attribute 'groupdict'") }
			n = n * 10 + digit
		}
		fields << n
	}
	if offset >= runes.len || runes[offset] != `Z` {
		return error("'NoneType' object has no attribute 'groupdict'")
	}
	if fields.len < 3 {
		return error("function missing required argument '${if fields.len == 1 {
			'month'
		} else {
			'day'
		}}' (pos ${fields.len + 1})")
	}
	if fields[0] < 1 { return error('year ${fields[0]} is out of range') }
	if fields[1] < 1 || fields[1] > 12 { return error('month must be in 1..12') }
	leap := fields[0] % 4 == 0 && (fields[0] % 100 != 0 || fields[0] % 400 == 0)
	days := [31, if leap { 29 } else { 28 }, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][fields[1] - 1]
	if fields[2] < 1 || fields[2] > days { return error('day is out of range for month') }
	for index in 3 .. fields.len {
		limit := if index == 3 { 23 } else { 59 }
		if fields[index] > limit {
			return error('${['year', 'month', 'day', 'hour', 'minute', 'second'][index]} must be in 0..${limit}')
		}
	}
}

fn plist_xml_value(mut x PlistXml, tag string) ! {
	if tag in ['array', 'dict'] {
		if x.stack.len == 0 { return error('pop from empty list') }
		frame := x.stack.pop()
		if tag == 'dict' && frame.has_key && frame.key != '' {
			return error("missing value for key '${frame.key}' at line ${C.XML_GetCurrentLineNumber(x.parser)}")
		}
		x.add(frame.value)!
		return
	}
	if tag == 'key' {
		if x.stack.len == 0 || x.stack.last().value.kind != .object || (x.stack.last().has_key && x.stack.last().key != '') {
			return error('unexpected key at line ${C.XML_GetCurrentLineNumber(x.parser)}')
		}
		x.stack[x.stack.len - 1].key = x.data.str()
		x.stack[x.stack.len - 1].has_key = true
		return
	}
	match tag {
		'true', 'false' { x.add(Property{ kind: .boolean, boolean: tag == 'true' })! }
		'integer' { x.add(Property{ kind: .number, text: plist_integer(x.data.str())! })! }
		'real' {
			raw := x.data.str().trim_space()
			// libc supplies correctly rounded binary32/binary64 decimal parsing.
			mut end := unsafe { &char(nil) }
			parsed := unsafe { C.strtod(&char(raw.str), &end) }
			if raw == '' || unsafe { end != &char(raw.str) + raw.len } {
				return error('could not convert string to float: ${raw}')
			}
			x.add(Property{ kind: .number, text: float_text(parsed) })!
		}
		'string' { x.add(Property{ kind: .string, text: x.data.str() })! }
		'data' { x.add(Property{ kind: .bytes, bytes: decode_plist_base64(x.data.str())! })! }
		'date' {
			raw := x.data.str()
			validate_date(raw)!
			x.add(Property{ kind: .opaque, text: 'datetime', bytes: raw.bytes() })!
		}
		else {} // plistlib ignores elements without a registered value handler.
	}
}

fn plist_xml_end(pointer voidptr, name &char) {
	mut x := unsafe { &PlistXml(pointer) }
	if x.failure != '' { return }
	plist_xml_value(mut x, unsafe { cstring_to_vstring(name) }) or { x.failure = err.msg() }
}

fn float_text(value f64) string {
	if math.is_nan(value) { return 'NaN' }
	if math.is_inf(value, 1) { return 'Infinity' }
	if math.is_inf(value, -1) { return '-Infinity' }
	representation := value.str()
	return if !representation.contains_any('.eE') { representation + '.0' } else { representation }
}

fn parse_xml_plist(data []u8) !Property {
	parser := C.XML_ParserCreate(unsafe { nil })
	if parser == unsafe { nil } { return error('cannot allocate XML parser') }
	// Expat owns its parser; callback strings are borrowed only for the call.
	// Every property/text value is copied into the host V collector's storage.
	defer { C.XML_ParserFree(parser) }
	mut state := PlistXml{ parser: parser, data: strings.new_builder(64) }
	C.XML_SetUserData(parser, unsafe { &state })
	C.XML_SetElementHandler(parser, plist_xml_start, plist_xml_end)
	C.XML_SetCharacterDataHandler(parser, plist_xml_text)
	C.XML_SetEntityDeclHandler(parser, plist_xml_entity)
	mut offset := 0
	for {
		end := int_min(data.len, offset + 1048576)
		input := if end == offset { unsafe { &char(nil) } } else { unsafe { &char(&data[offset]) } }
		status := C.XML_Parse(parser, input, i32(end - offset), if end == data.len { 1 } else { 0 })
		if state.failure != '' { return error(state.failure) }
		if status == 0 {
			message := unsafe { cstring_to_vstring(C.XML_ErrorString(C.XML_GetErrorCode(parser))) }
			return error('${message}: line ${C.XML_GetCurrentLineNumber(parser)}, column ${C.XML_GetCurrentColumnNumber(parser)}')
		}
		if end == data.len { break }
		offset = end
	}
	return state.root
}

struct BinaryPlist {
	data     []u8
	offsets  []u64
	ref_size int
mut:
	active map[int]bool
	cache  map[int]Property
}

fn big_endian(data []u8) big.Integer { return big.integer_from_bytes(data, signum: 1) }

fn be(data []u8, offset int, size int) !u64 {
	if size < 1 || size > 8 || offset < 0 || offset > data.len - size {
		return error('Invalid file')
	}
	mut n := u64(0)
	for byte in data[offset..offset + size] { n = (n << 8) | byte }
	return n
}

fn (b BinaryPlist) span(offset int, size int) ![]u8 {
	if offset < 0 || size < 0 || offset > b.data.len - size { return error('Invalid file') }
	return b.data[offset..offset + size]
}

fn (mut b BinaryPlist) object(index int) !Property {
	if index < 0 || index >= b.offsets.len { return error('Invalid file') }
	if found := b.cache[index] { return found }
	if index in b.active { return error('cyclic plist object graph') }
	b.active[index] = true
	defer { b.active.delete(index) }
	off := b.offsets[index]
	if off >= u64(b.data.len) { return error('Invalid file') }
	mut offset := int(off)
	token := b.data[offset]
	offset++
	kind := token >> 4
	low := token & 15
	mut result := Property{}
	if token == 0 {
		result = Property{}
	} else if token in [u8(8), 9] {
		result = Property{ kind: .boolean, boolean: token == 9 }
	} else if token == 15 {
		result = Property{ kind: .bytes }
	} else if kind == 1 {
		data := b.span(offset, 1 << low)!
		mut n := big_endian(data)
		if low >= 3 && data[0] & 128 != 0 { n = n - big.one_int.left_shift(u32(data.len * 8)) }
		result = Property{ kind: .number, text: n.str() }
	} else if token in [u8(0x22), 0x23] {
		word := be(b.data, offset, if token == 0x22 { 4 } else { 8 })!
		result = Property{
			kind: .number
			text: float_text(if token == 0x22 {
				f64(math.f32_from_bits(u32(word)))
			} else {
				math.f64_from_bits(word)
			})
		}
	} else if token == 0x33 {
		date_word := be(b.data, offset, 8)!
		seconds := math.f64_from_bits(date_word)
		if math.is_nan(seconds) || seconds < -63113904000.0 || seconds >= 252423993600.0 {
			return error('Invalid file')
		}
		result = Property{ kind: .opaque, text: 'datetime', bytes: b.span(offset, 8)!.clone() }
	} else if kind == 8 {
		if big_endian(b.span(offset, int(low) + 1)!) >= big.one_int.left_shift(64) {
			return error('Invalid file')
		}
		result = Property{ kind: .opaque, text: 'UID', bytes: b.span(offset, int(low) + 1)!.clone() }
	} else if kind in [u8(4), 5, 6, 10, 13] {
		mut size := u64(low)
		if low == 15 {
			marker := b.span(offset, 1)![0]
			offset++
			// plistlib's extended length width uses the low two marker bits.
			width := 1 << (marker & 3)
			size = be(b.data, offset, width)!
			offset += width
		}
		stride := if kind == 6 {
			2
		} else if kind in [u8(10), 13] {
			b.ref_size
		} else {
			1
		}
		factor := if kind == 13 { 2 } else { 1 }
		if stride < 1 || size > u64((b.data.len - offset) / stride / factor) {
			return error('Invalid file')
		}
		n := int(size)
		match kind {
			4 { result = Property{ kind: .bytes, bytes: b.span(offset, n)!.clone() } }
			5 { result = Property{ kind: .string, text: ascii(b.span(offset, n)!)! } }
			6 { result = Property{ kind: .string, text: utf16(b.span(offset, n * 2)!, false)! } }
			10 {
				mut items := []Property{cap: n}
				for i in 0 .. n {
					items << b.object(int(be(b.data, offset + i * stride, stride)!))!
				}
				result = Property{ kind: .array, array: items }
			}
			13 {
				mut fields := map[string]Property{}
				for i in 0 .. n {
					key := b.object(int(be(b.data, offset + i * stride, stride)!))!
					if key.kind != .string { return error('Invalid file') }
					fields[key.text] = b.object(int(be(b.data, offset + (i + n) * stride, stride)!))!
				}
				result = Property{ kind: .object, fields: fields }
			}
			else {}
		}
	} else {
		return error('Invalid file')
	}
	b.cache[index] = result
	return result
}

fn utf16(data []u8, little bool) !string {
	if data.len % 2 != 0 { return error('truncated UTF-16 data') }
	mut output := []rune{}
	mut i := 0
	for i < data.len {
		first := if little {
			u16(data[i]) | (u16(data[i + 1]) << 8)
		} else {
			(u16(data[i]) << 8) | data[i + 1]
		}
		i += 2
		mut code := u32(first)
		if first >= 0xd800 && first <= 0xdbff {
			if i >= data.len { return error('incomplete UTF-16 surrogate pair') }
			second := if little {
				u16(data[i]) | (u16(data[i + 1]) << 8)
			} else {
				(u16(data[i]) << 8) | data[i + 1]
			}
			i += 2
			if second < 0xdc00 || second > 0xdfff { return error('invalid UTF-16 surrogate pair') }
			code = 0x10000 + ((u32(first) - 0xd800) << 10) + u32(second) - 0xdc00
		} else if first >= 0xdc00 && first <= 0xdfff {
			return error('unpaired UTF-16 surrogate')
		}
		output << rune(code)
	}
	return output.string()
}

pub fn parse_plist(data []u8) !Property {
	if data.len >= 8 && data[..8].bytestr() == 'bplist00' {
		if data.len < 40 { return error('Invalid file') }
		trailer := data.len - 32
		offset_size := int(data[trailer + 6])
		ref_size := int(data[trailer + 7])
		count := be(data, trailer + 8, 8)!
		top := be(data, trailer + 16, 8)!
		table := be(data, trailer + 24, 8)!
		if offset_size < 1 || offset_size > 8 || ref_size < 1 || ref_size > 8 || table > u64(data.len) || count > u64((data.len - int(table)) / offset_size) || top >= count {
			return error('Invalid file')
		}
		mut offsets := []u64{cap: int(count)}
		for i in 0 .. int(count) { offsets << be(data, int(table) + i * offset_size, offset_size)! }
		mut binary := BinaryPlist{ data: data, offsets: offsets, ref_size: ref_size }
		return binary.object(int(top)) or { return error('Invalid file') }
	}
	content := if data.len >= 2 && data[0] == 0xff && data[1] == 0xfe {
		utf16(data[2..], true)!.bytes()
	} else if data.len >= 2 && data[0] == 0xfe && data[1] == 0xff {
		utf16(data[2..], false)!.bytes()
	} else if data.len >= 3 && data[..3] == [u8(0xef), 0xbb, 0xbf] {
		data[3..]
	} else {
		data
	}

	if !content.bytestr().starts_with('<?xml') && !content.bytestr().starts_with('<plist') {
		return error('Invalid file')
	}
	return parse_xml_plist(data)
}
