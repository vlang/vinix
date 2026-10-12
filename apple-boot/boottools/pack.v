// SPDX-License-Identifier: GPL-2.0-or-later
module boottools

import cachecli
import os
import strconv
import time

pub const blob_alignment = u64(0x4000)
pub const payload_header_size = 80

pub fn align(value u64, alignment u64) !u64 {
	if alignment == 0 || value > ~u64(0) - (alignment - 1) {
		return error('invalid alignment or overflow')
	}
	return (value + alignment - 1) / alignment * alignment
}

fn word(data []u8, at u64, size int, little bool) !u64 {
	if size < 1 || size > 8 || at > u64(data.len) || u64(size) > u64(data.len) - at {
		return error('truncated binary field')
	}
	mut value := u64(0)
	for index in 0 .. size {
		value = (value << 8) | data[int(at) + if little { size - 1 - index } else { index }]
	}
	return value
}

fn put(mut data []u8, at int, value u64, size int, little bool) {
	for index in 0 .. size {
		data[at + index] = u8(value >> (8 * if little { index } else { size - 1 - index }))
	}
}

pub fn elf_symbol(data []u8, wanted string) !u64 {
	if data.len < 64 || data[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1] {
		return error('not a 64-bit little-endian ELF')
	}
	section_offset := word(data, 0x28, 8, true)!
	section_size := word(data, 0x3a, 2, true)!
	section_count := word(data, 0x3c, 2, true)!
	if section_size < 64 || section_offset > u64(data.len) || section_count > (u64(data.len) - section_offset) / section_size {
		return error('truncated ELF section table')
	}
	for index in u64(0) .. section_count {
		section := section_offset + index * section_size
		if word(data, section + 4, 4, true)! != 2 { continue }
		strings_index := word(data, section + 40, 4, true)!
		if strings_index >= section_count { return error('invalid ELF string table index') }
		strings := section_offset + strings_index * section_size
		strings_offset := word(data, strings + 24, 8, true)!
		strings_size := word(data, strings + 32, 8, true)!
		symbol_offset := word(data, section + 24, 8, true)!
		symbol_size := word(data, section + 32, 8, true)!
		stride := word(data, section + 56, 8, true)!
		if stride < 24 || symbol_offset > u64(data.len) || symbol_size > u64(data.len) - symbol_offset || strings_offset > u64(data.len) || strings_size > u64(data.len) - strings_offset {
			return error('invalid ELF symbol/string bounds')
		}
		for at := symbol_offset; at < symbol_offset + symbol_size; at += stride {
			name := word(data, at, 4, true)!
			if name >= strings_size { return error('invalid ELF symbol name') }
			start := strings_offset + name
			mut end := start
			for end < strings_offset + strings_size && data[int(end)] != 0 { end++ }
			if end == strings_offset + strings_size { return error('unterminated ELF symbol name') }
			if data[int(start)..int(end)].bytestr() == wanted { return word(data, at + 8, 8, true) }
		}
	}
	return error('no symbol ' + wanted)
}

pub fn pack(loader []u8, loader_end u64, kernel []u8, initramfs []u8, cmdline string, flags u32, build_time u64) ![]u8 {
	if u64(loader.len) > loader_end { return error('loader extends past loader_end') }
	if kernel.len < 4 || kernel[..4] != [u8(0x7f), `E`, `L`, `F`] {
		return error('the kernel is not an ELF file')
	}
	kernel_offset := align(u64(payload_header_size), blob_alignment)!
	initramfs_offset := align(kernel_offset + u64(kernel.len), blob_alignment)!
	cmdline_offset := align(initramfs_offset + u64(initramfs.len), blob_alignment)!
	total := align(cmdline_offset + u64(cmdline.len) + 1, blob_alignment)!
	if loader_end > u64(0x7fffffff) || total > u64(0x7fffffff) - loader_end {
		return error('Apple image exceeds host array bounds')
	}
	mut image := []u8{len: int(loader_end + total)}
	copy(mut image, loader)
	base := int(loader_end)
	copy(mut image[base..], 'VNXAPPL1'.bytes())
	put(mut image, base + 8, u64(payload_header_size), 4, true)
	put(mut image, base + 12, flags, 4, true)
	for index, value in [kernel_offset, u64(kernel.len), initramfs_offset, u64(initramfs.len),
		cmdline_offset, u64(cmdline.len), build_time, total] {
		put(mut image, base + 16 + index * 8, value, 8, true)
	}
	copy(mut image[base + int(kernel_offset)..], kernel)
	copy(mut image[base + int(initramfs_offset)..], initramfs)
	copy(mut image[base + int(cmdline_offset)..], cmdline.bytes())
	return image
}

fn output_option(argv []string) []string {
	mut result := []string{}
	mut separated := false
	for arg in argv {
		if arg == '--' { separated = true }
		if !separated && arg.starts_with('-o') {
			result << if arg == '-o' {
				'--output'
			} else {
				'--output=' + arg[2..].trim_string_left('=')
			}
		} else {
			result << arg
		}
	}
	return result
}

pub fn pack_cli(argv []string) int {
	args := cachecli.arguments(output_option(argv), ['--loader', '--loader-elf', '--kernel',
		'--initramfs', '--cmdline', '--build-time', '--output'], []string{}, ['--map-low-4g'], 0, 0, 'usage: pack --kernel ELF --output FILE [--loader FILE --loader-elf ELF --initramfs TAR --cmdline TEXT --map-low-4g --build-time INTEGER]') or {
		eprintln(err)
		return 2
	}
	kernel := args.required('--kernel') or {
		eprintln(err)
		return 2
	}
	output := args.required('--output') or {
		eprintln(err)
		return 2
	}
	stamp := strconv.parse_uint(args.value('--build-time', time.now().unix().str()), 10, 64) or {
		eprintln(err)
		return 2
	}
	loader := os.read_bytes(path_option(args, '--loader', here() + '/build/vinix-apple-loader.bin')) or {
		eprintln(err)
		return 1
	}
	elf := os.read_bytes(path_option(args, '--loader-elf', here() + '/build/vinix-apple-loader.elf')) or {
		eprintln(err)
		return 1
	}
	end := elf_symbol(elf, 'loader_end') or {
		eprintln(err)
		return 1
	}
	kernel_data := os.read_bytes(path_value(kernel)) or {
		eprintln(err)
		return 1
	}
	initramfs := if '--initramfs' in args.options {
		os.read_bytes(path_option(args, '--initramfs', '')) or {
			eprintln(err)
			return 1
		}
	} else {
		[]u8{}
	}
	image := pack(loader, end, kernel_data, initramfs, args.value('--cmdline', ''), if '--map-low-4g' in args.options {
		u32(1)
	} else {
		u32(0)
	}, stamp) or {
		eprintln(err)
		return 1
	}
	os.write_file_array(path_value(output), image) or {
		eprintln(err)
		return 1
	}
	eprintln(output + ': ' + image.len.str() + ' bytes')
	return 0
}
