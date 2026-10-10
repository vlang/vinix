// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// A zone whose temperature is whatever is written to it, for testing the
// policy on a machine that has no sensor or cannot be heated: QEMU. Only in a
// kernel built with -d thermal_selftest.
//
//	/sys/class/thermal/thermal_zoneN/emul_temp
//	    Linux's name. Write millidegrees Celsius, or `error` -- or anything
//	    below absolute zero -- for a sensor that fails every reading.
//	/sys/class/thermal/selftest_zone
//	    1 while the zone is registered. Write 0 to unregister it and 1 to
//	    register it again.
//
// The zone is `vinix_selftest`: passive at 80 C, hot at 95 C, critical at
// 105 C. It carries a second sensor five degrees below the first and a fan
// that runs at whatever it is set to, so that the hwmon files have something
// behind them too.
@[has_globals]
module thermal

import devcore
import errno
import fs
import katomic
import lib

__global (
	thermal_selftest_handle      u64
	thermal_selftest_temperature i64
	thermal_selftest_failing     u32
	thermal_selftest_fan_percent u32
	// selftest_zone is being written.
	thermal_selftest_changing u32
)

fn selftest_read(_ voidptr) ?i64 {
	if katomic.load(&thermal_selftest_failing) != 0 {
		return none
	}
	return thermal_selftest_temperature
}

fn selftest_read_second(_ voidptr) ?i64 {
	if katomic.load(&thermal_selftest_failing) != 0 {
		return none
	}
	return thermal_selftest_temperature - 5000
}

fn selftest_alarm(_ voidptr) ?bool {
	if katomic.load(&thermal_selftest_failing) != 0 {
		return none
	}
	return thermal_selftest_temperature >= 105000
}

fn selftest_fan_rpm(_ voidptr) ?u64 {
	return u64(katomic.load(&thermal_selftest_fan_percent)) * 30
}

fn selftest_fan_set(_ voidptr, percent u32) bool {
	if percent > 100 {
		return false
	}
	katomic.store(mut &thermal_selftest_fan_percent, percent)
	return true
}

fn selftest_register() bool {
	if thermal_selftest_handle != 0 {
		return true
	}
	mut second := Sensor{
		label:        'Selftest second'
		read:         selftest_read_second
		context:      unsafe { nil }
		has_maximum:  true
		maximum:      80000
		has_critical: true
		critical:     105000
	}
	mut fan := Fan{
		label:       'Selftest fan'
		read_rpm:    selftest_fan_rpm
		set_percent: selftest_fan_set
		context:     unsafe { nil }
	}
	mut zone := Zone{
		name:         'vinix_selftest'
		label:        'Selftest'
		read:         selftest_read
		alarm:        selftest_alarm
		context:      unsafe { nil }
		sensors:      unsafe { &second }
		sensor_count: 1
		fans:         unsafe { &fan }
		fan_count:    1
	}
	zone.add_trip(.passive, 80000, 5000)
	zone.add_trip(.hot, 95000, 2000)
	zone.add_trip(.critical, 105000, 2000)
	handle := register_zone(zone)
	if handle == 0 {
		return false
	}
	thermal_selftest_handle = handle
	// The zone's directory is there: register_zone() published it.
	thermal_lock.acquire()
	mut slot := -1
	for i in 0 .. max_zones {
		if thermal_zones[i] != unsafe { nil } && thermal_zones[i].handle == handle {
			slot = i
		}
	}
	thermal_lock.release()
	if slot >= 0 {
		attribute(numbered(zone_base, slot, '/emul_temp', -1, ''), 0o200, unsafe { nil },
			store_emul_temp, unsafe { nil })
	}
	return true
}

fn selftest_start() {
	thermal_selftest_temperature = 40000
	katomic.store(mut &thermal_selftest_failing, u32(0))
	fs.sysfs_attribute('class/thermal/selftest_zone', 0o644, show_selftest_zone, store_selftest_zone,
		unsafe { nil })
	if selftest_fake_kind() != fake_none {
		fs.sysfs_attribute('class/thermal/x86_fake_temp', 0o200, unsafe { nil }, store_fake_temp,
			unsafe { nil })
	}
	if !selftest_register() {
		C.kprintf(c'thermal: the self-test zone could not be registered\n')
	}
}

fn store_emul_temp(_ voidptr, data &u8, length u64) u64 {
	word := fs.sysfs_word(data, length)
	if word == 'error' {
		katomic.store(mut &thermal_selftest_failing, u32(1))
		return 0
	}
	value := parse_signed(word) or { return errno.einval }
	if value <= absolute_zero {
		katomic.store(mut &thermal_selftest_failing, u32(1))
		return 0
	}
	thermal_selftest_temperature = value
	katomic.store(mut &thermal_selftest_failing, u32(0))
	return 0
}

fn show_selftest_zone(_ voidptr, mut text lib.Text) {
	text.add(if thermal_selftest_handle != 0 { '1\n' } else { '0\n' })
}

// This file is not one of the zone's, so removing the zone from here is not a
// file removing itself. One writer at a time: two would each register a zone
// and leave one of them with no handle to take it away by.
fn store_selftest_zone(_ voidptr, data &u8, length u64) u64 {
	value := fs.sysfs_unsigned(data, length) or { return errno.einval }
	if value > 1 {
		return errno.einval
	}
	if !katomic.cas(mut &thermal_selftest_changing, u32(0), u32(1)) {
		return errno.ebusy
	}
	mut result := u64(0)
	if value == 0 {
		handle := thermal_selftest_handle
		if handle != 0 {
			thermal_selftest_handle = 0
			unregister_zone(handle)
		}
	} else if !selftest_register() {
		result = u64(errno.enomem)
	}
	katomic.store(mut &thermal_selftest_changing, u32(0))
	return result
}

// ── A processor's sensors, made up ──────────────────────────────────────────
//
// QEMU's processors have no temperature sensor and no energy counter, so the
// x86-64 drivers would never run under it. vinix.thermal_fake=intel or =amd
// on the command line gives them registers to read: the drivers ask here
// before they ask the processor, and find a Sky Lake with a package sensor,
// a sensor in each core and RAPL counters, or a Ryzen 7 2700X with Tctl, two
// die sensors and its package counter. Everything above the instruction that
// reads a register is then the code a real machine runs, including the
// interrupt that takes a read to the core it is of.
//
//	/sys/class/thermal/x86_fake_temp
//	    The made-up package's temperature. Write millidegrees Celsius, or
//	    `critical` and `normal` for the processor's own critical status bit.
//
// The package starts at 45 C; each core is three degrees below it and a
// degree below the core before. The package counter starts just short of
// wrapping and counts 15 W; the core counter counts 10 W.
//
// Kept in plain numbers, with no x86 type in sight: this file is also built
// for arm64, where nothing calls it.

__global (
	thermal_fake_parsed      u32
	thermal_fake_kind        u32
	thermal_fake_temperature i64
	thermal_fake_critical    u32
	thermal_fake_start       u64
)

const fake_none = u32(0)
const fake_intel = u32(1)
const fake_amd = u32(2)

// What selftest_fake_msr() says of a register.
const fake_not_mine = u32(0)
const fake_read = u32(1)
const fake_absent = u32(2)

const fake_tjmax = i64(100000)

// Which processor is made up, if any.
fn selftest_fake_kind() u32 {
	if katomic.load(&thermal_fake_parsed) == 0 {
		mut kind := fake_none
		if word := devcore.boot_option('vinix.thermal_fake=') {
			if word == 'intel' {
				kind = fake_intel
			} else if word == 'amd' {
				kind = fake_amd
			}
		}
		thermal_fake_kind = kind
		thermal_fake_temperature = 45000
		thermal_fake_start = devcore.now_ns()
		katomic.store(mut &thermal_fake_parsed, u32(1))
	}
	return thermal_fake_kind
}

// A counter that started at `first` and has counted `rate` a second since.
fn selftest_fake_counter(first u64, rate u64) u64 {
	microseconds := (devcore.now_ns() - thermal_fake_start) / 1000
	return (first + microseconds * rate / 1000000) & 0xffffffff
}

// An Intel status register for `temperature`.
fn selftest_fake_status(temperature i64, critical bool) u64 {
	mut below := (fake_tjmax - temperature) / 1000
	if below < 0 {
		below = 0
	}
	if below > 127 {
		below = 127
	}
	mut status := (u64(1) << 31) | (u64(below) << 16)
	if critical {
		status |= 0x30
	}
	return status
}

// Model-specific register `index` of the made-up processor, as its CPU
// `cpu_number` reads it.
fn selftest_fake_msr(cpu_number u64, index u32, value &u64) u32 {
	kind := selftest_fake_kind()
	temperature := thermal_fake_temperature
	critical := katomic.load(&thermal_fake_critical) != 0
	mut found := u64(0)
	if kind == fake_intel {
		match index {
			// IA32_THERM_STATUS, IA32_PACKAGE_THERM_STATUS.
			0x19c { found = selftest_fake_status(temperature - 3000 - i64(cpu_number) * 1000, false) }
			0x1b1 { found = selftest_fake_status(temperature, critical) }
			// IA32_TEMPERATURE_TARGET: TjMax 100 C, the fans' target 15 below.
			0x1a2 { found = (u64(100) << 16) | (u64(15) << 8) }
			// The unit register: 2^-14 J a count.
			0x606 { found = 0x000a0e03 }
			// Package: 15 W. Cores: 10 W. Graphics: there, and never used.
			0x611 { found = selftest_fake_counter(0xfffe0000, 245760) }
			0x639 { found = selftest_fake_counter(0x1000, 163840) }
			0x641 { found = 0 }
			// No memory counter, and none of what TjMax is guessed from.
			0x619, 0x17, 0xee { return fake_absent }
			else { return fake_not_mine }
		}
	} else if kind == fake_amd {
		match index {
			// 2^-16 J a count, and 15 W of them.
			0xc0010299 { found = 0x000a1003 }
			0xc001029b { found = selftest_fake_counter(0xfffe0000, 983040) }
			else { return fake_not_mine }
		}
	} else {
		return fake_not_mine
	}
	unsafe {
		*value = found
	}
	return fake_read
}

// A register behind the made-up AMD host bridge's SMN index. False for one
// that is not there.
fn selftest_fake_smn(address u32, value &u32) bool {
	temperature := thermal_fake_temperature
	mut found := u32(0)
	if address == 0x59800 {
		// Tctl, in eighths of a degree from bit 21.
		found = u32(temperature / 125) << 21
	} else if address == 0x59954 || address == 0x59958 {
		// Two dies, four and five degrees below it: valid, and eighths of a
		// degree above -49 C.
		die := i64((address - 0x59954) / 4)
		found = (u32(1) << 11) | u32((temperature - 4000 - die * 1000 + 49000) / 125)
	}
	unsafe {
		*value = found
	}
	return true
}

fn store_fake_temp(_ voidptr, data &u8, length u64) u64 {
	word := fs.sysfs_word(data, length)
	if word == 'critical' {
		katomic.store(mut &thermal_fake_critical, u32(1))
		return 0
	}
	if word == 'normal' {
		katomic.store(mut &thermal_fake_critical, u32(0))
		return 0
	}
	value := parse_signed(word) or { return errno.einval }
	if value < 0 || value > 200000 {
		return errno.einval
	}
	thermal_fake_temperature = value
	return 0
}
