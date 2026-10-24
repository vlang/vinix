// SPDX-License-Identifier: GPL-2.0-or-later
module main

// A bounded local cache. Limits are advisory on Apple; this implementation
// evicts oldest insertions, including at the hard ceiling of 4096 entries.
// Native opaque ivars stay zero except the measured discarded-content flag.
struct CacheEntry { key u64 value u64 hash u64 cost u64 }
struct CacheCandidate { key u64 index int }
struct FoundationCache {
mut:
	initialized bool
	initializing bool
	active int
	version u64
	count_limit u64
	cost_limit u64
	cost u64
	evicts bool
	entries []CacheEntry
}
fn ns_cache_ivars() [10]string {
	return ['_cacheDelegate', '_cache', '_discardableContentState', '_evictOnSuspension', '_evictsDiscarded', '_moribund', '_doDelegateWillEvictValue', '_observesNotification', '_notificationToken', '_notificationLock']!
}
fn ns_cache_ivar_types() [10]string {
	return ['@"<NSCacheDelegate>"', '^{cache_s=}', 'C', 'B', 'B', 'B', 'B', 'B', 'Q', '{os_unfair_lock_s="_os_unfair_lock_opaque"I}']!
}
fn ns_cache_offsets() [10]int { return [8, 16, 24, 25, 26, 27, 28, 29, 32, 40]! }
fn ns_cache_metadata() {
	mut cls := ios_runtime.classes[ios_runtime.names['NSCache']] or { panic('iOS: missing NSCache') }
	for i, name in ns_cache_ivars() {
		cls.ivars[name] = &ObjIvar{name: name.clone(), types: ns_cache_ivar_types()[i].clone(), offset: i64(ns_cache_offsets()[i]), size: if i < 2 || i == 8 { u64(8) } else if i == 9 { u64(4) } else { u64(1) }}
	}
}
fn ns_cache_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'NSCache' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic cache superclass chain')
}
fn ns_cache_require_class(cls u64) {
	if ns_cache_family(cls) && cls != ios_runtime.names['NSCache'] { panic('iOS: custom cache subclass construction is not implemented') }
}
fn ns_cache_install(cls u64, mut header ObjHeader) {
	if cls != ios_runtime.names['NSCache'] { return }
	header.cache = unsafe { &FoundationCache(C.calloc(1, sizeof(FoundationCache))) }
	if header.cache == unsafe { nil } { panic('iOS: cannot allocate cache state') }
	header.cache.entries = []CacheEntry{}
	header.cache.entries.flags |= .noslices
}
// Caller holds the runtime lock. Never infer ownership from the current isa.
fn ns_cache_storage(object u64, initialized bool) &ObjHeader {
	header := obj_header(object)
	if header.cache == unsafe { nil } || header.destroying || header.destroyed
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 || header.native_size < 48
		|| header.cls != header.allocation_cls || read64(object) != header.allocation_cls
		|| header.allocation_cls != ios_runtime.names['NSCache'] { panic('iOS: cache requires live owned built-in storage') }
	if initialized && (!header.cache.initialized || header.cache.initializing) { panic('iOS: cache requires initialization') }
	for offset := u64(8); offset < 48; offset++ {
		expected := if offset == 26 && header.cache.evicts { u8(1) } else { u8(0) }
		if unsafe { *(&u8(object + offset)) } != expected { panic('iOS: cache opaque body was changed') }
	}
	return header
}
fn ns_cache_initialize(object u64) u64 {
	C.ios_objc_initialize_lock()
	mut header := ns_cache_storage(object, false)
	if header.cache.initialized || header.cache.initializing { panic('iOS: cache is already initialized') }
	header.cache.initializing = true; objc_retain(object)
	C.ios_objc_initialize_unlock()
	name := owned_string('')
	C.ios_objc_initialize_lock()
	header = ns_cache_storage(object, false)
	if !header.cache.initializing || header.cache.initialized || header.fields[0] != 0
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 1 { panic('iOS: cache string constructor changed destination storage') }
	header.cache.initializing = false
	if name == 0 {
		if header.caller_storage { panic('iOS: failed cache initializer cannot consume caller storage') }
		C.ios_objc_initialize_unlock(); objc_release(object); objc_release(object); return 0
	}
	un_request_text(name)
	header.fields[0] = name; header.cache.initialized = true; header.cache.evicts = true
	unsafe { *(&u8(object + 26)) = 1 }
	C.ios_objc_initialize_unlock(); objc_release(object)
	return object
}
fn ns_cache_enter(object u64) {
	C.ios_objc_initialize_lock()
	mut header := ns_cache_storage(object, true)
	header.cache.active++; objc_retain(object)
	C.ios_objc_initialize_unlock()
}
fn ns_cache_leave(object u64) {
	C.ios_objc_initialize_lock()
	mut header := ns_cache_storage(object, true)
	header.cache.active--
	C.ios_objc_initialize_unlock(); objc_release(object)
}
fn ns_cache_retire(header &ObjHeader) {
	C.ios_objc_initialize_lock(); defer { C.ios_objc_initialize_unlock() }
	if header.cache != unsafe { nil } && (header.cache.active != 0 || header.cache.initializing) { panic('iOS: destroying an active cache') }
}
fn ns_cache_release_entry(entry CacheEntry) { objc_release(entry.key); objc_release(entry.value) }
fn ns_cache_dispose(object u64, mut header ObjHeader) {
	state := header.cache; header.cache = unsafe { nil }
	if state == unsafe { nil } { return }
	unsafe { C.memset(voidptr(object + 8), 0, 40) }
	for entry in state.entries { ns_cache_release_entry(entry) }
	unsafe { state.entries.free() }; C.free(state)
}
fn ns_cache_set_name(object u64, input u64) {
	ns_cache_enter(object); defer { ns_cache_leave(object) }
	C.ios_objc_initialize_lock()
	snapshot := if input == 0 { ''.clone() } else { un_request_text(input).clone() }
	C.ios_objc_initialize_unlock()
	defer { unsafe { snapshot.free() } }
	// Apple's cache stores the UTF-8 name through a C string.
	end := snapshot.index_u8(0)
	name := owned_string(unsafe { tos(snapshot.str, if end >= 0 { end } else { snapshot.len }) })
	if name == 0 { panic('iOS: cache name constructor failed') }
	C.ios_objc_initialize_lock()
	mut header := ns_cache_storage(object, true); un_request_text(name)
	old := header.fields[0]; header.fields[0] = name
	C.ios_objc_initialize_unlock(); objc_release(old)
}
// Hash/equality, string constructors and dealloc callbacks run outside the
// runtime lock. Pin candidate keys until a version-checked update commits.
fn ns_cache_candidates(object u64, hash u64) ([]CacheCandidate, u64) {
	C.ios_objc_initialize_lock(); defer { C.ios_objc_initialize_unlock() }
	state := ns_cache_storage(object, true).cache
	mut candidates := []CacheCandidate{cap: state.entries.len}
	for i, entry in state.entries { if entry.hash == hash { candidates << CacheCandidate{objc_retain(entry.key), i} } }
	return candidates, state.version
}
fn ns_cache_release_candidates(candidates []CacheCandidate) {
	for candidate in candidates { objc_release(candidate.key) }
	unsafe { candidates.free() }
}
fn ns_cache_trim(mut state FoundationCache, mut removed []CacheEntry) {
	for state.entries.len > 0 && (state.entries.len > 4096
		|| (state.count_limit != 0 && u64(state.entries.len) > state.count_limit)
		|| (state.cost_limit != 0 && state.cost > state.cost_limit)) {
		entry := state.entries[0]; state.entries.delete(0); state.cost -= entry.cost; removed << entry
	}
}
fn ns_cache_entry(object u64, key u64, value u64, cost u64, operation string) u64 {
	ns_cache_enter(object); defer { ns_cache_leave(object) }
	if key == 0 {
		if operation == 'set' { panic('iOS: cache requires a nonnil key') }
		return 0
	}
	if operation == 'set' && value == 0 { panic('iOS: cache requires a nonnil value') }
	objc_retain(key); defer { objc_release(key) }
	if operation == 'set' {
		objc_retain(value)
		// Discardable-content ownership is a separate protocol implementation.
		for selector in ['beginContentAccess', 'endContentAccess', 'discardContentIfPossible', 'isContentDiscarded']! {
			if objc_responds(value, selector.str) { panic('iOS: cache discardable content is not implemented') }
		}
	}
	defer { if operation == 'set' { objc_release(value) } }
	hash := ns_set_item_hash(key)
	for _ in 0 .. 64 {
		candidates, version := ns_cache_candidates(object, hash)
		mut index := -1
		for candidate in candidates { if ns_set_item_equal(candidate.key, key, 0) { index = candidate.index; break } }
		C.ios_objc_initialize_lock()
		mut state := ns_cache_storage(object, true).cache
		if state.version != version { C.ios_objc_initialize_unlock(); ns_cache_release_candidates(candidates); continue }
		mut removed := []CacheEntry{cap: state.entries.len + 1}
		mut result := u64(0)
		if operation == 'get' {
			if index >= 0 { result = objc_retain(state.entries[index].value) }
		} else {
			if index >= 0 { entry := state.entries[index]; state.entries.delete(index); state.cost -= entry.cost; removed << entry }
			if operation == 'set' {
				// Evict before adding rather than allowing unsigned total-cost wrap.
				for state.entries.len > 0 && cost > ~u64(0) - state.cost { entry := state.entries[0]; state.entries.delete(0); state.cost -= entry.cost; removed << entry }
				state.entries << CacheEntry{objc_retain(key), objc_retain(value), hash, cost}; state.cost += cost
				ns_cache_trim(mut state, mut removed)
			}
			state.version++
		}
		C.ios_objc_initialize_unlock()
		ns_cache_release_candidates(candidates)
		for entry in removed { ns_cache_release_entry(entry) }; unsafe { removed.free() }
		return objc_autorelease(result)
	}
	panic('iOS: cache key callbacks or contention prevented progress')
}
fn ns_cache_clear_or_limit(object u64, selector string, value u64) {
	ns_cache_enter(object); defer { ns_cache_leave(object) }
	C.ios_objc_initialize_lock()
	mut state := ns_cache_storage(object, true).cache
	mut removed := []CacheEntry{cap: state.entries.len}
	if selector == 'removeAllObjects' { for entry in state.entries { removed << entry }; state.entries.clear(); state.cost = 0 }
	else { if selector == 'setCountLimit:' { state.count_limit = value } else { state.cost_limit = value }; ns_cache_trim(mut state, mut removed) }
	state.version++
	C.ios_objc_initialize_unlock()
	for entry in removed { ns_cache_release_entry(entry) }; unsafe { removed.free() }
}
fn ns_cache_types(name string, meta bool, selector string) ?string {
	if name != 'NSCache' || meta { return none }
	return match selector {
		'init', 'name', 'delegate' { '@16@0:8' }
		'objectForKey:' { '@24@0:8@16' }
		'setName:', 'setDelegate:', 'removeObjectForKey:' { 'v24@0:8@16' }
		'setObject:forKey:' { 'v32@0:8@16@24' }
		'setObject:forKey:cost:' { 'v40@0:8@16@24Q32' }
		'removeAllObjects' { 'v16@0:8' }
		'countLimit', 'totalCostLimit' { 'Q16@0:8' }
		'setCountLimit:', 'setTotalCostLimit:' { 'v24@0:8Q16' }
		'evictsObjectsWithDiscardedContent' { 'B16@0:8' }
		'setEvictsObjectsWithDiscardedContent:' { 'v20@0:8B16' }
		else { none }
	}
}
fn ns_cache_unsupported(selector string) bool {
	return selector in ['copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:', 'supportsSecureCoding', 'initWithCoder:', 'encodeWithCoder:', 'classForCoder', 'allObjects', 'mapTableRepresentation', '__apply:', 'minimumObjectCount', 'setMinimumObjectCount:', 'evictsObjectsWhenApplicationEntersBackground', 'setEvictsObjectsWhenApplicationEntersBackground:']!
}
fn ns_cache_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	mut owned := ns_cache_family(cls)
	if !meta {
		C.ios_objc_initialize_lock()
		if header := ios_runtime.objects[object] { owned = owned || header.cache != unsafe { nil } }
		C.ios_objc_initialize_unlock()
	}
	if !owned { return false }
	if ns_cache_unsupported(selector) { panic('iOS: cache option is not implemented') }
	if ns_cache_types('NSCache', meta, selector) == none { return false }
	match selector {
		'init' { frame.x[0] = ns_cache_initialize(object) }
		'setName:' { ns_cache_set_name(object, frame.x[2]) }
		'objectForKey:', 'removeObjectForKey:', 'setObject:forKey:', 'setObject:forKey:cost:' {
			setting := selector.starts_with('setObject:')
			frame.x[0] = ns_cache_entry(object, if setting { frame.x[3] } else { frame.x[2] }, if setting { frame.x[2] } else { u64(0) }, if selector == 'setObject:forKey:cost:' { frame.x[4] } else { u64(0) }, if setting { 'set' } else if selector == 'objectForKey:' { 'get' } else { 'remove' })
		}
		'removeAllObjects', 'setCountLimit:', 'setTotalCostLimit:' { ns_cache_clear_or_limit(object, selector, frame.x[2]) }
		else {
			C.ios_objc_initialize_lock()
			mut header := ns_cache_storage(object, true)
			match selector {
				'name' { frame.x[0] = objc_retain(header.fields[0]) }
				'delegate' { frame.x[0] = 0 }
				'setDelegate:' { if frame.x[2] != 0 { panic('iOS: cache delegates are not implemented') } }
				'countLimit' { frame.x[0] = header.cache.count_limit }
				'totalCostLimit' { frame.x[0] = header.cache.cost_limit }
				'evictsObjectsWithDiscardedContent' { frame.x[0] = u64(header.cache.evicts) }
				'setEvictsObjectsWithDiscardedContent:' { header.cache.evicts = frame.x[2] & 255 != 0; unsafe { *(&u8(object + 26)) = u8(header.cache.evicts) } }
				else {}
			}
			C.ios_objc_initialize_unlock()
			if selector == 'name' { frame.x[0] = objc_autorelease(frame.x[0]) }
		}
	}
	return true
}
