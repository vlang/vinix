@[has_globals]
module channel

// GPU firmware ring buffer channels
// Generic RxChannel and TxChannel for firmware communication
// Channel types: DeviceControl, Pipe (vertex/fragment/compute x 4 priorities),
// FwCtl, Event, FwLog, KTrace, Stats
// Translates channel.rs from the Asahi Linux GPU driver

import klock
import katomic

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
@[packed]
pub struct RingHeader {
pub mut:
	read_ptr  u32
	pad_04    [7]u32
	write_ptr u32
	pad_24    [3]u32
}

// The firmware-control channel uses a smaller state object with write_ptr at
// 0x10. Its entry ring is otherwise operated like every other TX channel.
@[packed]
pub struct FwCtlRingHeader {
pub mut:
	read_ptr  u32
	pad_04    [3]u32
	write_ptr u32
	pad_14    [3]u32
}

// Generic transmit channel (driver -> firmware)
pub struct TxChannel {
pub mut:
	name       string
	state_base u64 // VA of state object in GPU address space
	state_phys u64 // physical address of state object
	ring_base  u64 // VA of ring buffer in GPU address space
	ring_phys  u64 // physical address
	ring_size  u32 // number of entries
	entry_size u32 // size of each entry in bytes
	write_off  u32 // write_ptr offset in the state object
	lock       klock.Lock
}

// Generic receive channel (firmware -> driver)
pub struct RxChannel {
pub mut:
	name        string
	state_base  u64
	state_phys  u64
	ring_base   u64
	ring_phys   u64
	ring_size   u32
	entry_size  u32
	subchannels u32
	lock        klock.Lock
}

pub fn new_tx_channel(name string, state_va u64, state_phys u64, ring_va u64,
	ring_phys u64, ring_size u32, entry_size u32) TxChannel {
	return TxChannel{
		name: name
		state_base: state_va
		state_phys: state_phys
		ring_base: ring_va
		ring_phys: ring_phys
		ring_size: ring_size
		entry_size: entry_size
		write_off: 0x20
	}
}

pub fn new_fwctl_tx_channel(name string, state_va u64, state_phys u64, ring_va u64,
	ring_phys u64, ring_size u32, entry_size u32) TxChannel {
	mut channel := new_tx_channel(name, state_va, state_phys, ring_va, ring_phys, ring_size, entry_size)
	channel.write_off = 0x10
	return channel
}

pub fn new_rx_channel(name string, state_va u64, state_phys u64, ring_va u64,
	ring_phys u64, ring_size u32, entry_size u32) RxChannel {
	return new_rx_channel_with_subchannels(name, state_va, state_phys, ring_va, ring_phys, ring_size, entry_size, 1)
}

pub fn new_rx_channel_with_subchannels(name string, state_va u64, state_phys u64,
	ring_va u64, ring_phys u64, ring_size u32, entry_size u32, subchannels u32) RxChannel {
	return RxChannel{
		name: name
		state_base: state_va
		state_phys: state_phys
		ring_base: ring_va
		ring_phys: ring_phys
		ring_size: ring_size
		entry_size: entry_size
		subchannels: subchannels
	}
}

// Write an entry to the ring buffer, advance write_ptr with wrap
pub fn (mut ch TxChannel) enqueue(data voidptr) bool {
	ch.lock.acquire()
	defer {
		ch.lock.release()
	}

	read_ptr := unsafe { &u32(ch.state_phys + higher_half) }
	mut write_ptr := unsafe { &u32(ch.state_phys + higher_half + ch.write_off) }
	wp := katomic.load(write_ptr)
	rp := katomic.load(read_ptr)
	next_wp := (wp + 1) % ch.ring_size

	// One entry stays empty so equal pointers unambiguously mean empty.
	if next_wp == rp {
		return false
	}

	offset := u64(wp) * u64(ch.entry_size)
	dest := unsafe { voidptr(ch.ring_phys + higher_half + offset) }
	unsafe {
		C.memcpy(dest, data, ch.entry_size)
	}

	katomic.store(mut write_ptr, next_wp)
	return true
}

// Read an entry from the ring buffer, advance read_ptr with wrap
pub fn (mut ch RxChannel) dequeue(data voidptr) bool {
	return ch.dequeue_subchannel(data, 0)
}

// Read one firmware-log subchannel. Other RX channel types use index zero.
pub fn (mut ch RxChannel) dequeue_subchannel(data voidptr, index u32) bool {
	if index >= ch.subchannels {
		return false
	}
	ch.lock.acquire()
	defer {
		ch.lock.release()
	}

	state_offset := u64(index) * u64(sizeof(RingHeader))
	mut read_ptr := unsafe { &u32(ch.state_phys + higher_half + state_offset) }
	write_ptr := unsafe { &u32(ch.state_phys + higher_half + state_offset + 0x20) }
	rp := katomic.load(read_ptr)
	wp := katomic.load(write_ptr)

	if rp == wp {
		return false
	}

	offset := (u64(index) * u64(ch.ring_size) + u64(rp)) * u64(ch.entry_size)
	src := unsafe { voidptr(ch.ring_phys + higher_half + offset) }
	unsafe {
		C.memcpy(data, src, ch.entry_size)
	}

	new_rp := (rp + 1) % ch.ring_size
	katomic.store(mut read_ptr, new_rp)
	return true
}

// Read the next entry without advancing the read pointer
pub fn (ch &RxChannel) peek(data voidptr) bool {
	return ch.peek_subchannel(data, 0)
}

pub fn (ch &RxChannel) peek_subchannel(data voidptr, index u32) bool {
	if index >= ch.subchannels {
		return false
	}
	state_offset := u64(index) * u64(sizeof(RingHeader))
	read_ptr := unsafe { &u32(ch.state_phys + higher_half + state_offset) }
	write_ptr := unsafe { &u32(ch.state_phys + higher_half + state_offset + 0x20) }
	rp := katomic.load(read_ptr)
	wp := katomic.load(write_ptr)

	if rp == wp {
		return false
	}

	offset := (u64(index) * u64(ch.ring_size) + u64(rp)) * u64(ch.entry_size)
	src := unsafe { voidptr(ch.ring_phys + higher_half + offset) }
	unsafe {
		C.memcpy(data, src, ch.entry_size)
	}
	return true
}

// Check if the transmit channel is full
pub fn (ch &TxChannel) is_full() bool {
	read_ptr := unsafe { &u32(ch.state_phys + higher_half) }
	write_ptr := unsafe { &u32(ch.state_phys + higher_half + ch.write_off) }
	wp := katomic.load(write_ptr)
	rp := katomic.load(read_ptr)
	return (wp + 1) % ch.ring_size == rp
}

// Check if the receive channel is empty
pub fn (ch &RxChannel) is_empty() bool {
	read_ptr := unsafe { &u32(ch.state_phys + higher_half) }
	write_ptr := unsafe { &u32(ch.state_phys + higher_half + 0x20) }
	rp := katomic.load(read_ptr)
	wp := katomic.load(write_ptr)
	return rp == wp
}
