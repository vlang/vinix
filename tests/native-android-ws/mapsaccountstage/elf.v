// SPDX-License-Identifier: GPL-2.0-or-later
module mapsaccountstage

pub struct Elf {
pub:
	needed      []string
	interpreter string
	soname      string
	runpath     string
}

struct Segment {
	kind    u32
	offset  u64
	address u64
	size    u64
	memory  u64
}

fn u16_at(bytes []u8, at int) u16 {
	return u16(bytes[at]) | u16(bytes[at + 1]) << 8
}

fn u32_at(bytes []u8, at int) u32 {
	return u32(u16_at(bytes, at)) | u32(u16_at(bytes, at + 2)) << 16
}

fn u64_at(bytes []u8, at int) u64 {
	return u64(u32_at(bytes, at)) | u64(u32_at(bytes, at + 4)) << 32
}

fn bounded(length int, offset u64, size u64) bool {
	return offset <= u64(length) && size <= u64(length) - offset
}

fn cstring(bytes []u8, offset u64) !string {
	if offset >= u64(bytes.len) { return error('ELF string offset outside table') }
	start := int(offset)
	mut end := start
	for end < bytes.len && bytes[end] != 0 {
		if bytes[end] <= 32 || bytes[end] >= 127 { return error('unsafe ELF dynamic string') }
		end++
	}
	if end == start || end == bytes.len { return error('empty or unterminated ELF string') }
	return bytes[start..end].bytestr()
}

pub fn inspect_elf(bytes []u8) !Elf {
	if bytes.len < 64 || bytes[..7] != [u8(0x7f), `E`, `L`, `F`, 2, 1, 1]
		|| u16_at(bytes, 16) !in [u16(2), 3] || u16_at(bytes, 18) != 183
		|| u32_at(bytes, 20) != 1 || u16_at(bytes, 52) != 64 {
		return error('expected Linux AArch64 ELF64 executable or shared object')
	}
	offset, stride, count := u64_at(bytes, 32), int(u16_at(bytes, 54)), int(u16_at(bytes, 56))
	if stride != 56 || count == 0 || count > 1024 || !bounded(bytes.len, offset, u64(stride * count)) {
		return error('invalid ELF program header table')
	}
	mut segments := []Segment{}
	mut dynamic := Segment{}
	mut has_dynamic := false
	mut interpreter := ''
	for index in 0 .. count {
		at := int(offset) + index * stride
		segment := Segment{u32_at(bytes, at), u64_at(bytes, at + 8), u64_at(bytes, at + 16), u64_at(bytes, at + 32), u64_at(bytes, at + 40)}
		if !bounded(bytes.len, segment.offset, segment.size) { return error('ELF segment outside file') }
		if segment.kind == 1 {
			if segment.size > segment.memory || segment.memory > ~u64(0) - segment.address {
				return error('invalid ELF load memory span')
			}
			segments << segment
		} else if segment.kind == 2 {
			if has_dynamic || segment.size == 0 || segment.size % 16 != 0 || segment.size > 1024 * 1024 {
				return error('duplicate or invalid ELF dynamic segment')
			}
			dynamic = segment
			has_dynamic = true
		} else if segment.kind == 3 {
			if interpreter != '' || segment.size < 2 || segment.size > 4096 {
				return error('duplicate or invalid ELF interpreter')
			}
			data := bytes[int(segment.offset)..int(segment.offset + segment.size)]
			interpreter = cstring(data, 0)!
			if interpreter.len + 1 != data.len || interpreter != '/lib/ld-musl-aarch64.so.1' {
				return error('unexpected ELF interpreter')
			}
		}
	}
	if !has_dynamic {
		if interpreter != '' { return error('ELF interpreter lacks dynamic segment') }
		return Elf{}
	}
	return parse_dynamic(bytes, segments, dynamic, interpreter)
}

fn parse_dynamic(bytes []u8, segments []Segment, dynamic Segment, interpreter string) !Elf {
	if mapped_offset(segments, dynamic.address, dynamic.size)! != dynamic.offset {
		return error('ELF dynamic segment file and virtual mappings differ')
	}
	mut needed_offsets := []u64{}
	mut strtab := u64(0)
	mut strsz := u64(0)
	mut soname_offset := u64(0)
	mut runpath_offset := u64(0)
	mut seen := map[u64]bool{}
	mut terminated := false
	for at := int(dynamic.offset); at < int(dynamic.offset + dynamic.size); at += 16 {
		tag, value := u64_at(bytes, at), u64_at(bytes, at + 8)
		if tag == 0 { terminated = true break }
		if tag == 15 { return error('legacy ELF RPATH is forbidden') }
		if tag == 1 {
			if needed_offsets.len >= 128 { return error('too many ELF dependencies') }
			needed_offsets << value
		} else if tag in [u64(5), 10, 14, 29] {
			if tag in seen { return error('duplicate ELF string metadata tag') }
			seen[tag] = true
			match tag {
				5 { strtab = value }
				10 { strsz = value }
				14 { soname_offset = value }
				else { runpath_offset = value }
			}
		}
	}
	if !terminated || 5 !in seen || 10 !in seen || strsz == 0 || strsz > 16 * 1024 * 1024 {
		return error('unterminated ELF dynamic table or missing bounded string table')
	}
	start := mapped_offset(segments, strtab, strsz)!
	strings := bytes[int(start)..int(start + strsz)]
	mut needed := []string{}
	for at in needed_offsets {
		name := cstring(strings, at)!
		if name.contains_any('/\\') || name in ['.', '..'] || name in needed {
			return error('path-bearing or duplicate ELF dependency')
		}
		needed << name
	}
	soname := if 14 in seen { cstring(strings, soname_offset)! } else { '' }
	if soname.contains_any('/\\') || soname in ['.', '..'] { return error('unsafe ELF SONAME') }
	return Elf{needed, interpreter, soname, if 29 in seen { cstring(strings, runpath_offset)! } else { '' }}
}

fn mapped_offset(segments []Segment, address u64, size u64) !u64 {
	if size == 0 || size > ~u64(0) - address { return error('invalid ELF mapped span') }
	mut mappings := 0
	mut intersections := 0
	mut offset := u64(0)
	for segment in segments {
		if address < segment.address + segment.memory && segment.address < address + size {
			intersections++
		}
		if address >= segment.address && address - segment.address <= segment.size
			&& size <= segment.size - (address - segment.address) {
			offset = segment.offset + (address - segment.address)
			mappings++
		}
	}
	if mappings != 1 || intersections != 1 { return error('ELF span has no unique file mapping') }
	return offset
}
