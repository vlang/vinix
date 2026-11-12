// SPDX-License-Identifier: GPL-2.0-or-later
module wineunwind

import crypto.sha256

fn number(data string, at int, width int) !u64 {
	if at < 0 || at > data.len || width > data.len - at { return error('unwind field outside file') }
	mut value := u64(0)
	for i in 0 .. width { value |= u64(data[at + i]) << (8 * i) }
	return value
}

fn span(data string, at int, size int) !string {
	if at < 0 || at > data.len || size < 0 || size > data.len - at { return error('unwind span outside file') }
	return unsafe { tos(data.str + at, size) }
}

fn signed(data string, at int, base int) !int {
	return base + int(i32(u32(number(data, at, 4)!)))
}

fn leb(data string, start int) !(int, int) {
	mut at := start
	mut value := 0
	for shift in [0, 7, 14, 21, 28]! {
		byte := u8(number(data, at, 1)!)
		at++
		value |= int(byte & 127) << shift
		if byte & 128 == 0 { return value, at }
	}
	return error('unwind LEB exceeds bound')
}

// Independently compare every original frame/index entry and decode the new
// constant CFA program. No original CFI instruction/expression is regenerated.
pub fn check(original string, changed string) !int {
	if sha256.hexhash(original) != '0d2c95650eb6eff9e7a539d08cb118068b102d812cb505156d3525369dd1ec75'
		|| changed.len != 0x8f58c || number(changed, 0x38, 2)! != 12 {
		return error('unwind input or image length differs')
	}
	segment := 0x2a8
	file := int(number(changed, segment + 8, 8)!)
	va := int(number(changed, segment + 16, 8)!)
	if number(changed, segment, 4)! != 1 || number(changed, segment + 4, 4)! != 4
		|| file != 0x83000 || va != 0xb9000
		|| number(changed, segment + 24, 8)! != u64(va)
		|| number(changed, segment + 32, 8)! != u64(changed.len - file)
		|| number(changed, segment + 40, 8)! != u64(changed.len - file)
		|| number(changed, segment + 48, 8)! != 4096 {
		return error('unwind read-only LOAD differs')
	}
	for index in [1, 2, 14, 15]! {
		sh := 0x82690 + index * 64
		offset := int(number(changed, sh + 24, 8)!)
		address := int(number(changed, sh + 16, 8)!)
		if address - offset != va - file { return error('unwind section translation differs') }
		if index in [1, 2] {
			old := int(number(original, sh + 24, 8)!)
			size := int(number(original, sh + 32, 8)!)
			if number(changed, sh + 32, 8)! != u64(size) || span(changed, offset, size)! != span(original, old, size)! {
				return error('relocated note bytes differ')
			}
			for phindex in if index == 1 { [5, 7] } else { [6] } {
				ph := 0x40 + phindex * 56
				if number(changed, ph + 8, 8)! != u64(offset)
					|| number(changed, ph + 16, 8)! != u64(address)
					|| number(changed, ph + 24, 8)! != u64(address)
					|| number(changed, ph, 8)! != number(original, ph, 8)!
					|| span(changed, ph + 32, 24)! != span(original, ph + 32, 24)! {
					return error('relocated note program header differs')
				}
			}
		}
	}
	frame_sh := 0x82690 + 15 * 64
	frame := int(number(changed, frame_sh + 24, 8)!)
	frame_va := int(number(changed, frame_sh + 16, 8)!)
	hdr_sh := 0x82690 + 14 * 64
	hdr := int(number(changed, hdr_sh + 24, 8)!)
	hdr_va := int(number(changed, hdr_sh + 16, 8)!)
	if frame != 0x83060 || hdr != 0x8df90 || number(changed, frame_sh + 32, 8)! != 0xaf24
		|| number(changed, hdr_sh + 32, 8)! != 0x15fc
		|| span(changed, hdr, 4)! != '\x01\x1b\x03\x3b'
		|| signed(changed, hdr + 4, hdr_va + 4)! != frame_va
		|| number(changed, hdr + 8, 4)! != 702 {
		return error('unwind section/header bounds differ')
	}
	ph := 0x40 + 8 * 56
	if number(changed, ph + 8, 8)! != u64(hdr) || number(changed, ph + 16, 8)! != u64(hdr_va)
		|| number(changed, ph + 24, 8)! != u64(hdr_va)
		|| number(changed, ph + 32, 8)! != 0x15fc || number(changed, ph + 40, 8)! != 0x15fc {
		return error('GNU unwind program header differs')
	}
	if span(changed, frame, 24)! != span(original, 0x75290, 24)! { return error('CIE differs') }
	mut record := 24
	mut count := 0
	for record < 0xaef8 {
		size := int(number(original, 0x75290 + record, 4)!) + 4
		if size < 17 || record + size > 0xaef8 { return error('original frame outside bounds') }
		if span(changed, frame + record, 8)! != span(original, 0x75290 + record, 8)!
			|| span(changed, frame + record + 12, size - 12)! != span(original, 0x75290 + record + 12, size - 12)!
			|| signed(changed, frame + record + 8, frame_va + record + 8)!
				!= signed(original, 0x75290 + record + 8, 0x75290 + record + 8)! {
			return error('original frame identity or CFI differs')
		}
		record += size
		count++
	}
	if count != 701 || record != 0xaef8 { return error('original frame count differs') }
	for i in 0 .. 701 {
		old := 0x73c9c + 12 + i * 8
		new := hdr + 12 + i * 8
		if signed(changed, new, hdr_va)! != signed(original, old, 0x73c9c)!
			|| signed(changed, new + 4, hdr_va)! - frame_va
				!= signed(original, old + 4, 0x73c9c)! - 0x75290 {
			return error('original unwind index differs')
		}
	}
	fde := frame + record
	if signed(changed, hdr + 12 + 701 * 8, hdr_va)! != 0x61ba0
		|| signed(changed, hdr + 16 + 701 * 8, hdr_va)! != frame_va + record
		|| number(changed, fde, 4)! != 36 || number(changed, fde + 4, 4)! != u64(record + 4)
		|| signed(changed, fde + 8, frame_va + record + 8)! != 0x61ba0
		|| number(changed, fde + 12, 4)! != 25 || number(changed, fde + 16, 1)! != 0
		|| number(changed, fde + 40, 4)! != 0 {
		return error('trampoline FDE/index differs')
	}
	mut at := fde + 17
	mut cfa := 8
	mut saved := [17]int{}
	saved[16] = -8
	for at < fde + 40 {
		op := changed[at]
		at++
		if op == 0 { continue }
		value, next := leb(changed, at)!
		at = next
		if at > fde + 40 { return error('trampoline CFI exceeds record') }
		if op == 0x0e { cfa = value }
		else if op >= 0x80 && op <= 0x90 { saved[int(op & 63)] = -8 * value }
		else { return error('unsupported trampoline CFI') }
	}
	for i in 0 .. 17 {
		expected := match i { 3 { -56 } 6 { -48 } 12 { -40 } 13 { -32 } 14 { -24 } 15 { -16 } 16 { -8 } else { 0 } }
		if saved[i] != expected { return error('trampoline saved register differs') }
	}
	if cfa != 4368 { return error('trampoline CFA differs') }
	for bounds in [[original.len, file]!, [file + 0x54, frame]!, [fde + 40, hdr]!] {
		for offset in bounds[0] .. bounds[1] {
			if changed[offset] != 0 { return error('unwind metadata padding differs') }
		}
	}
	return count
}

// These fields are separately checked above; all other original bytes remain
// under the existing exact image-patch comparison.
pub fn metadata_byte(at int) bool {
	if at == 0x38 || at >= 0x2a8 && at < 0x2e0 { return true }
	for index in [5, 6, 7, 8]! {
		start := 0x40 + index * 56 + 8
		if at >= start && at < start + if index == 8 { 40 } else { 24 } { return true }
	}
	for index in [1, 2, 14, 15]! {
		start := 0x82690 + index * 64 + 16
		if at >= start && at < start + if index in [14, 15] { 24 } else { 16 } { return true }
	}
	return false
}
