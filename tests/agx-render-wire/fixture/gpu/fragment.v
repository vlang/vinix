// SPDX-License-Identifier: GPL-2.0-or-later
module gpu

import gpu.agx.fw
import gpu.agx.hw

fn fragment_put32(mut bytes [0x96c]u8, offset int, value u32) {
	for i in 0 .. 4 { bytes[offset + i] = u8(value >> (i * 8)) }
}

fn fragment_put64(mut bytes [0x96c]u8, offset int, value u64) {
	for i in 0 .. 8 { bytes[offset + i] = u8(value >> (i * 8)) }
}

fn fragment_expected(legacy &fw.G13RunFragment, newer bool, counter u64) [0x96c]u8 {
	mut expected := [0x96c]u8{}
	fragment_put32(mut expected, 0, 1)
	if newer {
		fragment_put64(mut expected, 4, counter)
		fragment_put64(mut expected, 0xc0, 0x100000)
		fragment_put64(mut expected, 0x6e8, 0x100000)
	}
	fragment_put64(mut expected, if newer { 0x750 } else { 0x740 }, legacy.job_params_3.unk_380)
	fragment_put64(mut expected, if newer { 0x758 } else { 0x748 }, legacy.job_params_3.unk_388)
	fragment_put64(mut expected, if newer { 0x768 } else { 0x750 }, legacy.job_params_3.depth_dimensions)
	flags := if newer { 0x770 } else { 0x758 }
	fragment_put32(mut expected, flags, legacy.unk_758_flag)
	fragment_put32(mut expected, flags + 4, legacy.unk_75c_flag)
	fragment_put32(mut expected, if newer { 0x888 } else { 0x870 }, legacy.busy_flag)
	fragment_put32(mut expected, if newer { 0x88c } else { 0x874 }, legacy.tvb_overflow_count)
	fragment_put32(mut expected, if newer { 0x890 } else { 0x878 }, legacy.unk_878)
	fragment_put32(mut expected, if newer { 0x8bc } else { 0x8a4 }, legacy.process_empty_tiles)
	fragment_put32(mut expected, if newer { 0x8c0 } else { 0x8a8 }, legacy.no_clear_pipeline_textures)
	fragment_put32(mut expected, if newer { 0x8c4 } else { 0x8ac }, legacy.msaa_zs)
	fragment_put32(mut expected, if newer { 0x8c8 } else { 0x8b0 }, legacy.unk_pointee)
	// 13.5's inserted words at 0x760 and 0x8cc stay zero.
	meta := if newer { 0x8d0 } else { 0x8b4 }
	fragment_put32(mut expected, meta, 0x00331122 | (u32(legacy.meta.no_preemption) << 24))
	fragment_put64(mut expected, meta + 4, legacy.meta.stamp)
	fragment_put64(mut expected, meta + 0xc, legacy.meta.fw_stamp)
	fragment_put32(mut expected, meta + 0x14, legacy.meta.stamp_value)
	fragment_put32(mut expected, meta + 0x18, legacy.meta.stamp_slot)
	fragment_put32(mut expected, meta + 0x1c, legacy.meta.evctl_index)
	fragment_put32(mut expected, meta + 0x20, legacy.meta.flush_stamps)
	fragment_put32(mut expected, meta + 0x24, legacy.meta.uuid)
	fragment_put32(mut expected, meta + 0x28, legacy.meta.event_sequence)
	fragment_put32(mut expected, meta + 0x2c, legacy.unk_after_meta)
	tail := if newer { 0x900 } else { 0x8e4 }
	fragment_put64(mut expected, tail, legacy.unk_buf_0)
	fragment_put64(mut expected, tail + 8, legacy.unk_buf_8)
	fragment_put64(mut expected, tail + 0x10, legacy.unk_buf_10)
	fragment_put64(mut expected, tail + 0x18, legacy.cur_ts)
	fragment_put64(mut expected, tail + 0x20, legacy.start_ts)
	fragment_put64(mut expected, tail + 0x28, legacy.end_ts)
	fragment_put32(mut expected, tail + 0x30, legacy.unk_914)
	fragment_put64(mut expected, tail + 0x34, legacy.unk_918)
	fragment_put32(mut expected, tail + 0x3c, legacy.unk_920)
	expected[tail + 0x40] = legacy.client_sequence
	for i in 0 .. 3 { expected[tail + 0x41 + i] = legacy.pad_925[i] }
	fragment_put32(mut expected, tail + 0x44, legacy.unk_928)
	expected[tail + 0x48] = legacy.unk_92c
	return expected
}

pub fn run_fragment_repack_checks() {
	assert sizeof(fw.G13RunFragment) == 0x930, 'fragment 12.3 size expected 0x930'
	assert sizeof(fw.G13RunFragmentV135) == 0x96c, 'fragment 13.5 size expected 0x96c'
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
						job_params_3: fw.G13FragmentJobParameters3{
							unk_380: 0x1234_5678_0100_0000 + u64(cycle)
							unk_388: 0x8765_4321_0200_0000 + u64(cycle)
							depth_dimensions: 0x8000_0000_0300_0000 + u64(cycle)
						}
						unk_758_flag: scratch
						unk_75c_flag: ~scratch
						busy_flag: u32(cycle)
						tvb_overflow_count: ~u32(cycle)
						unk_878: 0xabc12345
						process_empty_tiles: u32(cycle % 2)
						no_clear_pipeline_textures: u32(cycle % 3)
						msaa_zs: u32(cycle % 5)
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
						unk_buf_8: ~tail
						unk_buf_10: 1
						cur_ts: counter
						start_ts: 0xffff_ffa0_3000_0010 + u64(cycle) * 0x20
						end_ts: 0xffff_ffa0_3000_0018 + u64(cycle) * 0x20
						unk_914: scratch
						unk_918: 0xffff_ffa0_4567_89ab
						unk_920: ~scratch
						client_sequence: u8(cycle)
						pad_925: [u8(0x12), 0x34, 0x56]!
						unk_928: 0x12345678
						unk_92c: 0xa5
					}
					old_expected := fragment_expected(unsafe { &legacy }, false, counter)
					old_bytes := unsafe { &u8(&legacy) }
					for i in 0 .. 0x930 {
						assert unsafe { old_bytes[i] } == old_expected[i], 'fragment 12.3 byte mismatch at ${i}'
					}
					actual := fw.make_g13_fragment_v13_5(unsafe { &legacy }, counter)
					expected := fragment_expected(unsafe { &legacy }, true, counter)
					for i in 0 .. expected.len {
						assert actual.bytes[i] == expected[i], 'fragment repack byte mismatch at ${i}'
					}
					assert legacy.unk_pointee == scratch && legacy.unk_after_meta == ~scratch && legacy.unk_buf_0 == tail
					cases += 2
				}
			}
		}
	}
	println('G13 fragment repack: ${cases} complete byte images; both ABIs, sizes, depth insertion, flags, scratch/reserved separation, metadata, timestamps and complete common tail passed')
}
