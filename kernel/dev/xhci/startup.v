// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module xhci

const hcc_port_power_control = u32(1) << 3
const portsc_power = u32(1) << 9
// Exclude write-one-to-clear status, reset requests and the link write strobe.
const portsc_write_mask = ~(u32(0x80fe0012) | (u32(1) << 16))
const legacy_bios_owned = u32(1) << 16
const legacy_os_owned = u32(1) << 24

// Devices on an unpowered port may not even assert Connected. Do this for
// every root port, including empty ones, before the boot-time device scan.
fn power_ports(hcc1 u32) {
	if hcc1 & hcc_port_power_control != 0 {
		for port := u32(1); port <= xhci_ports; port++ {
			reg := port_register(port)
			sc := rd(reg)
			if sc & portsc_power == 0 {
				wr(reg, (sc & portsc_write_mask) | portsc_power)
				// Flush the posted register write before connection debounce.
				rd(reg)
			}
		}
	}
	busywait_us(100000)
}

// Ask firmware to release the controller before resetting it. Some firmware
// never clears BIOS Owned; after the bounded wait, clear it ourselves and
// disable legacy SMIs so firmware cannot keep operating our controller.
// Capability links are relative DWORD offsets within the mapped BAR.
fn take_ownership(first u64, length u64) bool {
	mut offset := first
	for steps := 0; offset != 0 && steps < 64; steps++ {
		if length < 4 || offset > length - 4 {
			println('xhci: legacy capability outside controller registers')
			return false
		}
		reg := xhci_cap + offset
		value := rd(reg)
		if value & 0xff == 1 {
			if length < 8 || offset > length - 8 {
				println('xhci: truncated legacy capability')
				return false
			}
			wr(reg, value | legacy_os_owned)
			deadline := now_ns() + 1000000000
			for rd(reg) & legacy_bios_owned != 0 && now_ns() < deadline {
				busywait_us(10)
			}
			if rd(reg) & legacy_bios_owned != 0 {
				println('xhci: firmware handoff timed out; forcing ownership')
				wr(reg, (rd(reg) | legacy_os_owned) & ~legacy_bios_owned)
			}
			// SMI enables off; their status bits are write-1-to-clear.
			wr(reg + 4, (rd(reg + 4) & 0xffff1fee) | 0xe0000000)
			return true
		}
		next := u64((value >> 8) & 0xff)
		if next == 0 {
			return true
		}
		offset += next << 2
	}
	return offset == 0
}
