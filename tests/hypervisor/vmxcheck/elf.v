// SPDX-License-Identifier: GPL-2.0-only
module vmxcheck

import hosttest
import os

struct Section {
	kind       u32
	address    u64
	offset     u64
	size       u64
	link       u32
	entry_size u64
}

fn span(data []u8, offset u64, length u64) ![]u8 {
	if offset > u64(data.len) || length > u64(data.len) - offset {
		return error('truncated ELF64 range')
	}
	return data[int(offset)..int(offset + length)]
}

fn little(data []u8, offset int, width int) u64 {
	mut value := u64(0)
	for index in 0 .. width { value |= u64(data[offset + index]) << (8 * index) }
	return value
}

// The checker needs no platform-specific nm to read a little-endian ELF64
// function. Validate every file range before narrowing offsets or slicing.
pub fn symbol_bytes(path string, name string) ![]u8 {
	return elf_symbol(os.read_bytes(path)!, path, name)
}

fn elf_symbol(data []u8, path string, name string) ![]u8 {
	if data.len < 64 || data[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1] {
		return error('not little-endian ELF64: ${path}')
	}
	section_offset := little(data, 40, 8)
	stride := little(data, 58, 2)
	count := little(data, 60, 2)
	if count > 0 && stride < 64 { return error('invalid ELF64 section stride') }
	span(data, section_offset, count * stride)!
	mut sections := []Section{cap: int(count)}
	for index in 0 .. int(count) {
		row := span(data, section_offset + u64(index) * stride, 64)!
		sections << Section{
			kind:       u32(little(row, 4, 4))
			address:    little(row, 16, 8)
			offset:     little(row, 24, 8)
			size:       little(row, 32, 8)
			link:       u32(little(row, 40, 4))
			entry_size: little(row, 56, 8)
		}
	}
	for section in sections {
		if section.kind != 2 { continue }
		if section.link >= u32(sections.len) { return error('invalid ELF64 string-table index') }
		strings := sections[section.link]
		names := span(data, strings.offset, strings.size)!
		symbols := span(data, section.offset, section.size)!
		if section.entry_size < 24 || section.size % section.entry_size != 0 {
			return error('invalid ELF64 symbol stride')
		}
		mut position := u64(0)
		for position < section.size {
			row := span(symbols, position, 24)!
			name_offset := little(row, 0, 4)
			if name_offset >= u64(names.len) { return error('invalid ELF64 symbol-name offset') }
			suffix := names[int(name_offset)..]
			end := suffix.index(u8(0))
			if end < 0 { return error('unterminated ELF64 symbol name') }
			text := suffix[..end].bytestr()
			hosttest.module_decode_utf8(text)!
			if text == name {
				index := little(row, 6, 2)
				if index >= u64(sections.len) { return error('invalid ELF64 symbol-section index') }
				content := sections[int(index)]
				value := little(row, 8, 8)
				length := little(row, 16, 8)
				if value < content.address { return error('invalid ELF64 symbol address') }
				delta := value - content.address
				if delta > content.size || length > content.size - delta {
					return error('ELF64 symbol exceeds its section')
				}
				return span(span(data, content.offset, content.size)!, delta, length)!.clone()
			}
			position += section.entry_size
		}
	}
	return error('missing ${name} in ${path}')
}
