// SPDX-License-Identifier: GPL-2.0-or-later
// Read-only ARM64 call-site hints; dynamic values/control flow remain unknown.
module main

import encoding.binary
import macho
import os

fn unresolved(_ string, _ string) !u64 { return 0x4000000000 }
fn location(image macho.Image, address u64, size u64) !int {
	for segment in image.segments {
		if address >= segment.address && address - segment.address <= segment.filesize
			&& size <= segment.filesize - (address - segment.address) {
			return int(segment.fileoff + address - segment.address)
		}
	}
	return error('unmapped address')
}
fn word(image macho.Image, address u64) !u64 {
	offset := location(image, address, 8)!
	return binary.little_endian_u64(image.data[offset..offset + 8])
}
fn page_address(instruction u32, pc u64) u64 {
	bits := u64((instruction >> 5) & 0x7ffff) << 2 | u64((instruction >> 29) & 3)
	delta := if bits & 0x100000 != 0 { i64(bits) - 0x200000 } else { i64(bits) }
	return u64(i64(pc & ~u64(4095)) + delta * 4096)
}
fn key_text(image macho.Image, pointers map[u64]u64, address u64) string {
	data := pointers[address + 16] or { return '<dynamic>' }
	length := word(image, address + 24) or { return '<dynamic>' }
	if length == 0 || length > 128 { return '<dynamic>' }
	offset := location(image, data, length) or { return '<dynamic>' }
	bytes := image.data[offset..offset + int(length)]
	if bytes.any(it < 32 || it > 126) { return '<non-ASCII>' }
	return bytes.bytestr()
}
fn main() {
	if os.args.len != 2 { panic('usage: inspect-objc-key MACH_O | --selftest') }
	if os.args[1] == '--selftest' {
		assert page_address(0x90000001, 0x100001234) == 0x100001000;
		assert page_address(0xf0ffffe1, 0x100001234) == 0x100000000;
		println('ARM64 ADRP signed-page decoding: PASS')
		return
	}
	image := macho.parse(os.read_bytes(os.args[1])!)!
	layout := image.layout(16384)!
	mut text := macho.Section{}
	mut selectors := macho.Section{}
	mut strings := macho.Section{}
	mut stubs := macho.Section{}
	mut value_key := u64(0)
	mut current_device := u64(0)
	for segment in image.segments {
		for section in segment.sections {
			if section.name == '__text' { text = section }
			if section.name == '__objc_selrefs' { selectors = section }
			if section.name == '__cfstring' { strings = section }
			if section.name == '__objc_stubs' { stubs = section }
			if section.name != '__objc_methname' { continue }
			offset := location(image, section.address, section.size)!
			mut start := 0
			for i in 0 .. int(section.size) {
				if image.data[offset + i] != 0 { continue }
				name := image.data[offset + start..offset + i].bytestr()
				if name == 'valueForKey:' { value_key = section.address + u64(start) }
				if name == 'currentDevice' { current_device = section.address + u64(start) }
				start = i + 1
			}
		}
	}
	if value_key == 0 || text.size == 0 || selectors.size == 0 { panic('missing Objective-C sections') }
	mut pointers := map[u64]u64{}
	for fixup in image.plan_fixups(layout, layout.base, unresolved)! {
		address := layout.base + fixup.offset
		if (address >= selectors.address && address - selectors.address < selectors.size)
			|| (address >= strings.address && address - strings.address < strings.size) {
			pointers[address] = fixup.value
		}
	}
	mut registers := [32]u64{}
	mut methods := map[u64]u64{}
	// Current clang selector stubs are 32-byte aligned ADRP/LDR x1 entries.
	for index := u64(0); index + 8 <= stubs.size; index += 32 {
		pc := stubs.address + index
		at := location(image, pc, 8)!
		first := binary.little_endian_u32(image.data[at..at + 4])
		second := binary.little_endian_u32(image.data[at + 4..at + 8])
		if first & 0x9f00001f != 0x90000001 || second & 0xffc003ff != 0xf9400021 { continue }
		slot := page_address(first, pc) + u64((second >> 10) & 4095) * 8
		value := pointers[slot] or { continue }
		if value in [value_key, current_device]! { methods[pc] = value }
	}
	mut last_device := u64(0)
	offset := location(image, text.address, text.size)!
	for index := 0; index + 4 <= int(text.size); index += 4 {
		instruction := binary.little_endian_u32(image.data[offset + index..offset + index + 4])
		pc := text.address + u64(index)
		rd := int(instruction & 31)
		rn := int((instruction >> 5) & 31)
		if instruction & 0x9f000000 == 0x90000000 {
			registers[rd] = page_address(instruction, pc)
		} else if instruction & 0xff000000 == 0x91000000 {
			shift := if instruction & 0x400000 != 0 { 12 } else { 0 }
			registers[rd] = registers[rn] + (u64((instruction >> 10) & 4095) << shift)
		} else if instruction & 0xffe0ffe0 == 0xaa0003e0 {
			registers[rd] = registers[int((instruction >> 16) & 31)]
		} else if instruction & 0xffc00000 == 0xf9400000 {
			address := registers[rn] + u64((instruction >> 10) & 4095) * 8
			registers[rd] = pointers[address] or { u64(0) }
		} else if instruction & 0xfc000000 == 0x94000000 {
			bits := i64(instruction & 0x3ffffff)
			delta := if bits & 0x2000000 != 0 { bits - 0x4000000 } else { bits }
			target := u64(i64(pc) + delta * 4)
			selector := methods[target] or { registers[1] }
			if selector == current_device { last_device = pc }
			if selector == value_key {
				println('call=0x${pc.hex()} key=${key_text(image, pointers, registers[2])} preceding-currentDevice=${if last_device != 0 && pc - last_device < 256 { (pc - last_device).str() } else { "unknown" }}')
			}
			for r in 0 .. 19 { registers[r] = 0 }
		}
	}
}
