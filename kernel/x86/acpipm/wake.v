// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Devices that can end a suspend to RAM: the lid, the buttons that are
// devices, the keyboard.
//
// While the machine runs, such a device speaks through an event that is
// switched on like any other. For a suspend to RAM every event is switched
// off but those marked as able to wake the machine, so a lid whose event was
// not marked can be opened without the machine noticing. Firmware names the
// event in the device's _PRW (uacpi/wake.v); here each such device is found
// once, its event marked, and then, around every suspend to RAM:
//
//   before   if its wake source is allowed (/sys/class/wakeup) and firmware
//            says it can end a sleep this deep: its power resources on, the
//            device told (_DSW or _PSW), the event left enabled;
//   after    the device told it need not, and the event no longer left
//            enabled.
//
// A power resource switched on for this is left on: nothing here counts who
// else needs it, and switching off one that the device also runs from would
// take the device down.
//
// /sys/power/acpi_wakeup lists the devices: name, wake source, the deepest
// state, the event, how it is told, and how many sleeps it was armed for.
// `vinix.acpi_wake=off` leaves all of it undone.
@[has_globals]
module acpipm

import devcore
import fs
import lib
import syspower
import uacpi
import wakesrc

const wake_devices_max = 8
const sleep_state_s3 = 3

struct WakeDevice {
mut:
	node   uacpi.Node
	source wakesrc.Source
	info   uacpi.WakeInfo
	// Its event could be marked.
	usable bool
	armed  bool
	method uacpi.WakeMethod
	arms   u64
}

__global (
	acpipm_wake       [wake_devices_max]WakeDevice
	acpipm_wake_count int
	acpipm_wake_off   bool
)

// A device of a kind that may wake the machine: remember it if firmware says
// how.
fn wake_found(node uacpi.Node, source wakesrc.Source) {
	if acpipm_wake_off || acpipm_wake_count >= wake_devices_max {
		return
	}
	mut device := &acpipm_wake[acpipm_wake_count]
	if !uacpi.wake_info(node, mut device.info) {
		return
	}
	device.node = node
	device.source = source
	device.usable = uacpi.setup_wake_gpe(device.info.gpe_block, device.info.gpe)
	acpipm_wake_count++
}

fn keyboard_found(_context voidptr, node uacpi.Node) {
	wake_found(node, .keyboard)
}

// Before firmware is told of a sleep to `state`.
fn wake_arm(state int) {
	for i in 0 .. acpipm_wake_count {
		mut device := &acpipm_wake[i]
		if !device.usable || device.info.deepest < state || !wakesrc.allowed(device.source) {
			continue
		}
		for r in 0 .. device.info.resource_count {
			uacpi.execute(device.info.resources[r], '_ON')
		}
		device.method = uacpi.device_wake(device.node, true, state)
		if uacpi.arm_wake_gpe(device.info.gpe_block, device.info.gpe, true) {
			device.armed = true
			device.arms++
		} else {
			uacpi.device_wake(device.node, false, state)
		}
	}
}

// After firmware has been told the machine is back.
fn wake_disarm() {
	for i in 0 .. acpipm_wake_count {
		mut device := &acpipm_wake[i]
		if !device.armed {
			continue
		}
		device.armed = false
		uacpi.arm_wake_gpe(device.info.gpe_block, device.info.gpe, false)
		uacpi.device_wake(device.node, false, sleep_state_s3)
	}
}

fn add_gpe(mut text lib.Text, info &uacpi.WakeInfo) {
	text.add('gpe 0x')
	text.add_radix(u64(info.gpe), 16, 2)
	if info.gpe_block != unsafe { nil } {
		text.add(' of a block device')
	}
}

fn show_wakeup(_ voidptr, mut text lib.Text) {
	for i in 0 .. acpipm_wake_count {
		device := &acpipm_wake[i]
		mut name := [8]u8{}
		length := uacpi.node_name(device.node, &name[0], 8)
		text.add(unsafe { tos(&name[0], length) })
		text.add_byte(` `)
		text.add(wakesrc.name(device.source))
		text.add(' S')
		text.add_unsigned(u64(device.info.deepest))
		text.add_byte(` `)
		add_gpe(mut text, &device.info)
		text.add(match device.method {
			.dsw { ' told by _DSW' }
			.psw { ' told by _PSW' }
			.failed { ' could not be told' }
			.nothing { '' }
		})
		text.add(if device.usable { ' armed ' } else { ' unusable, armed ' })
		text.add_unsigned(device.arms)
		text.add(' times\n')
	}
}

// Find what can wake the machine. After the lids and buttons have been
// found, which is where theirs are added.
fn initialise_wake() {
	if acpipm_wake_off {
		return
	}
	uacpi.for_each_device('PNP0303', keyboard_found, unsafe { nil })
	uacpi.for_each_device('PNP030B', keyboard_found, unsafe { nil })
	if acpipm_wake_count == 0 {
		return
	}
	syspower.on_deep_sleep(wake_arm, wake_disarm)
	fs.sysfs_attribute('power/acpi_wakeup', 0o444, show_wakeup, unsafe { nil }, unsafe { nil })
	C.kprintf(c'acpipm: %lld devices can wake the machine from a sleep\n', i64(acpipm_wake_count))
}

fn wake_decide() {
	acpipm_wake_off = !devcore.boot_flag('vinix.acpi_wake=', true)
}
