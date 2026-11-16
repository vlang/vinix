// SPDX-License-Identifier: GPL-2.0-or-later
module gpu

import gpu.agx.fw
import gpu.agx.hw

fn fragment_put32(mut bytes [0x974]u8, offset int, value u32) {
	for i in 0 .. 4 { bytes[offset + i] = u8(value >> (i * 8)) }
}

fn fragment_put64(mut bytes [0x974]u8, offset int, value u64) {
	for i in 0 .. 8 { bytes[offset + i] = u8(value >> (i * 8)) }
}

pub fn run_fragment_repack_checks() {
	assert fw.g13_fragment_job_params_3_offset_for(.v13_5_partial) or { panic('missing fragment offset') } == 0x4b8,
		'fragment third-parameter offset expected 0x4b8'
	assert fw.g13_fragment_job_params_3_offset_for(.v12_3) or { panic('missing legacy offset') } == 0x4b0
	if _ := fw.g13_fragment_job_params_3_offset_for(hw.FirmwareAbi.g17_26_5_partial) { assert false }
	mut cases := 0
	for cycle in 0 .. 200 {
		for scratch in [u32(0), 1, 0x7fff_ffff, 0x8000_0000, ~u32(0)]! {
			for counter in [u64(0), u64(cycle) << 32, ~u64(0)]! {
				for tail in [u64(0), 0xffff_ffa0_1234_5678 + u64(cycle)]! {
					legacy := fw.G13RunFragment{
						tag: 1
						unk_pointee: scratch
						meta: fw.G13JobMeta{
							unk_0: 0x1122
							unk_2: 0x33
							no_preemption: u8(cycle % 2)
							stamp: 0xffff_ffa0_1000_0000 + u64(cycle) * 8
							fw_stamp: 0xffff_ffa0_2000_0000 + u64(cycle) * 8
							stamp_value: u32(cycle) << 24
							stamp_slot: u32(cycle % 128)
							evctl_index: 0x12345678
							flush_stamps: u32(cycle % 2)
							uuid: u32(cycle) | 0xa500_0000
							event_sequence: ~u32(0) - u32(cycle)
						}
						unk_after_meta: ~scratch
						unk_buf_0: tail
					}
					actual := fw.make_g13_fragment_v13_5(unsafe { &legacy }, counter)
					mut expected := [0x974]u8{}
					fragment_put32(mut expected, 0, 1)
					fragment_put64(mut expected, 4, counter)
					fragment_put64(mut expected, 0xc0, 0x100000)
					fragment_put64(mut expected, 0x6e8, 0x100000)
					fragment_put32(mut expected, 0x8c8, scratch)
					// The newly inserted 13.3 word at 0x8cc stays zero.
					fragment_put32(mut expected, 0x8d0, 0x00331122 | (u32(cycle % 2) << 24))
					fragment_put64(mut expected, 0x8d4, legacy.meta.stamp)
					fragment_put64(mut expected, 0x8dc, legacy.meta.fw_stamp)
					fragment_put32(mut expected, 0x8e4, legacy.meta.stamp_value)
					fragment_put32(mut expected, 0x8e8, legacy.meta.stamp_slot)
					fragment_put32(mut expected, 0x8ec, legacy.meta.evctl_index)
					fragment_put32(mut expected, 0x8f0, legacy.meta.flush_stamps)
					fragment_put32(mut expected, 0x8f4, legacy.meta.uuid)
					fragment_put32(mut expected, 0x8f8, legacy.meta.event_sequence)
					fragment_put32(mut expected, 0x8fc, ~scratch)
					fragment_put64(mut expected, 0x900, tail)
					for i in 0 .. expected.len {
						assert actual.bytes[i] == expected[i], 'fragment repack byte mismatch at ${i}'
					}
					assert legacy.unk_pointee == scratch && legacy.unk_after_meta == ~scratch && legacy.unk_buf_0 == tail
					cases++
				}
			}
		}
	}
	println('G13 fragment repack: ${cases} complete byte images; third-parameter offset, scratch/reserved separation, nonzero metadata and counters passed')
}
