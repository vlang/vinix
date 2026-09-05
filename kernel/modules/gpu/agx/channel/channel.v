@[has_globals]
module channel

// GPU firmware ring buffer channels
// Generic RxChannel and TxChannel for firmware communication
// Channel types: DeviceControl, Pipe (vertex/fragment/compute x 4 priorities),
// FwCtl, Event, FwLog, KTrace, Stats
// Translates channel.rs from the Asahi Linux GPU driver

import klock
import katomic
import memory

// Channel type indices
pub const channel_device_ctrl = u32(0)
pub const channel_pipe = u32(1) // 4 priorities x 3 types (vertex/fragment/compute)
pub const channel_fw_ctrl = u32(13)
pub const channel_event = u32(14)
pub const channel_fw_log = u32(15)
pub const channel_ktrace = u32(16)
pub const channel_stats = u32(17)

// G13 v12.3 ChannelState. The firmware owns read_ptr for TX channels and
// write_ptr for RX channels. Both pointers are modulo the ring entry count.
// The real ABI allocates this state separately from the entry array; the
// current partial implementation keeps them adjacent until InitData is ported.
@[packed]
pub struct RingHeader {
pub mut:
	read_ptr  u32
	pad_04    [7]u32
	write_ptr u32
	pad_24    [3]u32
}

// Generic transmit channel (driver -> firmware)
pub struct TxChannel {
pub mut:
	name       string
	ring_base  u64 // VA of ring buffer in GPU address space
	ring_phys  u64 // physical address
	ring_size  u32 // number of entries
	entry_size u32 // size of each entry in bytes
	header     &RingHeader = unsafe { nil }
	lock       klock.Lock
}

// Generic receive channel (firmware -> driver)
pub struct RxChannel {
pub mut:
	name       string
	ring_base  u64
	ring_phys  u64
	ring_size  u32
	entry_size u32
	header     &RingHeader = unsafe { nil }
	lock       klock.Lock
}

pub fn new_tx_channel(name string, ring_va u64, ring_phys u64, ring_size u32, entry_size u32) TxChannel {
	// Header lives at the start of the ring buffer physical mapping
	hdr := unsafe { &RingHeader(ring_phys + higher_half) }
	// Zero-initialize the header
	unsafe {
		C.memset(hdr, 0, sizeof(RingHeader))
	}
	return TxChannel{
		name: name
		ring_base: ring_va
		ring_phys: ring_phys
		ring_size: ring_size
		entry_size: entry_size
		header: hdr
	}
}

pub fn new_rx_channel(name string, ring_va u64, ring_phys u64, ring_size u32, entry_size u32) RxChannel {
	hdr := unsafe { &RingHeader(ring_phys + higher_half) }
	unsafe {
		C.memset(hdr, 0, sizeof(RingHeader))
	}
	return RxChannel{
		name: name
		ring_base: ring_va
		ring_phys: ring_phys
		ring_size: ring_size
		entry_size: entry_size
		header: hdr
	}
}

// Write an entry to the ring buffer, advance write_ptr with wrap
pub fn (mut ch TxChannel) enqueue(data voidptr) bool {
	ch.lock.acquire()
	defer {
		ch.lock.release()
	}

	wp := katomic.load(&ch.header.write_ptr)
	rp := katomic.load(&ch.header.read_ptr)
	next_wp := (wp + 1) % ch.ring_size

	// One entry stays empty so equal pointers unambiguously mean empty.
	if next_wp == rp {
		return false
	}

	offset := u64(wp) * u64(ch.entry_size)
	// Data area starts after the header
	dest := unsafe { voidptr(ch.ring_phys + higher_half + sizeof(RingHeader) + offset) }
	unsafe {
		C.memcpy(dest, data, ch.entry_size)
	}

	katomic.store(mut &ch.header.write_ptr, next_wp)
	return true
}

// Read an entry from the ring buffer, advance read_ptr with wrap
pub fn (mut ch RxChannel) dequeue(data voidptr) bool {
	ch.lock.acquire()
	defer {
		ch.lock.release()
	}

	rp := katomic.load(&ch.header.read_ptr)
	wp := katomic.load(&ch.header.write_ptr)

	if rp == wp {
		return false
	}

	offset := u64(rp) * u64(ch.entry_size)
	src := unsafe { voidptr(ch.ring_phys + higher_half + sizeof(RingHeader) + offset) }
	unsafe {
		C.memcpy(data, src, ch.entry_size)
	}

	new_rp := (rp + 1) % ch.ring_size
	katomic.store(mut &ch.header.read_ptr, new_rp)
	return true
}

// Read the next entry without advancing the read pointer
pub fn (ch &RxChannel) peek(data voidptr) bool {
	rp := katomic.load(&ch.header.read_ptr)
	wp := katomic.load(&ch.header.write_ptr)

	if rp == wp {
		return false
	}

	offset := u64(rp) * u64(ch.entry_size)
	src := unsafe { voidptr(ch.ring_phys + higher_half + sizeof(RingHeader) + offset) }
	unsafe {
		C.memcpy(data, src, ch.entry_size)
	}
	return true
}

// Check if the transmit channel is full
pub fn (ch &TxChannel) is_full() bool {
	wp := katomic.load(&ch.header.write_ptr)
	rp := katomic.load(&ch.header.read_ptr)
	return (wp + 1) % ch.ring_size == rp
}

// Check if the receive channel is empty
pub fn (ch &RxChannel) is_empty() bool {
	rp := katomic.load(&ch.header.read_ptr)
	wp := katomic.load(&ch.header.write_ptr)
	return rp == wp
}
