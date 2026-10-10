// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Devices that are not on a bus that can be asked what is on it: the VirtIO
// transports of a virtual ARM machine, and everything an Apple SoC has, which
// firmware describes in a device tree and each driver finds for itself.
//
// Those drivers predate the device core and start the way they always have.
// What they add is one call when they have their device working, so that the
// machine's list of devices and of who drives them is complete whichever way
// a driver came by its hardware.
module devcore

// Record that the driver called `driver` has the platform device `name`,
// which firmware describes as `compatible`. The device and the driver's
// record are made if they are not there yet. Returns the device, or nil when
// a table is full.
pub fn claim_platform(name string, compatible string, driver string) &Device {
	return claim_on(.platform, name, compatible, driver)
}

fn claim_on(bus Bus, name string, compatible string, driver string) &Device {
	gate_enter()
	defer {
		gate_leave()
	}
	mut record := find_driver(bus, driver) or {
		register_driver(Driver{
			name: driver
			bus:  bus
		}) or { return unsafe { nil } }
	}
	mut dev := find(bus, name)
	if dev == unsafe { nil } {
		dev = new_device(bus, name)
		// Device-tree compatibles and the literals drivers pass both outlive
		// the device.
		dev.compatible = compatible
		if !add(mut dev) {
			unsafe {
				dev.name.free()
				free(dev)
			}
			return unsafe { nil }
		}
	}
	claim(mut dev, mut record)
	return dev
}

// The same for a PCI function a driver found by itself: the device is the
// one enumeration made, and only the claim is new.
pub fn claim_pci(mut dev Device, driver string) bool {
	gate_enter()
	defer {
		gate_leave()
	}
	mut record := find_driver(.pci, driver) or {
		register_driver(Driver{
			name: driver
			bus:  .pci
		}) or { return false }
	}
	return claim(mut dev, mut record)
}
