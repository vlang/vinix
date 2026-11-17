// SPDX-License-Identifier: GPL-2.0-or-later
module syncobj

pub enum FenceKind {
	generic
	stub
	queue
	chain
}

pub struct FenceSnapshot {
pub:
	status int
	timestamp_ns u64
	context u64
	seqno u64
	kind FenceKind
}

// Status/time are sampled together under the first-completion lock. A pending
// fence reports zero even if its producer has prepared an error before signal.
pub fn snapshot(fence &DmaFence) FenceSnapshot {
	if fence == unsafe { nil } { return FenceSnapshot{} }
	is_signaled(fence)
	return identity(fence)
}

// Names may be queried without enabling/refreshing chain completion (including
// on a detailed-info validation/allocation failure). Status here is only the
// already-published state; callers needing readiness use snapshot instead.
pub fn identity(fence &DmaFence) FenceSnapshot {
	if fence == unsafe { nil } { return FenceSnapshot{} }
	mut f := unsafe { fence }
	f.lock.acquire()
	result := FenceSnapshot{
		status: if !f.signaled { 0 } else if f.error != 0 { f.error } else { 1 }
		timestamp_ns: if f.signaled { f.timestamp_ns } else { 0 }
		context: f.context
		seqno: f.seqno
		kind: if f.chain { .chain } else if f.private_stub { .stub } else if f.queue_context != 0 { .queue } else { .generic }
	}
	f.lock.release()
	return result
}
