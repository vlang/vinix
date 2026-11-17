// SPDX-License-Identifier: GPL-2.0-or-later
module syncobj

// Serial fixture only. Restore the allocator before running any other suite.
pub fn set_context_for_fake_checks(next u64) u64 {
	queue_context_lock.acquire()
	old := queue_contexts.next
	queue_contexts.next = next
	queue_context_lock.release()
	return old
}
