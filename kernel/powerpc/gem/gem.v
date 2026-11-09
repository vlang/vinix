// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module gem

import powerpc.boot
import powerpc.cpu
import powerpc.mmio
import powerpc.pages
import powerpc.pci
import powerpc.runtime
import powerpc.serial

__global gem_base u32
__global gem_dma u32
__global gem_hz u32
__global gem_phy u32
__global gem_rx u32
__global gem_tx u32
__global gem_ready bool
__global gem_duplex u32
__global gem_mac [6]u8

fn wait_clear(offset u32, mask u32) bool {
	deadline := cpu.timebase() + gem_hz / 10
	for cpu.timebase() < deadline {
		if mmio.read32(gem_base + offset) & mask == 0 { return true }
	}
	return false
}

fn mii(address u32, reg u32, write bool, value u32) u32 {
	mmio.write32(gem_base + 0x620c, (if write { u32(0x50020000) } else { u32(0x60020000) }) | address << 23 | reg << 18 | (value & 0xffff))
	deadline := cpu.timebase() + gem_hz / 100
	for cpu.timebase() < deadline {
		result := mmio.read32(gem_base + 0x620c)
		if result & 0x10000 != 0 { return result & 0xffff }
	}
	return 0xffff
}

pub fn present() bool { return gem_ready }

pub fn link() bool {
	if !gem_ready { return false }
	mii(gem_phy, 1, false, 0) // BMSR link is latched low; read twice.
	status := mii(gem_phy, 1, false, 0)
	if status == 0xffff || status & 0x24 != 0x24 { return false }
	common := mii(gem_phy, 4, false, 0) & mii(gem_phy, 5, false, 0)
	duplex := if common & 0x100 != 0 || (common & 0x80 == 0 && common & 0x40 != 0) { u32(1) } else { u32(0) }
	if common & 0x1e0 == 0 { return false }
	if duplex != gem_duplex {
		mmio.write32(gem_base + 0x6030, 0)
		if !wait_clear(0x6030, 1) { return false }
		mmio.write32(gem_base + 0x603c, if duplex == 1 { u32(0x61) } else { u32(0x25) })
		mmio.write32(gem_base + 0x6030, if duplex == 1 { u32(7) } else { u32(1) })
		gem_duplex = duplex
	}
	return true
}

pub fn mac(destination &u8) {
	unsafe { for i in 0 .. 6 { destination[i] = gem_mac[i] } }
}

fn rx_descriptor(index u32) {
	desc := gem_dma + index * 16
	mmio.write32(desc, 0x88000000) // 2048-byte buffer, device ownership
	mmio.write32(desc + 4, 0)
	mmio.write32(desc + 8, gem_dma + 4096 + index * 2048)
	mmio.write32(desc + 12, 0)
}

pub fn init(info &boot.Info, mut pool pages.Pool) {
	gem_hz = info.timebase_hz
	for i := u32(0); i < info.pci_count && i < 8; i++ {
		device := info.pci[i]
		if device.class != 0x020000 || device.vendor != 0x106b || device.size < 0x9054
			|| (device.device != 0x21 && device.device != 0x24 && device.device != 0x32)
			|| !pci.enable(unsafe { &device }) { continue }
		gem_base = device.base
		mmio.write32(gem_base + 0x10, 0xffffffff)
		mmio.write32(gem_base + 0x1010, 3)
		if !wait_clear(0x1010, 3) { continue }
		gem_mac = device.mac
		mut nonzero := u32(0)
		for b in gem_mac { nonzero |= b }
		if nonzero == 0 {
			for j := u32(0); j < 3; j++ {
				value := mmio.read32(gem_base + 0x6088 - j * 4)
				gem_mac[j * 2] = u8(value >> 8)
				gem_mac[j * 2 + 1] = u8(value)
				nonzero |= value & 0xffff
			}
		}
		if nonzero == 0 || gem_mac[0] & 1 != 0 { continue }
		mmio.write32(gem_base + 0x6210, mmio.read32(gem_base + 0x6210) & ~u32(6))
		gem_phy = 32
		for phy := u32(0); phy < 32; phy++ {
			id := mii(phy, 2, false, 0)
			if id != 0 && id != 0xffff { gem_phy = phy; break }
		}
		if gem_phy == 32 { continue }
		// Advertise standard 10/100 modes. Gigabit PHY tuning is model-specific.
		if mii(gem_phy, 1, false, 0) & 0x100 != 0 {
			mii(gem_phy, 9, true, mii(gem_phy, 9, false, 0) & ~u32(0x300))
		}
		mii(gem_phy, 4, true, 0x01e1)
		mii(gem_phy, 0, true, 0x1200)
		gem_dma = pool.take(18, 1)
		if gem_dma == 0 { return }
		runtime.fill(voidptr(gem_dma), 0, 18 * 4096)
		for index := u32(0); index < 32; index++ { rx_descriptor(index) }
		mmio.publish(gem_dma, 18 * 4096)
		mmio.write32(gem_base + 0x2008, gem_dma + 2048)
		mmio.write32(gem_base + 0x200c, 0)
		mmio.write32(gem_base + 0x4004, gem_dma)
		mmio.write32(gem_base + 0x4008, 0)
		for j := u32(0); j < 3; j++ {
			mmio.write32(gem_base + 0x6088 - j * 4, u32(gem_mac[j * 2]) << 8 | gem_mac[j * 2 + 1])
		}
		mmio.write32(gem_base + 0x6040, 0)
		mmio.write32(gem_base + 0x6044, 8)
		mmio.write32(gem_base + 0x6048, 4)
		mmio.write32(gem_base + 0x604c, 64)
		mmio.write32(gem_base + 0x6050, 64)
		mmio.write32(gem_base + 0x6054, 1518)
		mmio.write32(gem_base + 0x6058, 7)
		mmio.write32(gem_base + 0x605c, 4)
		mmio.write32(gem_base + 0x6060, 16)
		mmio.write32(gem_base + 0x6064, 0x8808)
		mmio.write32(gem_base + 0x9050, 4) // MII rather than internal serial PCS
		mmio.write32(gem_base + 0x2004, 1)
		mmio.write32(gem_base + 0x4000, 1)
		mmio.write32(gem_base + 0x4100, 28)
		mmio.write32(gem_base + 0x603c, 0x61)
		mmio.write32(gem_base + 0x6030, 7)
		mmio.write32(gem_base + 0x6034, 5)
		gem_ready = true
		gem_duplex = 2
		serial.text(c'VINIX-PPC: GEM Ethernet ready\n')
		return
	}
}

pub fn send(data &u8, size u32) int {
	if !gem_ready { return -19 }
	if size < 14 || size > 1514 { return -90 }
	if !link() { return -100 }
	desc := gem_dma + 2048 + gem_tx * 16
	buffer := gem_dma + 69632
	count := if size < 60 { u32(60) } else { size }
	runtime.fill(voidptr(buffer), 0, count)
	runtime.copy(voidptr(buffer), data, size)
	mmio.publish(buffer, count)
	mmio.write32(desc, 0xc0000000 | count)
	mmio.write32(desc + 4, 0)
	mmio.write32(desc + 8, buffer)
	mmio.write32(desc + 12, 0)
	mmio.publish(desc & ~u32(31), 32)
	next := (gem_tx + 1) & 31
	mmio.write32(gem_base + 0x2000, next)
	deadline := cpu.timebase() + gem_hz / 4
	for cpu.timebase() < deadline {
		if mmio.read32(gem_base + 0x2100) & 8191 == next { gem_tx = next; return int(size) }
	}
	// Quarantine the DMA allocation if the engine fails to relinquish it.
	gem_ready = false
	mmio.write32(gem_base + 0x6030, 0)
	mmio.write32(gem_base + 0x2004, 0)
	return -110
}

pub fn receive_pending() bool {
	if !gem_ready { return false }
	desc := gem_dma + gem_rx * 16
	mmio.acquire(desc & ~u32(31), 32)
	return mmio.read32(desc) & 0x80000000 == 0
}

pub fn receive(destination &u8, capacity u32) int {
	if !gem_ready { return -19 }
	desc := gem_dma + gem_rx * 16
	mmio.acquire(desc & ~u32(31), 32)
	status := mmio.read32(desc)
	if status & 0x80000000 != 0 { return -11 }
	length := (status >> 16) & 0x7fff
	buffer := gem_dma + 4096 + gem_rx * 2048
	mut result := -90
	if length >= 14 && length <= 1514 && length <= capacity && mmio.read32(desc + 4) & 0x40000000 == 0 {
		mmio.acquire(buffer, 2048)
		runtime.copy(destination, voidptr(buffer), length)
		result = int(length)
	}
	gem_rx = (gem_rx + 1) & 31
	// Hardware prefetches four descriptors. Recycle only complete groups,
	// so a cache-line flush never overwrites a neighbouring DMA completion.
	if gem_rx & 3 == 0 {
		first := (gem_rx + 28) & 31
		for i := first; i < first + 4; i++ { rx_descriptor(i) }
		mmio.publish(gem_dma + first * 16, 64)
		mmio.write32(gem_base + 0x4100, first)
	}
	return result
}
