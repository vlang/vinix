// In-memory transport for the production queue engine.
@[has_globals]
module virtio_net

import dma

__global (
	allocations      int
	live_allocations int
	fail_allocation  int
	bad_ring_bus     u64
	pci_legacy       = true
	offer_any_layout = true
	queue_max        = u32(256)
	installed        [2]u16
	installed_count  int
	notifications    [2]int
	reset_count      int
	reset_succeeds   = true
	disabled         bool
	device_status    u8
	barriers         int
)

fn C.kprintf(format &char) int

@[export: 'kprintf']
fn quiet(format &char) int {
	_ = format
	return 0
}

fn dma_barrier() {
	barriers++
}

fn dma_read16(address u64) u16 {
	return unsafe { *&u16(address) }
}

fn dma_read32(address u64) u32 {
	return unsafe { *&u32(address) }
}

fn transport_is_pci() bool {
	return pci_legacy
}

fn transport_page_size() u64 {
	return if pci_legacy { u64(4096) } else { u64(16384) }
}

fn alloc_dma(bytes u64) ?dma.Buffer {
	allocations++
	if allocations == fail_allocation { return none }
	ptr := unsafe { malloc(int(bytes)) }
	unsafe { C.memset(ptr, 0, bytes) }
	live_allocations++
	return dma.Buffer{
		virt:  u64(ptr)
		bus:   if allocations == 1 && bad_ring_bus != 0 {
			bad_ring_bus
		} else {
			0x100000 + u64(allocations) * 0x400000
		}
		bytes: bytes
	}
}

fn free_dma(buffer dma.Buffer) {
	if buffer.bus != 0 {
		unsafe { free(voidptr(buffer.virt)) }
		live_allocations--
	}
}

fn transport_reset() bool {
	reset_count++
	if !reset_succeeds { return false }
	device_status = 0
	return true
}

fn transport_disable() bool {
	disabled = true
	return true
}

fn transport_status(value u8) {
	device_status = value
}

fn transport_features() u32 {
	return (u32(1) << 5) | if offer_any_layout {
		u32(1) << 27
	} else {
		u32(0)
	}
}

fn transport_accept(value u32) {
	assert value == (u32(1) << 5) | (u32(1) << 27)
}

fn transport_mac(index u64) u8 {
	return u8(index + 2)
}

fn transport_queue_max(index u16) u32 {
	_ = index
	return queue_max
}

fn transport_queue_install(index u16, size u16, address u64) {
	assert live_allocations == 4 && barriers > 0
	assert legacy_dma_ring(address, ring_bytes(size), transport_page_size())
	installed[index] = size
	installed_count++
}

fn transport_notify(index u16) {
	notifications[index]++
}

fn transport_ack() {}
