// SPDX-License-Identifier: GPL-2.0-or-later
module syncobj

import katomic
import memory

// Like dma_fence_allocate_private_stub: a fresh successful completion with
// context/seqno zero and no queue provenance. Installed fence metadata follows
// the existing retention policy so captured snapshots survive replacement.
pub fn new_private_stub(timestamp_ns u64) ?&DmaFence {
	allocation := memory.malloc_packed_fallible(sizeof(DmaFence))
	if allocation == unsafe { nil } { return none }
	mut fence := unsafe { &DmaFence(allocation) }
	unsafe { *fence = DmaFence{ timestamp_ns: timestamp_ns } }
	katomic.store(mut &fence.signaled, true)
	return fence
}
