// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The PCI bus, as the device core sees it: one device per function the scan
// found, named the way Linux names it, hanging off the bridge it sits behind.
module devcore

import lib
import pci

// "0000:00:1f.2": domain, bus, device and function, as lspci prints them.
fn pci_name(bus u8, slot u8, function u8) string {
	mut text := unsafe { &lib.Text(C.vinix_stack_alloc(sizeof(lib.Text))) }
	unsafe { *text = lib.new_text(16) }
	text.add('0000:')
	text.add_radix(u64(bus), 16, 2)
	text.add_byte(`:`)
	text.add_radix(u64(slot), 16, 2)
	text.add_byte(`.`)
	text.add_radix(u64(function), 16, 1)
	return text.str()
}

fn pci_bdf(p &pci.PCIDevice) i64 {
	return (i64(p.bus) << 8) | (i64(p.slot) << 3) | i64(p.function)
}

// The core's device for a PCI function, or nil if it has none.
pub fn of_pci(p &pci.PCIDevice) &Device {
	devcore_table_lock.acquire()
	defer {
		devcore_table_lock.release()
	}
	for i in 0 .. devcore_device_count {
		if voidptr(devcore_devices[i].pci) == voidptr(p) {
			return devcore_devices[i]
		}
	}
	return unsafe { nil }
}

fn of_pci_bdf(bdf i64) &Device {
	devcore_table_lock.acquire()
	defer {
		devcore_table_lock.release()
	}
	for i in 0 .. devcore_device_count {
		p := devcore_devices[i].pci
		if p != unsafe { nil } && pci_bdf(p) == bdf {
			return devcore_devices[i]
		}
	}
	return unsafe { nil }
}

// Add the device for one PCI function. The scan lists a bridge before what is
// behind it, so the parent is already there to be found.
pub fn add_pci(p &pci.PCIDevice) &Device {
	name := pci_name(p.bus, p.slot, p.function)
	mut dev := new_device(.pci, name)
	unsafe { name.free() }
	dev.vendor = p.vendor_id
	dev.device = p.device_id
	dev.class = p.class
	dev.subclass = p.subclass
	dev.prog_if = p.prog_if
	dev.revision = u8(p.revision_id)
	dev.pci = unsafe { p }
	if p.parent >= 0 {
		dev.parent = of_pci_bdf(p.parent)
	}
	if !add(mut dev) {
		unsafe {
			dev.name.free()
			free(dev)
		}
		return unsafe { nil }
	}
	return dev
}

// Hand the core every function the boot scan found. Called once, after
// pci.initialise() and before the first PCI driver registers.
pub fn enumerate_pci() {
	mut added := 0
	for p in scanned_devices {
		if of_pci(p) != unsafe { nil } {
			continue
		}
		if add_pci(p) != unsafe { nil } {
			added++
		}
	}
	C.kprintf(c'devcore: %lld PCI functions enumerated\n', i64(added))
}

// What a PCI driver's `matches` is usually made of.
pub fn (dev &Device) is_pci(vendor u16, device u16) bool {
	return dev.bus == .pci && dev.vendor == vendor && dev.device == device
}

pub fn (dev &Device) is_pci_class(class u8, subclass u8, prog_if u8) bool {
	return dev.bus == .pci && dev.class == class && dev.subclass == subclass
		&& dev.prog_if == prog_if
}
