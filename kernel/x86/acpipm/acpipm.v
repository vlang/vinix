// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The power devices a PC's firmware describes: batteries, the charger, the
// lid, and a power or sleep button that is a device in the namespace rather
// than a fixed feature.
//
// Each is found by its hardware ID, read through the methods the ACPI
// specification gives it, and listened to through Notify. What is read goes
// to the modules that know what to do with it -- psupply for batteries and
// chargers, syspower for the lid and buttons -- so nothing here decides
// anything. The method names, package layouts and Notify values are the
// specification's (ACPI 6.5, chapter 10 for power sources, 9.4 for the lid);
// the handling of what firmware leaves out follows Linux's drivers
// (drivers/acpi/battery.c, ac.c, button.c).
//
// Each device found is also added to the device core on the acpi bus and
// recorded as claimed, so that /sys/bus/acpi shows what the machine has and
// what has it.
@[has_globals]
module acpipm

import devcore
import uacpi

const notify_status_changed = u64(0x80)
const notify_information_changed = u64(0x81)

// _STA: the device is there.
const sta_present = u64(1) << 0
// _STA of a battery: the battery itself is in its bay.
const sta_battery_present = u64(1) << 4

__global (
	acpipm_started  bool
	acpipm_batteries int
	acpipm_adapters  int
	acpipm_lids      int
	acpipm_buttons   int
)

// Put a namespace device on the acpi bus as claimed by `driver`. The name is
// the node's own, numbered when two share one.
fn add_device(node uacpi.Node, hid string, mut driver devcore.Driver) {
	mut name := [16]u8{}
	mut length := uacpi.node_name(node, &name[0], 12)
	if length == 0 {
		name[0] = `D`
		name[1] = `E`
		name[2] = `V`
		length = 3
	}
	for suffix := 0; suffix < 10; suffix++ {
		name[length] = `:`
		name[length + 1] = u8(`0` + suffix)
		candidate := unsafe { tos(&name[0], length + 2) }
		if devcore.find(.acpi, candidate) != unsafe { nil } {
			continue
		}
		mut dev := devcore.new_device(.acpi, candidate)
		dev.compatible = hid
		dev.bus_data = voidptr(node)
		if !devcore.add(mut dev) {
			return
		}
		devcore.claim(mut dev, mut driver)
		return
	}
}

fn register(name string) &devcore.Driver {
	return devcore.register_driver(devcore.Driver{
		name: name
		bus:  .acpi
	}) or { panic('acpipm: driver table full') }
}

// Find the power devices and start listening to them. Called once ACPI events
// are on and the power supply and system power modules are up.
pub fn initialise() {
	if acpipm_started {
		return
	}
	acpipm_started = true
	mut battery_driver := register('battery')
	mut adapter_driver := register('ac')
	mut button_driver := register('button')
	uacpi.for_each_device('PNP0C0A', battery_found, voidptr(battery_driver))
	uacpi.for_each_device('ACPI0003', adapter_found, voidptr(adapter_driver))
	uacpi.for_each_device('PNP0C0D', lid_found, voidptr(button_driver))
	uacpi.for_each_device('PNP0C0C', power_button_found, voidptr(button_driver))
	uacpi.for_each_device('PNP0C0E', sleep_button_found, voidptr(button_driver))
	if acpipm_batteries + acpipm_adapters + acpipm_lids + acpipm_buttons != 0 {
		C.kprintf(c'acpipm: %lld batteries, %lld chargers, %lld lids, %lld buttons\n', i64(acpipm_batteries),
			i64(acpipm_adapters), i64(acpipm_lids), i64(acpipm_buttons))
	}
}
