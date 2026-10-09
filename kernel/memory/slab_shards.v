// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module memory

import katomic

const max_slab_shards = 8

__global (
	slab_shards      [max_slab_shards][18]Slab
	slab_shard_count u64
)

// SMP publishes this once all CPU identity registers are valid. Existing boot
// objects retain their original slab pointer. Cross-CPU frees use the header's
// owner, so migration and remote frees require no deferred-object queue.
fn enable_slab_shards(count u64) {
	if count <= 1 { return }
	limit := if count < max_slab_shards { count } else { u64(max_slab_shards) }
	for row := u64(0); row < limit; row++ {
		for i in 0 .. slabs.len {
			if slabs[i].ent_size != 0 { slab_shards[row][i].init(slabs[i].ent_size) }
		}
	}
	katomic.store(mut &slab_shard_count, limit)
}

fn current_slab_shard() int {
	count := katomic.load(&slab_shard_count)
	if count == 0 { return -1 }
	return int(slab_cpu_number() % count)
}

fn class_snapshot(s &Slab) HeapClass {
	mut slab := unsafe { s }
	slab.@lock.acquire()
	value := HeapClass{ size: slab.ent_size, live: slab.live, pages: slab.pages }
	slab.@lock.release()
	return value
}

fn trim_slab(s &Slab) u64 {
	mut slab := unsafe { s }
	slab.@lock.acquire()
	base := slab.spare
	slab.spare = 0
	if base != 0 {
		mut hdr := unsafe { &SlabHeader(base) }
		hdr.magic = 0
		slab.pages--
	}
	slab.@lock.release()
	if base == 0 { return 0 }
	check_empty_page(unsafe { &SlabHeader(base) }, slab.ent_size)
	pmm_free(voidptr(base - higher_half), 1)
	return page_size
}
