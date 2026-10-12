// SPDX-License-Identifier: GPL-2.0-or-later
// Polled RTL8168G/GU / RTL8111G/GU Ethernet, including the ThinkPad E470.
// One interface, software checksums, 1500-byte MTU, no interrupt dependency.
@[has_globals]
module rtl8169

import devcore
import dma
import klock
import socket.inet

__global (
	rtl_regs              u64
	rtl_ready             bool
	rtl_device            &devcore.Device = unsafe { nil }
	rtl_mac               [6]u8
	rtl_rx_ring           dma.Buffer
	rtl_rx_buffers        dma.Buffer
	rtl_tx_ring           dma.Buffer
	rtl_tx_buffers        dma.Buffer
	rtl_rx_next           u32
	rtl_tx_next           u32
	rtl_tx_clean          u32
	rtl_tx_pending        u32
	rtl_tx_kick           u64
	rtl_rx_lock           klock.Lock
	rtl_tx_lock           klock.Lock
	rtl_link              bool
	rtl_link_sample       u64
	rtl_tx_queued         u64
	rtl_tx_completed      u64
	rtl_rx_packets        u64
	rtl_rx_dropped        u64
	rtl_interrupt_errors  u16
	rtl_diagnostic_sample u64
)

fn pause_ms(ms u64) { devcore.sleep_ms(ms) }

fn wait_phy_reset() bool {
	limit := devcore.deadline(600 * devcore.millisecond)
	for {
		control := phy_read(0) or { return false }
		if control & 0x8000 == 0 { return true }
		if limit.expired() { return false }
		pause_ms(10)
	}
}

fn wait32(port u64, mask u32, set bool) bool {
	limit := devcore.deadline(10 * devcore.millisecond)
	for {
		value := read32(port)
		if value != 0xffffffff && (value & mask != 0) == set { return true }
		if limit.expired() { return false }
		devcore.stall(10 * devcore.microsecond)
	}
}

fn wait8(port u64, mask u8, set bool) bool {
	limit := devcore.deadline(200 * devcore.millisecond)
	for {
		value := read8(port)
		if value != 0xff && (value & mask != 0) == set { return true }
		if limit.expired() { return false }
		devcore.stall(10 * devcore.microsecond)
	}
}

fn card_matches(dev &devcore.Device) bool {
	return dev.bus == .pci && dev.vendor == 0x10ec && dev.device == 0x8168
}

pub fn initialise() {
	devcore.register_driver(devcore.Driver{
		name:     'rtl8169'
		bus:      .pci
		matches:  card_matches
		probe:    card_probe
		remove:   card_remove
		suspend:  card_suspend
		resume:   card_resume
		shutdown: card_shutdown
		reset:    card_reset
	}) or {}
}

fn card_probe(mut dev devcore.Device) bool {
	if rtl_device != unsafe { nil } { return false }
	mut other_mac := [6]u8{}
	mut mtu := u32(0)
	if inet.link_info(unsafe { &other_mac }, unsafe { &mtu }) { return false }
	// Firmware can leave the NIC in D3hot even on a cold boot.
	pm := dev.pci.capability(1)
	if pm != 0 {
		control := dev.pci.read[u16](u32(pm) + 4)
		if control & 3 != 0 {
			dev.pci.write[u16](u32(pm) + 4, control & ~u16(0x8103))
			pause_ms(10)
		}
	}
	command := dev.pci.read[u16](4)
	dev.pci.update_command(7, u16(1) << 10)
	mut base := u64(0)
	mut span := u64(0)
	for index in [u8(2), 1, 0]! {
		bar := dev.pci.get_bar(index)
		if bar.is_mmio && bar.base != 0 && bar.size >= 256 {
			base = bar.base
			span = bar.size
			break
		}
	}
	if base == 0 {
		print('rtl8169: no usable memory BAR\n')
		return false
	}
	rtl_regs = map_registers(base, span)
	if rtl_regs == 0 {
		print('rtl8169: register mapping failed\n')
		return false
	}
	dev.pci.write[u16](4, (command & ~u16(5)) | 2 | (u16(1) << 10))
	config := read32(0x40)
	rtl_version = chip_version(config)
	C.kprintf(c'rtl8169: PCI %llx:%llx.%llx 10ec:8168, TxConfig=%08llx, MAC version %d\n',
		u64(dev.pci.bus), u64(dev.pci.slot), u64(dev.pci.function), u64(config), rtl_version)
	if rtl_version == 0 {
		print('rtl8169: unsupported silicon revision; leaving it unbound\n')
		return false
	}
	pcie := dev.pci.capability(0x10)
	if pcie != 0 {
		link := dev.pci.read[u16](u32(pcie) + 0x10)
		dev.pci.write[u16](u32(pcie) + 0x10, link & ~u16(0x103))
	}
	// G/GU store the permanent station address in EXGMAC as well as MAC0.
	low := eri_read(0xe0) or { u32(0) }
	high := eri_read(0xe4) or { u32(0) }
	if low != 0 || high & 0xffff != 0 {
		for i in 0 .. 4 { rtl_mac[i] = u8(low >> (8 * i)) }
		rtl_mac[4] = u8(high)
		rtl_mac[5] = u8(high >> 8)
	} else {
		for i in 0 .. 6 { rtl_mac[i] = read8(u64(i)) }
	}
	if rtl_mac[0] & 1 != 0 || !valid_station_address() {
		print('rtl8169: invalid station address\n')
		return false
	}
	if !allocate_rings(mut dev) {
		print('rtl8169: DMA allocation failed\n')
		free_rings(mut dev)
		return false
	}
	if !hardware_start() {
		print('rtl8169: startup failed (reset, OOB, PHY or ERI timeout)\n')
		hardware_stop(mut dev)
		free_rings(mut dev)
		return false
	}
	hardware_enable(mut dev)
	rtl_device = unsafe { dev }
	rtl_link = read8(0x6c) != 0xff && read8(0x6c) & 2 != 0
	rtl_link_sample = devcore.now_ns()
	rtl_tx_queued = 0
	rtl_tx_completed = 0
	rtl_rx_packets = 0
	rtl_rx_dropped = 0
	rtl_interrupt_errors = 0
	rtl_diagnostic_sample = rtl_link_sample
	rtl_ready = true
	if !inet.attach(&rtl_mac, inet.driver_rtl8169) {
		fence()
		hardware_stop(mut dev)
		free_rings(mut dev)
		rtl_device = unsafe { nil }
		print('rtl8169: IP stack attach failed\n')
		return false
	}
	inet.set_link(inet.driver_rtl8169, rtl_link)
	C.kprintf(c'rtl8169: MAC %02llx:%02llx:%02llx:%02llx:%02llx:%02llx, link %s; %s\n',
		u64(rtl_mac[0]), u64(rtl_mac[1]), u64(rtl_mac[2]), u64(rtl_mac[3]), u64(rtl_mac[4]), u64(rtl_mac[5]),
		if rtl_link { c'up' } else { c'down' }, if rtl_link {
			c'DHCP requested'
		} else {
			c'waiting for carrier before DHCP'
		})
	return true
}

fn valid_station_address() bool {
	for byte in rtl_mac { if byte != 0 { return true } }
	return false
}

fn allocate_rings(mut dev devcore.Device) bool {
	rtl_rx_ring = dma.alloc_buffer(mut dev, u64(descriptors) * 16) or { return false }
	rtl_rx_buffers = dma.alloc_buffer(mut dev, u64(descriptors) * buffer_bytes) or { return false }
	rtl_tx_ring = dma.alloc_buffer(mut dev, u64(descriptors) * 16) or { return false }
	rtl_tx_buffers = dma.alloc_buffer(mut dev, u64(descriptors) * buffer_bytes) or { return false }
	return true
}

fn free_rings(mut dev devcore.Device) {
	dma.free_buffer(mut dev, rtl_rx_ring)
	dma.free_buffer(mut dev, rtl_rx_buffers)
	dma.free_buffer(mut dev, rtl_tx_ring)
	dma.free_buffer(mut dev, rtl_tx_buffers)
	rtl_rx_ring = dma.Buffer{}
	rtl_rx_buffers = dma.Buffer{}
	rtl_tx_ring = dma.Buffer{}
	rtl_tx_buffers = dma.Buffer{}
}

fn hardware_start() bool {
	write16(0x3c, 0)
	if !leave_oob() {
		print('rtl8169: OOB FIFO handoff timed out\n')
		return false
	}
	write8(0x37, 0x10)
	if !wait8(0x37, 0x10, false) {
		print('rtl8169: reset timed out\n')
		return false
	}
	write16(0x3c, 0)
	write16(0x3e, 0xffff)
	write8(0x50, 0xc0)
	defer { write8(0x50, 0) }
	write8(0x6f, read8(0x6f) | 0xc0)
	if !configure_mac() {
		print('rtl8169: MAC/EPHY setup timed out\n')
		return false
	}
	if !configure_phy() {
		print('rtl8169: PHY/firmware setup failed\n')
		return false
	}
	// Restore the factory MAC; reset does not imply firmware restored it.
	low := u32(rtl_mac[0]) | u32(rtl_mac[1]) << 8 | u32(rtl_mac[2]) << 16 | u32(rtl_mac[3]) << 24
	high := u32(rtl_mac[4]) | u32(rtl_mac[5]) << 8
	write32(4, high)
	_ := read8(0x37) // flush posted PCI writes before the next station word
	write32(0, low)
	_ := read8(0x37)
	if read32(0) != low || read16(4) != u16(high) {
		print('rtl8169: station-address setup failed\n')
		return false
	}
	write32(8, 0xffffffff)
	write32(12, 0xffffffff)
	// Preserve the chip's normal-mode/timer bits; disable checksum and VLAN
	// offload without clearing the entire inherited C+ command register.
	write16(0xe0, read16(0xe0) & 0x2003)
	write16(0xe2, 0) // interrupt mitigation off (we poll)
	write8(0xec, 0x27)
	write16(0xda, u16(buffer_bytes))
	initialise_rings()
	write32(0x24, u32(rtl_tx_ring.bus >> 32))
	write32(0x20, u32(rtl_tx_ring.bus))
	write32(0xe8, u32(rtl_rx_ring.bus >> 32))
	write32(0xe4, u32(rtl_rx_ring.bus))
	dma_barrier()
	return true
}

fn hardware_enable(mut dev devcore.Device) {
	// All DMA addresses are programmed before mastering is allowed. Permit
	// mastering before enabling RX/TX, so their first descriptor fetch can
	// succeed on physical PCIe controllers.
	dev.pci.update_command(0, 4)
	_ := dev.pci.read[u16](4)
	write8(0x37, 0x0c)
	write32(0x40, (u32(3) << 24) | (u32(7) << 8) | 0x80)
	write32(0x44, 0xc800 | (u32(7) << 8) | 0x0e)
	_ := read8(0x37)
}

fn initialise_rings() {
	unsafe {
		C.memset(voidptr(rtl_rx_ring.virt), 0, rtl_rx_ring.bytes)
		C.memset(voidptr(rtl_tx_ring.virt), 0, rtl_tx_ring.bytes)
		for index := u32(0); index < descriptors; index++ {
			rx := rtl_rx_ring.virt + u64(index) * 16
			tx := rtl_tx_ring.virt + u64(index) * 16
			*&u64(rx + 8) = rtl_rx_buffers.bus + u64(index) * buffer_bytes
			*&u32(rx) = desc_owned | ring_end(index) | u32(buffer_bytes)
			*&u64(tx + 8) = rtl_tx_buffers.bus + u64(index) * buffer_bytes
			*&u32(tx) = ring_end(index)
		}
	}
	rtl_rx_next = 0
	rtl_tx_next = 0
	rtl_tx_clean = 0
	rtl_tx_pending = 0
	rtl_tx_kick = 0
	dma_barrier()
}

// Disable bus mastering even if reset fails, before any DMA memory is freed.
fn hardware_stop(mut dev devcore.Device) {
	write16(0x3c, 0)
	write8(0x37, 0x10)
	_ := wait8(0x37, 0x10, false)
	dev.pci.update_command(4, 0)
	dma_barrier()
}

fn fence() {
	rtl_ready = false
	rtl_rx_lock.acquire()
	rtl_rx_lock.release()
	rtl_tx_lock.acquire()
	rtl_tx_lock.release()
	rtl_link = false
	inet.set_link(inet.driver_rtl8169, false)
}

fn card_remove(mut dev devcore.Device) {
	fence()
	inet.detach_owned(inet.driver_rtl8169)
	hardware_stop(mut dev)
	free_rings(mut dev)
	rtl_device = unsafe { nil }
}

fn card_shutdown(mut dev devcore.Device) {
	fence()
	hardware_stop(mut dev)
}

fn card_suspend(mut dev devcore.Device) bool {
	fence()
	hardware_stop(mut dev)
	return true
}

fn card_resume(mut dev devcore.Device) bool {
	dev.pci.update_command(5, 2 | (u16(1) << 10))
	if !hardware_start() {
		hardware_stop(mut dev)
		return false
	}
	hardware_enable(mut dev)
	rtl_link = read8(0x6c) != 0xff && read8(0x6c) & 2 != 0
	rtl_link_sample = devcore.now_ns()
	rtl_ready = true
	inet.set_link(inet.driver_rtl8169, rtl_link)
	return true
}

fn card_reset(mut dev devcore.Device) bool {
	fence()
	hardware_stop(mut dev)
	return card_resume(mut dev)
}

fn reclaim_tx() {
	for rtl_tx_pending > 0 {
		if descriptor_status(rtl_tx_ring.virt + u64(rtl_tx_clean) * 16) & desc_owned != 0 { break }
		dma_barrier()
		rtl_tx_clean = (rtl_tx_clean + 1) % descriptors
		rtl_tx_pending--
		rtl_tx_completed++
	}
}

@[export: 'vinix_rtl8169_send']
pub fn send(frame voidptr, length u64) int {
	if !rtl_ready || !rtl_link || frame == unsafe { nil } || length < 14 || length > 1518 {
		return -1
	}
	rtl_tx_lock.acquire()
	defer { rtl_tx_lock.release() }
	if !rtl_ready || !rtl_link { return -1 }
	reclaim_tx()
	if rtl_tx_pending == descriptors { return -1 }
	index := rtl_tx_next
	descriptor := rtl_tx_ring.virt + u64(index) * 16
	buffer := rtl_tx_buffers.virt + u64(index) * buffer_bytes
	// Hardware pads too, but an explicit minimum keeps stale DMA bytes out
	// of short Ethernet frames on revisions with padding quirks.
	padded := if length < 60 { u64(60) } else { length }
	unsafe {
		C.memcpy(voidptr(buffer), frame, length)
		if padded > length { C.memset(voidptr(buffer + length), 0, padded - length) }
		*&u32(descriptor + 4) = 0
	}
	dma_barrier()
	set_descriptor_status(descriptor, desc_owned | desc_first | desc_last | ring_end(index) | u32(padded))
	dma_barrier()
	rtl_tx_pending++
	rtl_tx_queued++
	rtl_tx_next = (index + 1) % descriptors
	write8(0x38, 0x40)
	rtl_tx_kick = devcore.now_ns()
	return 0
}

pub fn poll() {
	if !rtl_ready || !rtl_rx_lock.test_and_acquire() { return }
	defer { rtl_rx_lock.release() }
	if !rtl_ready { return }
	now := devcore.now_ns()
	if now - rtl_link_sample >= 100 * devcore.millisecond {
		rtl_link_sample = now
		status := read8(0x6c)
		link := status != 0xff && status & 2 != 0
		if link != rtl_link {
			rtl_link = link
			// Publish carrier before DHCP's synchronous transmit callback.
			inet.set_link(inet.driver_rtl8169, link)
			C.kprintf(c'rtl8169: link %s, PHY status=%02llx\n', if link { c'up' } else { c'down' }, u64(status))
			if link { write8(0x38, 0x40) }
		}
		// Wi-Fi explicitly selects the shared physical stack on join. Once it
		// detaches, restore this live wired adapter without stealing Wi-Fi.
		if link {
			if inet.attach_if_idle(unsafe { &rtl_mac }, inet.driver_rtl8169) { inet.set_link(inet.driver_rtl8169, true) }
		}
	}
	// RTL8168 can lose TxPoll requests when packets are queued close together
	// (r8169's completion path kicks the remaining burst again). Poll owns
	// reclamation too, so DHCP cannot leave an owned descriptor stranded until
	// another send. Never release a buffer while the device still owns it.
	if rtl_tx_lock.test_and_acquire() {
		completed := rtl_tx_completed
		reclaim_tx()
		if rtl_tx_pending != 0 && rtl_link
			&& (rtl_tx_completed != completed
				|| (now >= rtl_tx_kick && now - rtl_tx_kick >= devcore.millisecond)) {
			dma_barrier()
			write8(0x38, 0x40)
			rtl_tx_kick = now
		}
		rtl_tx_lock.release()
	}
	// Ring addresses are only read under the lock: remove waits before free.
	for drained := u32(0); drained < descriptors; drained++ {
		index := rtl_rx_next
		descriptor := rtl_rx_ring.virt + u64(index) * 16
		status := descriptor_status(descriptor)
		if status & desc_owned != 0 { break }
		dma_barrier()
		length := received_length(status)
		if length != 0 {
			if inet.receive_owned(inet.driver_rtl8169, voidptr(rtl_rx_buffers.virt + u64(index) * buffer_bytes), length) {
				rtl_rx_packets++
			} else {
				rtl_rx_dropped++
			}
		} else {
			rtl_rx_dropped++
		}
		unsafe { *&u32(descriptor + 4) = 0 }
		dma_barrier()
		set_descriptor_status(descriptor, desc_owned | ring_end(index) | u32(buffer_bytes))
		rtl_rx_next = (index + 1) % descriptors
	}
	rtl_interrupt_errors |= read16(0x3e) & 0x805a
	write16(0x3e, 0xffff)
	if now - rtl_diagnostic_sample >= 5 * devcore.second {
		rtl_diagnostic_sample = now
		diagnose_lease()
	}
}

fn diagnose_lease() {
	// No DHCP exchange can begin until carrier appears. The startup and
	// link-change messages already describe this condition.
	if !rtl_link { return }
	mut address := u32(0)
	mut netmask := u32(0)
	mut gateway := u32(0)
	mut dns := [3]u32{}
	if inet.configuration(unsafe { &address }, unsafe { &netmask }, unsafe { &gateway }, unsafe { &dns }) {
		return
	}
	if !rtl_tx_lock.test_and_acquire() { return }
	reclaim_tx()
	queued := rtl_tx_queued
	completed := rtl_tx_completed
	pending := rtl_tx_pending
	mut oldest := u32(0)
	if pending != 0 { oldest = descriptor_status(rtl_tx_ring.virt + u64(rtl_tx_clean) * 16) }
	rtl_tx_lock.release()
	C.kprintf(c'rtl8169: awaiting DHCP: PHY=%02llx CMD=%02llx errors=%04llx TX queued=%llu completed=%llu pending=%llu oldest=%08llx RX packets=%llu dropped=%llu next=%08llx\n',
		u64(read8(0x6c)), u64(read8(0x37)), u64(rtl_interrupt_errors), queued, completed, u64(pending), u64(oldest),
		rtl_rx_packets, rtl_rx_dropped, u64(descriptor_status(rtl_rx_ring.virt + u64(rtl_rx_next) * 16)))
}
