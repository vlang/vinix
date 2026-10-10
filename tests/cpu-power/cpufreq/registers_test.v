// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// What the x86 frequency drivers put in their registers, on the host.
// registers.v beside this file is the kernel's registers_amd64.v.
module cpufreq

// IA32_HWP_CAPABILITIES of a Skylake laptop: lowest 1, most efficient 8,
// guaranteed 28, highest 42.
const skylake_caps = u64(0x01081c2a)

fn test_hwp_capabilities() {
	caps := hwp_caps(skylake_caps)
	assert caps.highest == 42
	assert caps.guaranteed == 28
	assert caps.most_efficient == 8
	assert caps.lowest == 1
}

fn test_levels_round_away_from_the_limit() {
	assert level_at_most(4200000, khz_per_level) == 42
	assert level_at_most(4199999, khz_per_level) == 41
	assert level_at_least(800000, khz_per_level) == 8
	assert level_at_least(800001, khz_per_level) == 9
	// A performance core of a hybrid processor.
	assert level_at_most(4500000, khz_per_level_hybrid_p) == 57
	assert level_at_least(4500000, khz_per_level_hybrid_p) == 58
	assert level_at_most(999999999, khz_per_level) == 255
	assert level_at_most(4200000, 0) == 0
}

fn test_epp_values_are_linux_s() {
	// HWP_EPP_* in msr-index.h.
	assert intel_epp(.performance) == 0x00
	assert intel_epp(.balance_performance) == 0x80
	assert intel_epp(.balance_power) == 0xc0
	assert intel_epp(.power) == 0xff
	// AMD_CPPC_EPP_* in amd-pstate.h: balance_power differs.
	assert amd_epp(.performance) == 0x00
	assert amd_epp(.balance_performance) == 0x80
	assert amd_epp(.balance_power) == 0xbf
	assert amd_epp(.power) == 0xff
}

fn test_hwp_plan_ondemand_leaves_the_processor_its_range() {
	caps := hwp_caps(skylake_caps)
	plan := hwp_plan(.ondemand, .balance_performance, caps, khz_per_level, 100000, 4200000)
	assert plan.lowest == 1
	assert plan.highest == 42
	assert plan.desired == 0
	assert plan.preference == 0x80
	assert hwp_plan(.ondemand, .power, caps, khz_per_level, 100000, 4200000).preference == 0xff
}

fn test_hwp_plan_performance_raises_the_floor() {
	// intel_pstate_hwp_set(): min = max and EPP 0 under the performance policy.
	caps := hwp_caps(skylake_caps)
	plan := hwp_plan(.performance, .power, caps, khz_per_level, 100000, 4200000)
	assert plan.lowest == 42 && plan.highest == 42
	assert plan.preference == 0
}

fn test_hwp_plan_powersave_lowers_the_ceiling() {
	caps := hwp_caps(skylake_caps)
	plan := hwp_plan(.powersave, .performance, caps, khz_per_level, 800000, 4200000)
	assert plan.lowest == 8 && plan.highest == 8
	assert plan.preference == 0xff
}

fn test_hwp_plan_keeps_to_the_allowed_range() {
	caps := hwp_caps(skylake_caps)
	// A thermal limit of 2.1 GHz and a user floor of 1.25 GHz.
	plan := hwp_plan(.ondemand, .balance_performance, caps, khz_per_level, 1250000, 2100000)
	assert plan.lowest == 13
	assert plan.highest == 21
	// The ceiling is never above what was allowed, even by rounding.
	assert hwp_plan(.performance, .performance, caps, khz_per_level, 0, 2199999).highest == 21
	// And never outside what the processor has.
	wide := hwp_plan(.ondemand, .performance, caps, khz_per_level, 0, 9000000)
	assert wide.lowest == 1 && wide.highest == 42
	low := hwp_plan(.ondemand, .performance, caps, khz_per_level, 0, 50000)
	assert low.lowest == 1 && low.highest == 1
}

fn test_hwp_request_encoding() {
	request := PerfRequest{
		lowest:     8
		highest:    42
		desired:    0
		preference: 0x80
	}
	assert hwp_request(0, request, true) == 0x80002a08
	// Without the preference feature that byte is left as it was found.
	assert hwp_request(0x33000000, request, false) == 0x33002a08
	// The activity window (bits 41:32) is kept; package control (bit 42) and
	// the old range are not.
	found := u64(0x000004a5_ff11ff01)
	assert hwp_request(found, request, true) == u64(0x000000a5_80002a08)
	// Only the low byte of each field is ever written.
	wild := PerfRequest{
		lowest:     0x108
		highest:    0x12a
		desired:    0x100
		preference: 0x180
	}
	assert hwp_request(0, wild, true) == 0x80002a08
}

fn test_hwp_request_decoding() {
	fields := hwp_request_fields(0x80152a08)
	assert fields.lowest == 8
	assert fields.highest == 42
	assert fields.desired == 0x15
	assert fields.preference == 0x80
	// Round trip.
	plan := hwp_plan(.ondemand, .balance_power, hwp_caps(skylake_caps), khz_per_level,
		1200000, 3000000)
	back := hwp_request_fields(hwp_request(0, plan, true))
	assert back.lowest == plan.lowest && back.highest == plan.highest
	assert back.desired == 0 && back.preference == 0xc0
}

fn test_speedstep_models_are_intel_pstate_s() {
	for model in [u32(0x2a), 0x2d, 0x3a, 0x3c, 0x3d, 0x3e, 0x3f, 0x45, 0x46, 0x47, 0x4e, 0x4f,
		0x55, 0x56, 0x5c, 0x5e, 0x6a, 0x7a, 0x8d, 0x8f, 0xa5] {
		assert speedstep_model(model)
	}
	// Nehalem predates the list; Silvermont and Airmont are on it with
	// registers of their own, which are not driven; QEMU's model is 6.
	for model in [u32(0x1e), 0x25, 0x37, 0x4c, 0x06, 0x97] {
		assert !speedstep_model(model)
	}
}

// MSR_PLATFORM_INFO of a Haswell i7-4770: lowest ratio 8, nominal 34.
const haswell_platform_info = u64(0x0000_0800_0000_2200)

// MSR_TURBO_RATIO_LIMIT: 39 with one core active.
const haswell_turbo_limit = u64(0x25262727)

fn test_speedstep_ratios() {
	s := speedstep(haswell_platform_info, haswell_turbo_limit, 0, true)
	assert s.lowest == 8
	assert s.nominal == 34
	assert s.turbo == 39
	assert !s.turbo_disabled
	assert speedstep_highest(s) == 39
}

fn test_speedstep_turbo_switched_off() {
	// turbo_is_disabled(): no IDA in CPUID, or IA32_MISC_ENABLE[38].
	by_firmware := speedstep(haswell_platform_info, haswell_turbo_limit, misc_enable_turbo_disable,
		true)
	assert by_firmware.turbo_disabled
	assert speedstep_highest(by_firmware) == 34
	no_turbo := speedstep(haswell_platform_info, haswell_turbo_limit, 0, false)
	assert no_turbo.turbo_disabled
	assert speedstep_highest(no_turbo) == 34
	// core_get_turbo_pstate(): a turbo ratio below the nominal is the nominal.
	odd := speedstep(haswell_platform_info, 0x10, 0, true)
	assert odd.turbo == 34
}

fn test_speedstep_ratio_for_a_target() {
	s := speedstep(haswell_platform_info, haswell_turbo_limit, 0, true)
	assert speedstep_ratio(s, 3900000, 3900000) == 39
	assert speedstep_ratio(s, 2000000, 3900000) == 20
	assert speedstep_ratio(s, 2000001, 3900000) == 21
	// Clamped to what the processor has.
	assert speedstep_ratio(s, 100000, 3900000) == 8
	assert speedstep_ratio(s, 9000000, 9000000) == 39
	// And to the allowed ceiling: a thermal limit of 60 %.
	assert speedstep_ratio(s, 3900000, 2340000) == 23
	off := speedstep(haswell_platform_info, haswell_turbo_limit, misc_enable_turbo_disable,
		true)
	assert speedstep_ratio(off, 3900000, 3900000) == 34
}

fn test_perf_ctl_encoding() {
	s := speedstep(haswell_platform_info, haswell_turbo_limit, 0, true)
	// core_get_val(): the ratio in bits 15:8.
	assert perf_ctl(s, 39, 3900000) == 0x2700
	assert perf_ctl(s, 20, 3900000) == 0x1400
	// The ceiling is at or under the nominal ratio and the processor has
	// turbo: bit 32 holds it back, as for intel_pstate's no_turbo.
	assert perf_ctl(s, 34, 3400000) == u64(0x1_0000_2200)
	assert perf_ctl(s, 23, 2340000) == u64(0x1_0000_1700)
	// With turbo already off there is nothing to hold back.
	off := speedstep(haswell_platform_info, haswell_turbo_limit, misc_enable_turbo_disable,
		true)
	assert perf_ctl(off, 34, 3400000) == 0x2200
	assert perf_status_ratio(0x0000_1a2b_0000_2200) == 34
}

// MSR_AMD_CPPC_CAP1 of a Zen 3: lowest 13, lowest nonlinear 56, nominal 119,
// highest 166.
const zen_caps = u64(0xa677380d)

fn test_cppc_capabilities() {
	caps := cppc_caps(zen_caps)
	assert caps.lowest == 13
	assert caps.lowest_nonlinear == 56
	assert caps.nominal == 119
	assert caps.highest == 166
	// The nominal level is the nominal frequency: 3.4 GHz here.
	assert cppc_khz(caps, 3400000, 119) == 3400000
	assert cppc_khz(caps, 3400000, 166) == 4742857
	assert cppc_khz(caps, 3400000, 13) == 371428
	assert cppc_khz(CppcCaps{}, 3400000, 100) == 0
}

fn test_cppc_plan() {
	caps := cppc_caps(zen_caps)
	highest := cppc_khz(caps, 3400000, caps.highest)
	lowest := cppc_khz(caps, 3400000, caps.lowest)
	auto := cppc_plan(.ondemand, .balance_performance, caps, 3400000, lowest, highest)
	// The whole range comes back as the whole range of levels.
	assert auto.lowest == 13 && auto.highest == 166
	assert auto.desired == 0 && auto.preference == 0x80
	// amd_pstate_epp_update_limit(): the floor is the nominal level under
	// the performance policy, and the preference 0.
	fast := cppc_plan(.performance, .power, caps, 3400000, lowest, highest)
	assert fast.lowest == 119 && fast.highest == 166 && fast.preference == 0
	// Unless the ceiling is lower than that.
	capped := cppc_plan(.performance, .power, caps, 3400000, lowest, 2000000)
	assert capped.highest == 70 && capped.lowest == 70
	slow := cppc_plan(.powersave, .performance, caps, 3400000, lowest, highest)
	assert slow.lowest == 13 && slow.highest == 13 && slow.preference == 0xff
	// Nothing to scale by: the hardware's own range, untouched.
	blind := cppc_plan(.ondemand, .power, caps, 0, 0, 0)
	assert blind.lowest == 13 && blind.highest == 166
}

fn test_cppc_request_encoding() {
	// AMD_CPPC_MAX_PERF is the low byte, MIN_PERF the next: the reverse of
	// Intel's register.
	request := PerfRequest{
		lowest:     13
		highest:    166
		desired:    0
		preference: 0x80
	}
	assert cppc_request(0, request) == 0x80000da6
	assert cppc_request(u64(0xdead_beef_1234_5678), request) == u64(0xdead_beef_8000_0da6)
	held := PerfRequest{
		lowest:     119
		highest:    166
		desired:    140
		preference: 0
	}
	assert cppc_request(0, held) == 0x008c77a6
}

fn test_effective_frequency() {
	// Ran at the base frequency throughout.
	assert effective_khz(1000000, 1000000, 3400000) == 3400000
	// Half of it, and a quarter above it.
	assert effective_khz(500000, 1000000, 3400000) == 1700000
	assert effective_khz(1250000, 1000000, 3400000) == 4250000
	// Did not run: nothing to say.
	assert effective_khz(0, 0, 3400000) == 0
	// A long interval: the counts are scaled down, not overflowed.
	big := u64(1) << 50
	assert effective_khz(big, big, 3400000) == 3400000
	assert effective_khz(big / 2, big, 3400000) == 1700000
}
