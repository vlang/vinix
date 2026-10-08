// Independent address-set model of the single-lock, non-SMR port protocol.
// This package does not import or execute the production allocator.
module zonemodel

pub const magazine_capacity = 32

pub struct Magazine {
pub mut:
	items []u64
}

pub struct Depot {
pub mut:
	full  []&Magazine
	empty []&Magazine
}

@[heap]
pub struct Cache {
pub mut:
	alloc &Magazine
	free_mag &Magazine
	depot Depot
	rr    int
}

pub fn new_cache() &Cache {
	mut empty := []&Magazine{}
	for _ in 0 .. 4 { empty << &Magazine{} }
	return &Cache{alloc: &Magazine{}, free_mag: &Magazine{}, depot: Depot{empty: empty}}
}

pub fn (mut cache Cache) pop() u64 {
	if cache.alloc.items.len == 0 && cache.free_mag.items.len != 0 {
		cache.alloc, cache.free_mag = cache.free_mag, cache.alloc
	}
	return if cache.alloc.items.len != 0 { cache.alloc.items.pop() } else { 0 }
}

pub fn (mut cache Cache) push(address u64) bool {
	if cache.free_mag.items.len == magazine_capacity && cache.alloc.items.len < magazine_capacity {
		cache.alloc, cache.free_mag = cache.free_mag, cache.alloc
	}
	if cache.free_mag.items.len == magazine_capacity { return false }
	cache.free_mag.items << address
	return true
}

pub struct Zone {
pub mut:
	capacity int
	free     []map[int]bool
	empty    []int
	partial  []int
	full     []int
	detached map[int]bool
	live     map[u64]bool
	recirc   Depot
	limit    int
}

pub fn new_zone(capacity int, pages int, limit int) Zone {
	assert capacity > 0 && capacity <= 256 && limit >= 0 && limit <= 4
	mut result := Zone{capacity: capacity, limit: limit}
	for p in 0 .. pages {
		mut free := map[int]bool{}
		for s in 0 .. capacity { free[s] = true }
		result.free << free
		result.empty.insert(0, p)
	}
	return result
}

pub fn encode(page int, slot int) u64 { return u64(page + 1) * 4096 + u64(slot) * 16 }

pub fn decode(address u64) (int, int) { return int(address / 4096) - 1, int(address % 4096 / 16) }

pub fn (zone Zone) available() int {
	mut result := 0
	for p, free in zone.free { if p !in zone.detached { result += free.len } }
	return result
}

fn remove_page(mut queue []int, page int) {
	index := queue.index(page)
	if index >= 0 { queue.delete(index) }
}

fn (mut zone Zone) queue(page int) {
	remove_page(mut zone.empty, page)
	remove_page(mut zone.partial, page)
	remove_page(mut zone.full, page)
	if zone.free[page].len == zone.capacity { zone.empty.insert(0, page) }
	else if zone.free[page].len != 0 { zone.partial.insert(0, page) }
	else { zone.full.insert(0, page) }
}

pub fn (mut zone Zone) reserve(count int, mut cache Cache) ?[]u64 {
	if count > zone.available() { return none }
	mut result := []u64{}
	for result.len < count {
		page := if zone.partial.len != 0 { zone.partial[0] } else { zone.empty[0] }
		for result.len < count && zone.free[page].len != 0 {
			start := (cache.rr + 1) % 256
			mut slot := 256
			mut first := 256
			for candidate in zone.free[page].keys() {
				if candidate < first { first = candidate }
				if candidate >= start && candidate < slot { slot = candidate }
			}
			if slot == 256 { slot = first }
			zone.free[page].delete(slot)
			cache.rr = slot
			result << encode(page, slot)
		}
		zone.queue(page)
	}
	return result
}

pub fn (mut zone Zone) drop(address u64) {
	page, slot := decode(address)
	assert page !in zone.detached && address !in zone.live
	assert slot !in zone.free[page]
	zone.free[page][slot] = true
	zone.queue(page)
}

fn move(mut source []&Magazine, mut destination []&Magazine, count int, head bool) {
	assert count > 0 && count <= source.len
	items := source[..count].clone()
	source.delete_many(0, count)
	if head { for index := items.len - 1; index >= 0; index-- { destination.insert(0, items[index]) } }
	else { destination << items }
}

fn take_first(mut queue []&Magazine) &Magazine {
	result := queue[0]
	queue.delete(0)
	return result
}

pub fn (mut zone Zone) allocate(mut cache Cache) u64 {
	mut address := cache.pop()
	if address == 0 {
		if zone.limit != 0 {
			if cache.depot.full.len == 0 {
				if cache.depot.empty.len >= zone.limit {
					move(mut cache.depot.empty, mut zone.recirc.empty, cache.depot.empty.len - zone.limit / 2, true)
				}
				count := int_min(zone.limit - cache.depot.empty.len, zone.recirc.full.len)
				if count != 0 { move(mut zone.recirc.full, mut cache.depot.full, count, false) }
			}
			if cache.depot.full.len != 0 {
				old := cache.alloc
				cache.alloc = take_first(mut cache.depot.full)
				assert old.items.len == 0
				cache.depot.empty.insert(0, old)
			}
		} else if zone.recirc.full.len != 0 {
			old := cache.alloc
			cache.alloc = take_first(mut zone.recirc.full)
			assert old.items.len == 0
			zone.recirc.empty.insert(0, old)
		}
		if cache.alloc.items.len == 0 && zone.available() != 0 {
			cache.alloc.items = zone.reserve(int_min(magazine_capacity, zone.available()), mut cache) or { []u64{} }
		}
		address = cache.pop()
	}
	if address != 0 {
		assert address !in zone.live
		zone.live[address] = true
	}
	return address
}

fn int_min(a int, b int) int { return if a < b { a } else { b } }

// A nil cache models the original direct-to-backing release path.
pub fn (mut zone Zone) release(address u64, mut cache Cache) bool {
	if address !in zone.live { return false }
	zone.live.delete(address)
	if unsafe { &cache != nil } {
		if cache.push(address) { return true }
		mut magazine := &Magazine(unsafe { nil })
		if zone.limit != 0 {
			if cache.depot.empty.len == 0 {
				if cache.depot.full.len >= zone.limit {
					move(mut cache.depot.full, mut zone.recirc.full, cache.depot.full.len - zone.limit / 2, false)
				}
				count := int_min(zone.limit - cache.depot.full.len, zone.recirc.empty.len)
				if count != 0 { move(mut zone.recirc.empty, mut cache.depot.empty, count, true) }
			}
			if cache.depot.empty.len != 0 { magazine = take_first(mut cache.depot.empty) }
			if magazine != unsafe { nil } {
				old := cache.free_mag
				cache.free_mag = magazine
				assert old.items.len == magazine_capacity && magazine.items.len == 0
				cache.depot.full << old
			}
		} else {
			if zone.recirc.empty.len != 0 { magazine = take_first(mut zone.recirc.empty) }
			else if cache.depot.empty.len != 0 { magazine = take_first(mut cache.depot.empty) }
			if magazine != unsafe { nil } {
				old := cache.free_mag
				cache.free_mag = magazine
				assert old.items.len == magazine_capacity && magazine.items.len == 0
				zone.recirc.full << old
			}
		}
		if magazine != unsafe { nil } { assert cache.push(address); return true }
	}
	zone.drop(address)
	return true
}

pub fn (mut zone Zone) drain_mag(mut magazine Magazine) {
	for address in magazine.items { zone.drop(address) }
	magazine.items.clear()
}

pub fn (mut zone Zone) drain(mut cache Cache) {
	zone.drain_mag(mut cache.alloc)
	zone.drain_mag(mut cache.free_mag)
	for cache.depot.full.len != 0 {
		mut magazine := take_first(mut cache.depot.full)
		zone.drain_mag(mut magazine)
		cache.depot.empty.insert(0, magazine)
	}
}

pub fn (mut zone Zone) drain_recirc() {
	for zone.recirc.full.len != 0 {
		mut magazine := take_first(mut zone.recirc.full)
		zone.drain_mag(mut magazine)
		zone.recirc.empty.insert(0, magazine)
	}
}

pub fn (mut zone Zone) reclaim() ?int {
	if zone.empty.len == 0 { return none }
	page := zone.empty[0]
	zone.empty.delete(0)
	assert zone.free[page].len == zone.capacity
	zone.detached[page] = true
	return page
}

pub fn (zone Zone) check(caches []&Cache) {
	mut magazines := zone.recirc.full.clone()
	magazines << zone.recirc.empty
	mut depots := [zone.recirc]
	for cache in caches {
		assert cache.alloc.items.len <= magazine_capacity && cache.free_mag.items.len <= magazine_capacity
		magazines << cache.alloc
		magazines << cache.free_mag
		magazines << cache.depot.full
		magazines << cache.depot.empty
		depots << cache.depot
	}
	assert magazines.len == caches.len * 6
	mut identities := map[u64]bool{}
	mut cached := map[u64]bool{}
	for magazine in magazines {
		identity := u64(unsafe { voidptr(magazine) })
		assert identity !in identities
		identities[identity] = true
		for address in magazine.items {
			assert address !in cached && address !in zone.live
			cached[address] = true
		}
	}
	for depot in depots {
		assert depot.full.all(it.items.len == magazine_capacity)
		assert depot.empty.all(it.items.len == 0)
	}
	mut reserved := map[u64]bool{}
	for page, free in zone.free {
		if page in zone.detached { continue }
		for slot in 0 .. zone.capacity { if slot !in free { reserved[encode(page, slot)] = true } }
	}
	mut expected := cached.clone()
	for address in zone.live.keys() { expected[address] = true }
	assert reserved == expected
	mut pages := map[int]bool{}
	for queue in [zone.empty, zone.partial, zone.full] {
		for page in queue { assert page !in pages; pages[page] = true }
	}
	mut attached := map[int]bool{}
	for page in 0 .. zone.free.len { if page !in zone.detached { attached[page] = true } }
	assert pages == attached
	assert zone.empty.all(zone.free[it].len == zone.capacity)
	assert zone.partial.all(zone.free[it].len > 0 && zone.free[it].len < zone.capacity)
	assert zone.full.all(zone.free[it].len == 0)
}
