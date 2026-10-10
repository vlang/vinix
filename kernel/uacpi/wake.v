// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// What firmware says of a device that can wake the machine, and the three
// things to be done for one before a sleep it is to end.
//
// _PRW is a package: the event the device signals with -- a number among the
// FADT's general purpose events, or a package of a GPE block device and a
// number in it -- then the deepest sleep state the device can end, then the
// power resources that must be on for it to be able to. Before the sleep
// those resources are switched on, the device is told through _DSW (or the
// older _PSW) that it is to wake the machine, and the event is left enabled
// when all the others are switched off; afterwards the device is told it no
// longer has to. That is Linux's acpi_enable_wakeup_device_power() and
// acpi_enable_wakeup_devices(), drivers/acpi/power.c and wakeup.c.
module uacpi

@[c_extern]
fn C.uacpi_disable_gpe_for_wake(device voidptr, index u16) UACPIStatus

pub const wake_resources_max = 4

pub struct WakeInfo {
pub mut:
	// The event's block device, or nil for one of the FADT's.
	gpe_block Node
	gpe       u16
	// The deepest sleep state the device can end: 3 for a suspend to RAM.
	deepest        int
	resources      [wake_resources_max]Node
	resource_count int
}

// Which of the two methods told a device about waking the machine.
pub enum WakeMethod {
	nothing
	psw
	dsw
	failed
}

// Read `node`'s _PRW into `info`. False where it has none, or one that is
// not in either form the specification gives.
pub fn wake_info(node Node, mut info WakeInfo) bool {
	mut prw := evaluate_package(node, '_PRW') or { return false }
	mut good := prw.len() >= 2
	if good {
		if number := prw.integer(0) {
			info.gpe_block = unsafe { nil }
			info.gpe = u16(number)
			good = number <= 0xffff
		} else if event := prw.package(0) {
			block := event.node(0, node) or { Node(unsafe { nil }) }
			number := event.integer(1) or { u64(0x10000) }
			info.gpe_block = block
			info.gpe = u16(number)
			good = event.len() == 2 && block != unsafe { nil } && number <= 0xffff
		} else {
			good = false
		}
	}
	if good {
		deepest := prw.integer(1) or { u64(0xff) }
		info.deepest = int(deepest)
		good = deepest <= 5
	}
	info.resource_count = 0
	if good {
		for i := 2; i < prw.len() && info.resource_count < wake_resources_max; i++ {
			if resource := prw.node(i, node) {
				info.resources[info.resource_count] = resource
				info.resource_count++
			}
		}
	}
	prw.release()
	return good
}

// Say that the event may end a sleep. What it does while the machine runs
// is left as it is: an event with a method of its own goes on running it.
pub fn setup_wake_gpe(block Node, index u16) bool {
	return C.uacpi_setup_gpe_for_wake(voidptr(block), index, unsafe { nil }) == .ok
}

// Leave the event on, or not, when a sleep switches off what may not end it.
pub fn arm_wake_gpe(block Node, index u16, armed bool) bool {
	if armed {
		return C.uacpi_enable_gpe_for_wake(voidptr(block), index) == .ok
	}
	return C.uacpi_disable_gpe_for_wake(voidptr(block), index) == .ok
}

fn execute_three(node Node, path &char, first u64, second u64, third u64) UACPIStatus {
	mut objects := [C.uacpi_object_create_integer(first), C.uacpi_object_create_integer(second),
		C.uacpi_object_create_integer(third)]!
	mut status := UACPIStatus.out_of_memory
	if objects[0] != unsafe { nil } && objects[1] != unsafe { nil } && objects[2] != unsafe { nil } {
		arguments := ObjectArray{
			objects: unsafe { &objects[0] }
			count:   3
		}
		status = C.uacpi_execute(voidptr(node), path, &arguments)
	}
	for object in objects {
		if object != unsafe { nil } {
			C.uacpi_object_unref(object)
		}
	}
	return status
}

// Tell the device that it is, or is no longer, to wake the machine from
// sleep state `state`: _DSW where it has one, with the device left in D3,
// _PSW otherwise. Most devices have neither, and need neither.
pub fn device_wake(node Node, enable bool, state int) WakeMethod {
	if has_method(node, '_DSW') {
		status := if enable {
			execute_three(node, c'_DSW', 1, u64(state), 3)
		} else {
			execute_three(node, c'_DSW', 0, 0, 0)
		}
		return if status == .ok { WakeMethod.dsw } else { WakeMethod.failed }
	}
	if has_method(node, '_PSW') {
		return if execute_integer(node, '_PSW', if enable { u64(1) } else { u64(0) }) {
			WakeMethod.psw
		} else {
			WakeMethod.failed
		}
	}
	return .nothing
}
