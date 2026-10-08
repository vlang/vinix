// Preserve the original six independent protocol/source scenarios.
module zonemodel

import heapmodel
import os

pub fn migrating_ownership() {
	for limit in [0, 1, 2, 4] {
		mut rng := heapmodel.random(u64(0x584e55 + limit))
		mut zone := new_zone(127, 8, limit)
		mut caches := []&Cache{}
		for _ in 0 .. 4 { caches << new_cache() }
		mut live := []u64{}
		for step in 0 .. 20000 {
			mut cache := caches[rng.below(4)]
			if live.len == 0 || (live.len < 800 && rng.below(10) < 6) {
				address := zone.allocate(mut cache)
				if address != 0 { assert address !in live; live << address }
			} else {
				index := rng.below(live.len)
				address := live[index]
				live.delete(index)
				assert zone.release(address, mut cache)
				assert !zone.release(address, mut cache)
			}
			if step % 71 == 0 { zone.drain(mut cache); zone.drain_recirc() }
			zone.check(caches)
			mut expected := map[u64]bool{}
			for address in live { expected[address] = true }
			assert expected == zone.live
		}
		for address in live { assert zone.release(address, mut caches[0]) }
		for mut cache in caches { zone.drain(mut cache) }
		zone.drain_recirc()
		zone.check(caches)
		assert zone.available() == 127 * 8
		for {
			zone.reclaim() or { break }
			zone.check(caches)
		}
		assert zone.available() == 0
	}
}

pub fn cached_pages() {
	mut zone := new_zone(64, 1, 2)
	mut cache := new_cache()
	address := zone.allocate(mut cache)
	assert zone.release(address, mut cache)
	zone.reclaim() or {
		zone.drain(mut cache)
		zone.drain_recirc()
		assert zone.reclaim() or { panic('backing not reclaimable') } == 0
		zone.check([cache])
		return
	}
	assert false, 'cached backing reclaimed'
}

pub fn live_survivor() {
	mut zone := new_zone(64, 1, 2)
	mut cache := new_cache()
	address := zone.allocate(mut cache)
	zone.drain(mut cache)
	zone.drain_recirc()
	zone.reclaim() or {
		assert zone.available() == 63
		mut direct := &Cache(unsafe { nil })
		assert zone.release(address, mut direct)
		assert zone.reclaim() or { panic('backing not reclaimable') } == 0
		zone.check([cache])
		return
	}
	assert false, 'live backing reclaimed'
}

pub fn failed_batch() {
	mut zone := new_zone(64, 1, 2)
	mut cache := new_cache()
	zone.reserve(65, mut cache) or {
		assert zone.available() == 64
		zone.check([cache])
		return
	}
	assert false, 'oversized batch reserved'
}

pub fn partial_swap() {
	mut cache := new_cache()
	cache.alloc.items = [u64(1), 2]
	for address in 3 .. 35 { cache.free.items << u64(address) }
	assert cache.push(99)
	assert cache.free.items == [u64(1), 2, 99]
	assert cache.alloc.items.len == magazine_capacity
}

fn required_index(source string, needle string) int {
	return source.index(needle) or { panic('Missing ' + needle) }
}

pub fn source_integration(root string) ! {
	zone := os.read_file(os.join_path(root, 'kernel/xnualloc/zone.v'))!
	bitmap := os.read_file(os.join_path(root, 'kernel/xnualloc/bitmap.v'))!
	bridge := os.read_file(os.join_path(root, 'kernel/memory/xnu_zone_heap.v'))!
	physical := os.read_file(os.join_path(root, 'kernel/memory/physical.v'))!
	assert !zone.contains('mut rr u16')
	assert bitmap.contains('pub const no_element = u64(0xffffffffffffffff)')
	assert !bitmap.contains('pub const no_element = u64(-1)')
	assert zone.contains('z.zone_element_resolve_from(z.full, addr)')
	assert zone.contains('z.zone_element_resolve_from(z.partial, addr)')
	assert zone.contains('z.zone_element_resolve_from(z.empty, addr)')
	assert !zone.contains('heads := [z.full, z.partial, z.empty]!')
	assert zone.contains('z.zone_mark_valid(addr)')
	free_body := bridge.all_after('fn xnu_heap_free(').all_before('fn xnu_heap_realloc')
	assert required_index(free_body, 'zone_mark_invalid') < required_index(free_body, 'C.memset')
	assert required_index(free_body, 'C.memset') < required_index(free_body, 'zfree_ext')
	cache := bridge.all_after('fn (mut h XnuHeapClass) cache_locked').all_before('fn (mut h XnuHeapClass) grow_locked')
	assert required_index(cache, 'if count == 0') < required_index(cache, 'xnu_heap_cpu_number()')
	assert cache.contains('allow_create && h.zone.elems_free != 0')
	assert physical.contains('return xnu_heap_alloc(size)')
	assert physical.contains('return xnu_heap_realloc(ptr, new_size)')
	for arch in ['x86', 'aarch64'] {
		smp := os.read_file(os.join_path(root, 'kernel', arch, 'smp/smp.v'))!
		assert required_index(smp, 'for katomic.load(&cpu_local.online)') < required_index(smp, 'memory.heap_enable_cpu_caches')
	}
}
