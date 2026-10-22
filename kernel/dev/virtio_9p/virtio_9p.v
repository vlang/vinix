// SPDX-License-Identifier: GPL-2.0-or-later
// One synchronous mount session, one outstanding descriptor chain, polling.
// No request memory is released until device reset is acknowledged. If reset
// fails, the global Channel and all its DMA mappings remain quarantined for
// the rest of this boot, and reconnect is refused. Disabling bus mastering is
// only containment, never used as proof that in-flight DMA has stopped.
@[has_globals]
module virtio_9p

import devcore
import dma
import klock

pub struct Channel {
pub mut:
	tx &u8 = unsafe { nil }
	rx &u8 = unsafe { nil }
mut:
	device       &devcore.Device = unsafe { nil }
	io           u16
	base         u64
	config_bytes u64
	ring         dma.Buffer
	buffers      dma.Buffer
	size         u16
	avail        u64
	used         u64
	produced     u16
	consumed     u16
	ready        bool
	quarantined  bool
	installed    bool
	lock         klock.Lock
}

__global (
	ninep_session    Channel
	ninep_claim_lock klock.Lock
	ninep_claimed    bool
)

pub fn connect(tag string) ?&Channel {
	if tag.len == 0 || tag.len > 255 { return none }
	for c in tag { if c == 0 || c == `/` { return none } }
	ninep_claim_lock.acquire()
	defer { ninep_claim_lock.release() }
	if ninep_claimed || ninep_session.quarantined { return none }
	ninep_claimed = true
	if !ninep_session.locate(tag) {
		ninep_claimed = false
		return none
	}
	if !ninep_session.start() {
		ninep_session.stop_locked()
		if !ninep_session.quarantined { ninep_claimed = false }
		return none
	}
	return unsafe { &ninep_session }
}

fn (mut ch Channel) start() bool {
	if !ch.reset() {
		ch.quarantined = true
		ch.disable()
		return false
	}
	ch.set_status(1)
	ch.set_status(3)
	if ch.features() & 1 == 0 { return false }
	// Only mount tag. In particular, EVENT_IDX and INDIRECT_DESC are off.
	ch.accept(1)
	ch.size = queue_size(ch.queue_max())
	if ch.size == 0 { return false }
	ch.ring = ch.alloc_dma(ring_bytes(ch.size)) or { return false }
	if !valid_ring(ch.ring.bus, ch.ring.bytes, ch.page_size()) { return false }
	ch.buffers = ch.alloc_dma(u64(buffer_bytes) * 2) or { return false }
	ch.tx = unsafe { &u8(ch.buffers.virt) }
	ch.rx = unsafe { &u8(ch.buffers.virt + buffer_bytes) }
	ch.avail = ch.ring.virt + u64(ch.size) * 16
	ch.used = ch.ring.virt + used_offset(ch.size)
	ch.produced = 0
	ch.consumed = 0
	// Explicitly zero the ring, regardless of allocator implementation.
	unsafe { C.memset(voidptr(ch.ring.virt), 0, ch.ring.bytes) }
	unsafe { *&u16(ch.avail) = 1 } // VIRTQ_AVAIL_F_NO_INTERRUPT
	ch.barrier()
	ch.install(ch.ring.bus)
	ch.installed = true
	ch.barrier()
	ch.set_status(7)
	ch.ready = true
	return true
}

// The filesystem holds its session lock across constructing the packet,
// exchanging it, and parsing it. This lock also excludes transport shutdown.
pub fn exchange(context voidptr, request &u8, length u32, reply &u8, capacity u32) int {
	mut ch := unsafe { &Channel(context) }
	if ch == unsafe { nil } { return -5 }
	ch.lock.acquire()
	defer { ch.lock.release() }
	if !ch.ready || ch.quarantined || length < 7 || length > buffer_bytes
		|| capacity < 7 || capacity > buffer_bytes || request != ch.tx || reply != ch.rx {
		return -5
	}
	// Chain 0 is device-readable, chain 1 is device-writable. No indirects.
	unsafe {
		*&u64(ch.ring.virt) = ch.buffers.bus
		*&u32(ch.ring.virt + 8) = length
		*&u16(ch.ring.virt + 12) = 1
		*&u16(ch.ring.virt + 14) = 1
		*&u64(ch.ring.virt + 16) = ch.buffers.bus + buffer_bytes
		*&u32(ch.ring.virt + 24) = capacity
		*&u16(ch.ring.virt + 28) = 2
		*&u16(ch.ring.virt + 30) = 0
		*&u16(ch.avail + 4 + u64(ch.produced % ch.size) * 2) = 0
	}
	ch.barrier()
	ch.produced++
	unsafe { *&u16(ch.avail + 2) = ch.produced }
	ch.barrier()
	ch.notify()
	limit := devcore.deadline(5 * devcore.second)
	// Both clock and iteration limits are finite, including a stalled clock.
	for _ in 0 .. 100000000 {
		current := ch.read16(ch.used + 2)
		if current != ch.consumed {
			ch.barrier()
			slot := ch.used + 4 + u64(ch.consumed % ch.size) * 8
			id := ch.read32(slot)
			n := ch.read32(slot + 4)
			if !valid_completion(ch.consumed, current, id, n, capacity) {
				ch.stop_locked()
				return -71
			}
			ch.consumed = current
			ch.ack()
			return int(n)
		}
		if limit.expired() { break }
		devcore.relax()
	}
	ch.stop_locked()
	return -110
}

fn (mut ch Channel) stop_locked() {
	ch.ready = false
	// Reset must acknowledge before freeing even a completed queue: a device
	// can still prefetch descriptors or config while DRIVER_OK remains set.
	if !ch.reset() {
		ch.disable()
		ch.quarantined = true
		return
	}
	ch.barrier()
	ch.disable()
	ch.free_dma(ch.buffers)
	ch.free_dma(ch.ring)
	ch.buffers = dma.Buffer{}
	ch.ring = dma.Buffer{}
	ch.tx = unsafe { nil }
	ch.rx = unsafe { nil }
	ch.installed = false
}

pub fn (mut ch Channel) close() {
	ninep_claim_lock.acquire()
	defer { ninep_claim_lock.release() }
	ch.lock.acquire()
	defer { ch.lock.release() }
	ch.stop_locked()
	if !ch.quarantined { ninep_claimed = false }
}
