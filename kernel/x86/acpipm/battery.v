// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The control method battery (PNP0C0A).
//
// Two methods describe it. _BIX, or _BIF on firmware older than ACPI 4, says
// what the battery is -- its design and last full capacity, its voltage, its
// chemistry, who made it -- and changes only when the battery is swapped or
// has relearned its capacity, which firmware announces with Notify 0x81.
// _BST says how it is now: charging or discharging, how fast, how much is
// left, at what voltage; firmware announces a change of state with Notify
// 0x80, and the level itself is simply read when somebody wants to know.
//
// A battery counts in milliwatt-hours or in milliampere-hours and says which.
// Firmware writes 0xFFFFFFFF for a figure it does not know; such a figure is
// reported as absent, never as a number.
module acpipm

import devcore
import psupply
import uacpi

const unknown_value = u64(0xffffffff)

// _BST state bits.
const state_discharging = u64(1) << 0
const state_charging = u64(1) << 1
const state_critical = u64(1) << 2

struct Battery {
mut:
	node   uacpi.Node
	supply &psupply.Supply = unsafe { nil }
	// What _BIX said, kept until firmware says it changed.
	information_read bool
	in_charge        bool
	design           u64
	full             u64
	design_voltage   u64
	cycles           u64
	technology       [psupply.text_bytes]u8
	technology_len   int
	model            [psupply.text_bytes]u8
	model_len        int
	serial           [psupply.text_bytes]u8
	serial_len       int
	maker            [psupply.text_bytes]u8
	maker_len        int
}

const max_batteries = 4

__global (
	acpipm_battery_table [max_batteries]Battery
)

// A figure firmware gave, or zero when it gave none.
fn known(value u64) u64 {
	return if value == unknown_value || value > unknown_value { u64(0) } else { value }
}

fn copy_text(destination &u8, source string) int {
	for i in 0 .. source.len {
		unsafe {
			destination[i] = source[i]
		}
	}
	return source.len
}

// The chemistry by Linux's names, from the string firmware gives it.
fn (mut battery Battery) set_technology(kind &u8, length int) {
	text := unsafe { tos(kind, length) }
	name := if text.starts_with('NiCd') {
		'NiCd'
	} else if text.starts_with('NiMH') {
		'NiMH'
	} else if text.starts_with('LION') || text.starts_with('LI-ION') || text.starts_with('LiIon')
		|| text.starts_with('Li-ion') {
		'Li-ion'
	} else if text.starts_with('LiP') || text.starts_with('LIP') {
		'Li-poly'
	} else {
		'Unknown'
	}
	battery.technology_len = copy_text(&battery.technology[0], name)
}

// Read _BIX, or _BIF where there is none. The two hold the same things in
// different places.
fn (mut battery Battery) read_information() bool {
	mut extended := true
	mut package := uacpi.evaluate_package(battery.node, '_BIX') or {
		extended = false
		uacpi.evaluate_package(battery.node, '_BIF') or { return false }
	}
	defer {
		package.release()
	}
	// Where each figure is: _BIX starts with a revision, and has a cycle
	// count and five sampling figures _BIF lacks.
	first := if extended { 1 } else { 0 }
	strings := if extended { 16 } else { 9 }
	if package.len() < strings + 4 {
		return false
	}
	unit := package.integer(first) or { return false }
	battery.in_charge = unit == 1
	battery.design = known(package.integer(first + 1) or { u64(0) }) * 1000
	battery.full = known(package.integer(first + 2) or { u64(0) }) * 1000
	battery.design_voltage = known(package.integer(first + 4) or { u64(0) }) * 1000
	battery.cycles = if extended { known(package.integer(8) or { u64(0) }) } else { u64(0) }
	battery.model_len = package.text(strings, &battery.model[0], psupply.text_bytes)
	battery.serial_len = package.text(strings + 1, &battery.serial[0], psupply.text_bytes)
	mut kind := [psupply.text_bytes]u8{}
	kind_len := package.text(strings + 2, &kind[0], psupply.text_bytes)
	battery.set_technology(&kind[0], kind_len)
	battery.maker_len = package.text(strings + 3, &battery.maker[0], psupply.text_bytes)
	// A battery that has never been through a full cycle reports no last
	// full capacity; its design capacity is the best figure there is.
	if battery.full == 0 {
		battery.full = battery.design
	}
	battery.information_read = true
	return true
}

fn battery_read(context voidptr, mut reading psupply.Reading) bool {
	mut battery := unsafe { &Battery(context) }
	status := uacpi.evaluate_integer(battery.node, '_STA') or { sta_present | sta_battery_present }
	if status & sta_battery_present == 0 {
		// An empty bay. What was known about the last battery in it is not
		// true of the next.
		battery.information_read = false
		reading.present = false
		return true
	}
	if !battery.information_read && !battery.read_information() {
		return false
	}
	mut package := uacpi.evaluate_package(battery.node, '_BST') or { return false }
	defer {
		package.release()
	}
	if package.len() < 4 {
		return false
	}
	state := package.integer(0) or { return false }
	rate := known(package.integer(1) or { u64(0) })
	remaining := package.integer(2) or { return false }
	voltage := known(package.integer(3) or { u64(0) })
	if remaining == unknown_value {
		return false
	}
	reading.present = true
	reading.in_charge = battery.in_charge
	reading.amount = remaining * 1000
	reading.full = battery.full
	reading.design = battery.design
	reading.rate = rate * 1000
	reading.voltage_uv = voltage * 1000
	reading.design_voltage_uv = battery.design_voltage
	reading.cycles = battery.cycles
	reading.critical = state & state_critical != 0
	// Firmware that sets both bits is discharging: that is the one that
	// matters, and what Linux takes it for.
	reading.status = if state & state_discharging != 0 {
		psupply.Status.discharging
	} else if state & state_charging != 0 {
		psupply.Status.charging
	} else if battery.full != 0 && reading.amount >= battery.full {
		psupply.Status.full
	} else {
		psupply.Status.not_charging
	}
	reading.technology = battery.technology
	reading.technology_len = battery.technology_len
	reading.model = battery.model
	reading.model_len = battery.model_len
	reading.serial = battery.serial
	reading.serial_len = battery.serial_len
	reading.maker = battery.maker
	reading.maker_len = battery.maker_len
	return true
}

fn battery_notify(context voidptr, _node voidptr, value u64) uacpi.UACPIStatus {
	mut battery := unsafe { &Battery(context) }
	if value == notify_information_changed {
		battery.information_read = false
	}
	if battery.supply != unsafe { nil } {
		mut supply := battery.supply
		psupply.changed(mut supply)
	}
	return .ok
}

fn battery_found(context voidptr, node uacpi.Node) {
	if acpipm_batteries >= max_batteries {
		return
	}
	mut battery := unsafe { &acpipm_battery_table[acpipm_batteries] }
	battery.node = node
	battery.information_read = false
	mut name := [16]u8{}
	mut length := uacpi.node_name(node, &name[0], 12)
	if length == 0 {
		name[0] = `B`
		name[1] = `A`
		name[2] = `T`
		name[3] = u8(`0` + acpipm_batteries)
		length = 4
	}
	battery.supply = psupply.register(psupply.Supply{
		name:    unsafe { tos(&name[0], length) }
		kind:    .battery
		read:    battery_read
		context: voidptr(battery)
	}) or { return }
	acpipm_batteries++
	uacpi.on_notify(node, battery_notify, voidptr(battery))
	mut driver := unsafe { &devcore.Driver(context) }
	add_device(node, 'PNP0C0A', mut driver)
}
