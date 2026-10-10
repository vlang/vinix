// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// PCI hotplug where firmware has a say in it.
//
// On a PC it is firmware that knows what a port's slot is wired to, and ACPI
// is how it and the system settle who watches the ports:
//
//  - Each PCI host bridge is asked, through its _OSC method, to hand over its
//    Express ports' hotplug. If every bridge does -- or none has an _OSC, as
//    on a machine too old to keep its ports -- the ports are the system's,
//    and the device core polls them (devcore/hotplug.v).
//  - If firmware keeps them, it does the watching, and tells the system
//    through a Notify on the namespace node of the device concerned: 1, "a
//    device may have appeared here"; 3, "this device is wanted back"; 0 on a
//    bridge, "look at everything behind this". The node's place on the PCI
//    buses is worked out from the _ADR of each node between it and its host
//    bridge, and the device core is asked to look there, or to let go of
//    what is there, after which the node's _EJ0 tells firmware the device
//    can leave.
//
// The notifications are listened for in either case: a machine may hand over
// its Express ports and still announce a docking station through ACPI.
@[has_globals]
module acpihp

import devcore
import pci
import uacpi

const notify_bus_check = u64(0)
const notify_device_check = u64(1)
const notify_eject_request = u64(3)

// How deep under its host bridge a device can sit.
const max_depth = 16

__global (
	acpihp_bridges  int
	acpihp_refused  int
	acpihp_arrivals u64
	acpihp_ejects   u64
)

// The place on the PCI buses of the device a namespace node stands for: its
// bus and its device number. False if the node is not a PCI device, or a
// bridge above it has not been given a bus.
fn place_of(node uacpi.Node) (u8, u8, bool) {
	mut addresses := [max_depth]u64{}
	mut depth := 0
	mut current := node
	for {
		if current == unsafe { nil } {
			// The top of the namespace, and no host bridge on the way.
			return 0, 0, false
		}
		if uacpi.is_pci_root(current) {
			break
		}
		if depth >= max_depth {
			return 0, 0, false
		}
		addresses[depth] = uacpi.evaluate_integer(current, '_ADR') or { return 0, 0, false }
		depth++
		current = uacpi.parent_of(current)
	}
	if depth == 0 {
		// The host bridge itself.
		return 0, 0, false
	}
	// The host bridge's bus, then down through each bridge to the bus the
	// node's device is on.
	mut bus := u8(uacpi.evaluate_integer(current, '_BBN') or { 0 })
	for level := depth - 1; level > 0; level-- {
		place := u8((addresses[level] >> 16) & 0x1f)
		mut function := u8(addresses[level] & 0x7)
		if addresses[level] & 0xffff == 0xffff {
			function = 0
		}
		bridge := pci.record_at(bus, place, function)
		if bridge == unsafe { nil } || !bridge.present() || bridge.header_type != 1 {
			return 0, 0, false
		}
		bus = bridge.secondary_bus()
		if bus == 0 {
			return 0, 0, false
		}
	}
	return bus, u8((addresses[0] >> 16) & 0x1f), true
}

// The device core has let go of the device: firmware may take it.
fn ejected(context voidptr) {
	if !uacpi.execute_integer(uacpi.Node(context), '_EJ0', 1) {
		print('acpihp: _EJ0 failed; the device stays in its slot\n')
	}
}

// Every Notify in the machine passes through here; the ones that are not
// about a PCI device's coming or going are somebody else's.
fn notified(_ voidptr, node voidptr, value u64) uacpi.UACPIStatus {
	if value != notify_bus_check && value != notify_device_check && value != notify_eject_request {
		return .ok
	}
	if value == notify_bus_check {
		// Sent to a bridge, or to a host bridge: look behind it. Looking
		// everywhere finds the same devices.
		if uacpi.is_pci_root(uacpi.Node(node)) {
			devcore.request_rescan(.pci)
			return .ok
		}
		_, _, known := place_of(uacpi.Node(node))
		if known {
			devcore.request_rescan(.pci)
		}
		return .ok
	}
	bus, place, known := place_of(uacpi.Node(node))
	if !known {
		return .ok
	}
	if value == notify_device_check {
		acpihp_arrivals++
		devcore.pci_arrival(bus, place)
		return .ok
	}
	// Without an _EJ0 firmware has no way to be told, and asking for the
	// device back means something else; leave it.
	if !uacpi.has_method(uacpi.Node(node), '_EJ0') {
		return .ok
	}
	acpihp_ejects++
	if !devcore.pci_eject(bus, place, ejected, node) {
		print('acpihp: an eject request could not be queued\n')
	}
	return .ok
}

fn ask_bridge(_ voidptr, node uacpi.Node) {
	acpihp_bridges++
	if !uacpi.has_method(node, '_OSC') {
		return
	}
	granted := uacpi.pci_osc(node, uacpi.osc_supports_msi, uacpi.osc_control_hotplug | uacpi.osc_control_express) or {
		acpihp_refused++
		return
	}
	if granted & uacpi.osc_control_hotplug == 0 {
		acpihp_refused++
	}
}

// Settle with firmware who watches the ports, and start listening to what it
// announces. Returns whether the Express ports are the system's to run.
// Called once the namespace is up, before the device core's hotplug starts.
pub fn initialise() bool {
	uacpi.for_each_device('PNP0A03', ask_bridge, unsafe { nil })
	if !uacpi.on_every_notify(notified, unsafe { nil }) {
		print('acpihp: could not listen for device notifications\n')
	}
	own := acpihp_refused == 0
	C.kprintf(c'acpihp: %lld PCI host bridge(s); Express hotplug is %s\n', i64(acpihp_bridges),
		if own { c'the system\'s' } else { c'firmware\'s' })
	return own
}
