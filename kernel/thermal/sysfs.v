// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Thermal zones as /sys shows them, in Linux's layout, so that sensors(1), a
// desktop's temperature applet or a script that reads thermal_zone0/temp
// needs nothing written for Vinix:
//
//	/sys/class/thermal/thermal_zoneN/
//	    type temp                     what it is; millidegrees Celsius, read now
//	    mode                          enabled or disabled; root may write either
//	    policy                        step_wise
//	    trip_point_M_type _temp _hyst
//	    read_failures                 Vinix's: readings that failed, ever
//	/sys/class/thermal/cooling_device0/
//	    type max_state cur_state      the limit on CPU performance, in steps
//	/sys/class/thermal/thermal_limit      Vinix's: that limit, in percent
//	/sys/class/thermal/critical_count     Vinix's: critical trips acted on
//	/sys/class/thermal/poll_count         Vinix's: passes of the polling thread
//	/sys/class/hwmon/hwmonN/
//	    name
//	    temp1_input _label _max _crit _crit_alarm    the zone itself
//	    tempM_...                                    its other sensors
//	    fanM_input _label _min _max, pwmM            its fans
//
// A temperature that cannot be read reads as an empty file: there is no number
// that means "no reading", and the last one is not the temperature now.
//
// thermal_zoneN and hwmonN share the zone's place in the table as their N.
// Every file's context is the zone's record or something inside it, which
// unregister_zone() frees only after the files are gone.
module thermal

import cpufreq
import errno
import fs
import katomic
import lib

// `base` `n` `middle` `m` `tail`, a negative number left out. The builder is
// on the stack, as procfs has it: one made as a local value is moved to the
// heap by the compiler and left there.
fn numbered(base string, n int, middle string, m int, tail string) string {
	mut text := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *text = lib.new_text(96) }
	text.add(base)
	if n >= 0 {
		text.add_unsigned(u64(n))
	}
	text.add(middle)
	if m >= 0 {
		text.add_unsigned(u64(m))
	}
	text.add(tail)
	return text.str()
}

// Publish an attribute at `path`, which this frees.
fn attribute(path string, mode u32, show fs.SysfsShow, store fs.SysfsStore, context voidptr) {
	fs.sysfs_attribute(path, mode, show, store, context)
	unsafe { path.free() }
}

fn add_line(mut text lib.Text, value i64) {
	text.add_decimal(value)
	text.add_byte(`\n`)
}

// ── The class ───────────────────────────────────────────────────────────────

fn publish_class() {
	fs.sysfs_directory('class/thermal')
	fs.sysfs_directory('class/hwmon')
	fs.sysfs_text('class/thermal/cooling_device0/type', 'Processor\n')
	fs.sysfs_attribute('class/thermal/cooling_device0/max_state', 0o444, show_max_state,
		unsafe { nil }, unsafe { nil })
	fs.sysfs_attribute('class/thermal/cooling_device0/cur_state', 0o444, show_cur_state,
		unsafe { nil }, unsafe { nil })
	fs.sysfs_attribute('class/thermal/thermal_limit', 0o444, show_thermal_limit, unsafe { nil },
		unsafe { nil })
	fs.sysfs_attribute('class/thermal/critical_count', 0o444, show_critical_count, unsafe { nil },
		unsafe { nil })
	fs.sysfs_attribute('class/thermal/poll_count', 0o444, show_poll_count, unsafe { nil },
		unsafe { nil })
}

fn show_max_state(_ voidptr, mut text lib.Text) {
	add_line(mut text, i64(deepest_state))
}

fn show_cur_state(_ voidptr, mut text lib.Text) {
	add_line(mut text, i64(katomic.load(&thermal_cooling_state)))
}

fn show_thermal_limit(_ voidptr, mut text lib.Text) {
	add_line(mut text, i64(cpufreq.thermal_limit()))
}

fn show_critical_count(_ voidptr, mut text lib.Text) {
	add_line(mut text, i64(katomic.load(&thermal_critical_count)))
}

fn show_poll_count(_ voidptr, mut text lib.Text) {
	add_line(mut text, i64(katomic.load(&thermal_poll_count)))
}

// ── A zone ──────────────────────────────────────────────────────────────────

const zone_base = 'class/thermal/thermal_zone'
const hwmon_base = 'class/hwmon/hwmon'

fn publish_zone(mut record ZoneRecord) {
	if record.published {
		return
	}
	n := record.slot
	context := voidptr(record)
	directory := numbered(zone_base, n, '', -1, '')
	fs.sysfs_directory(directory)
	unsafe { directory.free() }
	attribute(numbered(zone_base, n, '/type', -1, ''), 0o444, show_zone_type, unsafe { nil },
		context)
	attribute(numbered(zone_base, n, '/temp', -1, ''), 0o444, show_zone_temp, unsafe { nil },
		context)
	attribute(numbered(zone_base, n, '/mode', -1, ''), 0o644, show_zone_mode, store_zone_mode,
		context)
	attribute(numbered(zone_base, n, '/policy', -1, ''), 0o444, show_zone_policy, unsafe { nil },
		context)
	attribute(numbered(zone_base, n, '/read_failures', -1, ''), 0o444, show_zone_failures,
		unsafe { nil }, context)
	for m in 0 .. record.zone.trip_count {
		trip := voidptr(unsafe { &record.zone.trips[m] })
		attribute(numbered(zone_base, n, '/trip_point_', m, '_type'), 0o444, show_trip_type,
			unsafe { nil }, trip)
		attribute(numbered(zone_base, n, '/trip_point_', m, '_temp'), 0o444, show_trip_temp,
			unsafe { nil }, trip)
		attribute(numbered(zone_base, n, '/trip_point_', m, '_hyst'), 0o444, show_trip_hyst,
			unsafe { nil }, trip)
	}

	// The hwmon view: the zone's own temperature is temp1.
	attribute(numbered(hwmon_base, n, '/name', -1, ''), 0o444, show_hwmon_name, unsafe { nil },
		context)
	attribute(numbered(hwmon_base, n, '/temp1_input', -1, ''), 0o444, show_zone_temp,
		unsafe { nil }, context)
	if record.zone.label.len != 0 {
		attribute(numbered(hwmon_base, n, '/temp1_label', -1, ''), 0o444, show_zone_label,
			unsafe { nil }, context)
	}
	if record.limits.has_passive {
		attribute(numbered(hwmon_base, n, '/temp1_max', -1, ''), 0o444, show_zone_max,
			unsafe { nil }, context)
	}
	if record.limits.has_critical {
		attribute(numbered(hwmon_base, n, '/temp1_crit', -1, ''), 0o444, show_zone_crit,
			unsafe { nil }, context)
	}
	if record.zone.alarm != unsafe { nil } {
		attribute(numbered(hwmon_base, n, '/temp1_crit_alarm', -1, ''), 0o444, show_zone_alarm,
			unsafe { nil }, context)
	}
	for i in 0 .. record.zone.sensor_count {
		sensor := unsafe { &record.zone.sensors[i] }
		m := i + 2
		attribute(numbered(hwmon_base, n, '/temp', m, '_input'), 0o444, show_sensor_input,
			unsafe { nil }, voidptr(sensor))
		if sensor.label.len != 0 {
			attribute(numbered(hwmon_base, n, '/temp', m, '_label'), 0o444, show_sensor_label,
				unsafe { nil }, voidptr(sensor))
		}
		if sensor.has_maximum {
			attribute(numbered(hwmon_base, n, '/temp', m, '_max'), 0o444, show_sensor_max,
				unsafe { nil }, voidptr(sensor))
		}
		if sensor.has_critical {
			attribute(numbered(hwmon_base, n, '/temp', m, '_crit'), 0o444, show_sensor_crit,
				unsafe { nil }, voidptr(sensor))
		}
		if sensor.alarm != unsafe { nil } {
			attribute(numbered(hwmon_base, n, '/temp', m, '_crit_alarm'), 0o444, show_sensor_alarm,
				unsafe { nil }, voidptr(sensor))
		}
	}
	for i in 0 .. record.zone.fan_count {
		fan := unsafe { &record.zone.fans[i] }
		m := i + 1
		if fan.read_rpm != unsafe { nil } {
			attribute(numbered(hwmon_base, n, '/fan', m, '_input'), 0o444, show_fan_input,
				unsafe { nil }, voidptr(fan))
		}
		if fan.label.len != 0 {
			attribute(numbered(hwmon_base, n, '/fan', m, '_label'), 0o444, show_fan_label,
				unsafe { nil }, voidptr(fan))
		}
		if fan.has_minimum {
			attribute(numbered(hwmon_base, n, '/fan', m, '_min'), 0o444, show_fan_min,
				unsafe { nil }, voidptr(fan))
		}
		if fan.has_maximum {
			attribute(numbered(hwmon_base, n, '/fan', m, '_max'), 0o444, show_fan_max,
				unsafe { nil }, voidptr(fan))
		}
		if fan.set_percent != unsafe { nil } {
			attribute(numbered(hwmon_base, n, '/pwm', m, ''), 0o644, show_fan_pwm, store_fan_pwm,
				voidptr(fan))
		}
	}
	record.published = true
}

// Remove the zone's files. Once this has returned none of them is being read
// or written.
fn unpublish_zone(mut record ZoneRecord) {
	if !record.published {
		return
	}
	zone := numbered(zone_base, record.slot, '', -1, '')
	fs.sysfs_remove(zone)
	hwmon := numbered(hwmon_base, record.slot, '', -1, '')
	fs.sysfs_remove(hwmon)
	unsafe {
		zone.free()
		hwmon.free()
	}
	record.published = false
}

fn show_zone_type(context voidptr, mut text lib.Text) {
	record := unsafe { &ZoneRecord(context) }
	text.add(record.zone.name)
	text.add_byte(`\n`)
}

fn show_hwmon_name(context voidptr, mut text lib.Text) {
	record := unsafe { &ZoneRecord(context) }
	text.add(record.zone.hwmon_name)
	text.add_byte(`\n`)
}

fn show_zone_label(context voidptr, mut text lib.Text) {
	record := unsafe { &ZoneRecord(context) }
	text.add(record.zone.label)
	text.add_byte(`\n`)
}

// The temperature now, read from the sensor rather than remembered.
fn show_zone_temp(context voidptr, mut text lib.Text) {
	record := unsafe { &ZoneRecord(context) }
	if value := record.zone.read(record.zone.context) {
		if value > absolute_zero {
			add_line(mut text, value)
		}
	}
}

fn show_zone_mode(context voidptr, mut text lib.Text) {
	record := unsafe { &ZoneRecord(context) }
	thermal_lock.acquire()
	on := record.enabled && !record.state.faulted
	thermal_lock.release()
	text.add(if on { 'enabled\n' } else { 'disabled\n' })
}

// Switching a zone off stops its readings and leaves the limit where it is;
// switching it on again, which is also how one that failed is brought back,
// starts it afresh.
fn store_zone_mode(context voidptr, data &u8, length u64) u64 {
	mut record := unsafe { &ZoneRecord(context) }
	word := fs.sysfs_word(data, length)
	if word == 'enabled' {
		thermal_lock.acquire()
		record.enabled = true
		record.state = rearm(record.state)
		thermal_lock.release()
		return 0
	}
	if word == 'disabled' {
		thermal_lock.acquire()
		record.enabled = false
		thermal_lock.release()
		return 0
	}
	return errno.einval
}

fn show_zone_policy(_ voidptr, mut text lib.Text) {
	text.add('step_wise\n')
}

fn show_zone_failures(context voidptr, mut text lib.Text) {
	record := unsafe { &ZoneRecord(context) }
	thermal_lock.acquire()
	failed := record.failed_reads
	thermal_lock.release()
	add_line(mut text, i64(failed))
}

fn show_zone_max(context voidptr, mut text lib.Text) {
	record := unsafe { &ZoneRecord(context) }
	add_line(mut text, record.limits.passive)
}

fn show_zone_crit(context voidptr, mut text lib.Text) {
	record := unsafe { &ZoneRecord(context) }
	add_line(mut text, record.limits.critical)
}

fn show_zone_alarm(context voidptr, mut text lib.Text) {
	record := unsafe { &ZoneRecord(context) }
	if raised := record.zone.alarm(record.zone.context) {
		add_line(mut text, if raised { i64(1) } else { i64(0) })
	}
}

fn show_trip_type(context voidptr, mut text lib.Text) {
	trip := unsafe { &Trip(context) }
	text.add(match trip.kind {
		.passive { 'passive\n' }
		.hot { 'hot\n' }
		.critical { 'critical\n' }
	})
}

fn show_trip_temp(context voidptr, mut text lib.Text) {
	trip := unsafe { &Trip(context) }
	add_line(mut text, trip.temperature)
}

fn show_trip_hyst(context voidptr, mut text lib.Text) {
	trip := unsafe { &Trip(context) }
	add_line(mut text, trip.hysteresis)
}

// ── Its other sensors and its fans ──────────────────────────────────────────

fn show_sensor_input(context voidptr, mut text lib.Text) {
	sensor := unsafe { &Sensor(context) }
	if sensor.read == unsafe { nil } {
		return
	}
	if value := sensor.read(sensor.context) {
		if value > absolute_zero {
			add_line(mut text, value)
		}
	}
}

fn show_sensor_label(context voidptr, mut text lib.Text) {
	sensor := unsafe { &Sensor(context) }
	text.add(sensor.label)
	text.add_byte(`\n`)
}

fn show_sensor_max(context voidptr, mut text lib.Text) {
	sensor := unsafe { &Sensor(context) }
	add_line(mut text, sensor.maximum)
}

fn show_sensor_crit(context voidptr, mut text lib.Text) {
	sensor := unsafe { &Sensor(context) }
	add_line(mut text, sensor.critical)
}

fn show_sensor_alarm(context voidptr, mut text lib.Text) {
	sensor := unsafe { &Sensor(context) }
	if raised := sensor.alarm(sensor.context) {
		add_line(mut text, if raised { i64(1) } else { i64(0) })
	}
}

fn show_fan_input(context voidptr, mut text lib.Text) {
	fan := unsafe { &Fan(context) }
	if rpm := fan.read_rpm(fan.context) {
		add_line(mut text, i64(rpm))
	}
}

fn show_fan_label(context voidptr, mut text lib.Text) {
	fan := unsafe { &Fan(context) }
	text.add(fan.label)
	text.add_byte(`\n`)
}

fn show_fan_min(context voidptr, mut text lib.Text) {
	fan := unsafe { &Fan(context) }
	add_line(mut text, i64(fan.minimum))
}

fn show_fan_max(context voidptr, mut text lib.Text) {
	fan := unsafe { &Fan(context) }
	add_line(mut text, i64(fan.maximum))
}

// pwmN is hwmon's 0 to 255; the fan takes percent.
fn show_fan_pwm(context voidptr, mut text lib.Text) {
	fan := unsafe { &Fan(context) }
	if fan.percent_set {
		add_line(mut text, i64((fan.percent * 255 + 50) / 100))
	}
}

fn store_fan_pwm(context voidptr, data &u8, length u64) u64 {
	mut fan := unsafe { &Fan(context) }
	value := fs.sysfs_unsigned(data, length) or { return errno.einval }
	if value > 255 {
		return errno.einval
	}
	percent := u32((value * 100 + 127) / 255)
	if !fan.set_percent(fan.context, percent) {
		return errno.eio
	}
	fan.percent = percent
	fan.percent_set = true
	return 0
}
