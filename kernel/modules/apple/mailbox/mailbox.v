@[has_globals]
module mailbox

// Apple ASC Mailbox
// 96-bit messages: 64-bit data + 32-bit endpoint/flags
// MMIO-based send/receive for communication with coprocessors (GPU, DCP, etc.)

import aarch64.kio
import aarch64.cpu
import klock
import memory

// ASC mailbox v4 register offsets. The mailbox DT resource starts at the
// mailbox window (the combined ASC window used by m1n1 places this at
// ASC + 0x8000). A2I is the AP -> coprocessor inbox and I2A is the
// coprocessor -> AP outbox.
const mbox_a2i_ctrl = u32(0x110)
const mbox_i2a_ctrl = u32(0x114)
const mbox_a2i_send0 = u32(0x800)
const mbox_a2i_send1 = u32(0x808)
const mbox_i2a_recv0 = u32(0x830)
const mbox_i2a_recv1 = u32(0x838)

// Status bits
const mbox_empty = u32(1 << 17)
const mbox_full = u32(1 << 16)

pub struct MboxMsg {
pub mut:
	data0 u64 // Lower 64 bits of message data
	data1 u32 // Upper 32 bits (endpoint + type)
}

pub struct Mailbox {
pub mut:
	base u64
	lock klock.Lock
}

pub fn new_mailbox(base u64) Mailbox {
	return Mailbox{
		// Map the ASC mailbox aperture as Device memory (registers up to 0xc14).
		base: memory.map_mmio(base, 0x1000)
	}
}

fn (mbox &Mailbox) read_reg(offset u32) u32 {
	return kio.mmin32(unsafe { &u32(mbox.base + offset) })
}

fn (mbox &Mailbox) write_reg(offset u32, value u32) {
	kio.mmout32(unsafe { &u32(mbox.base + offset) }, value)
}

// Send a message to the coprocessor (AP -> IOP)
pub fn (mut mbox Mailbox) send(msg MboxMsg) bool {
	mbox.lock.acquire()
	defer {
		mbox.lock.release()
	}

	// Wait for space in the send FIFO
	for i := 0; i < 1000000; i++ {
		status := mbox.read_reg(mbox_a2i_ctrl)
		if status & mbox_full == 0 {
			// The high-word MMIO write publishes this message to the IOP.
			// Make every preceding shared-memory write globally visible first.
			cpu.dmb_sy()
			// Write data low first, then high (write to high triggers send)
			mbox.write_reg(mbox_a2i_send0, u32(msg.data0))
			mbox.write_reg(mbox_a2i_send0 + 4, u32(msg.data0 >> 32))
			mbox.write_reg(mbox_a2i_send1, msg.data1)
			return true
		}
		cpu.isb()
	}

	C.printf(c'mailbox: Send timeout\n')
	return false
}

// Receive a message from the coprocessor (IOP -> AP)
pub fn (mut mbox Mailbox) recv() ?MboxMsg {
	mbox.lock.acquire()
	defer {
		mbox.lock.release()
	}

	status := mbox.read_reg(mbox_i2a_ctrl)
	if status & mbox_empty != 0 {
		return none
	}

	lo := mbox.read_reg(mbox_i2a_recv0)
	hi := mbox.read_reg(mbox_i2a_recv0 + 4)
	flags := mbox.read_reg(mbox_i2a_recv1)
	// The message may advertise data the IOP just wrote to shared memory.
	// Prevent later consumers from observing that memory before the FIFO read.
	cpu.dmb_sy()

	return MboxMsg{
		data0: u64(lo) | (u64(hi) << 32)
		data1: flags
	}
}

// Blocking receive with timeout (in iterations)
pub fn (mut mbox Mailbox) recv_blocking(timeout int) ?MboxMsg {
	for i := 0; i < timeout; i++ {
		msg := mbox.recv() or {
			cpu.wfe()
			continue
		}
		return msg
	}
	return none
}

// Extract endpoint from the low byte of the mailbox's second word.
pub fn msg_endpoint(msg &MboxMsg) u8 {
	return u8(msg.data1 & 0xff)
}
