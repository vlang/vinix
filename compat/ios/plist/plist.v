// SPDX-License-Identifier: GPL-2.0-or-later
module plist

import encoding.base64
import math.bits
import strconv
import strings

pub enum Kind { string integer real boolean array dictionary data }

pub struct Value {
pub:
	kind Kind
	text string
	integer i64
	real f64
	boolean bool
	values []Value
	fields map[string]Value
	data []u8
}

pub fn (value &Value) free() {
	for item in value.values { item.free() }
	for _, item in value.fields { item.free() }
	unsafe { value.text.free(); value.values.free(); value.fields.free(); value.data.free() }
}

struct Binary {
	data []u8
	count u64
	top u64
	table u64
	offset_size u64
	ref_size u64
mut:
	visited map[u64]bool
	charged u64
}

fn (r Binary) number(offset u64, size u64, end u64) !u64 {
	if size == 0 || size > 8 || offset > end || size > end - offset { return error('plist: invalid integer/range') }
	mut value := u64(0)
	for i in u64(0) .. size { value = (value << 8) | r.data[int(offset + i)] }
	return value
}

fn (mut r Binary) charge(size u64) ! {
	if size > 32 * 1024 * 1024 || r.charged > 32 * 1024 * 1024 - size { return error('plist: expanded object tree exceeds limit') }
	r.charged += size
}

fn (mut r Binary) object(index u64, depth int) !Value {
	if index >= r.count || depth > 64 || index in r.visited { return error('plist: invalid reference/cycle/depth') }
	r.charge(u64(sizeof(Value)))!
	r.visited[index] = true
	defer { r.visited.delete(index) }
	offset := r.number(r.table + index * r.offset_size, r.offset_size, u64(r.data.len) - 32)!
	if offset < 8 || offset >= r.table { return error('plist: object offset exceeds object table') }
	marker := r.data[int(offset)]
	mut position := offset + 1
	kind := marker >> 4
	if marker in [u8(8), 9] { return Value{kind: .boolean, boolean: marker == 9} }
	if kind == 1 {
		size := u64(1) << (marker & 15)
		return Value{kind: .integer, integer: i64(r.number(position, size, r.table)!)}
	}
	if kind == 2 {
		size := u64(1) << (marker & 15)
		word := r.number(position, size, r.table)!
		if size !in [u64(4), 8] { return error('plist: unsupported real size') }
		return Value{kind: .real, real: if size == 4 { f64(bits.f32_from_bits(u32(word))) } else { bits.f64_from_bits(word) }}
	}
	if kind !in [u8(4), 5, 6, 10, 13] { return error('plist: unsupported binary object type') }
	mut length := u64(marker & 15)
	if length == 15 {
		if position >= r.table || r.data[int(position)] >> 4 != 1 { return error('plist: invalid extended length') }
		size := u64(1) << (r.data[int(position)] & 15)
		length = r.number(position + 1, size, r.table)!
		position += 1 + size
	}
	stride := if kind == 6 { u64(2) } else if kind in [u8(10), 13] { r.ref_size } else { u64(1) }
	if length > 16777216 || position > r.table || length > (r.table - position) / stride
		|| (kind == 13 && length > (r.table - position) / (stride * 2)) { return error('plist: object payload exceeds bounds') }
	r.charge(length * stride)!
	if kind == 4 { return Value{kind: .data, data: r.data[int(position)..int(position + length)].clone()} }
	if kind == 5 { return Value{kind: .string, text: r.data[int(position)..int(position + length)].bytestr()} }
	if kind == 6 {
		mut bytes := []u8{cap: int(length) * 3}
		bytes.flags |= .noslices
		defer { unsafe { bytes.free() } }
		mut i := u64(0)
		for i < length {
			mut code := u32(r.number(position + i * 2, 2, r.table)!)
			i++
			if code >= 0xd800 && code <= 0xdbff {
				if i == length { return error('plist: incomplete UTF-16 surrogate pair') }
				low := u32(r.number(position + i * 2, 2, r.table)!)
				if low < 0xdc00 || low > 0xdfff { return error('plist: invalid UTF-16 surrogate pair') }
				code = 0x10000 + ((code - 0xd800) << 10) + low - 0xdc00
				i++
			} else if code >= 0xdc00 && code <= 0xdfff { return error('plist: unpaired UTF-16 surrogate') }
			append_utf8(mut bytes, code)
		}
		return Value{kind: .string, text: bytes.bytestr()}
	}
	if kind == 10 {
		mut values := []Value{cap: int(length)}
		mut complete := false
		defer { if !complete { for value in values { value.free() }; unsafe { values.free() } } }
		for i in u64(0) .. length { values << r.object(r.number(position + i * stride, stride, r.table)!, depth + 1)! }
		complete = true
		return Value{kind: .array, values: values}
	}
	mut fields := map[string]Value{}
	mut complete := false
	defer { if !complete { for _, value in fields { value.free() }; unsafe { fields.free() } } }
	for i in u64(0) .. length {
		key := r.object(r.number(position + i * stride, stride, r.table)!, depth + 1)!
		defer { key.free() }
		if key.kind != .string || key.text in fields { return error('plist: invalid/duplicate dictionary key') }
		fields[key.text] = r.object(r.number(position + (i + length) * stride, stride, r.table)!, depth + 1)!
	}
	complete = true
	return Value{kind: .dictionary, fields: fields}
}

fn append_utf8(mut bytes []u8, code u32) {
	if code < 0x80 { bytes << u8(code) }
	else if code < 0x800 { bytes << u8(0xc0 | code >> 6); bytes << u8(0x80 | code & 63) }
	else if code < 0x10000 {
		bytes << u8(0xe0 | code >> 12); bytes << u8(0x80 | (code >> 6) & 63); bytes << u8(0x80 | code & 63)
	} else {
		bytes << u8(0xf0 | code >> 18); bytes << u8(0x80 | (code >> 12) & 63)
		bytes << u8(0x80 | (code >> 6) & 63); bytes << u8(0x80 | code & 63)
	}
}

pub fn parse(data []u8) !Value {
	if data.len == 0 || data.len > 16777216 { return error('plist: input exceeds size limit') }
	if data.len < 8 || data[..8] != 'bplist00'.bytes() { return parse_xml(data)! }
	if data.len < 40 { return error('plist: truncated binary trailer') }
	trailer := u64(data.len) - 32
	mut r := Binary{data: data, count: 0, top: 0, table: 0, offset_size: 0, ref_size: 0}
	count := r.number(trailer + 8, 8, u64(data.len))!
	top := r.number(trailer + 16, 8, u64(data.len))!
	table := r.number(trailer + 24, 8, u64(data.len))!
	offset_size := u64(data[int(trailer) + 6])
	ref_size := u64(data[int(trailer) + 7])
	if count == 0 || count > 65536 || top >= count || table < 8 || table > trailer
		|| offset_size !in [u64(1), 2, 4, 8] || ref_size !in [u64(1), 2, 4, 8]
		|| count > (trailer - table) / offset_size { return error('plist: invalid binary trailer/table') }
	r = Binary{data: data, count: count, top: top, table: table, offset_size: offset_size, ref_size: ref_size}
	defer { unsafe { r.visited.free() } }
	return r.object(top, 0)
}

// A plist reader keeps text/CDATA in document order and preserves string
// whitespace. The general XML DOM trims text, which changes preference values.
struct XmlReader {
    text string
mut:
    position int
    remaining int = 65536
}

fn (r XmlReader) at(token string) bool {
    if token.len > r.text.len - r.position { return false }
    for i, c in token { if r.text[r.position + i] != c { return false } }
    return true
}

fn xml_space(c u8) bool { return c in [u8(9), 10, 13, 32] }

fn (mut r XmlReader) spaces() {
    for r.position < r.text.len && xml_space(r.text[r.position]) { r.position++ }
}

fn (mut r XmlReader) comment() ! {
    end := r.text.index_after('-->', r.position + 4) or { return error('plist: incomplete XML comment') }
    r.position = end + 3
}

fn (mut r XmlReader) between() ! {
    for {
        r.spaces()
        if !r.at('<!--') { return }
        r.comment()!
    }
}

fn (mut r XmlReader) close(name string) ! {
    if !r.at('</') { return error('plist: missing closing element') }
    r.position += 2
    if !r.at(name) { return error('plist: mismatched closing element') }
    r.position += name.len
    r.spaces()
    if !r.at('>') { return error('plist: invalid closing element') }
    r.position++
}

fn (mut r XmlReader) open(root bool) !(string, bool) {
    if !r.at('<') { return error('plist: expected an element') }
    r.position++
    start := r.position
    for r.position < r.text.len && r.text[r.position] >= `a` && r.text[r.position] <= `z` { r.position++ }
    if r.position == start { return error('plist: invalid element name') }
    name := r.text[start..r.position]
    mut complete := false
    defer { if !complete { unsafe { name.free() } } }
    r.spaces()
    if root && r.at('version') {
        r.position += 7
        r.spaces()
        if !r.at('=') { return error('plist: invalid version attribute') }
        r.position++
        r.spaces()
        if r.position == r.text.len || r.text[r.position] !in [u8(`"`), `'`] { return error('plist: unquoted version attribute') }
        quote := r.text[r.position]
        r.position++
        if !r.at('1.0') { return error('plist: unsupported plist version') }
        r.position += 3
        if r.position == r.text.len || r.text[r.position] != quote { return error('plist: invalid version attribute') }
        r.position++
        r.spaces()
    }
    empty := r.at('/>')
    if !empty && !r.at('>') { return error('plist: attributes are unsupported') }
    r.position += if empty { 2 } else { 1 }
    complete = true
    return name, empty
}

fn (mut r XmlReader) content(name string, empty bool) !string {
    if empty { return ''.clone() }
    mut output := strings.new_builder(64)
    defer { unsafe { output.free() } }
    for r.position < r.text.len {
        if r.at('</') { r.close(name)!; return output.str() }
        if r.at('<!--') { r.comment()!; continue }
        if r.at('<![CDATA[') {
            start := r.position + 9
            end := r.text.index_after(']]>', start) or { return error('plist: incomplete CDATA') }
            for i in start .. end { output.write_u8(r.text[i]) }
            r.position = end + 3
            continue
        }
        if r.at('<') { return error('plist: nested scalar elements') }
        start := r.position
        for r.position < r.text.len && r.text[r.position] != `<` { r.position++ }
        encoded := r.text[start..r.position]
        defer { unsafe { encoded.free() } }
        if encoded.contains(']]>') { return error('plist: CDATA terminator in text') }
        decoded := xml_unescape(encoded)!
        defer { unsafe { decoded.free() } }
        output.write_string(decoded)
    }
    return error('plist: incomplete scalar element')
}

fn xml_unescape(text string) !string {
	mut bytes := []u8{cap: text.len}
	bytes.flags |= .noslices
	defer { unsafe { bytes.free() } }
	mut i := 0
	for i < text.len {
		if text[i] != `&` {
            if text[i] < 32 && !xml_space(text[i]) { return error('plist: invalid XML control character') }
            bytes << text[i]; i++; continue
        }
		end := text.index_after(';', i + 1) or { return error('plist: incomplete XML entity') }
		if end - i > 16 { return error('plist: invalid XML entity') }
		entity := text[i + 1..end]
		code := match entity {
			'amp' { u32(`&`) } 'lt' { u32(`<`) } 'gt' { u32(`>`) }
			'quot' { u32(`"`) } 'apos' { u32(`'`) }
			else {
				if !entity.starts_with('#') { return error('plist: unknown XML entity') }
				number := if entity.starts_with('#x') { strconv.parse_uint(entity[2..], 16, 32)! } else { strconv.parse_uint(entity[1..], 10, 32)! }
				if number > 0x10ffff || (number >= 0xd800 && number <= 0xdfff) || (number < 32 && number !in [u64(9), 10, 13]) { return error('plist: invalid XML character reference') }
				u32(number)
			}
		}
		append_utf8(mut bytes, code)
		i = end + 1
	}
	return bytes.bytestr()
}

fn (mut r XmlReader) value(depth int, key bool) !Value {
    r.remaining--
    if depth > 64 || r.remaining < 0 { return error('plist: XML tree exceeds limits') }
    name, empty := r.open(false)!
    defer { unsafe { name.free() } }
    if (name == 'key') != key { return error('plist: misplaced/missing dictionary key') }
    if name in ['array', 'dict'] {
        mut values := []Value{}
        values.flags |= .noslices
        mut fields := map[string]Value{}
        mut complete := false
        defer {
            if !complete {
                for value in values { value.free() }
                for _, value in fields { value.free() }
                unsafe { values.free(); fields.free() }
            }
        }
        if !empty {
            for {
                r.between()!
                if r.at('</') { r.close(name)!; break }
                if name == 'array' { values << r.value(depth + 1, false)! }
                else {
                    item := r.value(depth + 1, true)!
                    defer { item.free() }
                    if item.text in fields { return error('plist: duplicate dictionary key') }
                    r.between()!
                    fields[item.text] = r.value(depth + 1, false)!
                }
            }
        }
        complete = true
        if name == 'array' { unsafe { fields.free() }; return Value{kind: .array, values: values} }
        unsafe { values.free() }
        return Value{kind: .dictionary, fields: fields}
    }
    text := r.content(name, empty)!
    defer { unsafe { text.free() } }
    match name {
        'string', 'key' { return Value{kind: .string, text: text.clone()} }
        'true', 'false' {
            for c in text { if !xml_space(c) { return error('plist: invalid boolean') } }
            return Value{kind: .boolean, boolean: name == 'true'}
        }
        'integer', 'real' {
            trimmed := text.trim_space()
            defer { if trimmed.str != text.str { unsafe { trimmed.free() } } }
            if name == 'integer' { return Value{kind: .integer, integer: strconv.parse_int(trimmed, 10, 64)!} }
            return Value{kind: .real, real: strconv.atof64(trimmed)!}
        }
        'data' {
            mut bytes := []u8{cap: text.len}
            bytes.flags |= .noslices
            defer { unsafe { bytes.free() } }
            for c in text { if !xml_space(c) { bytes << c } }
            compact := bytes.bytestr()
            defer { unsafe { compact.free() } }
            if compact.len % 4 != 0 { return error('plist: invalid base64 length') }
            mut padding := false
            for i, c in compact {
                if c == `=` { if i < compact.len - 2 { return error('plist: invalid base64 padding') }; padding = true }
                else if padding || !((c >= `A` && c <= `Z`) || (c >= `a` && c <= `z`) || (c >= `0` && c <= `9`) || c == `+` || c == `/`) { return error('plist: invalid base64 character') }
            }
            return Value{kind: .data, data: base64.decode(compact)}
        }
        else { return error('plist: unsupported XML object: ${name}') }
    }
}

fn xml_escape(mut output strings.Builder, text string) ! {
	for c in text {
		match c {
			`&` { output.write_string('&amp;') }
			`<` { output.write_string('&lt;') }
			`>` { output.write_string('&gt;') }
			else {
				if c < 32 && c !in [u8(9), 10, 13] { return error('plist: invalid XML control character') }
				output.write_u8(c)
			}
		}
	}
}

fn write_value(mut output strings.Builder, value Value, depth int) ! {
	if depth > 64 || output.len > 16777216 { return error('plist: output exceeds limits') }
	match value.kind {
		.string { output.write_string('<string>'); xml_escape(mut output, value.text)!; output.write_string('</string>') }
		.boolean { output.write_string(if value.boolean { '<true/>' } else { '<false/>' }) }
		.integer { text := value.integer.str(); output.write_string('<integer>'); output.write_string(text); output.write_string('</integer>'); unsafe { text.free() } }
		.real { text := value.real.str(); output.write_string('<real>'); output.write_string(text); output.write_string('</real>'); unsafe { text.free() } }
		.data { text := base64.encode(value.data); output.write_string('<data>'); output.write_string(text); output.write_string('</data>'); unsafe { text.free() } }
		.array { output.write_string('<array>'); for item in value.values { write_value(mut output, item, depth + 1)! }; output.write_string('</array>') }
		.dictionary {
			output.write_string('<dict>')
			for key, item in value.fields { output.write_string('<key>'); xml_escape(mut output, key)!; output.write_string('</key>'); write_value(mut output, item, depth + 1)! }
			output.write_string('</dict>')
		}
	}
}

// Serialize the same immutable property-list subset understood by parse().
pub fn encode_xml(value Value) !string {
	mut output := strings.new_builder(256)
	defer { unsafe { output.free() } }
	output.write_string('<?xml version="1.0" encoding="UTF-8"?><plist version="1.0">')
	write_value(mut output, value, 0)!
	output.write_string('</plist>')
	if output.len > 16777216 { return error('plist: output exceeds limits') }
	return output.str()
}

fn parse_xml(data []u8) !Value {
    text := data.bytestr()
    defer { unsafe { text.free() } }
    mut r := XmlReader{text: text}
    if r.at('\xef\xbb\xbf') { r.position += 3 }
    r.between()!
    if r.at('<?xml') {
        end := text.index_after('?>', r.position + 5) or { return error('plist: incomplete XML declaration') }
        r.position = end + 2
        r.between()!
    }
    if r.at('<!DOCTYPE') {
        r.position += 9
        if r.position == text.len || !xml_space(text[r.position]) { return error('plist: invalid doctype') }
        r.spaces()
        if !r.at('plist') { return error('plist: invalid doctype root') }
        r.position += 5
        mut quote := u8(0)
        for r.position < text.len {
            c := text[r.position]
            if c == `[` { return error('plist: internal entities are unsupported') }
            if quote != 0 { if c == quote { quote = 0 } }
            else if c in [u8(`"`), `'`] { quote = c }
            else if c == `>` { break }
            r.position++
        }
        if r.position == text.len { return error('plist: incomplete doctype') }
        r.position++
        r.between()!
    }
    name, empty := r.open(true)!
    defer { unsafe { name.free() } }
    if name != 'plist' || empty { return error('plist: XML root is not a populated plist') }
    r.between()!
    value := r.value(0, false)!
    mut complete := false
    defer { if !complete { value.free() } }
    r.between()!
    r.close('plist')!
    r.between()!
    if r.position != text.len { return error('plist: trailing document content') }
    complete = true
    return value
}
