// SPDX-License-Identifier: GPL-2.0-or-later
module main

import powerpc.boot

fn compatible(node u32, wanted &char) bool {
	mut value := [256]u8{}
	length := get_property(node, c'compatible', unsafe { &value[0] }, 256)
	if length <= 0 || length > 256 { return false }
	mut at := 0
	for at < length {
		mut i := 0
		for at + i < length && value[at + i] != 0 && unsafe { wanted[i] != 0 }
			&& value[at + i] == unsafe { u8(wanted[i]) } { i++ }
		if at + i < length && value[at + i] == 0 && unsafe { wanted[i] == 0 } { return true }
		for at < length && value[at] != 0 { at++ }
		at++
	}
	return false
}

fn discover_pci(node u32) {
	class := property_u32(node, c'class-code', 0)
	vendor := property_u32(node, c'vendor-id', 0)
	if class != 0x0c0310 && !(class == 0x020000 && vendor == 0x106b) { return }
	if boot_info.pci_count == 8 { return }
	parent := relation(c'parent', node)
	// UniNorth root buses use identity PCI memory windows on the G4. Nested
	// PCI bridges and translated windows require a separate range translator.
	if !compatible(parent, c'uni-north') { return }
	mut host := [2]u32{}
	mut buses := [2]u32{}
	mut reg := [5]u32{}
	mut bars := [30]u32{}
	if get_property(parent, c'reg', unsafe { &host[0] }, 8) != 8
		|| get_property(parent, c'bus-range', unsafe { &buses[0] }, 8) != 8
		|| get_property(node, c'reg', unsafe { &reg[0] }, 20) < 20
		|| host[0] > 0xff300000 { return }
	length := get_property(node, c'assigned-addresses', unsafe { &bars[0] }, sizeof(bars))
	if length <= 0 || length > int(sizeof(bars)) || length % 20 != 0 { return }
	for i := 0; i < length / 4; i += 5 {
		if bars[i] & 0x030000ff != 0x02000010 || bars[i + 1] != 0 || bars[i + 3] != 0
			|| bars[i + 2] < 0x80000000 || bars[i + 4] == 0
			|| bars[i + 4] > 0xffffffff - bars[i + 2] { continue }
		mut device := boot.PciDevice{
			base: bars[i + 2], size: bars[i + 4], config: host[0], bdf: reg[0] & 0x00ffff00,
			root_bus: buses[0], vendor: vendor, device: property_u32(node, c'device-id', 0), class: class
		}
		if get_property(node, c'local-mac-address', unsafe { &device.mac[0] }, 6) != 6 {
			get_property(node, c'mac-address', unsafe { &device.mac[0] }, 6)
		}
		boot_info.pci[boot_info.pci_count] = device
		boot_info.pci_count++
		puts(c'VINIX-PPC: PCI class ')
		hex(class)
		puts(c' base ')
		hex(device.base)
		puts(c'\r\n')
		break
	}
}
