@[has_globals]
module dcp

// AFK (Apple Firmware Kit) / EPIC protocol for structured DCP communication
//
// AFK provides a ringbuffer-based transport for structured messages between
// the kernel and DCP firmware. Each ringbuffer has a header with read/write
// pointers and a data region containing variable-length queue entries.
// The EPIC sub-protocol adds typed message categories (notify, command,
// reply, report) on top of AFK queue entries.

import memory
import klock
import aarch64.cpu
import lib

// AFK ringbuffer magic value (identifies a valid AFK queue)
pub const afk_magic = u32(0x1A5E4AFC)

// AFK operation codes used in queue entry headers
pub const afk_op_hello = u32(0)
pub const afk_op_hello_ack = u32(1)
pub const afk_op_init = u32(2)
pub const afk_op_init_ack = u32(3)
pub const afk_op_message = u32(4)
pub const afk_op_message_ack = u32(5)

// EPIC message categories (layered on top of AFK)
const epic_cat_notify = u32(0)
const epic_cat_command = u32(3)
const epic_cat_reply = u32(4)
const epic_cat_report = u32(5)

// Minimum ringbuffer size (must hold at least header + one entry)
const afk_min_ring_size = u64(0x1000)

// AFK ringbuffer header. Resides at the start of the ringbuffer region.
// The write_ptr and read_ptr are byte offsets into the data area that
// follows this header. Padding fields ensure cache-line alignment of
// the read and write pointers to avoid false sharing between producer
// and consumer.
pub struct AfkRingHeader {
pub mut:
	magic     u32
	version   u32
	buf_size  u32
	unk_c     u32
	write_ptr u32
	pad0      [3]u32
	read_ptr  u32
	pad1      [3]u32
}

// AFK queue entry header. Each entry in the ringbuffer starts with this
// header, followed by data_size bytes of payload.
pub struct AfkQueueEntry {
pub mut:
	magic       u32
	size        u32
	channel     u32
	op          u32
	data_offset u32
	data_size   u32
}

// AFK endpoint context. Manages a pair of TX/RX ringbuffers for
// bidirectional communication with the DCP firmware.
pub struct AfkEpContext {
pub mut:
	base      u64 // ringbuffer base address (kernel virtual)
	size      u64
	tx_header &AfkRingHeader = unsafe { nil }
	rx_header &AfkRingHeader = unsafe { nil }
	lock      klock.Lock
}

// Create a new AFK endpoint context at the given base address and size.
// The region is split in half: the first half is the TX ringbuffer and
// the second half is the RX ringbuffer.
pub fn new_afk_context(base u64, size u64) AfkEpContext {
	if size < afk_min_ring_size * 2 {
		C.printf(c'afk: Ringbuffer region too small: 0x%llx\n', size)
		return AfkEpContext{}
	}

	half := size / 2
	virt_base := base + higher_half

	tx_hdr := unsafe { &AfkRingHeader(virt_base) }
	rx_hdr := unsafe { &AfkRingHeader(virt_base + half) }

	return AfkEpContext{
		base:      virt_base
		size:      size
		tx_header: tx_hdr
		rx_header: rx_hdr
	}
}

// Send a message through the AFK TX ringbuffer.
// Returns false if the ringbuffer is full or the context is invalid.
pub fn (mut ctx AfkEpContext) send(channel u32, op u32, data []u8) bool {
	ctx.lock.acquire()
	defer {
		ctx.lock.release()
	}

	if ctx.tx_header == unsafe { nil } {
		return false
	}

	mut hdr := ctx.tx_header

	// Validate magic
	if hdr.magic != afk_magic {
		C.printf(c'afk: TX ringbuffer has bad magic 0x%x\n', hdr.magic)
		return false
	}

	// Calculate entry size (header + payload, aligned to 8 bytes)
	entry_size := u32(lib.align_up(u64(sizeof(AfkQueueEntry)) + u64(data.len), 8))

	// Check available space in the ringbuffer
	buf_size := hdr.buf_size
	write_ptr := hdr.write_ptr
	read_ptr := hdr.read_ptr

	available := if write_ptr >= read_ptr {
		buf_size - write_ptr + read_ptr
	} else {
		read_ptr - write_ptr
	}

	if entry_size >= available {
		C.printf(c'afk: TX ringbuffer full\n')
		return false
	}

	// Write the queue entry header at the current write pointer
	data_area := ctx.base + u64(sizeof(AfkRingHeader))
	entry_ptr := data_area + u64(write_ptr)

	entry := unsafe { &AfkQueueEntry(entry_ptr) }
	unsafe {
		entry.magic = afk_magic
		entry.size = entry_size
		entry.channel = channel
		entry.op = op
		entry.data_offset = u32(sizeof(AfkQueueEntry))
		entry.data_size = u32(data.len)
	}

	// Copy payload data after the entry header
	if data.len > 0 {
		payload_ptr := entry_ptr + u64(sizeof(AfkQueueEntry))
		unsafe {
			C.memcpy(voidptr(payload_ptr), data.data, data.len)
		}
	}

	// Memory barrier to ensure writes are visible before advancing pointer
	cpu.dsb_st()

	// Advance write pointer (wrap around if needed)
	new_write := (write_ptr + entry_size) % buf_size
	hdr.write_ptr = new_write

	// Signal the firmware
	cpu.dsb_sy()
	cpu.sev()

	return true
}

// Receive a message from the AFK RX ringbuffer.
// Returns the channel, operation code, and payload data, or none if empty.
pub fn (mut ctx AfkEpContext) recv() ?(u32, u32, []u8) {
	ctx.lock.acquire()
	defer {
		ctx.lock.release()
	}

	if ctx.rx_header == unsafe { nil } {
		return none
	}

	mut hdr := ctx.rx_header

	// Check for valid magic
	if hdr.magic != afk_magic {
		return none
	}

	// Check if ringbuffer is empty
	read_ptr := hdr.read_ptr
	write_ptr := hdr.write_ptr
	if read_ptr == write_ptr {
		return none
	}

	// Read barrier to ensure we see the latest data
	cpu.dsb_ld()

	// Parse the entry at the current read pointer
	data_area := ctx.base + u64(ctx.size / 2) + u64(sizeof(AfkRingHeader))
	entry_ptr := data_area + u64(read_ptr)

	entry := unsafe { &AfkQueueEntry(entry_ptr) }
	if entry.magic != afk_magic {
		C.printf(c'afk: RX entry has bad magic 0x%x\n', entry.magic)
		return none
	}

	channel := entry.channel
	op := entry.op
	data_size := entry.data_size

	// Copy payload out
	mut data := []u8{len: int(data_size)}
	if data_size > 0 {
		payload_ptr := entry_ptr + u64(entry.data_offset)
		unsafe {
			C.memcpy(data.data, voidptr(payload_ptr), data_size)
		}
	}

	// Advance read pointer
	entry_total := u32(lib.align_up(u64(entry.size), 8))
	new_read := (read_ptr + entry_total) % hdr.buf_size
	hdr.read_ptr = new_read

	cpu.dsb_sy()

	return channel, op, data
}

// Perform the AFK hello/init handshake with the DCP firmware.
// This must be done once when the endpoint is first started.
// Sequence: send HELLO -> recv HELLO_ACK -> send INIT -> recv INIT_ACK
pub fn (mut ctx AfkEpContext) handshake() bool {
	ctx.lock.acquire()
	defer {
		ctx.lock.release()
	}

	if ctx.tx_header == unsafe { nil } || ctx.rx_header == unsafe { nil } {
		C.printf(c'afk: Cannot handshake, ringbuffers not initialized\n')
		return false
	}

	// Initialise TX ringbuffer header
	ctx.tx_header.magic = afk_magic
	ctx.tx_header.version = 1
	half := u32(ctx.size / 2)
	ctx.tx_header.buf_size = half - u32(sizeof(AfkRingHeader))
	ctx.tx_header.write_ptr = 0
	ctx.tx_header.read_ptr = 0

	cpu.dsb_sy()

	// Step 1: Send HELLO
	hello_data := []u8{}
	// Release lock temporarily for send/recv since they acquire it
	ctx.lock.release()

	if !ctx.send(0, afk_op_hello, hello_data) {
		C.printf(c'afk: Failed to send HELLO\n')
		ctx.lock.acquire()
		return false
	}

	// Step 2: Wait for HELLO_ACK
	mut got_hello_ack := false
	for _ in 0 .. 10000000 {
		channel, op, _ := ctx.recv() or {
			cpu.wfe()
			continue
		}
		_ = channel
		if op == afk_op_hello_ack {
			got_hello_ack = true
			break
		}
	}

	if !got_hello_ack {
		C.printf(c'afk: Timeout waiting for HELLO_ACK\n')
		ctx.lock.acquire()
		return false
	}

	// Step 3: Send INIT
	init_data := []u8{}
	if !ctx.send(0, afk_op_init, init_data) {
		C.printf(c'afk: Failed to send INIT\n')
		ctx.lock.acquire()
		return false
	}

	// Step 4: Wait for INIT_ACK
	mut got_init_ack := false
	for _ in 0 .. 10000000 {
		channel, op, _ := ctx.recv() or {
			cpu.wfe()
			continue
		}
		_ = channel
		if op == afk_op_init_ack {
			got_init_ack = true
			break
		}
	}

	ctx.lock.acquire()

	if !got_init_ack {
		C.printf(c'afk: Timeout waiting for INIT_ACK\n')
		return false
	}

	println('afk: Handshake complete')
	return true
}
