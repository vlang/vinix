// SPDX-License-Identifier: GPL-2.0-or-later
module main

// malloc_zone_t's public ARM64 prefix, through its version-5 memalign slot.
// These are guest callbacks, never registered with the host's native malloc.
struct DarwinHeapZone {
mut:
	api [15]u64
	introspection [9]u64
	next &DarwinHeapZone = unsafe { nil }
	blocks &DarwinHeapBlock = unsafe { nil }
	count u32
	bytes usize
	peak usize
}

struct DarwinHeapBlock {
mut:
	hash_next &DarwinHeapBlock = unsafe { nil }
	next &DarwinHeapBlock = unsafe { nil }
	previous &DarwinHeapBlock = unsafe { nil }
	zone &DarwinHeapZone = unsafe { nil }
	pointer voidptr
	capacity usize
}

// All heap metadata shares the existing namespace/fork gate. Payloads remain
// ordinary native allocations, with no hidden prefix or guest-pointer reads.
__global heap_guard_depth = u64(0)
fn heap_lock() { C.ios_mach_threads_lock(); C.ios_store_pointer(unsafe { &heap_guard_depth }, 1) }
fn heap_unlock() { C.ios_store_pointer(unsafe { &heap_guard_depth }, 0); C.ios_mach_threads_unlock() }

fn heap_zone_initialize(mut zone DarwinHeapZone) {
	zone.api[2] = u64(unsafe { voidptr(darwin_zone_size) })
	zone.api[3] = u64(unsafe { voidptr(darwin_zone_malloc) })
	zone.api[4] = u64(unsafe { voidptr(darwin_zone_calloc) })
	zone.api[5] = u64(unsafe { voidptr(darwin_zone_valloc) })
	zone.api[6] = u64(unsafe { voidptr(darwin_zone_free) })
	zone.api[7] = u64(unsafe { voidptr(darwin_zone_realloc) })
	zone.api[8] = u64(unsafe { voidptr(darwin_zone_destroy) })
	zone.api[9] = u64(c'Vinix malloc zone')
	zone.api[12] = u64(unsafe { &zone.introspection[0] })
	zone.api[13] = 5
	zone.api[14] = u64(unsafe { voidptr(darwin_zone_memalign) })
	zone.introspection[0] = u64(unsafe { voidptr(heap_zone_enumerator) })
	zone.introspection[1] = u64(unsafe { voidptr(heap_zone_good_size) })
	zone.introspection[2] = u64(unsafe { voidptr(darwin_zone_check) })
	zone.introspection[3] = u64(unsafe { voidptr(heap_zone_print) })
	zone.introspection[4] = u64(unsafe { voidptr(heap_zone_log) })
	zone.introspection[5] = u64(unsafe { voidptr(heap_zone_force_lock) })
	zone.introspection[6] = u64(unsafe { voidptr(heap_zone_force_unlock) })
	zone.introspection[7] = u64(unsafe { voidptr(darwin_zone_statistics) })
	zone.introspection[8] = u64(unsafe { voidptr(heap_zone_locked) })
}

fn heap_start() {
	heap_zone_initialize(mut system_data.default_heap)
	system_data.heap_zones = unsafe { &system_data.default_heap }
}

fn heap_zone_find(pointer voidptr) &DarwinHeapZone {
	if system_data == unsafe { nil } { return unsafe { nil } }
	mut zone := system_data.heap_zones
	for zone != unsafe { nil } { if voidptr(zone) == pointer { return zone }; zone = zone.next }
	return unsafe { nil }
}

fn heap_bucket(pointer voidptr) u64 { value := u64(pointer) >> 4; return (value ^ (value >> 14)) & 1023 }
fn heap_block_find(pointer voidptr) &DarwinHeapBlock {
	if system_data == unsafe { nil } || pointer == unsafe { nil } { return unsafe { nil } }
	mut block := system_data.heap_blocks[heap_bucket(pointer)]
	for block != unsafe { nil } { if block.pointer == pointer { return block }; block = block.hash_next }
	return unsafe { nil }
}

fn heap_capacity(size usize) ?usize {
	if size > usize(0x7fffffffffffffff) - 15 { return none }
	return if size == 0 { usize(16) } else { (size + 15) & ~usize(15) }
}

fn heap_allocate(mut zone DarwinHeapZone, size usize, alignment usize, clear bool) voidptr {
	capacity := heap_capacity(size) or { darwin_set_errno(12); return unsafe { nil } }
	if zone.count == ~u32(0) || capacity > ~usize(0) - zone.bytes { darwin_set_errno(12); return unsafe { nil } }
	mut block := unsafe { &DarwinHeapBlock(C.calloc(1, sizeof(DarwinHeapBlock))) }
	if block == unsafe { nil } { darwin_set_errno(12); return unsafe { nil } }
	mut pointer := unsafe { voidptr(nil) }
	if alignment == 0 { pointer = C.malloc(capacity) }
	else if C.posix_memalign(unsafe { voidptr(&pointer) }, alignment, capacity) != 0 { pointer = unsafe { nil } }
	if pointer == unsafe { nil } { C.free(block); darwin_set_errno(12); return unsafe { nil } }
	if clear { unsafe { C.memset(pointer, 0, capacity) } }
	bucket := heap_bucket(pointer)
	unsafe { *block = DarwinHeapBlock{pointer: pointer, capacity: capacity, zone: &zone,
		hash_next: system_data.heap_blocks[bucket], next: zone.blocks} }
	if zone.blocks != unsafe { nil } { zone.blocks.previous = block }
	zone.blocks = block; system_data.heap_blocks[bucket] = block
	zone.count++; zone.bytes += capacity
	if zone.bytes > zone.peak { zone.peak = zone.bytes }
	return pointer
}

fn heap_release(block &DarwinHeapBlock) {
	mut zone := block.zone
	mut link := unsafe { &system_data.heap_blocks[heap_bucket(block.pointer)] }
	for unsafe { *link } != unsafe { nil } && voidptr(unsafe { *link }) != voidptr(block) { link = unsafe { &(*link).hash_next } }
	if unsafe { *link } == unsafe { nil } { panic('iOS: heap hash ownership lost') }
	unsafe { *link = block.hash_next }
	if block.previous == unsafe { nil } { zone.blocks = block.next } else { mut previous := block.previous; previous.next = block.next }
	if block.next != unsafe { nil } { mut next := block.next; next.previous = block.previous }
	zone.count--; zone.bytes -= block.capacity
	C.free(block.pointer); C.free(block)
}

fn darwin_zone_create(_ usize, flags u32) voidptr {
	if system_data == unsafe { nil } || flags != 0 { darwin_set_errno(45); return unsafe { nil } }
	saved_errno := unsafe { *C.ios_errno_address() }
	heap_lock(); defer { heap_unlock() }
	mut zone := unsafe { &DarwinHeapZone(C.calloc(1, sizeof(DarwinHeapZone))) }
	if zone == unsafe { nil } { darwin_set_errno(12); return unsafe { nil } }
	heap_zone_initialize(mut zone); zone.next = system_data.heap_zones; system_data.heap_zones = zone
	darwin_set_errno(saved_errno); return voidptr(zone)
}

fn darwin_default_zone() voidptr {
	if system_data == unsafe { nil } { return unsafe { nil } }
	return unsafe { voidptr(&system_data.default_heap) }
}

fn darwin_zone_malloc(pointer voidptr, size usize) voidptr { return heap_zone_allocate(pointer, size, 0, false) }
fn darwin_zone_calloc(pointer voidptr, count usize, size usize) voidptr {
	if size != 0 && count > ~usize(0) / size { darwin_set_errno(12); return unsafe { nil } }
	return heap_zone_allocate(pointer, count * size, 0, true)
}
fn darwin_zone_valloc(pointer voidptr, size usize) voidptr { return heap_zone_allocate(pointer, size, usize(C.getpagesize()), false) }
fn darwin_zone_memalign(pointer voidptr, alignment usize, size usize) voidptr {
	// Darwin leaves errno untouched for invalid zone-memalign alignments.
	if alignment < 8 || alignment & (alignment - 1) != 0 { return unsafe { nil } }
	return heap_zone_allocate(pointer, size, alignment, false)
}
fn heap_zone_allocate(pointer voidptr, size usize, alignment usize, clear bool) voidptr {
	saved_errno := unsafe { *C.ios_errno_address() }
	heap_lock(); defer { heap_unlock() }
	mut zone := heap_zone_find(pointer)
	if zone == unsafe { nil } { darwin_set_errno(22); return unsafe { nil } }
	result := heap_allocate(mut zone, size, alignment, clear)
	if result != unsafe { nil } { darwin_set_errno(saved_errno) }
	return result
}

fn darwin_zone_size(pointer voidptr, allocation voidptr) usize {
	saved_errno := unsafe { *C.ios_errno_address() }; defer { darwin_set_errno(saved_errno) }
	heap_lock(); defer { heap_unlock() }
	block := heap_block_find(allocation)
	if block == unsafe { nil } || voidptr(block.zone) != pointer { return 0 }
	return block.capacity
}
fn darwin_zone_from_pointer(pointer voidptr) voidptr {
	saved_errno := unsafe { *C.ios_errno_address() }; defer { darwin_set_errno(saved_errno) }
	heap_lock(); defer { heap_unlock() }
	block := heap_block_find(pointer)
	return if block == unsafe { nil } { unsafe { voidptr(nil) } } else { voidptr(block.zone) }
}

fn darwin_zone_free(pointer voidptr, allocation voidptr) {
	saved_errno := unsafe { *C.ios_errno_address() }; defer { darwin_set_errno(saved_errno) }
	if allocation == unsafe { nil } { return }
	heap_lock(); defer { heap_unlock() }
	block := heap_block_find(allocation)
	if block == unsafe { nil } || voidptr(block.zone) != pointer { panic('iOS: malloc zone free requires its own live allocation') }
	heap_release(block)
}

fn heap_resize(mut zone DarwinHeapZone, block &DarwinHeapBlock, size usize) voidptr {
	replacement := heap_allocate(mut zone, size, 0, false)
	if replacement == unsafe { nil } { return unsafe { nil } }
	amount := if block.capacity < size { block.capacity } else { size }
	unsafe { C.memcpy(replacement, block.pointer, amount) }
	heap_release(block)
	return replacement
}

fn darwin_zone_realloc(pointer voidptr, allocation voidptr, size usize) voidptr {
	if allocation == unsafe { nil } { return darwin_zone_malloc(pointer, size) }
	saved_errno := unsafe { *C.ios_errno_address() }
	heap_lock(); defer { heap_unlock() }
	mut zone := heap_zone_find(pointer); block := heap_block_find(allocation)
	if zone == unsafe { nil } || block == unsafe { nil } || voidptr(block.zone) != pointer { darwin_set_errno(22); return unsafe { nil } }
	result := heap_resize(mut zone, block, size)
	if result != unsafe { nil } { darwin_set_errno(saved_errno) }
	return result
}

fn heap_zone_remove(zone &DarwinHeapZone) {
	for zone.blocks != unsafe { nil } { heap_release(zone.blocks) }
	mut link := unsafe { &system_data.heap_zones }
	for voidptr(unsafe { *link }) != voidptr(zone) { link = unsafe { &(*link).next } }
	unsafe { *link = zone.next }
	C.free(zone)
}
fn darwin_zone_destroy(pointer voidptr) {
	saved_errno := unsafe { *C.ios_errno_address() }; defer { darwin_set_errno(saved_errno) }
	heap_lock(); defer { heap_unlock() }
	zone := heap_zone_find(pointer)
	if zone == unsafe { nil } || pointer == darwin_default_zone() { panic('iOS: malloc zone destruction requires a live custom zone') }
	heap_zone_remove(zone)
}
fn heap_stop() {
	heap_lock(); defer { heap_unlock() }
	for system_data.heap_zones != unsafe { nil } {
		zone := system_data.heap_zones
		if voidptr(zone) == darwin_default_zone() {
			for zone.blocks != unsafe { nil } { heap_release(zone.blocks) }
			system_data.heap_zones = zone.next
		} else { heap_zone_remove(zone) }
	}
}

fn darwin_zone_check(pointer voidptr) i32 {
	saved_errno := unsafe { *C.ios_errno_address() }; defer { darwin_set_errno(saved_errno) }
	heap_lock(); defer { heap_unlock() }
	if system_data == unsafe { nil } { return 0 }
	mut zone := if pointer == unsafe { nil } { system_data.heap_zones } else { heap_zone_find(pointer) }
	if zone == unsafe { nil } { return 0 }
	for zone != unsafe { nil } {
		mut count := u32(0); mut total := usize(0); mut previous := unsafe { &DarwinHeapBlock(nil) }; mut block := zone.blocks
		for block != unsafe { nil } {
			if count == zone.count || block.pointer == unsafe { nil } || block.capacity < 16 || block.capacity & 15 != 0 || voidptr(block.zone) != voidptr(zone) || voidptr(block.previous) != voidptr(previous) || voidptr(heap_block_find(block.pointer)) != voidptr(block) { return 0 }
			count++; total += block.capacity; previous = block; block = block.next
		}
		if count != zone.count || total != zone.bytes || zone.peak < total { return 0 }
		if pointer != unsafe { nil } { break }; zone = zone.next
	}
	return 1
}

fn heap_zone_good_size(_ voidptr, size usize) usize { return heap_capacity(size) or { usize(0) } }
fn heap_zone_enumerator(_ u32, _ voidptr, _ u32, _ u64, _ voidptr, _ voidptr) i32 { return 46 }
fn heap_zone_print(_ voidptr, _ i32) { panic('iOS: malloc zone debug printing is not implemented') }
fn heap_zone_log(_ voidptr, _ voidptr) { panic('iOS: malloc zone allocation logging is not implemented') }
fn heap_zone_force_lock(_ voidptr) { heap_lock() }
fn heap_zone_force_unlock(_ voidptr) { heap_unlock() }
fn heap_zone_locked(_ voidptr) i32 { return if C.ios_load_pointer(unsafe { &heap_guard_depth }) != 0 { 1 } else { 0 } }
fn darwin_zone_statistics(pointer voidptr, output voidptr) {
	saved_errno := unsafe { *C.ios_errno_address() }; defer { darwin_set_errno(saved_errno) }
	if output == unsafe { nil } { return }
	heap_lock(); defer { heap_unlock() }
	zone := heap_zone_find(pointer)
	mut words := [4]u64{}
	if zone != unsafe { nil } { words[0] = u64(zone.count); words[1] = u64(zone.bytes); words[2] = u64(zone.peak); words[3] = u64(zone.bytes) }
	unsafe { C.memcpy(output, voidptr(&words[0]), 32) }
}

fn darwin_realloc(pointer voidptr, size usize) voidptr {
	if pointer == unsafe { nil } { return darwin_malloc(size) }
	saved_errno := unsafe { *C.ios_errno_address() }
	heap_lock(); defer { heap_unlock() }
	block := heap_block_find(pointer)
	if block == unsafe { nil } { return C.realloc(pointer, size) }
	mut zone := block.zone; result := heap_resize(mut zone, block, size)
	if result != unsafe { nil } { darwin_set_errno(saved_errno) }
	return result
}
fn darwin_calloc(count usize, size usize) voidptr {
	if system_data == unsafe { nil } { return C.calloc(count, size) }
	return darwin_zone_calloc(darwin_default_zone(), count, size)
}
fn darwin_posix_memalign(output &voidptr, alignment usize, size usize) i32 {
	saved_errno := unsafe { *C.ios_errno_address() }; defer { darwin_set_errno(saved_errno) }
	if alignment < 8 || alignment & (alignment - 1) != 0 || output == unsafe { nil } { return 22 }
	if system_data == unsafe { nil } { return C.posix_memalign(output, alignment, size) }
	result := darwin_zone_memalign(darwin_default_zone(), alignment, size)
	if result == unsafe { nil } { return 12 }
	unsafe { *output = result }; return 0
}
fn darwin_strdup(text &char) &char {
	size := darwin_strlen(text); result := darwin_malloc(size + 1)
	if result != unsafe { nil } { unsafe { C.memcpy(result, voidptr(text), size + 1) } }
	return unsafe { &char(result) }
}

fn malloc_zone_symbol(symbol string) ?u64 {
	return match symbol {
		'_malloc_create_zone' { u64(unsafe { voidptr(darwin_zone_create) }) }
		'_malloc_destroy_zone' { u64(unsafe { voidptr(darwin_zone_destroy) }) }
		'_malloc_default_zone' { u64(unsafe { voidptr(darwin_default_zone) }) }
		'_malloc_zone_malloc' { u64(unsafe { voidptr(darwin_zone_malloc) }) }
		'_malloc_zone_calloc' { u64(unsafe { voidptr(darwin_zone_calloc) }) }
		'_malloc_zone_valloc' { u64(unsafe { voidptr(darwin_zone_valloc) }) }
		'_malloc_zone_memalign' { u64(unsafe { voidptr(darwin_zone_memalign) }) }
		'_malloc_zone_realloc' { u64(unsafe { voidptr(darwin_zone_realloc) }) }
		'_malloc_zone_free' { u64(unsafe { voidptr(darwin_zone_free) }) }
		'_malloc_zone_from_ptr' { u64(unsafe { voidptr(darwin_zone_from_pointer) }) }
		'_malloc_zone_check' { u64(unsafe { voidptr(darwin_zone_check) }) }
		else { return none }
	}
}
