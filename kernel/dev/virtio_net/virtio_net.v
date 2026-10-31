// A polling, legacy split-ring virtio-net driver. Architecture files contain
// the register transport only: ARM MMIO v1 and x86 transitional PCI port I/O.
@[has_globals]
module virtio_net

import dma
import katomic
import klock
import socket.inet

const feature_mac = u32(1) << 5
const feature_any_layout = u32(1) << 27
const status_driver_ok = u8(7)

struct Queue {
mut:
	index          u16
	size           u16
	ring           dma.Buffer
	buffers        dma.Buffer
	desc           u64
	avail          u64
	used           u64
	last_used      u16
	next_available u16
	free           [1024]bool // bounded by max_queue_size, including legacy PCI rings
}

__global (
	rx_queue         Queue
	tx_queue         Queue
	mac_address      [6]u8
	virtio_net_ready bool
	rx_lock          klock.Lock
	tx_lock          klock.Lock
)

fn setup_queue(index u16, receive bool) ?Queue {
	size := queue_size(transport_queue_max(index), transport_is_pci())
	if size == 0 { return none }
	ring := alloc_dma(ring_bytes(size)) or { return none }
	if !legacy_dma_ring(ring.bus, ring.bytes, transport_page_size()) {
		free_dma(ring)
		return none
	}
	buffers := alloc_dma(u64(size) * buffer_size) or {
		free_dma(ring)
		return none
	}
	mut queue := Queue{
		index:   index
		size:    size
		ring:    ring
		buffers: buffers
		desc:    ring.virt
		avail:   ring.virt + u64(size) * 16
		used:    ring.virt + used_offset(size)
	}
	// VIRTQ_AVAIL_F_NO_INTERRUPT; EVENT_IDX is deliberately not negotiated.
	unsafe {
		*&u16(queue.avail) = 1
	}
	for i := u16(0); i < size; i++ {
		descriptor := queue.desc + u64(i) * 16
		unsafe {
			*&u64(descriptor) = buffers.bus + u64(i) * buffer_size
			*&u32(descriptor + 8) = if receive { u32(buffer_size) } else { 0 }
			*&u16(descriptor + 12) = if receive { u16(2) } else { u16(0) }
			*&u16(descriptor + 14) = 0
		}
		queue.free[i] = !receive
		if receive {
			unsafe {
				*&u16(queue.avail + 4 + u64(i) * 2) = i
			}
		}
	}
	if receive {
		queue.next_available = size
		unsafe {
			*&u16(queue.avail + 2) = size
		}
	}
	return queue
}

fn free_queues() {
	free_dma(rx_queue.buffers)
	free_dma(rx_queue.ring)
	free_dma(tx_queue.buffers)
	free_dma(tx_queue.ring)
	rx_queue = Queue{}
	tx_queue = Queue{}
}

// TX lock only. Read the producer index before the acquire DMA barrier:
// seeing a new index makes the used entries and received bytes readable.
fn reap_tx() {
	used_index := dma_read16(tx_queue.used + 2)
	dma_barrier()
	count := completion_count(tx_queue.last_used, used_index, tx_queue.size)
	for _ in 0 .. int(count) {
		position := u64(tx_queue.last_used % tx_queue.size)
		id := dma_read32(tx_queue.used + 4 + position * 8)
		if id < u32(tx_queue.size) { tx_queue.free[id] = true }
		tx_queue.last_used++
	}
}

@[export: 'vinix_virtio_net_send']
pub fn send(frame voidptr, length u64) int {
	if !katomic.load(&virtio_net_ready) || frame == unsafe { nil } || length == 0
		|| length > buffer_size - net_header_size {
		return -1
	}
	// send may be entered synchronously by receive()/attach() under net_lock.
	// No TX holder enters the stack or takes rx_lock.
	tx_lock.acquire()
	defer { tx_lock.release() }
	if !katomic.load(&virtio_net_ready) { return -1 }
	reap_tx()
	mut id := -1
	for i := 0; i < int(tx_queue.size); i++ {
		if tx_queue.free[i] {
			id = i
			break
		}
	}
	if id < 0 { return -1 }
	tx_queue.free[id] = false
	buffer := tx_queue.buffers.virt + u64(id) * buffer_size
	unsafe {
		C.memset(voidptr(buffer), 0, net_header_size)
		C.memcpy(voidptr(buffer + net_header_size), frame, length)
		*&u32(tx_queue.desc + u64(id) * 16 + 8) = u32(length + net_header_size)
		*&u16(tx_queue.avail + 4 + u64(tx_queue.next_available % tx_queue.size) * 2) = u16(id)
	}
	tx_queue.next_available++
	dma_barrier()
	unsafe {
		*&u16(tx_queue.avail + 2) = tx_queue.next_available
	}
	dma_barrier()
	transport_notify(1)
	return 0
}

// Caller has found/reset the transport. No queue is exposed to DMA until BOTH
// allocations succeed. All failure paths reset before freeing active rings.
fn start() bool {
	if !transport_reset() { return false }
	transport_status(1)
	transport_status(3)
	offered := transport_features()
	// Each descriptor contains the header and frame together. Legacy drivers
	// must negotiate ANY_LAYOUT for this, or use separate header descriptors.
	if offered & feature_any_layout == 0 { return false }
	accepted := offered & (feature_mac | feature_any_layout)
	transport_accept(accepted)
	if accepted & feature_mac != 0 {
		for i in 0 .. 6 {
			mac_address[i] = transport_mac(u64(i))
		}
	} else {
		mac_address = [u8(0x52), 0x54, 0x00, 0x12, 0x34, 0x56]!
	}
	rx_queue = setup_queue(0, true) or { return false }
	tx_queue = setup_queue(1, false) or {
		free_queues()
		return false
	}
	dma_barrier()
	transport_queue_install(0, rx_queue.size, rx_queue.ring.bus)
	transport_queue_install(1, tx_queue.size, tx_queue.ring.bus)
	transport_status(status_driver_ok)
	// DHCP transmits from attach(), so TX must already be usable. Do not
	// hold either queue lock across attachment. Preserve any existing owner.
	katomic.store(mut &virtio_net_ready, true)
	if !inet.attach_if_idle(&mac_address, inet.driver_virtio) {
		stop()
		return false
	}
	transport_notify(0)
	C.kprintf(c'virtio-net: ready, DHCP requested\n')
	return true
}

// Fence readers first, then stop DMA. Called in task context, never send().
fn stop() {
	katomic.store(mut &virtio_net_ready, false)
	rx_lock.acquire()
	tx_lock.acquire()
	reset := transport_reset()
	dma_disabled := transport_disable()
	// devcore releases a PCI driver's DMA domain after removal/probe failure.
	// Do not return to that cleanup if neither stop mechanism can be verified.
	if transport_is_pci() && !reset && !dma_disabled {
		panic('virtio-net: device cannot be stopped safely')
	}
	tx_lock.release()
	rx_lock.release()
}

pub fn poll() {
	if !katomic.load(&virtio_net_ready) { return }
	// Timer/idle callbacks must skip a busy TX ring, never wait on send().
	if tx_lock.test_and_acquire() {
		if katomic.load(&virtio_net_ready) { reap_tx() }
		tx_lock.release()
	}
	if !rx_lock.test_and_acquire() { return }
	defer { rx_lock.release() }
	if !katomic.load(&virtio_net_ready) { return }
	used_index := dma_read16(rx_queue.used + 2)
	dma_barrier()
	count := completion_count(rx_queue.last_used, used_index, rx_queue.size)
	mut available := rx_queue.next_available
	// A descriptor can only complete once before this batch is published.
	mut seen := [1024]bool{}
	for _ in 0 .. int(count) {
		entry := rx_queue.used + 4 + u64(rx_queue.last_used % rx_queue.size) * 8
		id := dma_read32(entry)
		length := dma_read32(entry + 4)
		rx_queue.last_used++
		// Never truncate/repost a malformed ID, including duplicate completions.
		if id >= u32(rx_queue.size) {
			continue
		}
		if seen[id] {
			continue
		}
		seen[id] = true
		if valid_rx(id, rx_queue.size, length) {
			inet.receive_owned(inet.driver_virtio, voidptr(rx_queue.buffers.virt +
				u64(id) * buffer_size + net_header_size), u64(length) - net_header_size)
		}
		unsafe {
			*&u16(rx_queue.avail + 4 + u64(available % rx_queue.size) * 2) = u16(id)
		}
		available++
	}
	if available != rx_queue.next_available {
		rx_queue.next_available = available
		dma_barrier()
		unsafe {
			*&u16(rx_queue.avail + 2) = available
		}
		dma_barrier()
		transport_notify(0)
	}
	transport_ack()
}
