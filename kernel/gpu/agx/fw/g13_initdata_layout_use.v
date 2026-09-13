// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module fw

import gpu.agx.hw

// Address the G13 InitData blobs at whichever firmware ABI is in play.
//
// The builders in this directory were written against 12.3 and address their
// structures by bare offsets. 13.5 moves nearly all of them -- 143 of the 144
// they write -- so rather than a second set of literals, each write is
// translated through the field it addresses. The tables come from
// g13_initdata_layout.v, which is generated from m1n1's versioned firmware
// structures and checked against the 12.3 layout this tree already had.
//
// A translation that is not in the table is a write the generator never saw,
// which means the two have drifted: fail rather than write to a 12.3 offset in
// a 13.5 structure.

pub fn g13_initdata_abi_supported(abi hw.FirmwareAbi) bool {
	return abi == .v12_3 || abi == .v13_5_partial
}

// True when a 12.3 write has no destination at the selected ABI, because the
// field it addresses does not exist there. The write is skipped.
fn g13_offset_dropped(dropped []u32, abi hw.FirmwareAbi, offset u32) bool {
	if abi != .v13_5_partial {
		return false
	}
	for entry in dropped {
		if entry == offset {
			return true
		}
	}
	return false
}

pub fn g13_hwdata_a_offset_dropped(abi hw.FirmwareAbi, offset u32) bool {
	return g13_offset_dropped(g13_hwdata_a_offsets_dropped_v13_5, abi, offset)
}

pub fn g13_globals_offset_dropped(abi hw.FirmwareAbi, offset u32) bool {
	return g13_offset_dropped(g13_globals_offsets_dropped_v13_5, abi, offset)
}

fn g13_translate_offset(offsets_v12_3 []u32, offsets_v13_5 []u32, abi hw.FirmwareAbi,
	offset u32) ?u32 {
	if abi == .v12_3 {
		return offset
	}
	if abi != .v13_5_partial {
		return none
	}
	for index := 0; index < offsets_v12_3.len; index++ {
		if offsets_v12_3[index] == offset {
			return offsets_v13_5[index]
		}
	}
	return none
}

pub fn g13_hwdata_a_offset(abi hw.FirmwareAbi, offset u32) ?u32 {
	return g13_translate_offset(g13_hwdata_a_offsets_v12_3[..], g13_hwdata_a_offsets_v13_5[..],
		abi, offset)
}

pub fn g13_globals_offset(abi hw.FirmwareAbi, offset u32) ?u32 {
	return g13_translate_offset(g13_globals_offsets_v12_3[..], g13_globals_offsets_v13_5[..],
		abi, offset)
}

// The published size of each blob. The buffers are allocated at the larger
// 13.5 size; this is how much of one firmware is told to read.
pub fn g13_hwdata_a_active_size(abi hw.FirmwareAbi) ?u64 {
	return match abi {
		.v12_3 { g13_v12_3_hw_data_a_size }
		.v13_5_partial { g13_v13_5_hw_data_a_size }
		else { none }
	}
}

pub fn g13_globals_active_size(abi hw.FirmwareAbi) ?u64 {
	return match abi {
		.v12_3 { g13_v12_3_globals_size }
		.v13_5_partial { g13_v13_5_globals_size }
		else { none }
	}
}

pub fn g13_hwdata_b_active_size(abi hw.FirmwareAbi) ?u64 {
	return match abi {
		.v12_3 { g13_v12_3_hw_data_b_size }
		.v13_5_partial { g13_v13_5_hw_data_b_size }
		else { none }
	}
}

pub fn g13_active_io_mapping_count(abi hw.FirmwareAbi) ?u32 {
	return match abi {
		.v12_3 { g13_v12_3_io_mapping_count }
		.v13_5_partial { g13_v13_5_io_mapping_count }
		else { none }
	}
}

// The generated 12.3 column has to agree with the sizes the rest of this
// directory was built around, or the translation tables describe a different
// structure than the builders write into.
pub fn validate_g13_initdata_layout_tables() bool {
	return g13_v12_3_hw_data_a_size == g13_hwdata_a_size
		&& g13_v12_3_hw_data_b_size == g13_hwdata_b_size
		&& g13_v12_3_globals_size == g13_globals_size
		&& g13_v12_3_io_mapping_count == u32(g13_io_mapping_count)
		&& g13_hwdata_a_offsets_v12_3.len == g13_hwdata_a_offsets_v13_5.len
		&& g13_globals_offsets_v12_3.len == g13_globals_offsets_v13_5.len
}

// Where each PowerZone member sits, for the ABI in play. 13.5 inserts unk_10
// and unk_14 between filter_tc_xperiod and the filter coefficients, so the two
// coefficients move within the entry and the entry itself grows.
pub struct G13PowerZoneOffsets {
pub:
	stride            u32
	target            u32
	target_off        u32
	filter_tc_x4      u32
	filter_tc_xperiod u32
	filter_a_neg      u32
	filter_a          u32
	// 13.5 only. has_unk_10 is false at 12.3, where the field does not exist.
	unk_10     u32
	has_unk_10 bool
}

pub fn g13_power_zone_offsets(abi hw.FirmwareAbi) ?G13PowerZoneOffsets {
	match abi {
		.v12_3 {
			return G13PowerZoneOffsets{
				stride: u32(g13_v12_3_power_zone_size)
				target: g13_v12_3_power_zone_target_offset
				target_off: g13_v12_3_power_zone_target_off_offset
				filter_tc_x4: g13_v12_3_power_zone_filter_tc_x4_offset
				filter_tc_xperiod: g13_v12_3_power_zone_filter_tc_xperiod_offset
				filter_a_neg: g13_v12_3_power_zone_filter_a_neg_offset
				filter_a: g13_v12_3_power_zone_filter_a_offset
			}
		}
		.v13_5_partial {
			return G13PowerZoneOffsets{
				stride: u32(g13_v13_5_power_zone_size)
				target: g13_v13_5_power_zone_target_offset
				target_off: g13_v13_5_power_zone_target_off_offset
				filter_tc_x4: g13_v13_5_power_zone_filter_tc_x4_offset
				filter_tc_xperiod: g13_v13_5_power_zone_filter_tc_xperiod_offset
				filter_a_neg: g13_v13_5_power_zone_filter_a_neg_offset
				filter_a: g13_v13_5_power_zone_filter_a_offset
				unk_10: g13_v13_5_power_zone_unk_10_offset
				has_unk_10: true
			}
		}
		else {
			return none
		}
	}
}
