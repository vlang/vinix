// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Where the parts of power management meet.
//
// Thermal management knows a temperature is past what the machine survives,
// the power supplies know the charger was pulled, the frequency drivers know
// how to trade speed for heat and battery life. None of them knows about the
// others. The two decisions that need more than one of them are made here:
//
//   - a critical temperature turns the machine off, the way the power button
//     does when nobody is listening: storage flushed, devices stopped. Heat
//     is not something to ask a desktop's opinion on, so init is not asked.
//   - going onto the battery selects the power-saving performance profile,
//     and going back onto the charger the balanced one -- unless
//     /sys/power/profile_policy says `manual`, for a user who has chosen a
//     profile and wants it left alone.
@[has_globals]
module syspower

import cpufreq
import katomic
import psupply
import thermal

__global (
	// 0 follows the power source, 1 leaves the profile alone.
	syspower_profile_manual u32
	syspower_thermal_shutdowns u64
)

fn thermal_critical(zone string, millicelsius i64) {
	katomic.inc(mut &syspower_thermal_shutdowns)
	C.kprintf(c'syspower: %.*s is at %lld.%lld C, past its critical point; powering off\n',
		i32(zone.len), zone.str, millicelsius / 1000, (millicelsius % 1000) / 100)
	// From a thread of its own: this one is thermal management's, and is not
	// coming back from a successful power-off.
	transition(.power_off)
}

fn power_source_changed(on_battery bool) {
	if katomic.load(&syspower_profile_manual) != 0 {
		return
	}
	cpufreq.set_profile(if on_battery { cpufreq.Profile.power_saver } else { cpufreq.Profile.balanced })
}

pub fn profile_follows_source() bool {
	return katomic.load(&syspower_profile_manual) == 0
}

pub fn set_profile_follows_source(follow bool) {
	katomic.store(mut &syspower_profile_manual, if follow { u32(0) } else { u32(1) })
	if follow {
		power_source_changed(psupply.on_battery())
	}
}

// Connect the policies. Called from start().
fn connect_policies() {
	thermal.set_critical_handler(thermal_critical)
	psupply.on_source_change(power_source_changed)
}
