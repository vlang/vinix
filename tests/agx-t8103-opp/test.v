// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module main

// Regression fixture for the stock t8103 GPU operating-point table.
//
// m1n1 hands Linux a seven-entry table whose first entry is the off state:
// opp00 is enabled and carries a zero frequency, and calc_power_t8103()
// deliberately computes zero power for it. Both the device-tree loader and the
// G13 HwDataB builder used to reject zero-valued entries, so the standard table
// could not be loaded at all. Neither may drop the entry either, because
// firmware indexes this table directly: perf_state_base, num_pstates and
// max_pstate are all positions in it.
//
// The frequency ladder, cluster count and minimum SRAM voltage below are the
// t8103 values. The per-state voltage and power columns are representative of
// one m1n1 handoff rather than a captured boot; what the test pins is the
// derivation and the state numbering, not those particular microwatts.

import gpu.agx.hw
import gpu.agx.fw

const stock_frequencies_hz = [u64(0), 396_000_000, 528_000_000, 720_000_000, 924_000_000,
	1_128_000_000, 1_278_000_000]
const stock_voltages_uv = [u32(400_000), 612_000, 632_000, 678_000, 756_000, 846_000,
	897_000]
const stock_powers_uw = [u32(0), 1_911_000, 2_478_000, 3_559_000, 5_107_000, 7_000_000,
	8_791_000]
const stock_min_sram_uv = u32(790_000)
const stock_base_pstate = u32(1)

// Values a G13 HwDataB needs but that the performance table does not supply.
const test_uat_ttb_base = u64(0x8000_0000)
const test_unknown_page = u64(0xffff_0000)

fn stock_table() []hw.OppEntry {
	mut entries := []hw.OppEntry{cap: stock_frequencies_hz.len}
	for index in 0 .. stock_frequencies_hz.len {
		entries << hw.OppEntry{
			frequency_hz: stock_frequencies_hz[index]
			voltage_uv: [stock_voltages_uv[index]]
			power_uw: stock_powers_uw[index]
		}
	}
	return entries
}

fn stock_config() hw.HwConfig {
	mut cfg := hw.get_config(0x8103) or { panic('no t8103 hardware configuration') }
	cfg.gpu_power_sample_period = 8
	return cfg
}

fn loaded_config() hw.HwConfig {
	mut cfg := stock_config()
	assert cfg.apply_opp_table(stock_table(), stock_min_sram_uv, stock_base_pstate)
	return cfg
}

fn rejects(entries []hw.OppEntry, min_sram_uv u32, base_pstate u32) bool {
	mut cfg := stock_config()
	return !cfg.apply_opp_table(entries, min_sram_uv, base_pstate)
}

fn check_loaded_table() {
	cfg := loaded_config()

	// State numbering: the off state keeps index 0, so every later state has
	// the same index firmware and the device tree use. A loader that filtered
	// opp00 out would report six states with a base at 528 MHz.
	assert cfg.perf_state_count == 7
	assert cfg.perf_state_base == 1
	assert cfg.perf_state_off_count() == 1
	assert !cfg.perf_state_is_active(0)
	for state := u32(1); state < 7; state++ {
		assert cfg.perf_state_is_active(state)
	}
	assert cfg.perf_state_frequencies[0] == 0
	assert cfg.perf_state_powers[0] == 0
	assert cfg.perf_state_frequencies[1] == 396_000_000
	assert cfg.perf_state_frequencies[6] == 1_278_000_000
	assert cfg.max_power_mw == 8791
	assert cfg.min_sram_microvolt == stock_min_sram_uv
	assert cfg.perf_state_table_count == 1

	// SRAM voltage is the core voltage clamped up to the platform minimum.
	expected_mv := [u32(400), 612, 632, 678, 756, 846, 897]
	expected_sram_mv := [u32(790), 790, 790, 790, 790, 846, 897]
	for state in 0 .. 7 {
		assert cfg.perf_state_voltages[state * 16] == expected_mv[state]
		assert cfg.perf_state_sram_voltages[state * 16] == expected_sram_mv[state]
	}
}

fn check_firmware_table() {
	cfg := loaded_config()
	mut hwdata := fw.G13HwDataB{}
	assert fw.populate_g13_hwdata_b(mut hwdata, &cfg, test_uat_ttb_base, test_unknown_page)

	assert hwdata.num_pstates == 7
	assert hwdata.max_pstate == 6
	assert hwdata.min_sram_voltage_mv == 790
	assert hwdata.uat_ttb_base == test_uat_ttb_base
	assert hwdata.unknown_page == test_unknown_page

	expected_mhz := [u32(0), 396, 528, 720, 924, 1128, 1278]
	expected_rel_power := [u32(0), 21, 28, 40, 58, 79, 100]
	expected_boost := [u32(0), 0, 14, 36, 59, 82, 100]
	expected_mv := [u32(400), 612, 632, 678, 756, 846, 897]
	expected_sram_mv := [u32(790), 790, 790, 790, 790, 846, 897]
	for state in 0 .. 7 {
		assert hwdata.frequencies_mhz[state] == expected_mhz[state]
		assert hwdata.rel_max_powers[state] == expected_rel_power[state]
		assert hwdata.rel_boost_freqs[state] == expected_boost[state]
		assert hwdata.voltages_mv[state][0] == expected_mv[state]
		assert hwdata.sram_voltages_mv[state][0] == expected_sram_mv[state]
		// Columns past the cluster count mirror column 0 on a one-cluster part.
		assert hwdata.voltages_mv[state][7] == expected_mv[state]
		assert hwdata.sram_voltages_mv[state][7] == expected_sram_mv[state]
	}
	// Unused firmware slots stay zero rather than repeating the last state.
	for state in 7 .. 16 {
		assert hwdata.frequencies_mhz[state] == 0
		assert hwdata.rel_max_powers[state] == 0
		assert hwdata.rel_boost_freqs[state] == 0
	}
}

fn check_rejected_tables() {
	// An off state anywhere but index 0 would renumber every state above it.
	mut moved := stock_table()
	moved[3] = hw.OppEntry{
		frequency_hz: 0
		voltage_uv: [u32(678_000)]
		power_uw: 0
	}
	assert rejects(moved, stock_min_sram_uv, stock_base_pstate)

	// An entry that claims both zero frequency and nonzero power is not the
	// off state m1n1 emits, so it is not paraphrased into one.
	mut powered_off := stock_table()
	powered_off[0] = hw.OppEntry{
		frequency_hz: 0
		voltage_uv: [u32(400_000)]
		power_uw: 1000
	}
	assert rejects(powered_off, stock_min_sram_uv, stock_base_pstate)

	// Active states keep the validation they always had.
	mut weak := stock_table()
	weak[2] = hw.OppEntry{
		frequency_hz: 528_000_000
		voltage_uv: [u32(632_000)]
		power_uw: 999
	}
	assert rejects(weak, stock_min_sram_uv, stock_base_pstate)

	mut unordered := stock_table()
	unordered[4] = hw.OppEntry{
		frequency_hz: 700_000_000
		voltage_uv: [u32(756_000)]
		power_uw: 5_107_000
	}
	assert rejects(unordered, stock_min_sram_uv, stock_base_pstate)

	mut low_voltage := stock_table()
	low_voltage[5] = hw.OppEntry{
		frequency_hz: 1_128_000_000
		voltage_uv: [u32(999)]
		power_uw: 7_000_000
	}
	assert rejects(low_voltage, stock_min_sram_uv, stock_base_pstate)

	// One voltage per cluster, still.
	mut wide := stock_table()
	wide[1] = hw.OppEntry{
		frequency_hz: 396_000_000
		voltage_uv: [u32(612_000), 612_000]
		power_uw: 1_911_000
	}
	assert rejects(wide, stock_min_sram_uv, stock_base_pstate)

	// The base pstate must name a state the GPU can run at, and must leave a
	// higher state above it for the boost divisor.
	assert rejects(stock_table(), stock_min_sram_uv, 0)
	assert rejects(stock_table(), stock_min_sram_uv, 6)
	assert rejects(stock_table(), stock_min_sram_uv, 7)

	// A missing apple,min-sram-microvolt is still fatal.
	assert rejects(stock_table(), 0, stock_base_pstate)
}

fn check_rejected_firmware_tables() {
	// Firmware data construction enforces the same rule as the loader.
	mut base_on_off := loaded_config()
	base_on_off.perf_state_base = 0
	mut scratch := fw.G13HwDataB{}
	assert !fw.populate_g13_hwdata_b(mut scratch, &base_on_off, test_uat_ttb_base,
		test_unknown_page)

	mut off_with_power := loaded_config()
	off_with_power.perf_state_powers[0] = 5
	scratch = fw.G13HwDataB{}
	assert !fw.populate_g13_hwdata_b(mut scratch, &off_with_power, test_uat_ttb_base,
		test_unknown_page)

	mut active_without_power := loaded_config()
	active_without_power.perf_state_powers[3] = 0
	scratch = fw.G13HwDataB{}
	assert !fw.populate_g13_hwdata_b(mut scratch, &active_without_power, test_uat_ttb_base,
		test_unknown_page)
}

fn check_table_without_off_state() {
	// Nothing requires an off state; a table of active states only still loads
	// and still numbers its states from zero.
	active_entries := stock_table()[1..]
	mut cfg := stock_config()
	assert cfg.apply_opp_table(active_entries, stock_min_sram_uv, stock_base_pstate)
	assert cfg.perf_state_count == 6
	assert cfg.perf_state_off_count() == 0
	assert cfg.perf_state_is_active(0)
	assert cfg.perf_state_frequencies[0] == 396_000_000

	mut hwdata := fw.G13HwDataB{}
	assert fw.populate_g13_hwdata_b(mut hwdata, &cfg, test_uat_ttb_base, test_unknown_page)
	assert hwdata.num_pstates == 6
	assert hwdata.max_pstate == 5
	assert hwdata.frequencies_mhz[0] == 396
}

fn main() {
	assert fw.validate_g13_hwdata_layouts()
	check_loaded_table()
	check_firmware_table()
	check_rejected_tables()
	check_rejected_firmware_tables()
	check_table_without_off_state()
	println('t8103 operating-point table tests passed')
}
