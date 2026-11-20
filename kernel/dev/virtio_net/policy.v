// Pure legacy split-ring/probe decisions, also compiled by the host fixture.
module virtio_net

const max_queue_size = u16(1024)
const wanted_queue_size = u16(64)
const queue_align = u64(4096)
const buffer_size = u64(2048)
const net_header_size = u64(10)

fn legacy_pci_net(vendor u16, device u16, revision u8, header u8) bool {
	return vendor == 0x1af4 && device == 0x1000 && revision == 0 && header == 0
}

fn legacy_io_bar(base u64, size u64, mmio bool) bool {
	return !mmio && base != 0 && base <= 0xffff && size >= 26 && size <= 0x10000 - base
}

fn queue_size(maximum u32, is_pci bool) u16 {
	if maximum == 0 || maximum > 32768 || maximum & (maximum - 1) != 0 {
		return 0
	}
	// Legacy PCI has NO queue-size setter. Never lay out a smaller ring.
	if is_pci {
		return if maximum <= max_queue_size { u16(maximum) } else { u16(0) }
	}
	return if maximum < wanted_queue_size { u16(maximum) } else { wanted_queue_size }
}

fn used_offset(size u16) u64 {
	avail_end := u64(size) * 16 + 4 + 2 * u64(size) + 2
	return (avail_end + queue_align - 1) & ~(queue_align - 1)
}

fn ring_bytes(size u16) u64 {
	return used_offset(size) + 4 + 8 * u64(size) + 2
}

fn legacy_dma_ring(address u64, bytes u64, page_bytes u64) bool {
	if page_bytes < 4096 || page_bytes > 65536 || page_bytes & (page_bytes - 1) != 0 {
		return false
	}
	// PCI fixes the PFN unit at 4 KiB (44 address bits). Legacy MMIO uses
	// GuestPageSize, which is 16 KiB in this kernel's ARM configuration.
	limit := page_bytes << 32
	return address != 0 && address & (page_bytes - 1) == 0 && address < limit && bytes != 0
		&& bytes <= limit - address
}

fn legacy_pfn(address u64, page_bytes u64) u32 {
	return u32(address / page_bytes)
}

fn completion_count(last u16, current u16, size u16) u16 {
	count := u16(current - last)
	return if count <= size { count } else { u16(0) }
}

fn valid_rx(id u32, size u16, length u32) bool {
	return id < u32(size) && length >= net_header_size + 14 && length <= buffer_size
}
