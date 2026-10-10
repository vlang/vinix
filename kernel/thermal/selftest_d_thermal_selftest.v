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

import errno
import fs
import katomic
import lib

__global (
	thermal_selftest_handle      u64
	thermal_selftest_temperature i64
	thermal_selftest_failing     u32
	thermal_selftest_fan_percent u32
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
// file removing itself.
fn store_selftest_zone(_ voidptr, data &u8, length u64) u64 {
	value := fs.sysfs_unsigned(data, length) or { return errno.einval }
	if value == 0 {
		handle := thermal_selftest_handle
		if handle != 0 {
			thermal_selftest_handle = 0
			unregister_zone(handle)
		}
		return 0
	}
	if value == 1 {
		return if selftest_register() { u64(0) } else { u64(errno.enomem) }
	}
	return errno.einval
}
