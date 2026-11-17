// SPDX-License-Identifier: GPL-2.0-or-later
module syncobj

import memory

pub fn run_query_trace() {
	values := [u64(0), 1, 2, 3, u64(1) << 63, ~u64(0)]!
	for a in values { for b in values { for c in values {
		for predecessor in 0 .. 3 { for mask in 0 .. 8 {
			mut obj := SyncObj{}
			mut binary := DmaFence{}
			if predecessor != 0 { replace_fence(&obj, &binary) }
			if predecessor == 2 { signal(&binary) }
			mut leaves := [3]DmaFence{}
			mut nodes := unsafe { [3]&DmaFence{} }
			for index, point in [a, b, c]! {
				node := reserve_chain() or { panic('reserve') }
				assert add_chain_point(&obj, node, unsafe { &leaves[index] }, point)
				nodes[index] = node
			}
			for index in 0 .. 3 { if mask & (1 << index) != 0 { signal(unsafe { &leaves[index] }) } }
			for submitted in [false, true]! { println(query_timeline_point(&obj, submitted)) }
			signal(&binary)
			for index in 0 .. 3 { signal(unsafe { &leaves[index] }) }
			for node in nodes { assert is_signaled(node); memory.free(voidptr(node)) }
		} }
	} } }
}
