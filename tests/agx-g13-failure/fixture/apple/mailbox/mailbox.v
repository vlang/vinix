// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module mailbox

pub struct MboxMsg {
pub:
	data0 u64
	data1 u64
}

pub struct Mailbox {
mut:
	pending [16]MboxMsg
	empty_polls [16]int
	pending_len int
	pending_read int
	attempted_messages [16]MboxMsg
	sent_messages [16]MboxMsg
pub mut:
	attempts int
	timed_attempts int
	irq_send_attempts int
	sent int
	last MboxMsg
	fail_next_send bool
	send_timeout_mask u16
}

__global on_send fn () = unsafe { nil }

pub fn watch_send(callback fn ()) { on_send = callback }

pub fn new_mailbox(_ u64) Mailbox { return Mailbox{} }
pub fn msg_endpoint(message &MboxMsg) u8 { return u8(message.data1) }
pub fn (mut box Mailbox) inject(message MboxMsg) {
	box.inject_after(message, 0)
}
pub fn (mut box Mailbox) inject_after(message MboxMsg, empty_polls int) {
	assert box.pending_len < box.pending.len
	box.pending[box.pending_len] = message
	box.empty_polls[box.pending_len] = empty_polls
	box.pending_len++
}
pub fn (mut box Mailbox) recv() ?MboxMsg {
	if box.pending_read == box.pending_len { return none }
	if box.empty_polls[box.pending_read] > 0 {
		box.empty_polls[box.pending_read]--
		return none
	}
	message := box.pending[box.pending_read]
	box.pending_read++
	return message
}
pub fn (mut _ Mailbox) recv_blocking(_ int) ?MboxMsg { return none }

pub fn (box &Mailbox) sent_at(index int) MboxMsg {
	assert index < box.sent && index < box.sent_messages.len
	return box.sent_messages[index]
}

pub fn (box &Mailbox) attempted_at(index int) MboxMsg {
	assert index < box.attempts && index < box.attempted_messages.len
	return box.attempted_messages[index]
}

pub fn (mut box Mailbox) send(message MboxMsg) bool {
	if on_send != unsafe { nil } { on_send() }
	index := box.attempts
	box.attempts++
	mut timeout := false
	if index < box.attempted_messages.len {
		box.attempted_messages[index] = message
		timeout = box.send_timeout_mask & (u16(1) << index) != 0
	}
	if box.fail_next_send || timeout {
		box.fail_next_send = false
		return false
	}
	if box.sent < box.sent_messages.len { box.sent_messages[box.sent] = message }
	box.sent++
	box.last = message
	return true
}

pub fn (mut box Mailbox) send_timed(message MboxMsg) bool {
	box.timed_attempts++
	return box.send(message)
}

pub fn (mut box Mailbox) send_timed_irq(message MboxMsg, irq u32) bool {
	assert irq == 575
	box.irq_send_attempts++
	return box.send_timed(message)
}
