// SPDX-License-Identifier: GPL-2.0-or-later
module ohci

import powerpc.cpu
import powerpc.mmio
import powerpc.pages
import powerpc.serial

fn hub_status(mut host Controller, address u32, packet u32, port u32) int {
	if transfer(mut host, address, false, packet, 0x00a3, 0, port, 4) != 4 { return -1 }
	return int(mmio.read32(host.dma + 1024))
}

// USB 1.1 class requests, bounded to four external tiers and 32 addresses.
// Enumeration is serialized: only the port being assigned may use address 0.
fn enumerate_hub(mut host Controller, address u32, packet u32, configuration u32, root_port u32, depth u32, mut pool pages.Pool) {
	if depth == 4 { return }
	if transfer(mut host, address, false, packet, 0x0900, configuration, 0, 0) < 0 { return }
	size := transfer(mut host, address, false, packet, 0x06a0, 0x2900, 0, 64)
	if size < 9 { return }
	data := unsafe { &u8(host.dma + 1024) }
	ports := unsafe { u32(data[2]) }
	if ports == 0 || ports > 8 { return }
	// QEMU's eight-port hub omits bit zero in the reserved power mask.
	// Neither bitmap is consumed; accept that layout without reading past it.
	minimum := 7 + (ports + 8) / 8 + (ports + 7) / 8
	unsafe { if data[1] != 0x29 || u32(data[0]) < minimum || int(data[0]) > size { return } }
	power_delay := unsafe { u32(data[5]) * 2 + 100 }
	for port := u32(1); port <= ports; port++ {
		if transfer(mut host, address, false, packet, 0x0323, 8, port, 0) < 0 { return }
	}
	delay(power_delay)
	serial.text(c'VINIX-PPC: USB hub ready, depth ')
	serial.hex(depth + 1)
	serial.text(c'\n')
	for port := u32(1); port <= ports; port++ {
		initial := hub_status(mut host, address, packet, port)
		if initial < 0 || initial & 1 == 0 || initial & 8 != 0 { continue }
		transfer(mut host, address, false, packet, 0x0123, 16, port, 0)
		if transfer(mut host, address, false, packet, 0x0323, 4, port, 0) < 0 { continue }
		deadline := cpu.timebase() + u64(frequency / 10)
		mut status := -1
		for cpu.timebase() < deadline {
			status = hub_status(mut host, address, packet, port)
			if status < 0 || status & 1 == 0 || status & 8 != 0 || status & 0x12 == 2 { break }
			delay(2)
		}
		if status < 0 || status & 0x41b != 3 {
			transfer(mut host, address, false, packet, 0x0123, 1, port, 0)
			continue
		}
		delay(10)
		transfer(mut host, address, false, packet, 0x0123, 20, port, 0)
		if !enumerate_device(mut host, root_port, status & 0x200 != 0, depth + 1, mut pool) {
			transfer(mut host, address, false, packet, 0x0123, 1, port, 0)
		}
	}
}
