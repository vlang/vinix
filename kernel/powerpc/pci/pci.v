// SPDX-License-Identifier: GPL-2.0-or-later
module pci

import powerpc.boot
import powerpc.mmio

fn select(device &boot.PciDevice, offset u32) u32 {
	bus := device.bdf >> 16
	slot := (device.bdf >> 11) & 31
	if offset > 252 || (bus == device.root_bus && slot < 11) { return 0 }
	selector := if bus == device.root_bus {
		(u32(1) << slot) | (device.bdf & 0x700) | (offset & 0xfc)
	} else { device.bdf | (offset & 0xfc) | 1 }
	address := device.config + 0x800000
	for _ in 0 .. 16 {
		mmio.write32(address, selector)
		if mmio.read32(address) == selector { return device.config + 0xc00000 + (offset & 7) }
	}
	return 0
}

pub fn enable(device &boot.PciDevice) bool {
	identity := select(device, 0)
	if identity == 0 || mmio.read32(identity) != (device.device << 16 | device.vendor) { return false }
	command := select(device, 4)
	if command == 0 { return false }
	// Status is W1C: never replay its upper half when changing Command.
	mmio.write32(command, (mmio.read32(command) & 0xffff) | 6)
	return mmio.read32(command) & 6 == 6
}
