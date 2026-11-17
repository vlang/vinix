// SPDX-License-Identifier: GPL-2.0-or-later
module fake

import drm.syncobj

// Fake completion workers can finish in any order, including on one queue.
// Each submission is therefore an independent timeline. A shared context would
// let dma-fence merging discard an earlier job that is still pending.
fn new_submission_fence() ?&syncobj.DmaFence {
	context := syncobj.new_queue_context() or { return none }
	return syncobj.new_fence(context, 1)
}
