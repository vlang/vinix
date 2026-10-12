// SPDX-License-Identifier: GPL-2.0-or-later
module memory

import katomic

// Caller-owned statistics for opt-in native lifetime measurements. Boot has
// initialized the immutable class/shard registry; the caller holds no slab or
// PMM lock. Each class is sampled under its existing lock, independently of
// other classes. This is not an atomic whole-heap snapshot or XNU zone stats.
// Reject inadequate storage before writing. Unlike heap_classes(), this path
// allocates nothing and cannot warm an allocator shard while measuring it.
pub fn heap_classes_into(output &HeapClass, capacity int) int {
	$if xnu_zone ? { return -1 }
	mut needed := 0
	for i in 0 .. slabs.len {
		if slabs[i].ent_size != 0 { needed++ }
	}
	if output == unsafe { nil } || capacity < 0 || capacity < needed { return -1 }
	shards := katomic.load(&slab_shard_count)
	mut count := 0
	for i in 0 .. slabs.len {
		if slabs[i].ent_size == 0 { continue }
		original := class_snapshot(unsafe { &slabs[i] })
		mut live := original.live
		mut pages := original.pages
		for row := u64(0); row < shards; row++ {
			snapshot := class_snapshot(unsafe { &slab_shards[row][i] })
			live += snapshot.live
			pages += snapshot.pages
		}
		unsafe { output[count] = HeapClass{size: original.size, live: live, pages: pages} }
		count++
	}
	return count
}
