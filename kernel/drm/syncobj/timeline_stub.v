// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module syncobj

import katomic
import klock

__global timeline_stub_lock klock.Lock
__global timeline_stub_completion = DmaFence{}

// dma_fence_get_stub has permanent storage, context/seqno zero and a stable
// initialization timestamp. DRM startup initializes this once; the getter also
// closes first-use races without allocation. Binary SIGNAL keeps private stubs.
pub fn shared_timeline_stub() &DmaFence {
	timeline_stub_lock.acquire()
	if !timeline_stub_completion.signaled {
		timeline_stub_completion.private_stub = true
		timeline_stub_completion.timestamp_ns = now_ns()
		katomic.store(mut &timeline_stub_completion.signaled, true)
	}
	timeline_stub_lock.release()
	return unsafe { &timeline_stub_completion }
}
