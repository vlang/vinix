// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The lid (PNP0C0D) and the power and sleep buttons that are devices in the
// namespace (PNP0C0C, PNP0C0E) -- what a laptop has instead of, or as well
// as, the fixed-feature buttons uACPI reports directly.
//
// All three say what they have to say with Notify 0x80. A button has nothing
// more to add; the lid is then asked with _LID whether it is open, which is
// any non-zero answer.
module acpipm

import devcore
import syspower
import uacpi

fn lid_closed(node uacpi.Node) ?bool {
	open := uacpi.evaluate_integer(node, '_LID')?
	return open == 0
}

fn lid_notify(_context voidptr, node voidptr, value u64) uacpi.UACPIStatus {
	if value == notify_status_changed {
		closed := lid_closed(uacpi.Node(node)) or { return .ok }
		syspower.lid(closed)
	}
	return .ok
}

fn lid_found(context voidptr, node uacpi.Node) {
	if !uacpi.on_notify(node, lid_notify, unsafe { nil }) {
		return
	}
	acpipm_lids++
	wake_found(node, .lid)
	// Where it is now, for a machine started with its lid shut.
	if closed := lid_closed(node) {
		syspower.lid_found(closed)
	}
	mut driver := unsafe { &devcore.Driver(context) }
	add_device(node, 'PNP0C0D', mut driver)
}

// Nothing to stop: the devices are firmware's. A suspend is taken so that
// the resume below is given.
fn button_suspend(mut dev devcore.Device) bool {
	return true
}

// After any sleep a lid is asked where it is. Firmware does not always say
// that it was opened while the machine was down, least of all when opening
// it is what woke the machine. Open now and shut before: it was opened, and
// that is a wake source reporting. Shut now: whatever woke the machine, the
// lid is not shut a second time.
fn button_resume(mut dev devcore.Device) bool {
	if dev.compatible != 'PNP0C0D' || dev.bus_data == unsafe { nil } {
		return true
	}
	closed := lid_closed(uacpi.Node(dev.bus_data)) or { return true }
	if !closed && syspower.lid_state_name() == 'closed' {
		syspower.lid(false)
	} else {
		syspower.lid_found(closed)
	}
	return true
}

fn power_button_notify(_context voidptr, _node voidptr, value u64) uacpi.UACPIStatus {
	if value == notify_status_changed {
		syspower.button(.power)
	}
	return .ok
}

fn sleep_button_notify(_context voidptr, _node voidptr, value u64) uacpi.UACPIStatus {
	if value == notify_status_changed {
		syspower.button(.sleep)
	}
	return .ok
}

fn power_button_found(context voidptr, node uacpi.Node) {
	if !uacpi.on_notify(node, power_button_notify, unsafe { nil }) {
		return
	}
	acpipm_buttons++
	wake_found(node, .power_button)
	mut driver := unsafe { &devcore.Driver(context) }
	add_device(node, 'PNP0C0C', mut driver)
}

fn sleep_button_found(context voidptr, node uacpi.Node) {
	if !uacpi.on_notify(node, sleep_button_notify, unsafe { nil }) {
		return
	}
	acpipm_buttons++
	wake_found(node, .sleep_button)
	mut driver := unsafe { &devcore.Driver(context) }
	add_device(node, 'PNP0C0E', mut driver)
}
