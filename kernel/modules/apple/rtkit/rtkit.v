@[has_globals]
module rtkit

// Apple RTKit protocol
// Communication framework for Apple coprocessors (GPU ASC, DCP, etc.)
// Implements the boot handshake and endpoint management protocol.

import apple.mailbox
import memory
import klock

// RTKit message types (in bits [63:56] of data0)
pub const msg_hello = u8(1)
pub const msg_hello_ack = u8(2)
pub const msg_start_ep = u8(5)
pub const msg_epmap = u8(8)
pub const msg_epmap_reply = u8(8)
pub const msg_boot = u8(9)
pub const msg_boot_ack = u8(9)
pub const msg_init = u8(0x80)

// RTKit system endpoints
pub const ep_mgmt = u8(0)
pub const ep_crashlog = u8(1)
pub const ep_syslog = u8(2)
pub const ep_debug = u8(3)
pub const ep_ioreport = u8(4)
pub const ep_oslog = u8(5)

// RTKit boot states
pub enum RTKitState {
	idle
	hello_wait
	epmap_wait
	booting
	running
	error
}

pub struct RTKit {
pub mut:
	mbox      mailbox.Mailbox
	state     RTKitState
	endpoints [256]bool // endpoint availability bitmap
	lock      klock.Lock
	name      string
}

pub fn new_rtkit(mbox_base u64, name string) RTKit {
	return RTKit{
		mbox: mailbox.new_mailbox(mbox_base)
		state: .idle
		name: name
	}
}

// Perform the RTKit boot handshake
// Sequence: recv HELLO -> send HELLO_ACK -> recv EPMAP -> ack EPMAP -> send BOOT -> recv BOOT_ACK
pub fn (mut rtk RTKit) boot() bool {
	rtk.lock.acquire()
	defer {
		rtk.lock.release()
	}

	rtk.state = .hello_wait
	println('rtkit[${rtk.name}]: Starting boot handshake')

	// Step 1: Wait for HELLO from firmware
	hello_msg := rtk.mbox.recv_blocking(10000000) or {
		C.printf(c'rtkit[%s]: Timeout waiting for HELLO\n', rtk.name.str)
		rtk.state = .error
		return false
	}

	msg_t := mailbox.msg_type(&hello_msg)
	if msg_t != msg_hello {
		C.printf(c'rtkit[%s]: Expected HELLO (1), got %d\n', rtk.name.str, msg_t)
		rtk.state = .error
		return false
	}

	// Extract min/max protocol version from HELLO
	min_ver := u16(hello_msg.data0 & 0xffff)
	max_ver := u16((hello_msg.data0 >> 16) & 0xffff)
	println('rtkit[${rtk.name}]: HELLO received, protocol v${min_ver}-${max_ver}')

	// Step 2: Send HELLO_ACK with our protocol version (use max)
	ack := mailbox.MboxMsg{
		data0: (u64(msg_hello_ack) << 56) | u64(max_ver) | (u64(max_ver) << 16)
		data1: u32(ep_mgmt)
	}
	if !rtk.mbox.send(ack) {
		rtk.state = .error
		return false
	}

	rtk.state = .epmap_wait

	// Step 3: Handle EPMAP messages (endpoint bitmap)
	for {
		ep_msg := rtk.mbox.recv_blocking(10000000) or {
			C.printf(c'rtkit[%s]: Timeout waiting for EPMAP\n', rtk.name.str)
			rtk.state = .error
			return false
		}

		ep_type := mailbox.msg_type(&ep_msg)
		if ep_type != msg_epmap {
			// Could be IOREPORT/SYSLOG setup -- handle gracefully
			handle_system_message(mut rtk, ep_msg)
			continue
		}

		// Parse endpoint bitmap
		bitmap := ep_msg.data0 & 0xffffffff
		base := u8((ep_msg.data0 >> 32) & 0xff)
		done := (ep_msg.data0 >> 51) & 1

		for i := u8(0); i < 32; i++ {
			if bitmap & (u64(1) << i) != 0 {
				ep_id := base + i
				rtk.endpoints[ep_id] = true
			}
		}

		// Send EPMAP reply
		reply := mailbox.MboxMsg{
			data0: (u64(msg_epmap_reply) << 56) | ep_msg.data0
			data1: u32(ep_mgmt)
		}
		rtk.mbox.send(reply)

		if done != 0 {
			break
		}
	}

	// Step 4: Start system endpoints that the firmware reported
	start_system_endpoints(mut rtk)

	rtk.state = .booting
	println('rtkit[${rtk.name}]: Boot handshake complete')

	return true
}

fn handle_system_message(mut rtk RTKit, msg mailbox.MboxMsg) {
	ep := mailbox.msg_endpoint(&msg)
	match ep {
		ep_syslog {
			// Firmware syslog -- acknowledge
		}
		ep_ioreport {
			// IO report -- acknowledge
		}
		ep_oslog {
			// OS log -- acknowledge
		}
		else {}
	}
}

fn start_system_endpoints(mut rtk RTKit) {
	// Start endpoints that the firmware needs
	system_eps := [ep_crashlog, ep_syslog, ep_ioreport, ep_oslog]
	for ep in system_eps {
		if rtk.endpoints[ep] {
			start_ep := mailbox.MboxMsg{
				data0: (u64(msg_start_ep) << 56) | u64(ep)
				data1: u32(ep_mgmt)
			}
			rtk.mbox.send(start_ep)
		}
	}
}

// Start a user endpoint (e.g., firmware control, doorbell)
pub fn (mut rtk RTKit) start_endpoint(ep u8) bool {
	if !rtk.endpoints[ep] {
		C.printf(c'rtkit[%s]: Endpoint %d not available\n', rtk.name.str, ep)
		return false
	}

	msg := mailbox.MboxMsg{
		data0: (u64(msg_start_ep) << 56) | u64(ep)
		data1: u32(ep_mgmt)
	}
	return rtk.mbox.send(msg)
}

// Send a message to a specific endpoint
pub fn (mut rtk RTKit) send_msg(ep u8, msg_type u8, data u64) bool {
	msg := mailbox.MboxMsg{
		data0: (u64(msg_type) << 56) | (data & 0x00ffffffffffffff)
		data1: u32(ep)
	}
	return rtk.mbox.send(msg)
}

// Receive a message (from any endpoint)
pub fn (mut rtk RTKit) recv_msg() ?mailbox.MboxMsg {
	return rtk.mbox.recv()
}

// Blocking receive
pub fn (mut rtk RTKit) recv_msg_blocking(timeout int) ?mailbox.MboxMsg {
	return rtk.mbox.recv_blocking(timeout)
}
