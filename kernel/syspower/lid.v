// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The lid of a laptop.
//
// Closing it puts the machine to sleep, the way `mem` in /sys/power/state
// does, unless /sys/power/lid/action says to ignore it -- a laptop driving an
// external display with its lid shut wants that. Opening it is a wake source.
// The driver that hears the lid reports each change here, from a thread.
@[has_globals]
module syspower

import event
import katomic
import wakesrc

pub enum LidAction {
	suspend
	ignore
}

// The pending bit after the buttons'.
const lid_bit = u32(1) << 8

__global (
	// 0 unknown (no lid), 1 open, 2 closed.
	syspower_lid_state  u32
	syspower_lid_action LidAction
	syspower_lid_closes u64
)

// A lid exists and is in this position: what the driver says when it finds
// one. Nothing is done about a lid that is already shut when the machine
// starts.
pub fn lid_found(closed bool) {
	katomic.store(mut &syspower_lid_state, if closed { u32(2) } else { u32(1) })
}

// The lid moved.
pub fn lid(closed bool) {
	before := katomic.load(&syspower_lid_state)
	katomic.store(mut &syspower_lid_state, if closed { u32(2) } else { u32(1) })
	if !closed {
		wakesrc.report(.lid)
		return
	}
	if before == 2 {
		// Firmware saying it twice is not two closings.
		return
	}
	katomic.inc(mut &syspower_lid_closes)
	if syspower_lid_action == .ignore || sleeping() {
		return
	}
	for {
		pending := katomic.load(&syspower_pending)
		if pending & lid_bit != 0 || katomic.cas(mut &syspower_pending, pending, pending | lid_bit) {
			break
		}
	}
	event.trigger(mut syspower_wake, false)
}

pub fn lid_state_name() string {
	return match katomic.load(&syspower_lid_state) {
		1 { 'open' }
		2 { 'closed' }
		else { 'unknown' }
	}
}

pub fn lid_action() LidAction {
	return syspower_lid_action
}

pub fn set_lid_action(action LidAction) {
	syspower_lid_action = action
}

pub fn lid_closes() u64 {
	return katomic.load(&syspower_lid_closes)
}

// The lid was shut a moment ago: sleep, unless it has been opened again
// since, which is what a lid closed by mistake looks like.
fn lid_closed_action() {
	if katomic.load(&syspower_lid_state) != 2 || syspower_lid_action == .ignore {
		return
	}
	enter_sleep(if mem_is_deep() { SleepDepth.deep } else { SleepDepth.idle })
}
