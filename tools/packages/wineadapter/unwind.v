// SPDX-License-Identifier: GPL-2.0-or-later
module wineadapter

fn unwind_u32(data string, at int) u32 {
	mut value := u32(0)
	for i in 0 .. 4 { value |= u32(data[at + i]) << (8 * i) }
	return value
}

fn unwind_put32(mut data []u8, at int, value u32) {
	for i in 0 .. 4 { data[at + i] = u8(value >> (8 * i)) }
}

fn unwind_put64(mut data []u8, at int, value u64) {
	for i in 0 .. 8 { data[at + i] = u8(value >> (8 * i)) }
}

fn unwind_relative(mut data []u8, at int, target int, base int) ! {
	delta := i64(target) - i64(base)
	if delta < -2147483648 || delta > 2147483647 { return error('Wine unwind displacement overflow') }
	unwind_put32(mut data, at, u32(i32(delta)))
}

// Called only after private_server_patch has admitted the complete original
// ntdll pin and pe_mapping_patch has produced its exact code changes. Relocate
// the existing frame records without changing their CFI programs and add one
// FDE for the trampoline's constant stack state. All metadata stays read-only.
fn pe_unwind_patch(input string, image string) !string {
	old_frame := 0x75290
	old_size := 0xaefc
	old_hdr := 0x73c9c
	old_hdr_size := 0x15f4
	new_segment := 0x83000
	new_va := 0xb9000 // Above the original RW segment's BSS end, 0xb81c0.
	new_frame := 0x83060
	new_frame_va := new_va + new_frame - new_segment
	new_size := old_size + 40
	new_hdr := 0x8df90
	new_hdr_va := new_va + new_hdr - new_segment
	new_hdr_size := old_hdr_size + 8
	end := new_hdr + new_hdr_size
	cie := '\x14\x00\x00\x00\x00\x00\x00\x00\x01zR\x00\x01\x78\x10\x01\x1b\x0c\x07\x08\x90\x01\x00\x00'
	if input.len != 0x82cd0 || image.len != input.len
		|| input[0x38] != 11 || input[0x39] != 0
		|| unsafe { tos(input.str + old_frame, cie.len) } != cie
		|| unsafe { tos(input.str + old_hdr, 4) } != '\x01\x1b\x03\x3b'
		|| unwind_u32(input, old_hdr + 8) != 701
		|| unwind_u32(input, old_frame + old_size - 4) != 0 {
		return error('Wine unwind input layout differs')
	}
	mut bytes := []u8{len: end}
	defer { unsafe { bytes.free() } }
	unsafe {
		vmemcpy(bytes.data, image.str, image.len)
		vmemcpy(&bytes[new_segment], input.str + 0x2a8, 0x54) // Both original notes.
		vmemcpy(&bytes[new_frame], input.str + old_frame, old_size - 4)
	}
	// The original CIE has zR/pcrel-sdata4 and no personality or LSDA pointers.
	// Only the initial-PC fields change when these records move. Their relative
	// CIE references and complete instruction/expression bytes remain identical.
	mut record := cie.len
	mut records := 0
	for record < old_size - 4 {
		length := int(unwind_u32(input, old_frame + record)) + 4
		if length < 17 || record + length > old_size - 4
			|| unwind_u32(input, old_frame + record + 4) != u32(record + 4)
			|| input[old_frame + record + 16] != 0 {
			return error('Wine original FDE layout differs')
		}
		pc := old_frame + record + 8 + int(i32(unwind_u32(input, old_frame + record + 8)))
		unwind_relative(mut bytes, new_frame + record + 8, pc, new_frame_va + record + 8)!
		record += length
		records++
	}
	if record != old_size - 4 || records != 701 { return error('Wine original FDE count differs') }
	fde := new_frame + record
	fde_va := new_frame_va + record
	unwind_put32(mut bytes, fde, 36)
	unwind_put32(mut bytes, fde + 4, u32(record + 4))
	unwind_relative(mut bytes, fde + 8, 0x61ba0, fde_va + 8)!
	unwind_put32(mut bytes, fde + 12, 25)
	// CIE supplies CFA=RSP+8 and RIP=[CFA-8]. At the hook CFA=RSP+4368;
	// saved R15/R14/R13/R12/RBP/RBX occupy CFA-16 through CFA-56.
	rules := '\x00\x0e\x90\x22\x8f\x02\x8e\x03\x8d\x04\x8c\x05\x86\x06\x83\x07'
	unsafe { vmemcpy(&bytes[fde + 16], rules.str, rules.len) }
	for i in 0 .. 4 { bytes[new_hdr + i] = input[old_hdr + i] }
	unwind_relative(mut bytes, new_hdr + 4, new_frame_va, new_hdr_va + 4)!
	unwind_put32(mut bytes, new_hdr + 8, 702)
	mut previous := -1
	for i in 0 .. 701 {
		entry := old_hdr + 12 + i * 8
		pc := old_hdr + int(i32(unwind_u32(input, entry)))
		frame := old_hdr + int(i32(unwind_u32(input, entry + 4)))
		if pc <= previous || pc >= 0x61ba0 || frame < old_frame + cie.len
			|| frame >= old_frame + old_size - 4 {
			return error('Wine original unwind index differs')
		}
		unwind_relative(mut bytes, new_hdr + 12 + i * 8, pc, new_hdr_va)!
		unwind_relative(mut bytes, new_hdr + 16 + i * 8, new_frame_va + frame - old_frame, new_hdr_va)!
		previous = pc
	}
	unwind_relative(mut bytes, new_hdr + 12 + 701 * 8, 0x61ba0, new_hdr_va)!
	unwind_relative(mut bytes, new_hdr + 16 + 701 * 8, fde_va, new_hdr_va)!
	// Add a LOAD header in the old note storage, still within the first ELF
	// page. Both notes move intact and retain their NOTE/GNU_PROPERTY headers.
	bytes[0x38] = 12
	for i in 0 .. 56 { bytes[0x2a8 + i] = 0 }
	unwind_put32(mut bytes, 0x2a8, 1)
	unwind_put32(mut bytes, 0x2ac, 4)
	for at in [0x2b0, 0x2b8, 0x2c0]! {
		unwind_put64(mut bytes, at, u64(if at == 0x2b0 { new_segment } else { new_va }))
	}
	unwind_put64(mut bytes, 0x2c8, u64(end - new_segment))
	unwind_put64(mut bytes, 0x2d0, u64(end - new_segment))
	unwind_put64(mut bytes, 0x2d8, 0x1000)
	for index in [5, 6, 7, 8]! {
		off := if index == 6 { new_segment + 0x30 } else if index == 8 { new_hdr } else { new_segment }
		va := new_va + off - new_segment
		ph := 0x40 + index * 56
		unwind_put64(mut bytes, ph + 8, u64(off))
		unwind_put64(mut bytes, ph + 16, u64(va))
		unwind_put64(mut bytes, ph + 24, u64(va))
		if index == 8 {
			unwind_put64(mut bytes, ph + 32, u64(new_hdr_size))
			unwind_put64(mut bytes, ph + 40, u64(new_hdr_size))
		}
	}
	for index in [1, 2, 14, 15]! {
		off := if index == 1 { new_segment } else if index == 2 { new_segment + 0x30 }
			else if index == 14 { new_hdr } else { new_frame }
		sh := 0x82690 + index * 64
		unwind_put64(mut bytes, sh + 16, u64(new_va + off - new_segment))
		unwind_put64(mut bytes, sh + 24, u64(off))
		if index == 14 || index == 15 {
			unwind_put64(mut bytes, sh + 32, u64(if index == 14 { new_hdr_size } else { new_size }))
		}
	}
	return bytes.bytestr()
}
