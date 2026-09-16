// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module hw

// Firmware performance-state derivation, shared by every boot-data path.
//
// The firmware indexes this table directly: perf_state_base, num_pstates and
// max_pstate are all positions in it, so a state may never be dropped or
// renumbered on the way in. That matters because a stock t8103 table begins
// with an *off* state. Asahi's device tree enables opp00 with a zero frequency
// and zero power, and m1n1's calc_power_t8103() deliberately computes zero
// power for it, so rejecting zero-valued entries rejects the standard table.
// Off states are therefore represented rather than filtered, while every
// active state stays under the same strict validation as before.

// Firmware capacity: 16 performance states, each row holding 16 voltage
// columns. Consumers with a narrower row (G13 HwDataB stores 8) enforce that
// themselves; the shared table always uses the wider stride.
pub const perf_state_capacity = u32(16)
pub const perf_state_columns = u32(16)

// One operating point exactly as a boot device tree carries it: hertz,
// microvolts per cluster, and microwatts.
pub struct OppEntry {
pub:
	frequency_hz u64
	voltage_uv   []u32
	power_uw     u32
}

// True when the state drives the GPU. Index 0 of a stock t8103 table is the
// off state and reports zero frequency and zero power to firmware.
pub fn (cfg &HwConfig) perf_state_is_active(state u32) bool {
	return state < cfg.perf_state_count && cfg.perf_state_frequencies[state] != 0
}

// Number of leading off states, which is 0 or 1 for every table Vinix accepts.
pub fn (cfg &HwConfig) perf_state_off_count() u32 {
	if cfg.perf_state_count == 0 || cfg.perf_state_frequencies[0] != 0 {
		return 0
	}
	return 1
}

// Build the firmware performance-state table from an operating-points list.
//
// Only index 0 may be an off state, and an off state must report zero power:
// anything else is a table this driver has not seen and will not paraphrase
// for firmware. Every remaining state must be active, strictly increasing in
// frequency, and carry one voltage per cluster. base_state must name an active
// state that leaves at least one higher state above it, because the boost
// divisor firmware wants is (max_frequency - base_frequency) / 100.
pub fn (mut cfg HwConfig) apply_opp_table(entries []OppEntry, min_sram_microvolt u32,
	base_state u32) bool {
	count := u32(entries.len)
	if count < 2 || count > perf_state_capacity {
		println('agx: unusable operating-point count ${count}')
		return false
	}
	if min_sram_microvolt < 1000 {
		println('agx: invalid minimum SRAM voltage ${min_sram_microvolt} uV')
		return false
	}
	if cfg.num_clusters == 0 || cfg.num_clusters > perf_state_columns {
		println('agx: unusable cluster count ${cfg.num_clusters}')
		return false
	}
	min_sram_mv := min_sram_microvolt / 1000

	mut frequencies := [16]u32{}
	mut powers := [16]u32{}
	mut voltages := [256]u32{}
	mut sram_voltages := [256]u32{}
	mut max_power_mw := u32(0)
	for state := u32(0); state < count; state++ {
		entry := entries[state]
		if u32(entry.voltage_uv.len) != cfg.num_clusters {
			println('agx: operating point ${state} has ${entry.voltage_uv.len} voltages for ${cfg.num_clusters} clusters')
			return false
		}
		if entry.frequency_hz == 0 {
			// The off state exists so that firmware state 1 keeps index 1.
			if state != 0 {
				println('agx: operating point ${state} is off but is not the first state')
				return false
			}
			if entry.power_uw != 0 {
				println('agx: off operating point reports ${entry.power_uw} uW')
				return false
			}
		} else {
			if entry.frequency_hz > 0xffff_ffff || entry.power_uw < 1000 {
				println('agx: operating point ${state} has an out-of-range frequency or power')
				return false
			}
			if state > 0 && u32(entry.frequency_hz) <= frequencies[state - 1] {
				println('agx: operating point ${state} is not frequency ordered')
				return false
			}
		}
		frequencies[state] = u32(entry.frequency_hz)
		powers[state] = entry.power_uw / 1000
		if powers[state] > max_power_mw {
			max_power_mw = powers[state]
		}
		for cluster := u32(0); cluster < cfg.num_clusters; cluster++ {
			if entry.voltage_uv[cluster] < 1000 {
				println('agx: operating point ${state} cluster ${cluster} has an invalid voltage')
				return false
			}
			voltage_mv := entry.voltage_uv[cluster] / 1000
			destination := state * perf_state_columns + cluster
			voltages[destination] = voltage_mv
			sram_voltages[destination] = if voltage_mv > min_sram_mv {
				voltage_mv
			} else {
				min_sram_mv
			}
		}
	}
	if max_power_mw == 0 {
		println('agx: operating-point table reports no power at any state')
		return false
	}
	if base_state + 1 >= count || frequencies[base_state] == 0 {
		println('agx: base performance state ${base_state} is not an active state below ${count}')
		return false
	}

	cfg.perf_state_count = count
	cfg.perf_state_base = base_state
	cfg.perf_state_table_count = cfg.num_clusters
	cfg.perf_state_frequencies = frequencies
	cfg.perf_state_powers = powers
	cfg.perf_state_voltages = voltages
	cfg.perf_state_sram_voltages = sram_voltages
	cfg.max_power_mw = max_power_mw
	cfg.min_sram_microvolt = min_sram_microvolt
	return true
}
