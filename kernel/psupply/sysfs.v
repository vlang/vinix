// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Power supplies as /sys shows them: /sys/class/power_supply/<name>/ with the
// files and units Linux has, so that a battery applet, upower or `acpi` reads
// a Vinix machine the way it reads any other.
//
//	type                   Battery or Mains
//	online                 a charger: 1 when supplying power
//	present status         a battery: 1; Charging, Discharging, Full...
//	capacity               percent of what it holds when full
//	capacity_level         Critical Low Normal High Full
//	energy_now energy_full energy_full_design power_now      µWh, µW
//	charge_now charge_full charge_full_design current_now    µAh, µA
//	voltage_now voltage_min_design                           µV
//	time_to_empty_now time_to_full_now                       seconds
//	cycle_count technology model_name manufacturer serial_number
//	charge_control_end_threshold   percent; writable where the hardware can
//	uevent                 the same as POWER_SUPPLY_NAME=value lines
//
// A battery reports energy or charge, not both, and only the files for the
// one it reports exist. Reading any of them reads the battery again if what
// is known is more than a second old.
//
// The thresholds the kernel acts on are in /sys/class/power_supply/policy/.
module psupply

import errno
import fs
import lib

enum Attribute {
	kind
	online
	present
	status
	capacity
	capacity_level
	amount_now
	amount_full
	amount_design
	rate_now
	voltage_now
	voltage_design
	time_to_empty
	time_to_full
	cycle_count
	technology
	model_name
	manufacturer
	serial_number
	charge_limit
	uevent
}

const attribute_count = 21

// What a file's context points at: which supply, and which of its files.
struct AttributeRef {
mut:
	supply    &Supply = unsafe { nil }
	attribute Attribute
}

fn status_name(status Status) string {
	return match status {
		.unknown { 'Unknown' }
		.charging { 'Charging' }
		.discharging { 'Discharging' }
		.not_charging { 'Not charging' }
		.full { 'Full' }
	}
}

fn level_name(level Level) string {
	return match level {
		.unknown { 'Unknown' }
		.critical { 'Critical' }
		.low { 'Low' }
		.normal { 'Normal' }
		.high { 'High' }
		.full { 'Full' }
	}
}

// The name of an attribute's file. The amounts and the rate are called by
// what the battery counts in.
fn file_name(attribute Attribute, in_charge bool) string {
	return match attribute {
		.kind { 'type' }
		.online { 'online' }
		.present { 'present' }
		.status { 'status' }
		.capacity { 'capacity' }
		.capacity_level { 'capacity_level' }
		.amount_now { if in_charge { 'charge_now' } else { 'energy_now' } }
		.amount_full { if in_charge { 'charge_full' } else { 'energy_full' } }
		.amount_design { if in_charge { 'charge_full_design' } else { 'energy_full_design' } }
		.rate_now { if in_charge { 'current_now' } else { 'power_now' } }
		.voltage_now { 'voltage_now' }
		.voltage_design { 'voltage_min_design' }
		.time_to_empty { 'time_to_empty_now' }
		.time_to_full { 'time_to_full_now' }
		.cycle_count { 'cycle_count' }
		.technology { 'technology' }
		.model_name { 'model_name' }
		.manufacturer { 'manufacturer' }
		.serial_number { 'serial_number' }
		.charge_limit { 'charge_control_end_threshold' }
		.uevent { 'uevent' }
	}
}

// Whether a supply of this kind has the file at all.
fn applies(attribute Attribute, supply &Supply) bool {
	if attribute == .kind || attribute == .uevent {
		return true
	}
	if supply.kind == .mains {
		return attribute == .online
	}
	if attribute == .online {
		return false
	}
	if attribute == .charge_limit {
		return supply.set_charge_limit != unsafe { nil } || supply.reading.charge_limit != 0
	}
	return true
}

fn supply_path(supply &Supply, file string) string {
	mut text := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *text = lib.new_text(64) }
	text.add('class/power_supply/')
	text.add(supply.name)
	if file.len != 0 {
		text.add_byte(`/`)
		text.add(file)
	}
	return text.str()
}

fn publish_supply(mut supply Supply) {
	for index in 0 .. attribute_count {
		attribute := unsafe { Attribute(index) }
		supply.refs[index].supply = unsafe { supply }
		supply.refs[index].attribute = attribute
		if !applies(attribute, supply) {
			continue
		}
		path := supply_path(supply, file_name(attribute, supply.reading.in_charge))
		writable := attribute == .charge_limit && supply.set_charge_limit != unsafe { nil }
		if writable {
			fs.sysfs_attribute(path, 0o644, show_attribute, store_charge_limit, voidptr(&supply.refs[index]))
		} else {
			fs.sysfs_attribute(path, 0o444, show_attribute, unsafe { nil }, voidptr(&supply.refs[index]))
		}
		unsafe { path.free() }
	}
}

fn unpublish_supply(mut supply Supply) {
	if !psupply_published {
		return
	}
	path := supply_path(supply, '')
	fs.sysfs_remove(path)
	unsafe { path.free() }
}

// Publish what is registered, and from now on what registers. Called once
// /sys is mounted.
pub fn publish() {
	if psupply_published {
		return
	}
	gate()
	psupply_published = true
	fs.sysfs_directory('class/power_supply')
	fs.sysfs_attribute('class/power_supply/policy/low_percent', 0o644, show_low, store_low,
		unsafe { nil })
	fs.sysfs_attribute('class/power_supply/policy/critical_percent', 0o644, show_critical,
		store_critical, unsafe { nil })
	fs.sysfs_attribute('class/power_supply/policy/on_battery', 0o444, show_on_battery, unsafe { nil },
		unsafe { nil })
	for i in 0 .. max_supplies {
		mut supply := unsafe { &psupply_table[i] }
		if supply.used {
			publish_supply(mut supply)
		}
	}
}

fn add_bytes(mut text lib.Text, bytes &u8, length int) {
	for i in 0 .. length {
		text.add_byte(unsafe { bytes[i] })
	}
}

// One value, without its newline; uevent uses the same text.
fn add_value(mut text lib.Text, supply &Supply, attribute Attribute) {
	reading := &supply.reading
	match attribute {
		.kind { text.add(if supply.kind == .battery { 'Battery' } else { 'Mains' }) }
		.online { text.add_unsigned(if reading.online { u64(1) } else { u64(0) }) }
		.present { text.add_unsigned(if reading.present { u64(1) } else { u64(0) }) }
		.status {
			// A supply that could not be read just now is not known to be
			// doing what it was doing when it last could.
			text.add(status_name(if supply.read_ok { reading.status } else { Status.unknown }))
		}
		.capacity { text.add_decimal(i64(if supply.percent < 0 { 0 } else { supply.percent })) }
		.capacity_level {
			text.add(level_name(level_of(supply.percent, reading.status, psupply_policy.low_percent,
				psupply_policy.critical_percent)))
		}
		.amount_now { text.add_unsigned(reading.amount) }
		.amount_full { text.add_unsigned(reading.full) }
		.amount_design { text.add_unsigned(reading.design) }
		.rate_now {
			// The battery's own figure when it gives one; the smoothed one
			// when the rate had to be derived.
			text.add_unsigned(if reading.rate != 0 { reading.rate } else { supply.estimator.rate })
		}
		.voltage_now { text.add_unsigned(reading.voltage_uv) }
		.voltage_design { text.add_unsigned(reading.design_voltage_uv) }
		.time_to_empty { text.add_unsigned(supply.to_empty) }
		.time_to_full { text.add_unsigned(supply.to_full) }
		.cycle_count { text.add_unsigned(reading.cycles) }
		.technology { add_bytes(mut text, &reading.technology[0], reading.technology_len) }
		.model_name { add_bytes(mut text, &reading.model[0], reading.model_len) }
		.manufacturer { add_bytes(mut text, &reading.maker[0], reading.maker_len) }
		.serial_number { add_bytes(mut text, &reading.serial[0], reading.serial_len) }
		.charge_limit { text.add_unsigned(if reading.charge_limit == 0 { u64(100) } else { reading.charge_limit }) }
		.uevent {}
	}
}

// Linux's name for an attribute in uevent: POWER_SUPPLY_ and the file name in
// capitals.
fn add_uevent_line(mut text lib.Text, supply &Supply, attribute Attribute) {
	name := file_name(attribute, supply.reading.in_charge)
	text.add('POWER_SUPPLY_')
	for i in 0 .. name.len {
		c := name[i]
		text.add_byte(if c >= `a` && c <= `z` { c - 32 } else { c })
	}
	text.add_byte(`=`)
	add_value(mut text, supply, attribute)
	text.add_byte(`\n`)
}

fn show_attribute(context voidptr, mut text lib.Text) {
	reference := unsafe { &AttributeRef(context) }
	mut supply := reference.supply
	refresh(mut supply, false)
	if reference.attribute != .uevent {
		add_value(mut text, supply, reference.attribute)
		text.add_byte(`\n`)
		return
	}
	text.add('POWER_SUPPLY_NAME=')
	text.add(supply.name)
	text.add_byte(`\n`)
	for index in 0 .. attribute_count {
		attribute := unsafe { Attribute(index) }
		if attribute != .uevent && applies(attribute, supply) {
			add_uevent_line(mut text, supply, attribute)
		}
	}
}

fn store_charge_limit(context voidptr, data &u8, length u64) u64 {
	reference := unsafe { &AttributeRef(context) }
	mut supply := reference.supply
	percent := fs.sysfs_unsigned(data, length) or { return errno.einval }
	// Under half is not a limit anybody means, and firmware tends to refuse it.
	if percent < 50 || percent > 100 || supply.set_charge_limit == unsafe { nil } {
		return errno.einval
	}
	refused := supply.set_charge_limit(supply.context, percent)
	if refused != 0 {
		return refused
	}
	supply.read_ns = 0
	return 0
}

fn show_low(_ voidptr, mut text lib.Text) {
	text.add_decimal(i64(psupply_policy.low_percent))
	text.add_byte(`\n`)
}

fn show_critical(_ voidptr, mut text lib.Text) {
	text.add_decimal(i64(psupply_policy.critical_percent))
	text.add_byte(`\n`)
}

fn store_low(_ voidptr, data &u8, length u64) u64 {
	value := fs.sysfs_unsigned(data, length) or { return errno.einval }
	return if value <= 50 && set_thresholds(int(value), psupply_policy.critical_percent) {
		u64(0)
	} else {
		u64(errno.einval)
	}
}

fn store_critical(_ voidptr, data &u8, length u64) u64 {
	value := fs.sysfs_unsigned(data, length) or { return errno.einval }
	return if value <= 50 && set_thresholds(psupply_policy.low_percent, int(value)) {
		u64(0)
	} else {
		u64(errno.einval)
	}
}

fn show_on_battery(_ voidptr, mut text lib.Text) {
	text.add(if on_battery() { '1\n' } else { '0\n' })
}
