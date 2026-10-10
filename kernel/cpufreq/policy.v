// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// How fast a CPU should run: the decisions, apart from the machine.
//
// A policy is what is wanted of a CPU, or of the CPUs that share a clock:
// the range the hardware has, the narrower range the user allows, a governor
// that says where in the range to be, and a preference between performance
// and energy for hardware that chooses for itself. On top of the user's range
// comes the thermal limit (limit.v), which nothing here may exceed.
//
// The governors are Linux's by name and meaning:
//
//	performance   the top of the allowed range
//	powersave     the bottom of it
//	ondemand      as much as the load asks for: the busy share of the last
//	              interval, with headroom, as a share of the top
//
// and a profile is one word for the whole machine -- performance, balanced,
// power_saver -- that sets the governor and preference of every policy; it is
// what power management will set when the machine goes onto battery.
//
// Everything in this file is a function of plain values, with no kernel
// imports, so tests/cpu-power runs it on the host.
module cpufreq

pub enum Governor {
	performance
	powersave
	ondemand
}

pub fn governor_name(governor Governor) string {
	return match governor {
		.performance { 'performance' }
		.powersave { 'powersave' }
		.ondemand { 'ondemand' }
	}
}

pub fn governor_from_name(name string) ?Governor {
	if name == 'performance' {
		return Governor.performance
	}
	if name == 'powersave' {
		return Governor.powersave
	}
	// schedutil is what Linux calls its load-following governor now, and what
	// a script written for Linux is likely to write.
	if name == 'ondemand' || name == 'schedutil' {
		return Governor.ondemand
	}
	return none
}

// Linux's energy_performance_preference, without its "default".
pub enum Preference {
	performance
	balance_performance
	balance_power
	power
}

pub fn preference_name(preference Preference) string {
	return match preference {
		.performance { 'performance' }
		.balance_performance { 'balance_performance' }
		.balance_power { 'balance_power' }
		.power { 'power' }
	}
}

pub fn preference_from_name(name string) ?Preference {
	if name == 'performance' {
		return Preference.performance
	}
	if name == 'balance_performance' {
		return Preference.balance_performance
	}
	if name == 'balance_power' {
		return Preference.balance_power
	}
	if name == 'power' {
		return Preference.power
	}
	return none
}

// How far above the measured load the ondemand governor aims, in percent of
// it. 125 is what intel_pstate and schedutil use: a CPU four fifths busy is
// asked for its top frequency. The preference moves that point, since on
// hardware with no preference of its own this is all it can mean: at
// `performance` a CPU two thirds busy is already at the top, at `power` only
// one that is fully busy.
pub fn headroom_percent(preference Preference) u64 {
	return match preference {
		.performance { u64(150) }
		.balance_performance { u64(125) }
		.balance_power { u64(110) }
		.power { u64(100) }
	}
}

pub enum Profile {
	performance
	balanced
	power_saver
}

pub fn profile_name(profile Profile) string {
	return match profile {
		.performance { 'performance' }
		.balanced { 'balanced' }
		.power_saver { 'power_saver' }
	}
}

pub fn profile_from_name(name string) ?Profile {
	if name == 'performance' {
		return Profile.performance
	}
	if name == 'balanced' {
		return Profile.balanced
	}
	// With a hyphen as power-profiles-daemon spells it.
	if name == 'power_saver' || name == 'power-saver' {
		return Profile.power_saver
	}
	return none
}

pub fn profile_governor(profile Profile) Governor {
	return match profile {
		.performance { Governor.performance }
		.balanced { Governor.ondemand }
		.power_saver { Governor.ondemand }
	}
}

pub fn profile_preference(profile Profile) Preference {
	return match profile {
		.performance { Preference.performance }
		.balanced { Preference.balance_performance }
		.power_saver { Preference.power }
	}
}

// A policy's frequencies, in kHz as /sys gives them.
pub struct Limits {
pub mut:
	// What the hardware can do, and where it runs without turbo. All zero
	// when nothing says.
	hw_min_khz  u64
	hw_max_khz  u64
	nominal_khz u64
	// What scaling_min_freq and scaling_max_freq were last told, kept within
	// the hardware's range.
	user_min_khz u64
	user_max_khz u64
}

// `value` as a scaling_min_freq or scaling_max_freq: brought inside what the
// hardware can do, as Linux brings it, rather than refused.
pub fn within_hardware(limits Limits, value u64) u64 {
	if value < limits.hw_min_khz {
		return limits.hw_min_khz
	}
	if value > limits.hw_max_khz {
		return limits.hw_max_khz
	}
	return value
}

// The most the thermal limit allows: `percent` of the top frequency, but
// never less than the hardware's lowest, which cannot be gone below.
pub fn thermal_cap_khz(limits Limits, percent u32) u64 {
	share := if percent == 0 {
		u64(1)
	} else if percent > 100 {
		u64(100)
	} else {
		u64(percent)
	}
	cap := limits.hw_max_khz * share / 100
	return if cap < limits.hw_min_khz { limits.hw_min_khz } else { cap }
}

// The range in force: the user's, under the thermal limit. When the two
// disagree the ceiling wins and the floor comes down to it, as Linux's
// cpufreq_verify_within_limits() has it.
pub fn allowed_range(limits Limits, thermal_percent u32) (u64, u64) {
	cap := thermal_cap_khz(limits, thermal_percent)
	mut highest := within_hardware(limits, limits.user_max_khz)
	if highest > cap {
		highest = cap
	}
	mut lowest := within_hardware(limits, limits.user_min_khz)
	if lowest > highest {
		lowest = highest
	}
	return lowest, highest
}

// How busy a CPU was: `busy_ns` of `wall_ns`, in thousandths.
pub fn utilisation_permille(busy_ns u64, wall_ns u64) u32 {
	if wall_ns == 0 {
		return 0
	}
	if busy_ns >= wall_ns {
		return 1000
	}
	return u32(busy_ns * 1000 / wall_ns)
}

// The frequency a governor asks for within `lowest`..`highest`, for a CPU
// that was `utilisation` thousandths busy.
pub fn target_khz(governor Governor, preference Preference, utilisation u32, lowest u64, highest u64) u64 {
	if highest <= lowest {
		return highest
	}
	match governor {
		.performance {
			return highest
		}
		.powersave {
			return lowest
		}
		.ondemand {
			busy := if utilisation > 1000 { u64(1000) } else { u64(utilisation) }
			wanted := highest * busy * headroom_percent(preference) / 100000
			if wanted < lowest {
				return lowest
			}
			if wanted > highest {
				return highest
			}
			return wanted
		}
	}
}
