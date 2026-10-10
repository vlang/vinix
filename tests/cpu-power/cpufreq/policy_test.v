// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Governors, ranges, the thermal limit and profiles, on the host. policy.v
// beside this file is the kernel's own, linked in.
module cpufreq

// 800 MHz to 4.2 GHz, 3.6 GHz without turbo; nothing set by the user.
fn laptop() Limits {
	return Limits{
		hw_min_khz:   800000
		hw_max_khz:   4200000
		nominal_khz:  3600000
		user_min_khz: 800000
		user_max_khz: 4200000
	}
}

fn test_names_round_trip() {
	for governor in [Governor.performance, .powersave, .ondemand] {
		assert governor_from_name(governor_name(governor))? == governor
	}
	for preference in [Preference.performance, .balance_performance, .balance_power, .power] {
		assert preference_from_name(preference_name(preference))? == preference
	}
	for profile in [Profile.performance, .balanced, .power_saver] {
		assert profile_from_name(profile_name(profile))? == profile
	}
	assert governor_from_name('schedutil')? == Governor.ondemand
	assert profile_from_name('power-saver')? == Profile.power_saver
	if _ := governor_from_name('warp') {
		assert false
	}
	if _ := governor_from_name('') {
		assert false
	}
	if _ := preference_from_name('default') {
		assert false
	}
	if _ := profile_from_name('ludicrous') {
		assert false
	}
}

fn test_profiles() {
	assert profile_governor(.performance) == .performance
	assert profile_preference(.performance) == .performance
	assert profile_governor(.balanced) == .ondemand
	assert profile_preference(.balanced) == .balance_performance
	assert profile_governor(.power_saver) == .ondemand
	assert profile_preference(.power_saver) == .power
}

fn test_user_range_is_kept_inside_the_hardware() {
	limits := laptop()
	assert within_hardware(limits, 0) == 800000
	assert within_hardware(limits, 1) == 800000
	assert within_hardware(limits, 2000000) == 2000000
	assert within_hardware(limits, 99000000) == 4200000
}

fn test_thermal_cap() {
	limits := laptop()
	assert thermal_cap_khz(limits, 100) == 4200000
	assert thermal_cap_khz(limits, 50) == 2100000
	// Never below what the hardware can do, however hot.
	assert thermal_cap_khz(limits, 10) == 800000
	assert thermal_cap_khz(limits, 1) == 800000
	// What limit.v can hand over is 1 to 100; anything else is treated so.
	assert thermal_cap_khz(limits, 0) == 800000
	assert thermal_cap_khz(limits, 250) == 4200000
}

fn test_allowed_range() {
	mut limits := laptop()
	mut lowest, mut highest := allowed_range(limits, 100)
	assert lowest == 800000 && highest == 4200000

	// The user's range.
	limits.user_min_khz = 1200000
	limits.user_max_khz = 3000000
	lowest, highest = allowed_range(limits, 100)
	assert lowest == 1200000 && highest == 3000000

	// The thermal limit is under the user's ceiling: it wins.
	lowest, highest = allowed_range(limits, 50)
	assert lowest == 1200000 && highest == 2100000

	// And over it: it changes nothing.
	lowest, highest = allowed_range(limits, 90)
	assert lowest == 1200000 && highest == 3000000

	// It is under the user's floor too: the floor comes down to it.
	lowest, highest = allowed_range(limits, 25)
	assert lowest == 1050000 && highest == 1050000

	// A floor above the ceiling is brought down to the ceiling.
	limits.user_min_khz = 3500000
	limits.user_max_khz = 2000000
	lowest, highest = allowed_range(limits, 100)
	assert lowest == 2000000 && highest == 2000000
}

fn test_utilisation() {
	assert utilisation_permille(0, 100000000) == 0
	assert utilisation_permille(50000000, 100000000) == 500
	assert utilisation_permille(100000000, 100000000) == 1000
	// The counters are read a moment apart; busier than the wall clock is full.
	assert utilisation_permille(100000005, 100000000) == 1000
	assert utilisation_permille(1, 0) == 0
}

fn test_fixed_governors() {
	for busy in [u32(0), 500, 1000] {
		assert target_khz(.performance, .power, busy, 800000, 4200000) == 4200000
		assert target_khz(.powersave, .performance, busy, 800000, 4200000) == 800000
	}
}

fn test_ondemand_follows_the_load() {
	// With the usual headroom of a quarter, four fifths busy is the top.
	assert target_khz(.ondemand, .balance_performance, 0, 800000, 4200000) == 800000
	assert target_khz(.ondemand, .balance_performance, 100, 800000, 4200000) == 800000
	assert target_khz(.ondemand, .balance_performance, 400, 800000, 4200000) == 2100000
	assert target_khz(.ondemand, .balance_performance, 800, 800000, 4200000) == 4200000
	assert target_khz(.ondemand, .balance_performance, 1000, 800000, 4200000) == 4200000
	// More than full is full.
	assert target_khz(.ondemand, .balance_performance, 5000, 800000, 4200000) == 4200000
	// It never falls as the load rises.
	mut last := u64(0)
	for busy := u32(0); busy <= 1000; busy += 25 {
		now := target_khz(.ondemand, .balance_performance, busy, 800000, 4200000)
		assert now >= last
		last = now
	}
}

fn test_preference_moves_the_headroom() {
	// Half busy.
	assert target_khz(.ondemand, .performance, 500, 800000, 4000000) == 3000000
	assert target_khz(.ondemand, .balance_performance, 500, 800000, 4000000) == 2500000
	assert target_khz(.ondemand, .balance_power, 500, 800000, 4000000) == 2200000
	assert target_khz(.ondemand, .power, 500, 800000, 4000000) == 2000000
	// Only a fully busy CPU reaches the top at `power`.
	assert target_khz(.ondemand, .power, 900, 800000, 4000000) == 3600000
	assert target_khz(.ondemand, .power, 1000, 800000, 4000000) == 4000000
}

fn test_target_stays_under_the_thermal_limit() {
	limits := laptop()
	lowest, highest := allowed_range(limits, 60)
	assert highest == 2520000
	for governor in [Governor.performance, .powersave, .ondemand] {
		for busy in [u32(0), 300, 700, 1000] {
			khz := target_khz(governor, .performance, busy, lowest, highest)
			assert khz >= lowest && khz <= highest
		}
	}
	assert target_khz(.performance, .performance, 1000, lowest, highest) == 2520000
}

fn test_a_range_of_one_frequency() {
	// A machine with no driver: nothing to choose.
	assert target_khz(.ondemand, .balance_performance, 300, 1000000, 1000000) == 1000000
	assert target_khz(.powersave, .power, 300, 0, 0) == 0
}
