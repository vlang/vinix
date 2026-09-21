// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Build the two offset-addressed InitData blobs at both firmware ABIs and check
// where the bytes land.
//
// An M1 Air's firmware speaks 13.5 and this tree was written against 12.3. The
// offsets are translated through tables generated from m1n1's versioned
// definitions, which is only worth anything if the translation actually moves
// the writes: a size assertion cannot tell a correctly re-pointed structure
// from one still being written at 12.3 addresses.
//
// So the same configuration is built twice and compared. At 12.3 nothing moves.
// At 13.5 the fields move to where the generator says, the fields 13.5 adds get
// their values, and the 12.3-only field is not written at all.

import gpu.agx.hw
import gpu.agx.fw

// The fused ladder off a MacBookAir10,1; see tests/agx-t8103-opp.
const ladder_hz = [u64(0), 396_000_000, 528_000_000, 720_000_000, 924_000_000, 1_128_000_000,
	1_278_000_000]
const ladder_uv = [u32(400_000), 618_000, 650_000, 687_000, 778_000, 868_000, 928_000]
const ladder_uw = [u32(0), 1_911_000, 2_478_000, 3_559_000, 5_107_000, 7_000_000, 8_791_000]

// The apple,se-* defaults, which are also m1n1's t8103 values.
fn power_config() hw.G13PowerConfig {
	mut power := hw.G13PowerConfig{
		valid: true
		avg_power_filter_tc_ms: 1000
		avg_power_ki_only_f32: 1089470464
		avg_power_kp_f32: 1082130432
		avg_power_min_duty_cycle: 40
		avg_power_target_filter_tc: 125
		fast_die0_integral_gain_f32: 1128792064
		fast_die0_proportional_gain_f32: 1084227584
		fast_die0_release_temp: 80
		fender_idle_off_delay_ms: 40
		fw_early_wake_timeout_ms: 5
		idle_off_delay_ms: 2
		idle_off_standby_timer: 0
		perf_boost_ce_step: 25
		perf_boost_min_util: 100
		perf_filter_drop_threshold: 0
		perf_filter_time_constant: 5
		perf_filter_time_constant2: 50
		perf_integral_gain_f32: 0x40fca970
		perf_integral_gain2_f32: 1045045537
		perf_integral_min_clamp: 0
		perf_proportional_gain_f32: 0x416b53d1
		perf_proportional_gain2_f32: 1088115664
		perf_reset_iters: 6
		perf_tgt_utilization: 85
		ppm_filter_time_constant_ms: 100
		ppm_ki_f32: 1119289344
		ppm_kp_f32: 1088212173
		pwr_filter_time_constant: 313
		pwr_integral_gain_f32: 0x3ca59586
		pwr_integral_min_clamp: 0
		pwr_min_duty_cycle: 40
		pwr_proportional_gain_f32: 0x40a90fdb
		pwr_sample_period_aic_clks: 192000
		se_engagement_criteria: -1
		se_filter_time_constant: 9
		se_filter_time_constant_1: 3
		se_inactive_threshold: 2500
		se_ki_f32: 0xc2480000
		se_ki_1_f32: 0xc2c80000
		se_kp_f32: 0xc0a00000
		se_kp_1_f32: 0xc1200000
		se_reset_criteria: 50
		power_zone_count: 1
	}
	power.power_zones[0] = hw.G13PowerZoneConfig{
		target: 30000
		target_offset: 100
		filter_tc: 6875
	}
	power.core_leak_coef_f32[0] = 0x40000000
	power.sram_leak_coef_f32[0] = 0x40000000
	return power
}

fn config_for(abi hw.FirmwareAbi) hw.HwConfig {
	mut cfg := hw.get_config(0x8103) or { panic('no t8103 hardware configuration') }
	mut entries := []hw.OppEntry{}
	for index in 0 .. ladder_hz.len {
		entries << hw.OppEntry{
			frequency_hz: ladder_hz[index]
			voltage_uv: [ladder_uv[index]]
			power_uw: ladder_uw[index]
		}
	}
	assert cfg.apply_opp_table(entries, 790_000, 1)
	cfg.gpu_power_sample_period = 8
	cfg.g13_power = power_config()
	cfg.firmware_abi = abi
	return cfg
}

fn read_u32(bytes []u8, offset u32) u32 {
	index := int(offset)
	return u32(bytes[index]) | (u32(bytes[index + 1]) << 8) | (u32(bytes[index + 2]) << 16) | (u32(bytes[index + 3]) << 24)
}

fn read_u64(bytes []u8, offset u32) u64 {
	return u64(read_u32(bytes, offset)) | (u64(read_u32(bytes, offset + 4)) << 32)
}

fn hwdata_a_for(abi hw.FirmwareAbi) []u8 {
	cfg := config_for(abi)
	mut data := fw.G13HwDataA{}
	assert fw.populate_g13_hwdata_a(mut data, &cfg)
	mut out := []u8{len: data.bytes.len}
	for index in 0 .. data.bytes.len {
		out[index] = data.bytes[index]
	}
	return out
}

fn globals_for(abi hw.FirmwareAbi) []u8 {
	cfg := config_for(abi)
	mut data := fw.G13Globals{}
	assert fw.populate_g13_globals(mut data, &cfg)
	mut out := []u8{len: data.bytes.len}
	for index in 0 .. data.bytes.len {
		out[index] = data.bytes[index]
	}
	return out
}

// A value written through the translation has to appear where the generator
// says it does at each ABI, and nowhere else.
fn check_hwdata_a_translation() {
	old := hwdata_a_for(.v12_3)
	new := hwdata_a_for(.v13_5_partial)

	// pwr_sample_period_aic_clks: 0x004 at 12.3, and 13.5 leaves it there.
	assert read_u32(old, 0x004) == 192000
	assert read_u32(new, 0x004) == 192000

	// 0xc moves to 0x10. Both the source and the destination are checked: a
	// translation that silently did nothing would still satisfy the first.
	assert read_u32(old, 0x00c) == 4
	assert read_u32(new, 0x010) == 4

	// The base pstate scaling at 0x03c moves too.
	moved := fw.g13_hwdata_a_offset(.v13_5_partial, 0x03c) or { 0 }
	assert moved != 0x03c
	assert read_u32(old, 0x03c) == read_u32(new, moved)
}

// 13.5 grows HwDataA by the SE control block, and it is empty at 12.3 because
// the structure has no room for it there.
fn check_se_block() {
	new := hwdata_a_for(.v13_5_partial)
	assert read_u32(new, fw.g13_v13_5_hwdata_a_unk_e10_0_unk_38_offset) == 4
	assert read_u32(new, fw.g13_v13_5_hwdata_a_unk_e10_0_unk_3c_offset) == 8000
	assert read_u32(new, fw.g13_v13_5_hwdata_a_unk_e10_0_gpu_se_inactive_threshold_offset) == 2500
	assert read_u32(new, fw.g13_v13_5_hwdata_a_unk_e10_0_gpu_se_reset_criteria_offset) == 50
	// se_engagement_criteria is -1 on this chip and the field is signed.
	assert read_u32(new, fw.g13_v13_5_hwdata_a_unk_e10_0_gpu_se_engagement_criteria_offset) == 0xffff_ffff
	// Gains are carried as raw IEEE-754 words, never through an FPU.
	assert read_u32(new, fw.g13_v13_5_hwdata_a_unk_e10_0_gpu_se_kp_offset) == 0xc0a00000
	assert read_u32(new, fw.g13_v13_5_hwdata_a_unk_e10_0_gpu_se_kp_1_offset) == 0xc1200000
	// 65536.0f and 8000.0f, derived rather than pasted in.
	assert read_u32(new, fw.g13_v13_5_hwdata_a_unk_e10_0_unk_7c_offset) == 0x47800000
	assert read_u32(new, fw.g13_v13_5_hwdata_a_unk_e10_0_unk_9c_offset) == 0x45fa0000
	assert read_u32(new, fw.g13_v13_5_hwdata_a_unk_e10_0_unk_a0_offset) == 1400
	assert read_u32(new, fw.g13_v13_5_hwdata_a_unk_e10_0_unk_124_offset) == 40
	// se_filter_time_constant 9 and 3, times the 8 ms sample period.
	assert read_u32(new, fw.g13_v13_5_hwdata_a_unk_e10_0_gpu_se_filter_time_constant_ms_offset) == 72
	assert read_u32(new, fw.g13_v13_5_hwdata_a_unk_e10_0_gpu_se_filter_time_constant_1_ms_offset) == 24
	// ... and times clocks_per_period, as a 64-bit pair.
	clks := fw.g13_v13_5_hwdata_a_unk_e10_0_gpu_se_filter_time_constant_clks_offset
	assert read_u32(new, clks) == 9 * 192000
	assert read_u32(new, clks + 4) == 0
}

// 13.5 inserts two fields into the middle of a PowerZone entry, so the filter
// coefficients move within it. Writing them at the 12.3 positions would land on
// the inserted fields.
fn check_power_zone_entry() {
	old := hwdata_a_for(.v12_3)
	new := hwdata_a_for(.v13_5_partial)
	old_base := fw.g13_hwdata_a_offset(.v12_3, 0xc58) or { 0 }
	new_base := fw.g13_hwdata_a_offset(.v13_5_partial, 0xc58) or { 0 }
	old_at := fw.g13_power_zone_offsets(.v12_3) or { panic('no 12.3 zone offsets') }
	new_at := fw.g13_power_zone_offsets(.v13_5_partial) or { panic('no 13.5 zone offsets') }

	assert old_at.stride == 0x20
	assert new_at.stride == 0x28
	assert old_at.filter_a != new_at.filter_a

	assert read_u32(old, old_base + old_at.target) == 30000
	assert read_u32(new, new_base + new_at.target) == 30000
	// target - target_offset.
	assert read_u32(new, new_base + new_at.target_off) == 29900
	// The coefficient follows its member offset, not a fixed one.
	assert read_u32(old, old_base + old_at.filter_a) == read_u32(new, new_base + new_at.filter_a)
	// And the field 13.5 inserts carries m1n1's value.
	assert new_at.has_unk_10
	assert read_u32(new, new_base + new_at.unk_10) == 1320000000
}

// fast_die0_sensor_present exists only at 12.3. At 13.5 the write is skipped,
// so whatever 13.5 put at that offset stays as it is.
fn check_dropped_field() {
	assert !fw.g13_hwdata_a_offset_dropped(.v12_3, 0x1634)
	assert fw.g13_hwdata_a_offset_dropped(.v13_5_partial, 0x1634)
	if _ := fw.g13_hwdata_a_offset(.v13_5_partial, 0x1634) {
		assert false, 'a dropped field must not translate to an offset'
	}
}

fn check_globals() {
	old := globals_for(.v12_3)
	new := globals_for(.v13_5_partial)

	// The nested GlobalsSub writes: 0x5e keeps its position inside sub, 0x66
	// crosses a field 13.5 inserts there.
	assert read_u32(old, 0x5e) == read_u32(new, 0x6e)
	assert read_u32(old, 0x66) == read_u32(new, 0x82)

	// Fields 13.5 adds.
	assert read_u32(new, fw.g13_v13_5_globals_unk_24_0_offset) == 3000
	assert read_u32(new, fw.g13_v13_5_globals_unk_2c_0_offset) == 0
	assert read_u32(new, fw.g13_v13_5_globals_unk_1102c_8_offset) == 100
	assert read_u32(new, fw.g13_v13_5_globals_cl_kill_timeout_ms_offset) == 50

	// The shared-data arrays keep their shape; only the base moves.
	old_hws1 := fw.g13_globals_offset(.v12_3, 0x89f8) or { 0 }
	new_hws1 := fw.g13_globals_offset(.v13_5_partial, 0x89f8) or { 0 }
	assert old_hws1 != new_hws1
	for index in 0 .. 16 {
		assert read_u32(old, old_hws1 + u32(index * 4)) == read_u32(new, new_hws1 + u32(index * 4))
	}
	new_hws2 := fw.g13_globals_offset(.v13_5_partial, 0x8aa0) or { 0 }
	for index in 0 .. 16 {
		assert new[int(new_hws2) + 0x28 + index] == 0xff
	}
}

fn check_hwdata_b() {
	cfg := config_for(.v13_5_partial)
	mut data := fw.G13HwDataBBlob{}
	assert fw.populate_g13_hwdata_b_blob(mut data, &cfg, 0x1234_0000,
		0xffff_ffa0_1100_0000, 0xffff_ffae_1000_0000)
	assert fw.read_g13_hwdata_b_blob_u32(&data, 0x968) or { 0 } == 0x8103
	mut bytes := []u8{len: data.bytes.len}
	for index in 0 .. data.bytes.len {
		bytes[index] = data.bytes[index]
	}
	// HwDataB.timestamp_area_base moves with the expanded YUV table at 13.5,
	// but must still name the aperture used by the runtime timestamp allocator.
	assert read_u64(bytes, 0x28) == 0xffff_ffae_1000_0000
	for index := u32(0); index < 16; index++ {
		assert fw.read_g13_hwdata_b_blob_u32(&data,
			fw.g13_v13_5_hwdata_b_unk_arr_0_offset + index * 4) or { 0xffff_ffff } == index
	}
	assert fw.read_g13_hwdata_b_blob_u32(&data,
		fw.g13_v13_5_hwdata_b_unk_b38_0_offset) or { 0 } == 1
	assert fw.read_g13_hwdata_b_blob_u32(&data,
		fw.g13_v13_5_hwdata_b_unk_b38_4_offset) or { 0 } == 1
	assert fw.read_g13_hwdata_b_blob_u32(&data,
		fw.g13_v13_5_hwdata_b_unk_c3c_offset) or { 0 } == 0x1a
	for index, expected in [u32(0), 3, 7, 7] {
		assert fw.read_g13_hwdata_b_blob_u32(&data, 0x16ec + u32(index * 4)) or {
			0xffff_ffff
		} == expected
	}
	assert fw.set_g13_hwdata_b_io_mapping(mut data, .v13_5_partial, 0,
		fw.G13IoMapping{
			physical_address: 0x1111_2222_3333_4444
			virtual_address: 0x5555_6666_7777_8888
			total_size: 0x9999_aaaa
			element_size: 0xbbbb_cccc
			readwrite: 1
		})
	bytes = []u8{len: data.bytes.len}
	for index in 0 .. data.bytes.len {
		bytes[index] = data.bytes[index]
	}
	base := fw.g13_v13_5_hw_data_b_io_mappings_offset
	assert read_u64(bytes, base) == 0x1111_2222_3333_4444
	assert read_u64(bytes, base + 8) == 0x5555_6666_7777_8888
	assert read_u32(bytes, base + 16) == 0x9999_aaaa
	assert read_u32(bytes, base + 20) == 0xbbbb_cccc
	assert read_u64(bytes, base + 24) == 1
}

fn check_initdata() {
	mut data := fw.G13InitDataBlob{}
	assert fw.build_g13_initdata_blob(mut data, .v13_5_partial, 0x1111_2222_3333_4444,
		0x5555_6666_7777_8888, 0x9999_aaaa_bbbb_cccc, 0xdddd_eeee_ffff_0001, 40)
	mut bytes := []u8{len: data.bytes.len}
	for index in 0 .. data.bytes.len {
		bytes[index] = data.bytes[index]
	}
	assert read_u32(bytes, 0) == 0x1f28_6ba0
	assert read_u32(bytes, 4) == 0x00b0_0601
	assert read_u64(bytes, 8) == 0x1111_2222_3333_4444
	assert read_u64(bytes, 0x18) == 0x5555_6666_7777_8888
	assert read_u64(bytes, 0x20) == 0x9999_aaaa_bbbb_cccc
	assert read_u64(bytes, 0x28) == 0xdddd_eeee_ffff_0001
}

// Nothing outside the two G13 ABIs may build these blobs.
fn check_unsupported_abi_refused() {
	mut cfg := config_for(.v12_3)
	cfg.firmware_abi = .g17_26_5_partial
	mut hwdata := fw.G13HwDataA{}
	assert !fw.populate_g13_hwdata_a(mut hwdata, &cfg)
	mut globals := fw.G13Globals{}
	assert !fw.populate_g13_globals(mut globals, &cfg)
}

fn main() {
	check_hwdata_a_translation()
	check_se_block()
	check_power_zone_entry()
	check_dropped_field()
	check_globals()
	check_hwdata_b()
	check_initdata()
	check_unsupported_abi_refused()
	println('G13 firmware ABI translation tests passed')
}
