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
	// Where it is now, for a machine started with its lid shut.
	if closed := lid_closed(node) {
		syspower.lid_found(closed)
	}
	mut driver := unsafe { &devcore.Driver(context) }
	add_device(node, 'PNP0C0D', mut driver)
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
	mut driver := unsafe { &devcore.Driver(context) }
	add_device(node, 'PNP0C0C', mut driver)
}

fn sleep_button_found(context voidptr, node uacpi.Node) {
	if !uacpi.on_notify(node, sleep_button_notify, unsafe { nil }) {
		return
	}
	acpipm_buttons++
	mut driver := unsafe { &devcore.Driver(context) }
	add_device(node, 'PNP0C0E', mut driver)
}
