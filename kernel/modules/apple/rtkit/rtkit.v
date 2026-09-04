module rtkit

// Apple RTKit protocol over an ASC mailbox.
//
// Management message types occupy bits 59:52. Application endpoint payloads
// define their own layouts and must be passed through without modification.

import apple.mailbox
import aarch64.cpu
import klock

// RTKit management message types.
pub const msg_hello = u8(1)
pub const msg_hello_ack = u8(2)
pub const msg_start_ep = u8(5)
pub const msg_set_iop_power = u8(6)
pub const msg_iop_power_ack = u8(7)
pub const msg_epmap = u8(8)
pub const msg_epmap_reply = u8(8)
pub const msg_set_ap_power = u8(0xb)
pub const msg_ap_power_ack = u8(0xb)

// RTKit system endpoints.
pub const ep_mgmt = u8(0)
pub const ep_crashlog = u8(1)
pub const ep_syslog = u8(2)
pub const ep_debug = u8(3)
pub const ep_ioreport = u8(4)
pub const ep_oslog = u8(8)
pub const ep_tracekit = u8(0xa)

const management_type_shift = u32(52)
const management_type_mask = u64(0xff) << management_type_shift
const epmap_last = u64(1) << 51
const epmap_more = u64(1)
const start_ep_flag = u64(1) << 1
const app_endpoint_start = u8(0x20)
const min_supported_version = u16(11)
const max_supported_version = u16(12)
const power_state_on = u16(0x20)
const power_state_init = u16(0x220)
const boot_timeout = 10_000_000

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
	mbox             mailbox.Mailbox
	state            RTKitState
	endpoints        [256]bool
	lock             klock.Lock
	name             string
	protocol_version u16
	iop_power_state  u16
	ap_power_state   u16
}

pub fn new_rtkit(mbox_base u64, name string) RTKit {
	mut result := RTKit{
		mbox:  mailbox.new_mailbox(mbox_base)
		state: .idle
		name:  name
	}
	result.endpoints[ep_mgmt] = true
	return result
}

@[inline]
fn management_type(data u64) u8 {
	return u8((data >> management_type_shift) & 0xff)
}

@[inline]
fn management_message(kind u8, payload u64) u64 {
	return (payload & ~management_type_mask) | (u64(kind) << management_type_shift)
}

fn (mut rtk RTKit) send_management(kind u8, payload u64) bool {
	return rtk.mbox.send(mailbox.MboxMsg{
		data0: management_message(kind, payload)
		data1: u32(ep_mgmt)
	})
}

fn (mut rtk RTKit) send_start_endpoint(ep u8) bool {
	payload := (u64(ep) << 32) | start_ep_flag
	return rtk.send_management(msg_start_ep, payload)
}

fn (mut rtk RTKit) fail(message &char) bool {
	C.printf(c'rtkit[%s]: %s\n', rtk.name.str, message)
	rtk.state = .error
	return false
}

// Start an RTKit coprocessor after its ASC CPU has been released. This follows
// the version negotiation, endpoint-map, and AP/IOP power-state sequence used
// by current RTKit versions 11 and 12.
pub fn (mut rtk RTKit) boot() bool {
	rtk.lock.acquire()
	defer {
		rtk.lock.release()
	}

	if rtk.state == .running {
		return true
	}
	rtk.state = .hello_wait
	rtk.iop_power_state = 0
	rtk.ap_power_state = 0
	println('rtkit[${rtk.name}]: Starting boot handshake')

	// Wake the IOP. Its acknowledgment may arrive before or after HELLO/EPMAP.
	if !rtk.send_management(msg_set_iop_power, u64(power_state_init)) {
		return rtk.fail(c'failed to request IOP initialization')
	}

	mut endpoint_map_done := false
	mut ap_power_requested := false
	for _ in 0 .. boot_timeout {
		msg := rtk.mbox.recv() or {
			cpu.wfe()
			continue
		}
		ep := mailbox.msg_endpoint(&msg)
		if ep != ep_mgmt {
			handle_system_message(mut rtk, msg)
			continue
		}

		kind := management_type(msg.data0)
		match kind {
			msg_hello {
				min_version := u16(msg.data0 & 0xffff)
				max_version := u16((msg.data0 >> 16) & 0xffff)
				if min_version > max_supported_version || max_version < min_supported_version {
					C.printf(c'rtkit[%s]: unsupported protocol range %u-%u\n', rtk.name.str,
						min_version, max_version)
					rtk.state = .error
					return false
				}
				version := if max_version < max_supported_version {
					max_version
				} else {
					max_supported_version
				}
				rtk.protocol_version = version
				payload := u64(version) | (u64(version) << 16)
				if !rtk.send_management(msg_hello_ack, payload) {
					return rtk.fail(c'failed to acknowledge HELLO')
				}
				rtk.state = .epmap_wait
				println('rtkit[${rtk.name}]: negotiated protocol version ${version}')
			}
			msg_epmap {
				bitmap := u32(msg.data0 & 0xffff_ffff)
				block := u8((msg.data0 >> 32) & 0x7)
				last := msg.data0 & epmap_last != 0
				for bit := u8(0); bit < 32; bit++ {
					if bitmap & (u32(1) << bit) != 0 {
						ep_id := u16(block) * 32 + u16(bit)
						if ep_id < 256 {
							rtk.endpoints[ep_id] = true
						}
					}
				}
				mut reply := u64(block) << 32
				if last {
					reply |= epmap_last
				} else {
					reply |= epmap_more
				}
				if !rtk.send_management(msg_epmap_reply, reply) {
					return rtk.fail(c'failed to acknowledge endpoint map')
				}
				if last {
					endpoint_map_done = true
					start_system_endpoints(mut rtk)
				}
			}
			msg_iop_power_ack {
				rtk.iop_power_state = u16(msg.data0 & 0xffff)
			}
			msg_ap_power_ack {
				rtk.ap_power_state = u16(msg.data0 & 0xffff)
			}
			else {
				C.printf(c'rtkit[%s]: ignoring management message type 0x%x\n', rtk.name.str,
					kind)
			}
		}

		if endpoint_map_done && !ap_power_requested {
			if !rtk.send_management(msg_set_ap_power, u64(power_state_on)) {
				return rtk.fail(c'failed to request AP power state')
			}
			ap_power_requested = true
			rtk.state = .booting
		}
		if endpoint_map_done && rtk.iop_power_state == power_state_on
			&& rtk.ap_power_state == power_state_on {
			rtk.state = .running
			println('rtkit[${rtk.name}]: Boot handshake complete')
			return true
		}
	}

	return rtk.fail(c'boot handshake timed out')
}

fn handle_system_message(mut rtk RTKit, msg mailbox.MboxMsg) {
	ep := mailbox.msg_endpoint(&msg)
	match ep {
		ep_ioreport {
			kind := management_type(msg.data0)
			// Unknown IOReport requests 0x8 and 0xc must be acknowledged or
			// some coprocessors stop making progress.
			if kind == 0x8 || kind == 0xc {
				rtk.send_message(ep, msg.data0)
			}
		}
		ep_syslog {
			// Type 5 is a log notification. Echoing it releases the slot.
			if management_type(msg.data0) == 5 {
				rtk.send_message(ep, msg.data0)
			}
		}
		else {}
	}
}

fn start_system_endpoints(mut rtk RTKit) {
	system_eps := [ep_crashlog, ep_syslog, ep_debug, ep_ioreport, ep_oslog, ep_tracekit]
	for ep in system_eps {
		if rtk.endpoints[ep] {
			rtk.send_start_endpoint(ep)
		}
	}
}

// Start an application endpoint after RTKit has reached the ON state.
pub fn (mut rtk RTKit) start_endpoint(ep u8) bool {
	if !rtk.endpoints[ep] {
		C.printf(c'rtkit[%s]: Endpoint %d not available\n', rtk.name.str, ep)
		return false
	}
	if ep >= app_endpoint_start && rtk.state != .running {
		C.printf(c'rtkit[%s]: Endpoint %d requested before RTKit is running\n', rtk.name.str,
			ep)
		return false
	}
	return rtk.send_start_endpoint(ep)
}

// Send a protocol-defined payload without changing any of its bits.
pub fn (mut rtk RTKit) send_message(ep u8, data u64) bool {
	return rtk.mbox.send(mailbox.MboxMsg{
		data0: data
		data1: u32(ep)
	})
}

pub fn (mut rtk RTKit) recv_msg() ?mailbox.MboxMsg {
	return rtk.mbox.recv()
}

pub fn (mut rtk RTKit) recv_msg_blocking(timeout int) ?mailbox.MboxMsg {
	return rtk.mbox.recv_blocking(timeout)
}
