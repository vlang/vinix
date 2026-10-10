// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// How much of each CPU's performance may be used, as decided by something
// other than the load: thermal management lowering it when the machine runs
// hot, and raising it again when it has cooled.
//
// This is the one thing the thermal code and the frequency drivers share, and
// it is kept apart from both so that neither needs the other to be present: a
// machine with sensors and no frequency control still reports temperatures,
// and one with frequency control and no sensors runs unlimited.
@[has_globals]
module cpufreq

import katomic

__global (
	// 1..100: the share of top performance allowed. Zero until first set,
	// which reads as 100.
	cpufreq_thermal_percent u32
	// Counts changes, so that a driver's worker notices one without a lock.
	cpufreq_limit_generation u64
)

// Allow `percent` of top performance, 1 to 100. Called by thermal management
// from its own thread; the frequency driver applies it on its next pass.
pub fn set_thermal_limit(percent u32) {
	value := if percent == 0 {
		u32(1)
	} else if percent > 100 {
		u32(100)
	} else {
		percent
	}
	if katomic.load(&cpufreq_thermal_percent) == value {
		return
	}
	katomic.store(mut &cpufreq_thermal_percent, value)
	katomic.inc(mut &cpufreq_limit_generation)
}

pub fn thermal_limit() u32 {
	value := katomic.load(&cpufreq_thermal_percent)
	return if value == 0 { u32(100) } else { value }
}

pub fn limit_generation() u64 {
	return katomic.load(&cpufreq_limit_generation)
}
