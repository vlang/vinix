// SPDX-License-Identifier: GPL-2.0-or-later
// Read-only, bounded NIBArchive v1 decoding. Strings and data borrow the
// archive's private snapshot and remain valid until Archive.free().
module nib

import math

pub struct Object {
pub:
	class_id int
	first int
	count int
}

pub struct Value {
pub:
	key int
	kind u8
pub mut:
	integer u64
	real f64
	data []u8
}

pub struct Archive {
pub:
	data []u8
pub mut:
	objects []Object
	keys []string
	values []Value
	classes []string
}

pub fn (archive &Archive) free() {
	unsafe {
		// Bypass []string's deep destructor: these names borrow data.
		(&array(&archive.objects)).free()
		(&array(&archive.keys)).free()
		(&array(&archive.values)).free()
		(&array(&archive.classes)).free()
		archive.data.free()
	}
}

struct Reader {
	data []u8
mut:
	pos int
	end int
}

fn (mut r Reader) take(count int) ![]u8 {
	if count < 0 || count > r.end - r.pos { return error('truncated NIBArchive') }
	start := r.pos
	r.pos += count
	return unsafe { r.data[start..r.pos] }
}

fn (mut r Reader) byte() !u8 {
	bytes := r.take(1)!
	return bytes[0]
}

fn (mut r Reader) little(count int) !u64 {
	bytes := r.take(count)!
	mut value := u64(0)
	for i, b in bytes { value |= u64(b) << (i * 8) }
	return value
}

fn (mut r Reader) variable() !int {
	// NIBArchive uses the high bit to terminate (the reverse of LEB128).
	mut value := u64(0)
	for shift in [0, 7, 14, 21, 28]! {
		b := r.byte()!
		value |= u64(b & 0x7f) << shift
		if b & 0x80 != 0 {
			if value > 0x7fffffff { return error('NIBArchive integer exceeds limit') }
			return int(value)
		}
	}
	return error('unterminated NIBArchive integer')
}

fn (r &Reader) finished() ! {
	if r.pos != r.end { return error('NIBArchive table size mismatch') }
}

fn borrowed_text(data []u8) !string {
	if data.len == 0 { return error('empty NIBArchive name') }
	for b in data { if b == 0 || b > 0x7f { return error('invalid NIBArchive name') } }
	return unsafe { tos(data.data, data.len) }
}

pub fn parse(input []u8) !Archive {
	if input.len < 50 || input.len > 1024 * 1024 { return error('NIBArchive size is outside limit') }
	if input[..10] != 'NIBArchive'.bytes() { return error('invalid NIBArchive signature') }
	mut archive := Archive{data: input.clone()}
	mut complete := false
	defer { if !complete { archive.free() } }
	mut r := Reader{data: archive.data, pos: 10, end: 50}
	if r.little(4)! != 1 || r.little(4)! != 9 { return error('unsupported NIBArchive version') }
	object_count := int(r.little(4)!)
	object_start := int(r.little(4)!)
	key_count := int(r.little(4)!)
	key_start := int(r.little(4)!)
	value_count := int(r.little(4)!)
	value_start := int(r.little(4)!)
	class_count := int(r.little(4)!)
	class_start := int(r.little(4)!)
	if object_count < 1 || object_count > 4096 || key_count < 1 || key_count > 4096
		|| value_count < 1 || value_count > 16384 || class_count < 1 || class_count > 256 {
		return error('NIBArchive table count exceeds limit')
	}
	if object_start != 50 || key_start < object_start || value_start < key_start
		|| class_start < value_start || class_start > archive.data.len {
		return error('invalid NIBArchive table offsets')
	}
	archive.objects = []Object{cap: object_count}
	archive.keys = []string{cap: key_count}
	archive.values = []Value{cap: value_count}
	archive.classes = []string{cap: class_count}
	r.pos = object_start; r.end = key_start
	mut next := 0
	for _ in 0 .. object_count {
		obj := Object{class_id: r.variable()!, first: r.variable()!, count: r.variable()!}
		if obj.class_id >= class_count || obj.first != next || obj.count > value_count - next {
			return error('invalid NIBArchive object range')
		}
		next += obj.count
		archive.objects << obj
	}
	if next != value_count { return error('unowned NIBArchive values') }
	r.finished()!
	r.pos = key_start; r.end = value_start
	for _ in 0 .. key_count {
		length := r.variable()!
		archive.keys << borrowed_text(r.take(length)!)!
	}
	r.finished()!
	r.pos = value_start; r.end = class_start
	for _ in 0 .. value_count {
		key := r.variable()!
		kind := r.byte()!
		if key >= key_count { return error('invalid NIBArchive key reference') }
		mut value := Value{key: key, kind: kind}
		match kind {
			0, 1, 2, 3 { value.integer = r.little(1 << kind)! }
			4, 5 { value.integer = u64(kind - 4) }
			6 {
				bits := u32(r.little(4)!)
				value.real = f64(unsafe { *(&f32(&bits)) })
				if !math.is_finite(value.real) { return error('nonfinite NIBArchive float') }
			}
			7 {
				bits := r.little(8)!
				value.real = unsafe { *(&f64(&bits)) }
				if !math.is_finite(value.real) { return error('nonfinite NIBArchive double') }
			}
			8 { value.data = r.take(r.variable()!)! }
			9 {}
			10 {
				value.integer = r.little(4)!
				if value.integer >= u64(object_count) { return error('invalid NIBArchive object reference') }
			}
			else { return error('unsupported NIBArchive value type') }
		}
		archive.values << value
	}
	r.finished()!
	r.pos = class_start; r.end = archive.data.len
	for _ in 0 .. class_count {
		length := r.variable()!
		extra := r.variable()!
		if length < 2 || length > 256 || extra > 16 { return error('invalid NIBArchive class entry') }
		r.take(extra * 4)!
		name := r.take(length)!
		if name[length - 1] != 0 { return error('unterminated NIBArchive class name') }
		archive.classes << borrowed_text(unsafe { name[..length - 1] })!
	}
	r.finished()!
	complete = true
	return archive
}
