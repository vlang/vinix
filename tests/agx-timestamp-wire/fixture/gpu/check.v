// SPDX-License-Identifier: GPL-2.0-or-later
module gpu

import gpu.agx.fw
import gpu.agx.hw

#include <stdio.h>
#define kprintf printf
fn C.kprintf(format &char, ...) i32

struct Buffer { va u64 }
struct RenderJob { vertex Buffer fragment Buffer }
struct ComputeJob { command Buffer }
struct Queue { info Buffer }
struct Input { vertex_command_id u32 fragment_command_id u32 command_id u32 }
struct Sample { command u64 queue u64 uuid u32 }
struct Reference {
	kind string
	end bool
	old_time int
	new_time int
	old_kernel int
	new_kernel int
	old_user int
	new_user int
	scratch int
}

fn put(mut image [0x3c]u8, offset int, size int, value u64) {
	for i in 0 .. size { image[offset + i] = u8(value >> (i * 8)) }
}

fn check_empty_pair(command voidptr, offset int) {
	for i in 0 .. 16 { assert unsafe { (&u8(command))[offset + i] } == 0 }
}

pub fn run_checks() {
	assert sizeof(fw.G13MicroseqTimestamp) == old_size
	assert sizeof(fw.G13MicroseqTimestampV135) == new_size
	assert __offsetof(fw.G13MicroseqTimestamp, user_ts_pointers) == 0x24
	vertex := fw.G13RunVertex{}
	fragment := fw.G13RunFragment{}
	compute := fw.G13RunCompute{}
	vertex_new := fw.make_g13_vertex_v13_5(&vertex, 0)
	fragment_new := fw.make_g13_fragment_v13_5(&fragment, 0)
	compute_new := fw.make_g13_compute_v13_5(&compute, 0)
	for reference in references {
		old_pair := fw.g13_timestamp_user_ts_offset_for(.v12_3, match reference.kind {
			'vertex' { fw.g13_useq_pipe_vertex } 'fragment' { fw.g13_useq_pipe_fragment } else { fw.g13_useq_pipe_compute }
		}) or { panic('missing old pair') }
		assert old_pair == u64(reference.old_user)
		if reference.kind == 'vertex' { check_empty_pair(voidptr(&vertex), reference.old_user) }
		else if reference.kind == 'fragment' { check_empty_pair(voidptr(&fragment), reference.old_user) }
		else { check_empty_pair(voidptr(&compute), reference.old_user) }
		if reference.kind == 'vertex' { check_empty_pair(voidptr(&vertex_new), reference.new_user) }
		else if reference.kind == 'fragment' { check_empty_pair(voidptr(&fragment_new), reference.new_user) }
		else { check_empty_pair(voidptr(&compute_new), reference.new_user) }
	}
	for abi in [hw.FirmwareAbi.unknown, hw.FirmwareAbi.v12_3_partial, hw.FirmwareAbi.g17_26_5_partial] {
		if _ := fw.g13_timestamp_user_ts_offset_for(abi, fw.g13_useq_pipe_vertex) { assert false }
	}
	for abi in [hw.FirmwareAbi.v12_3, hw.FirmwareAbi.v13_5_partial] {
		for pipe in [u32(0), fw.g13_useq_pipe_vertex | fw.g13_useq_pipe_fragment, ~u32(0)] {
			if _ := fw.g13_timestamp_user_ts_offset_for(abi, pipe) { assert false }
		}
	}
	mut cases := 0
	for cycle in 0 .. 100 {
		for modern in [false, true] {
			for shift in [0, 1, 7, 15]! {
				for address in [u64(0), u64(0xffff_ffa0_1234_0000) + u64(cycle) * 0x4000, u64(0xffff_ffff_ffff_c000)]! {
					sample := Sample{address, u64(0xffff_ffa1_5678_0000) + u64(cycle) * 0x4000, u32(0x1234_0000) + u32(cycle)}
					for index, reference in references {
						mut destination := [0x80]u8{init: 0xa5}
						start := 16 + shift
						size := if modern { new_size } else { old_size }
						written := encode(index, sample, modern, unsafe { voidptr(&destination[start]) })
						assert written == u64(size)
						expected := expected_image(reference, sample, modern)
						for i in 0 .. destination.len {
							value := if i >= start && i < start + size { expected[i - start] } else { u8(0xa5) }
							assert destination[i] == value, '${reference.kind} end=${reference.end} modern=${modern}: timestamp byte mismatch at ${i - start}'
						}
						cases++
					}
				}
			}
		}
	}
	println('G13 timestamps: ${cases} complete source-modeled images from all six actual native initializers and the native writer; pair bindings, old/modern offsets, scratch, kernel pointers, opcode, UUID, zero optional pairs, rejected unknowns and destination guards passed')
}
