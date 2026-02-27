@[has_globals]
module mailbox

// Apple ASC Mailbox
// 96-bit messages: 64-bit data + 32-bit endpoint/flags
// MMIO-based send/receive for communication with coprocessors (GPU, DCP, etc.)

import aarch64.kio
import aarch64.cpu
import klock

// Mailbox registers (offsets from base)
const mbox_a2i_send0 = u32(0x800) // AP -> IOP data low
const mbox_a2i_send1 = u32(0x808) // AP -> IOP data high + flags
const mbox_i2a_recv0 = u32(0xc00) // IOP -> AP data low
const mbox_i2a_recv1 = u32(0xc08) // IOP -> AP data high + flags

// Control registers
const mbox_a2i_ctrl = u32(0x810)
const mbox_i2a_ctrl = u32(0xc10)

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
		base: base + higher_half
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

// Extract endpoint from message
pub fn msg_endpoint(msg &MboxMsg) u8 {
	return u8(msg.data1 & 0xff)
}

// Extract message type from data
pub fn msg_type(msg &MboxMsg) u8 {
	return u8(msg.data0 >> 56)
}
