module virtio_net

import aarch64.cpu
import aarch64.kio
import dma
import memory

__global device_base u64

fn rd(offset u64) u32 {
	return kio.mmin32(unsafe { &u32(device_base + offset) })
}

fn wr(offset u64, value u32) {
	kio.mmout32(unsafe { &u32(device_base + offset) }, value)
}

fn dma_barrier() {
	cpu.dmb_sy()
}

fn dma_read16(address u64) u16 {
	return kio.mmin[u16](unsafe { &u16(address) })
}

fn dma_read32(address u64) u32 {
	return kio.mmin32(unsafe { &u32(address) })
}

fn transport_is_pci() bool {
	return false
}

fn transport_page_size() u64 {
	return memory.page_size
}

fn alloc_dma(bytes u64) ?dma.Buffer {
	pages := (bytes + memory.page_size - 1) / memory.page_size
	phys := u64(memory.pmm_alloc_fallible(pages))
	if phys == 0 { return none }
	return dma.Buffer{
		virt:  phys + memory.get_hhdm_offset()
		bus:   phys
		bytes: bytes
	}
}

fn free_dma(buffer dma.Buffer) {
	if buffer.bus != 0 {
		memory.pmm_free(voidptr(buffer.bus),
			(buffer.bytes + memory.page_size - 1) / memory.page_size)
	}
}

fn transport_reset() bool {
	wr(0x070, 0)
	for _ in 0 .. 10000 {
		if rd(0x070) == 0 { return true }
	}
	return false
}

fn transport_disable() bool { return false }

fn transport_status(value u8) {
	wr(0x070, value)
}

fn transport_features() u32 {
	wr(0x014, 0)
	return rd(0x010)
}

fn transport_accept(value u32) {
	wr(0x024, 0)
	wr(0x020, value)
	wr(0x028, u32(memory.page_size))
}

fn transport_mac(index u64) u8 {
	return kio.mmin[u8](unsafe { &u8(device_base + 0x100 + index) })
}

fn transport_queue_max(index u16) u32 {
	wr(0x030, index)
	return rd(0x034)
}

fn transport_queue_install(index u16, size u16, address u64) {
	wr(0x030, index)
	wr(0x038, size)
	wr(0x03c, u32(queue_align))
	wr(0x040, legacy_pfn(address, transport_page_size()))
}

fn transport_notify(index u16) {
	wr(0x050, index)
}

fn transport_ack() {
	pending := rd(0x060)
	if pending != 0 { wr(0x064, pending) }
}

pub fn initialise(hhdm u64) {
	if device_base != 0 { return }
	for slot := u64(0); slot < 32; slot++ {
		// Match the existing QEMU virt legacy MMIO aperture. Device mappings
		// prevent speculative/combined accesses to transport registers.
		base := memory.map_mmio(0x0a000000 + slot * 0x200, 0x200)
		if base == 0 {
			continue
		}
		device_base = base
		if rd(0) != 0x74726976 || rd(8) != 1 || rd(4) != 1 {
			device_base = 0
			continue
		}
		if !start() {
			// If reset does not complete, keep the pages quarantined rather
			// than returning memory that the device might still be reading.
			if transport_reset() { free_queues() }
			C.kprintf(c'virtio-net: MMIO initialisation failed\n')
		}
		return
	}
	_ = hhdm
}
