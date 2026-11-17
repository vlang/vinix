// SPDX-License-Identifier: GPL-2.0-or-later
module syncobj

import memory
import time

pub fn check_shared_timeline_stub() {
	before := memory.attempts()
	first := shared_timeline_stub()
	stamp := snapshot(first).timestamp_ns
	assert stamp != 0 && snapshot(first).kind == .stub
	assert first.context == 0 && first.seqno == 0 && get_error(first) == 0
	assert first.queue_context == 0 && !first.chain && !first.chain_reserved
	for _ in 0 .. 1000 {
		time.advance()
		assert shared_timeline_stub() == first
		signal_error(first, -5); signal(first)
		assert snapshot(first).timestamp_ns == stamp && get_error(first) == 0
	}
	assert memory.attempts() == before
}

// Fixture-only retirement after every synchronous consumer/callback has
// returned. Production published metadata remains retained. Never free the
// permanent shared payload, nor any borrowed predecessor passed as stop.
pub fn retire_timeline_signal_chain_for_checks(head &DmaFence, stop &DmaFence) {
	mut cursor := unsafe { head }
	for cursor != stop {
		assert cursor != unsafe { nil } && cursor.chain && !cursor.chain_reserved
		assert is_signaled(cursor) && cursor.chain_waiters == unsafe { nil }
		assert !cursor.chain_notify_queued && cursor.chain_notify_next == unsafe { nil }
		next := unsafe { cursor.chain_prev }
		unsafe { cursor.waiters.free() }
		memory.free(voidptr(cursor))
		cursor = unsafe { next }
	}
}

pub fn assert_timeline_signal_payload_for_checks(head &DmaFence) {
	assert head.chain && head.chain_payload == shared_timeline_stub()
}
