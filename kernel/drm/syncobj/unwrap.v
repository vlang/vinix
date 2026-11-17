// SPDX-License-Identifier: GPL-2.0-or-later
module syncobj

// dma_fence_unwrap order: each chain payload's flat array, then previous chain.
pub struct FenceUnwrap {
mut:
	chain &DmaFence = unsafe { nil }
	array &DmaFence = unsafe { nil }
	index u32
}

fn unwrap_array(cursor &FenceUnwrap) &DmaFence {
	mut c := unsafe { cursor }
	c.array = chain_contained(c.chain)
	c.index = 0
	if c.array == unsafe { nil } { return unsafe { nil } }
	return if c.array.fence_array { unsafe { c.array.array_fences[0] } } else { unsafe { c.array } }
}

pub fn unwrap_first(head &DmaFence, cursor &FenceUnwrap) &DmaFence {
	unsafe { cursor.chain = head }
	return unwrap_array(cursor)
}

pub fn unwrap_next(cursor &FenceUnwrap) &DmaFence {
	mut c := unsafe { cursor }
	c.index++
	if c.array != unsafe { nil } && c.array.fence_array && c.index < c.array.array_count {
		return unsafe { c.array.array_fences[c.index] }
	}
	c.chain = chain_previous(c.chain)
	return unwrap_array(cursor)
}
