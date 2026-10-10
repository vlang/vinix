// SPDX-License-Identifier: GPL-2.0-or-later
module ansreads

import encoding.utf8
import x.json2

pub struct Number {
pub mut:
	raw string
}

pub fn (mut number Number) from_json_number(raw string) ! { number.raw = raw }

// Keep numeric tokens exact, including numbers outside machine widths and
// ignored metadata. A float, boolean or quoted number is never a range integer.
pub type Value = []Value | Number | bool | map[string]Value | string | json2.Null

fn integer_value(value Value) !i64 {
	if value is Number {
		if value.raw.contains('.') || value.raw.contains('e') || value.raw.contains('E') {
			return error('range offset and length must be integers')
		}
		return bounded_integer(value.raw, 10) or {
			return error('range requires nonnegative offset and 1..1048576 bytes')
		}
	}
	return error('range offset and length must be integers')
}

fn field(value map[string]Value, name string) Value {
	return value[name] or { Value(json2.Null{}) }
}

fn validate_ranges(ranges []Range) ! {
	mut ordered := ranges.clone()
	ordered.sort(a.offset < b.offset)
	for range in ordered {
		checked_range(range.offset, range.length)!
		if range.sha256.len != 64 || !range.sha256.bytes().all(it in '0123456789abcdef'.bytes()) {
			return error('invalid SHA-256 digest')
		}
	}
	for index in 1 .. ordered.len {
		if ordered[index - 1].offset + ordered[index - 1].length > ordered[index].offset {
			return error('overlapping or duplicate sample ranges')
		}
	}
}

pub fn validate_manifest(value Value) ![]Range {
	if value !is map[string]Value { return error('unrecognized manifest schema') }
	object := value as map[string]Value
	version := field(object, 'schema')
	if version !is string { return error('unrecognized manifest schema') }
	if (version as string) != schema { return error('unrecognized manifest schema') }
	items := field(object, 'ranges')
	if items !is []Value { return error('manifest requires 1..64 ranges') }
	entries := items as []Value
	if entries.len < 1 || entries.len > max_ranges {
		return error('manifest requires 1..64 ranges')
	}
	mut ranges := []Range{cap: entries.len}
	for entry in entries {
		if entry !is map[string]Value { return error('malformed range') }
		row := entry as map[string]Value
		range := checked_range(integer_value(field(row, 'offset'))!, integer_value(field(row, 'length'))!)!
		hash := field(row, 'sha256')
		if hash !is string { return error('invalid SHA-256 digest') }
		ranges << Range{range.offset, range.length, hash as string}
	}
	validate_ranges(ranges)!
	return ranges
}

// The insertion order is the original sort_keys order; encoding escapes Unicode
// and uses two-space indentation. Only the informational system string differs.
pub fn (manifest Manifest) json_text() string {
	mut entries := []json2.Any{cap: manifest.ranges.len}
	for range in manifest.ranges {
		entries << json2.Any({
			'length': json2.Any(range.length)
			'offset': json2.Any(range.offset)
			'sha256': json2.Any(range.sha256)
		})
	}
	value := {
		'ranges':           json2.Any(entries)
		'reference_label':  json2.Any(manifest.reference_label)
		'reference_system': json2.Any(manifest.reference_system)
		'schema':           json2.Any(schema)
		'source_kind':      json2.Any(manifest.source_kind)
	}
	return json2.encode(value, prettify: true, indent_string: '  ', escape_unicode: true) + '\n'
}

pub fn (report Report) json_text() string {
	return json2.encode(report, prettify: true, indent_string: '  ', escape_unicode: true) + '\n'
}

pub fn parse_manifest(text string) !Value {
	if !utf8.validate_str(text) { return error('manifest contains invalid UTF-8') }
	return json2.decode[Value](text, strict: true)!
}

pub fn (manifest Manifest) value() !Value { return parse_manifest(manifest.json_text())! }

pub fn save_new_manifest(path string, value Manifest) ! {
	fd := open_path(path, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW, 0o600)!
	defer { C.close(fd) }
	if descriptor_mode(fd)! != u32(C.S_IFREG) {
		return error('manifest destination must be a new regular file')
	}
	data := value.json_text()
	mut position := 0
	for position < data.len {
		count := C.write(fd, unsafe { data.str + position }, usize(data.len - position))
		if count < 0 && C.errno == C.EINTR { continue }
		if count < 0 { return syscall_error('write manifest') }
		if count == 0 { return error('short manifest write') }
		position += int(count)
	}
	for {
		if C.fsync(fd) == 0 { break }
		if C.errno != C.EINTR { return syscall_error('sync manifest') }
	}
}

pub fn load_manifest(path string) !Value {
	fd := open_path(path, C.O_RDONLY | C.O_CLOEXEC, 0)!
	defer { C.close(fd) }
	if descriptor_mode(fd)! != u32(C.S_IFREG) { return error('manifest must be a regular file') }
	mut data := []u8{cap: max_range + 1}
	mut buffer := []u8{len: 8192}
	for data.len <= max_range {
		// Borrow only for this synchronous read; buffer remains alive and fixed.
		mut portion := unsafe { buffer[..if max_range + 1 - data.len < buffer.len {
			max_range + 1 - data.len
		} else {
			buffer.len
		}] }
		count := read_into(fd, mut portion)!
		if count == 0 { break }
		data << portion[..count]
	}
	if data.len > max_range { return error('manifest is too large') }
	return parse_manifest(manifest_text(data)!)!
}

// Match JSON's BOM / leading-zero UTF-8, UTF-16 and UTF-32 detection. Decode
// strictly rather than substituting bad code units in a trusted reference.
fn manifest_text(data []u8) !string {
	mut width := 1
	mut little := false
	mut start := 0
	if data.len >= 4 && data[..4] == [u8(0), 0, 0xfe, 0xff] {
		width = 4
		start = 4
	} else if data.len >= 4 && data[..4] == [u8(0xff), 0xfe, 0, 0] {
		width = 4
		start = 4
		little = true
	} else if data.len >= 2 && data[..2] == [u8(0xfe), 0xff] {
		width = 2
		start = 2
	} else if data.len >= 2 && data[..2] == [u8(0xff), 0xfe] {
		width = 2
		start = 2
		little = true
	} else if data.len >= 3 && data[..3] == [u8(0xef), 0xbb, 0xbf] {
		start = 3
	} else if data.len >= 4 && data[0] == 0 && data[1] == 0 && data[2] == 0 {
		width = 4
	} else if data.len >= 4 && data[1] == 0 && data[2] == 0 && data[3] == 0 {
		width = 4
		little = true
	} else if data.len >= 2 && data[0] == 0 {
		width = 2
	} else if data.len >= 2 && data[1] == 0 {
		width = 2
		little = true
	}
	if width == 1 { return data[start..].bytestr() }
	if (data.len - start) % width != 0 { return error('truncated Unicode manifest') }
	mut result := []rune{cap: (data.len - start) / width}
	mut position := start
	for position < data.len {
		mut code := code_unit(data, position, width, little)
		position += width
		if width == 2 && code >= 0xd800 && code <= 0xdbff {
			if position >= data.len { return error('truncated Unicode surrogate') }
			low := code_unit(data, position, width, little)
			if low < 0xdc00 || low > 0xdfff { return error('invalid Unicode surrogate') }
			code = 0x10000 + (code - 0xd800) * 1024 + low - 0xdc00
			position += width
		}
		if code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff) {
			return error('invalid Unicode code point')
		}
		result << rune(code)
	}
	return result.string()
}

fn code_unit(data []u8, position int, width int, little bool) u32 {
	mut value := u32(0)
	for index in 0 .. width {
		shift := if little { index * 8 } else { (width - 1 - index) * 8 }
		value |= u32(data[position + index]) << shift
	}
	return value
}
