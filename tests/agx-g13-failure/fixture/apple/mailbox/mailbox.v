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
	sent int
	last MboxMsg
}

__global on_send fn () = unsafe { nil }

pub fn watch_send(callback fn ()) { on_send = callback }

pub fn new_mailbox(_ u64) Mailbox { return Mailbox{} }
pub fn msg_endpoint(message &MboxMsg) u8 { return u8(message.data1) }
pub fn (mut _ Mailbox) recv() ?MboxMsg { return none }
pub fn (mut _ Mailbox) recv_blocking(_ int) ?MboxMsg { return none }

pub fn (mut box Mailbox) send(message MboxMsg) bool {
	if on_send != unsafe { nil } { on_send() }
	box.sent++
	box.last = message
	return true
}
