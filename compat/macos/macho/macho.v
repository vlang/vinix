// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// Bounds-checked Mach-O metadata parsing for Vinix's userspace macOS layer.
module macho

pub const cpu_type_x86_64 = u32(0x01000007)
pub const cpu_type_arm64 = u32(0x0100000c)

const magic_64 = u32(0xfeedfacf)
const fat_magic = u32(0xcafebabe)
const fat_magic_64 = u32(0xcafebabf)
const mh_execute = u32(2)
const lc_segment_64 = u32(0x19)
const lc_symtab = u32(0x2)
const lc_load_dylib = u32(0xc)
const lc_load_weak_dylib = u32(0x80000018)
const lc_reexport_dylib = u32(0x8000001f)
const lc_load_upward_dylib = u32(0x80000023)
const lc_dyld_info = u32(0x22)
const lc_dyld_info_only = u32(0x80000022)
const lc_main = u32(0x80000028)
const lc_dyld_chained_fixups = u32(0x80000034)

pub struct Segment {
pub:
	name               string
	vm_address         u64
	vm_size            u64
	file_offset        u64
	file_size          u64
	max_protection     i32
	initial_protection i32
}

pub struct DyldInfo {
pub:
	rebase_offset    u32
	rebase_size      u32
	bind_offset      u32
	bind_size        u32
	weak_bind_offset u32
	weak_bind_size   u32
	lazy_bind_offset u32
	lazy_bind_size   u32
}

pub struct SymbolTable {
pub:
	offset         u32
	count          u32
	strings_offset u32
	strings_size   u32
}

pub struct Symbol {
pub:
	name    string
	value   u64
	defined bool
}

pub struct Image {
pub:
	data              []u8
	cpu_type          u32
	segments          []Segment
	dyld              DyldInfo
	symbol_table      SymbolTable
	entry_file_offset u64
	dependencies      []string
}

fn checked_end(start u64, length u64, limit int) !int {
	if start > u64(limit) || length > u64(limit) - start {
		return error('Mach-O range lies outside the file')
	}
	return int(start + length)
}

fn require(data []u8, offset int, length int) ! {
	if offset < 0 || length < 0 || offset > data.len || length > data.len - offset {
		return error('truncated Mach-O file')
	}
}

fn le_u16(data []u8, offset int) !u16 {
	require(data, offset, 2)!
	return u16(data[offset]) | u16(data[offset + 1]) << 8
}

fn le_u32(data []u8, offset int) !u32 {
	require(data, offset, 4)!
	return u32(data[offset]) | u32(data[offset + 1]) << 8 | u32(data[offset + 2]) << 16 | u32(data[offset + 3]) << 24
}

fn le_u64(data []u8, offset int) !u64 {
	low := le_u32(data, offset)!
	high := le_u32(data, offset + 4)!
	return u64(low) | u64(high) << 32
}

fn be_u32(data []u8, offset int) !u32 {
	require(data, offset, 4)!
	return u32(data[offset]) << 24 | u32(data[offset + 1]) << 16 | u32(data[offset + 2]) << 8 | u32(data[offset + 3])
}

fn be_u64(data []u8, offset int) !u64 {
	high := be_u32(data, offset)!
	low := be_u32(data, offset + 4)!
	return u64(high) << 32 | u64(low)
}

fn fixed_name(data []u8, offset int, width int) !string {
	require(data, offset, width)!
	mut length := 0
	for length < width && data[offset + length] != 0 {
		length++
	}
	return data[offset..offset + length].bytestr()
}

fn cstring(data []u8, offset int, limit int) !string {
	if offset < 0 || limit < offset || limit > data.len {
		return error('invalid Mach-O string range')
	}
	mut end := offset
	for end < limit && data[end] != 0 {
		end++
	}
	if end == limit {
		return error('unterminated Mach-O string')
	}
	return data[offset..end].bytestr()
}

// select_architecture accepts thin executables and both 32- and 64-bit fat
// containers. The returned bytes borrow data; callers must keep it alive.
pub fn select_architecture(data []u8, wanted_cpu u32) ![]u8 {
	require(data, 0, 4)!
	if le_u32(data, 0)! == magic_64 {
		if le_u32(data, 4)! != wanted_cpu {
			return error('Mach-O does not contain the host architecture')
		}
		return data
	}
	magic := be_u32(data, 0)!
	if magic != fat_magic && magic != fat_magic_64 {
		return error('not a 64-bit Mach-O executable')
	}
	count := int(be_u32(data, 4)!)
	entry_size := if magic == fat_magic_64 { 32 } else { 20 }
	if count < 1 || count > 64 {
		return error('invalid Mach-O fat architecture count')
	}
	require(data, 8, count * entry_size)!
	for index in 0 .. count {
		entry := 8 + index * entry_size
		cpu := be_u32(data, entry)!
		offset := if magic == fat_magic_64 {
			be_u64(data, entry + 8)!
		} else {
			u64(be_u32(data, entry + 8)!)
		}
		size := if magic == fat_magic_64 {
			be_u64(data, entry + 16)!
		} else {
			u64(be_u32(data, entry + 12)!)
		}
		if cpu != wanted_cpu {
			continue
		}
		end := checked_end(offset, size, data.len)!
		if size < 32 {
			return error('truncated Mach-O architecture slice')
		}
		return data[int(offset)..end]
	}
	return error('Mach-O does not contain the host architecture')
}

pub fn parse(data []u8, wanted_cpu u32) !Image {
	slice := select_architecture(data, wanted_cpu)!
	require(slice, 0, 32)!
	if le_u32(slice, 0)! != magic_64 || le_u32(slice, 4)! != wanted_cpu {
		return error('unsupported Mach-O architecture')
	}
	if le_u32(slice, 12)! != mh_execute {
		return error('Mach-O image is not an executable')
	}
	command_count := int(le_u32(slice, 16)!)
	command_bytes := int(le_u32(slice, 20)!)
	if command_count < 1 || command_count > 4096 {
		return error('invalid Mach-O load-command count')
	}
	require(slice, 32, command_bytes)!

	mut segments := []Segment{cap: 8}
	mut dependencies := []string{}
	mut dyld := DyldInfo{}
	mut symbols := SymbolTable{}
	mut entry_file_offset := u64(0)
	mut saw_entry := false
	mut offset := 32
	commands_end := 32 + command_bytes
	for _ in 0 .. command_count {
		require(slice, offset, 8)!
		command := le_u32(slice, offset)!
		size := int(le_u32(slice, offset + 4)!)
		if size < 8 || offset > commands_end || size > commands_end - offset {
			return error('invalid Mach-O load command')
		}
		match command {
			lc_segment_64 {
				if size < 72 {
					return error('truncated LC_SEGMENT_64')
				}
				segment := Segment{
					name: fixed_name(slice, offset + 8, 16)!
					vm_address: le_u64(slice, offset + 24)!
					vm_size: le_u64(slice, offset + 32)!
					file_offset: le_u64(slice, offset + 40)!
					file_size: le_u64(slice, offset + 48)!
					max_protection: i32(le_u32(slice, offset + 56)!)
					initial_protection: i32(le_u32(slice, offset + 60)!)
				}
				if segment.file_size > segment.vm_size {
					return error('Mach-O segment file size exceeds memory size')
				}
				checked_end(segment.file_offset, segment.file_size, slice.len)!
				segments << segment
			}
			lc_symtab {
				if size < 24 {
					return error('truncated LC_SYMTAB')
				}
				symbols = SymbolTable{
					offset: le_u32(slice, offset + 8)!
					count: le_u32(slice, offset + 12)!
					strings_offset: le_u32(slice, offset + 16)!
					strings_size: le_u32(slice, offset + 20)!
				}
			}
			lc_dyld_info, lc_dyld_info_only {
				if size < 48 {
					return error('truncated LC_DYLD_INFO')
				}
				dyld = DyldInfo{
					rebase_offset: le_u32(slice, offset + 8)!
					rebase_size: le_u32(slice, offset + 12)!
					bind_offset: le_u32(slice, offset + 16)!
					bind_size: le_u32(slice, offset + 20)!
					weak_bind_offset: le_u32(slice, offset + 24)!
					weak_bind_size: le_u32(slice, offset + 28)!
					lazy_bind_offset: le_u32(slice, offset + 32)!
					lazy_bind_size: le_u32(slice, offset + 36)!
				}
			}
			lc_main {
				if size < 24 {
					return error('truncated LC_MAIN')
				}
				entry_file_offset = le_u64(slice, offset + 8)!
				saw_entry = true
			}
			lc_dyld_chained_fixups {
				return error('Mach-O chained fixups are not supported; relink with -no_fixup_chains')
			}
			lc_load_dylib, lc_load_weak_dylib, lc_reexport_dylib, lc_load_upward_dylib {
				if size < 24 {
					return error('truncated Mach-O dylib command')
				}
				name_offset := int(le_u32(slice, offset + 8)!)
				if name_offset < 24 || name_offset >= size {
					return error('invalid Mach-O dylib name')
				}
				dependencies << cstring(slice, offset + name_offset, offset + size)!
			}
			else {}
		}
		offset += size
	}
	if offset != commands_end || segments.len == 0 || !saw_entry {
		return error('incomplete Mach-O executable')
	}
	checked_end(entry_file_offset, 1, slice.len)!
	validate_linkedit(slice, dyld, symbols)!
	return Image{
		data: slice
		cpu_type: wanted_cpu
		segments: segments
		dyld: dyld
		symbol_table: symbols
		entry_file_offset: entry_file_offset
		dependencies: dependencies
	}
}

fn validate_linkedit(data []u8, dyld DyldInfo, symbols SymbolTable) ! {
	for range in [[dyld.rebase_offset, dyld.rebase_size], [dyld.bind_offset, dyld.bind_size],
		[dyld.weak_bind_offset, dyld.weak_bind_size], [dyld.lazy_bind_offset, dyld.lazy_bind_size]] {
		checked_end(u64(range[0]), u64(range[1]), data.len)!
	}
	if symbols.count > 0 {
		checked_end(u64(symbols.offset), u64(symbols.count) * 16, data.len)!
		checked_end(u64(symbols.strings_offset), u64(symbols.strings_size), data.len)!
	}
}

pub fn (image &Image) symbols() ![]Symbol {
	table := image.symbol_table
	mut out := []Symbol{cap: int(table.count)}
	strings_end := int(u64(table.strings_offset) + u64(table.strings_size))
	for index in 0 .. int(table.count) {
		offset := int(table.offset) + index * 16
		string_index := int(le_u32(image.data, offset)!)
		type_ := image.data[offset + 4]
		if string_index == 0 {
			continue
		}
		if string_index < 0 || string_index >= int(table.strings_size) {
			return error('invalid Mach-O symbol name')
		}
		out << Symbol{
			name: cstring(image.data, int(table.strings_offset) + string_index, strings_end)!
			value: le_u64(image.data, offset + 8)!
			defined: type_ & 0x0e != 0
		}
	}
	return out
}

pub fn (image &Image) segment_for_file_offset(file_offset u64) ?Segment {
	for segment in image.segments {
		if file_offset >= segment.file_offset && file_offset - segment.file_offset < segment.file_size {
			return segment
		}
	}
	return none
}
