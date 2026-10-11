// SPDX-License-Identifier: GPL-2.0-or-later
module lwjglpatch

import bundlehost as bh
import compress.deflate
import encoding.binary
import hash.crc32
import os

// Use the system zlib with an output buffer bounded by the declared ZIP size.
#flag -lz
#include <zlib.h>
@[typedef]
struct C.z_stream {
mut:
	next_in   &u8
	avail_in  u32
	next_out  &u8
	avail_out u32
	total_out u64
}

fn C.zlibVersion() &char
fn C.inflateInit2_(&C.z_stream, i32, &char, i32) i32
fn C.inflate(&C.z_stream, i32) i32
fn C.inflateEnd(&C.z_stream) i32

fn inflate(packed []u8, size u64) ![]u8 {
	mut stream := C.z_stream{}
	if C.inflateInit2_(&stream, -15, C.zlibVersion(), i32(sizeof(C.z_stream))) != 0 {
		return error('Cannot initialize ZIP inflater')
	}
	defer { C.inflateEnd(&stream) }
	mut output := []u8{len: int(size) + 1}
	stream.next_in = packed.data
	stream.avail_in = u32(packed.len)
	stream.next_out = output.data
	stream.avail_out = u32(output.len)
	if C.inflate(&stream, 4) != 1 || stream.total_out != size || stream.avail_in != 0 {
		return error('Invalid compressed ZIP payload')
	}
	return output[..int(size)].clone()
}

fn word(data []u8, at int) u32 { return binary.little_endian_u32_at(data, at) }

fn short(data []u8, at int) u16 { return binary.little_endian_u16_at(data, at) }

fn set_word(mut data []u8, at int, value u32) {
	for i in 0 .. 4 { data[at + i] = u8(value >> (i * 8)) }
}

fn set_short(mut data []u8, at int, value u16) {
	for i in 0 .. 2 { data[at + i] = u8(value >> (i * 8)) }
}

pub fn patch_native(data []u8) !([]u8, bool) {
	mut matches := []int{}
	if data.len >= 20 {
		for offset := 0; offset <= data.len - 20; offset += 4 {
			if word(data, offset) & 0xffe0001f == 0xd2800003 && word(data, offset + 4) == 0x52800022 && word(data, offset + 8) == 0xaa0303e1 && word(data, offset + 12) == 0xaa1503e0 && word(data, offset + 16) & 0xfc000000 == 0x94000000 {
				matches << offset
			}
		}
	}
	if matches.len == 0 {
		if data.len >= 8 {
			for at in 0 .. data.len - 7 {
				if word(data, at) == 0xaa0403e2 && word(data, at + 4) == 0x2a0503e3 {
					return data, false
				}
			}
		}
		return error('LWJGL libffi snprintf call site was not found')
	}
	if matches.len != 1 {
		return error('expected one LWJGL libffi call site, found ' + matches.len.str())
	}
	at := matches[0]
	mut native := data.clone()
	set_word(mut native, at, (word(data, at) & ~u32(31)) | 1)
	set_word(mut native, at + 4, 0xaa0403e2)
	set_word(mut native, at + 8, 0x2a0503e3)
	set_word(mut native, at + 16, word(data, at + 16) - 4)
	return native, true
}

struct JarEntry {
	name       string
	central    []u8
	local      []u8
	compressed []u8
	data       []u8
	method     u16
}

fn bounds(data []u8, offset u64, size u64) bool {
	return offset <= u64(data.len) && size <= u64(data.len) - offset
}

fn parse_jar(data []u8) !([]JarEntry, []u8) {
	if data.len < 22 || data.len > 256 * 1024 * 1024 {
		return error('Invalid or oversized LWJGL JAR')
	}
	mut end := data.len - 22
	minimum := if data.len > 65557 { data.len - 65557 } else { 0 }
	for end >= minimum {
		if word(data, end) == 0x06054b50 { break }
		end--
	}
	if end < minimum || end + 22 + int(short(data, end + 20)) > data.len {
		return error('Invalid ZIP end record')
	}
	if short(data, end + 4) != 0 || short(data, end + 6) != 0 {
		return error('Multi-disk JAR is unsupported')
	}
	mut central_end := end
	mut central_size := u64(word(data, end + 12))
	mut stored_start := u64(word(data, end + 16))
	mut count := u64(short(data, end + 10))
	if end >= 76 && word(data, end - 20) == 0x07064b50 && word(data, end - 76) == 0x06064b50 {
		central_end -= 76
		central_size = binary.little_endian_u64_at(data, end - 36)
		stored_start = binary.little_endian_u64_at(data, end - 28)
		count = binary.little_endian_u64_at(data, end - 44)
	}
	if central_size > u64(central_end) { return error('Invalid ZIP directory extent') }
	start := central_end - int(central_size)
	if stored_start > u64(start) { return error('Invalid ZIP directory offset') }
	adjustment := u64(start) - stored_start
	mut current := start
	mut entries := []JarEntry{}
	mut inflated := u64(0)
	for current < central_end {
		if current > central_end - 46 || word(data, current) != 0x02014b50 {
			return error('Invalid ZIP central header')
		}
		names, extra, comments := int(short(data, current + 28)), int(short(data, current + 30)), int(short(data, current + 32))
		length := 46 + names + extra + comments
		if length > central_end - current { return error('Truncated ZIP central header') }
		mut size, compressed, offset := u64(word(data, current + 24)), u64(word(data, current + 20)), u64(word(data, current + 42))
		mut cursor := current + 46 + names
		extra_end := cursor + extra
		for cursor < extra_end {
			if cursor > extra_end - 4 { return error('Truncated ZIP extra field') }
			kind, bytes := short(data, cursor), int(short(data, cursor + 2))
			cursor += 4
			if bytes > extra_end - cursor { return error('Invalid ZIP extra field') }
			if kind == 1 {
				mut at := cursor
				for field_name in ['size', 'compressed', 'offset'] {
					value := match field_name {
						'size' { size }
						'compressed' { compressed }
						else { offset }
					}
					if value != 0xffffffff { continue }
					if at > cursor + bytes - 8 { return error('Invalid ZIP64 extra field') }
					actual := binary.little_endian_u64_at(data, at)
					match field_name {
						'size' { size = actual }
						'compressed' { compressed = actual }
						else { offset = actual }
					}
					at += 8
				}
			}
			cursor += bytes
		}
		if !bounds(data, offset, adjustment) { return error('Invalid ZIP local offset') }
		offset += adjustment
		if !bounds(data, offset, 30) || word(data, int(offset)) != 0x04034b50 {
			return error('Invalid ZIP local header')
		}
		at := int(offset)
		flags, method := short(data, current + 8), short(data, current + 10)
		if flags & 1 != 0 || method !in [u16(0), 8] {
			return error('Unsupported encrypted or compressed JAR entry')
		}
		name := data[current + 46..current + 46 + names].bytestr()
		local_names, local_extra := int(short(data, at + 26)), int(short(data, at + 28))
		payload := offset + 30 + u64(local_names) + u64(local_extra)
		if !bounds(data, payload, compressed) || !bounds(data, offset + 30, u64(local_names)) || data[at + 30..at + 30 + local_names].bytestr() != name {
			return error('Invalid ZIP payload extent or filename')
		}
		inflated += size
		if size > 128 * 1024 * 1024 || inflated > 256 * 1024 * 1024 {
			return error('LWJGL JAR expands beyond supported size')
		}
		packed := data[int(payload)..int(payload + compressed)].clone()
		decoded := if method == 0 { packed.clone() } else { inflate(packed, size)! }
		if u64(decoded.len) != size || crc32.sum(decoded) != word(data, current + 16) {
			return error('Invalid ZIP size or CRC32 for ' + name)
		}
		entries << JarEntry{name, data[current..current + length].clone(), data[at..int(payload)].clone(), packed, decoded, method}
		current += length
	}
	if u64(entries.len) != count { return error('Invalid ZIP entry count') }
	return entries, data[end + 22..end + 22 + int(short(data, end + 20))].clone()
}

pub fn patch_jar(path string) !bool {
	if os.file_size(path) > 256 * 1024 * 1024 { return error('LWJGL JAR is too large') }
	entries, comment := parse_jar(os.read_bytes(path)!)!
	mut bodies := [][]u8{}
	mut changes := []bool{}
	mut found := false
	mut changed := false
	for entry in entries {
		if entry.name.ends_with('/org/lwjgl/liblwjgl.so') {
			found = true
			body, updated := patch_native(entry.data)!
			bodies << body
			changes << updated
			changed = changed || updated
		} else {
			bodies << entry.data
			changes << false
		}
	}
	if !found { return error(path + ': no ARM64 liblwjgl.so entry') }
	if !changed { return false }
	if entries.len > 65535 { return error('Too many LWJGL JAR entries') }
	mut output := []u8{}
	mut central := []u8{}
	for i, entry in entries {
		packed := if changes[i] {
			if entry.method == 0 { bodies[i] } else { deflate.compress_raw(bodies[i])! }
		} else {
			entry.compressed
		}
		mut local := entry.local.clone()
		mut record := entry.central.clone()
		checksum := crc32.sum(bodies[i])
		set_short(mut local, 6, short(local, 6) & ~u16(8))
		set_short(mut record, 8, short(record, 8) & ~u16(8))
		for buffer_name in ['local', 'record'] {
			if buffer_name == 'local' {
				set_word(mut local, 14, checksum)
				set_word(mut local, 18, u32(packed.len))
				set_word(mut local, 22, u32(bodies[i].len))
			} else {
				set_word(mut record, 16, checksum)
				set_word(mut record, 20, u32(packed.len))
				set_word(mut record, 24, u32(bodies[i].len))
			}
		}
		set_word(mut record, 42, u32(output.len))
		output << local
		output << packed
		central << record
	}
	start := output.len
	output << central
	mut end := []u8{len: 22}
	set_word(mut end, 0, 0x06054b50)
	set_short(mut end, 8, u16(entries.len))
	set_short(mut end, 10, u16(entries.len))
	set_word(mut end, 12, u32(central.len))
	set_word(mut end, 16, u32(start))
	set_short(mut end, 20, u16(comment.len))
	output << end
	output << comment
	parse_jar(output)!
	work := bh.temporary(os.dir(path), '.minecraft-patch-')!
	defer { bh.retire(work) }
	os.write_file_array(work + '/patched.jar', output)!
	os.chmod(work + '/patched.jar', 0o600)!
	os.mv(work + '/patched.jar', path)!
	return true
}

pub fn patch_cli(args []string) int {
	options := bh.parse(args, [], [], 1, 'Usage: patch-lwjgl-aarch64 GAME_ROOT') or {
		eprintln(err)
		return 2
	}
	root := options.positional[0]
	mut jars := os.glob(root + '/libraries/org/lwjgl/lwjgl/*/lwjgl-*-natives-linux-arm64.jar') or {
		eprintln(err)
		return 1
	}
	jars.sort()
	if jars.len == 0 {
		eprintln('no LWJGL ARM64 core native was staged')
		return 2
	}
	mut count := 0
	for jar in jars {
		updated := patch_jar(jar) or {
			eprintln(err)
			return 1
		}
		if updated {
			count++
			println('  patched ' + jar[root.len + 1..])
		}
	}
	if count == 0 { println('  LWJGL ARM64 core native already patched') }
	return 0
}
