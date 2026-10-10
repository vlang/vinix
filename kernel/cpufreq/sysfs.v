// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The frequency policies as /sys shows them, in Linux's layout and units, so
// that cpupower, powertop, a desktop's power applet or `cat` find what they
// look for:
//
//	/sys/devices/system/cpu/cpuN/cpufreq/
//	    scaling_driver
//	    scaling_governor scaling_available_governors
//	    scaling_min_freq scaling_max_freq      the range in force, kHz
//	    scaling_cur_freq                       what the CPU runs at now
//	    cpuinfo_min_freq cpuinfo_max_freq      what the hardware can do
//	    energy_performance_preference
//	    energy_performance_available_preferences
//	/sys/devices/system/cpu/cpufreq/           Vinix's own
//	    thermal_limit      percent of top performance thermal management allows
//	    profile            performance, balanced or power_saver, for all CPUs
//
// Without a driver the same files are there and say what is true: driver
// "none", one governor, a frequency that does not change -- 0, and
// "<unknown>" for the current one as Linux prints it, where the machine gives
// no way to learn it. Nothing can be written then: the files are read-only and
// a write fails with EPERM instead of appearing to work. With a driver a
// write that names no governor or is not a number is EINVAL, and a frequency
// outside the hardware's range is brought inside it, as on Linux.
module cpufreq

import errno
import fs
import lib

fn show_driver(_ voidptr, mut text lib.Text) {
	text.add(cpufreq_driver.name)
	text.add_byte(`\n`)
}

fn show_governor(context voidptr, mut text lib.Text) {
	policy, _ := policy_for(u64(context))
	if policy != unsafe { nil } {
		text.add(governor_name(policy.governor))
	}
	text.add_byte(`\n`)
}

fn show_available_governors(_ voidptr, mut text lib.Text) {
	if cpufreq_driver.settable {
		text.add('performance powersave ondemand\n')
	} else {
		text.add('performance\n')
	}
}

fn show_min(context voidptr, mut text lib.Text) {
	policy, _ := policy_for(u64(context))
	if policy != unsafe { nil } {
		lowest, _ := allowed_range(policy.limits, thermal_limit())
		text.add_unsigned(lowest)
	}
	text.add_byte(`\n`)
}

fn show_max(context voidptr, mut text lib.Text) {
	policy, _ := policy_for(u64(context))
	if policy != unsafe { nil } {
		_, highest := allowed_range(policy.limits, thermal_limit())
		text.add_unsigned(highest)
	}
	text.add_byte(`\n`)
}

fn show_hardware_min(context voidptr, mut text lib.Text) {
	policy, _ := policy_for(u64(context))
	if policy != unsafe { nil } {
		text.add_unsigned(policy.limits.hw_min_khz)
	}
	text.add_byte(`\n`)
}

fn show_hardware_max(context voidptr, mut text lib.Text) {
	policy, _ := policy_for(u64(context))
	if policy != unsafe { nil } {
		text.add_unsigned(policy.limits.hw_max_khz)
	}
	text.add_byte(`\n`)
}

fn show_current(context voidptr, mut text lib.Text) {
	policy, index := policy_for(u64(context))
	mut khz := u64(0)
	if policy != unsafe { nil } {
		if cpufreq_driver.current != unsafe { nil } {
			khz = cpufreq_driver.current(index, policy)
		}
		if khz == 0 && !cpufreq_driver.settable {
			// A CPU nothing sets runs at its one frequency.
			khz = policy.limits.nominal_khz
		}
	}
	if khz == 0 {
		text.add('<unknown>\n')
		return
	}
	text.add_unsigned(khz)
	text.add_byte(`\n`)
}

fn show_preference(context voidptr, mut text lib.Text) {
	policy, _ := policy_for(u64(context))
	if policy == unsafe { nil } || !cpufreq_driver.has_preference {
		text.add('default\n')
		return
	}
	text.add(preference_name(policy.preference))
	text.add_byte(`\n`)
}

fn show_available_preferences(_ voidptr, mut text lib.Text) {
	if cpufreq_driver.has_preference {
		text.add('performance balance_performance balance_power power\n')
	} else {
		text.add('default\n')
	}
}

fn show_thermal_limit(_ voidptr, mut text lib.Text) {
	text.add_unsigned(thermal_limit())
	text.add_byte(`\n`)
}

fn show_profile(_ voidptr, mut text lib.Text) {
	text.add(profile_name(profile()))
	text.add_byte(`\n`)
}

// Change one policy under the lock and put it into effect. `change` returns
// 0 or the errno the write fails with.
fn store_policy(context voidptr, data &u8, length u64, change fn (mut policy Policy, word string) u64) u64 {
	if !cpufreq_driver.settable {
		return errno.eperm
	}
	word := fs.sysfs_word(data, length)
	cpufreq_lock.acquire()
	mut policy, index := policy_for(u64(context))
	mut code := u64(errno.enodev)
	if policy != unsafe { nil } {
		code = change(mut policy, word)
		if code == 0 {
			apply_policy(index, mut policy)
		}
	}
	cpufreq_lock.release()
	return code
}

fn change_governor(mut policy Policy, word string) u64 {
	policy.governor = governor_from_name(word) or { return errno.einval }
	return 0
}

fn store_governor(context voidptr, data &u8, length u64) u64 {
	return store_policy(context, data, length, change_governor)
}

// A decimal number of kHz, or none.
fn frequency(word string) ?u64 {
	return fs.sysfs_unsigned(word.str, u64(word.len))
}

fn change_min(mut policy Policy, word string) u64 {
	value := frequency(word) or { return errno.einval }
	policy.limits.user_min_khz = within_hardware(policy.limits, value)
	return 0
}

fn store_min(context voidptr, data &u8, length u64) u64 {
	return store_policy(context, data, length, change_min)
}

fn change_max(mut policy Policy, word string) u64 {
	value := frequency(word) or { return errno.einval }
	policy.limits.user_max_khz = within_hardware(policy.limits, value)
	return 0
}

fn store_max(context voidptr, data &u8, length u64) u64 {
	return store_policy(context, data, length, change_max)
}

fn change_preference(mut policy Policy, word string) u64 {
	wanted := preference_from_name(word) or { return errno.einval }
	// As intel_pstate refuses it: under the performance governor the
	// hardware is told "performance" whatever is written here, so taking
	// anything else would be a lie.
	if policy.governor == .performance && wanted != .performance {
		return errno.ebusy
	}
	policy.preference = wanted
	return 0
}

fn store_preference(context voidptr, data &u8, length u64) u64 {
	if !cpufreq_driver.has_preference {
		return errno.eopnotsupp
	}
	return store_policy(context, data, length, change_preference)
}

fn store_profile(_ voidptr, data &u8, length u64) u64 {
	wanted := profile_from_name(fs.sysfs_word(data, length)) or { return errno.einval }
	if !set_profile(wanted) {
		return errno.enodev
	}
	return 0
}

// `prefix`, `cpu_number` in decimal, `name`: a path built on the stack, as
// every path in /sys is.
fn cpu_path(cpu_number int, name string) string {
	mut text := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *text = lib.new_text(name.len + 48) }
	text.add('devices/system/cpu/cpu')
	text.add_unsigned(u64(cpu_number))
	text.add('/cpufreq/')
	text.add(name)
	return text.str()
}

fn publish_file(cpu_number int, name string, show fs.SysfsShow, store fs.SysfsStore) {
	path := cpu_path(cpu_number, name)
	// A file that cannot be written says so in its mode, and has nobody to
	// take a write: /sys answers one with EPERM.
	if store != unsafe { nil } && cpufreq_driver.settable {
		fs.sysfs_attribute(path, 0o644, show, store, voidptr(u64(cpu_number)))
	} else {
		fs.sysfs_attribute(path, 0o444, show, unsafe { nil }, voidptr(u64(cpu_number)))
	}
	unsafe { path.free() }
}

// Find the machine's frequency control, start keeping to the policies, and
// show them. Called once /sys is mounted.
pub fn publish() {
	start()
	for cpu_number in 0 .. max_cpus {
		if cpufreq_policy_of[cpu_number] == 0 {
			continue
		}
		publish_file(cpu_number, 'scaling_driver', show_driver, unsafe { nil })
		publish_file(cpu_number, 'scaling_governor', show_governor, store_governor)
		publish_file(cpu_number, 'scaling_available_governors', show_available_governors,
			unsafe { nil })
		publish_file(cpu_number, 'scaling_min_freq', show_min, store_min)
		publish_file(cpu_number, 'scaling_max_freq', show_max, store_max)
		publish_file(cpu_number, 'scaling_cur_freq', show_current, unsafe { nil })
		publish_file(cpu_number, 'cpuinfo_min_freq', show_hardware_min, unsafe { nil })
		publish_file(cpu_number, 'cpuinfo_max_freq', show_hardware_max, unsafe { nil })
		if cpufreq_driver.has_preference {
			publish_file(cpu_number, 'energy_performance_preference', show_preference,
				store_preference)
		} else {
			publish_file(cpu_number, 'energy_performance_preference', show_preference,
				unsafe { nil })
		}
		publish_file(cpu_number, 'energy_performance_available_preferences', show_available_preferences,
			unsafe { nil })
	}
	fs.sysfs_attribute('devices/system/cpu/cpufreq/thermal_limit', 0o444, show_thermal_limit,
		unsafe { nil }, unsafe { nil })
	if cpufreq_driver.settable {
		fs.sysfs_attribute('devices/system/cpu/cpufreq/profile', 0o644, show_profile,
			store_profile, unsafe { nil })
	} else {
		fs.sysfs_attribute('devices/system/cpu/cpufreq/profile', 0o444, show_profile,
			unsafe { nil }, unsafe { nil })
	}
}
