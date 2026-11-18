// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module mailbox

pub struct MboxMsg {
pub:
	data0 u64
	data1 u64
}

pub struct Mailbox {
pub mut:
	attempts int
	sent int
	last MboxMsg
	fail_next_send bool
}

__global on_send fn () = unsafe { nil }

pub fn watch_send(callback fn ()) { on_send = callback }

pub fn new_mailbox(_ u64) Mailbox { return Mailbox{} }
pub fn msg_endpoint(message &MboxMsg) u8 { return u8(message.data1) }
pub fn (mut _ Mailbox) recv() ?MboxMsg { return none }
pub fn (mut _ Mailbox) recv_blocking(_ int) ?MboxMsg { return none }

pub fn (mut box Mailbox) send(message MboxMsg) bool {
	if on_send != unsafe { nil } { on_send() }
	box.attempts++
	if box.fail_next_send {
		box.fail_next_send = false
		return false
	}
	box.sent++
	box.last = message
	return true
}
