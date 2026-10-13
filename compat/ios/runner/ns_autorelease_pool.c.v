// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn ns_pool_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'NSAutoreleasePool' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic autorelease pool superclass chain')
}

fn ns_pool_require_class(cls u64) {
	if ns_pool_family(cls) && cls != ios_runtime.names['NSAutoreleasePool'] { panic('iOS: autorelease pool subclass construction is not implemented') }
}

fn ns_pool_reject_ownership(object u64) {
	if object == 0 { return }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if header := ios_runtime.objects[object] {
		if header.pool_owned { panic('iOS: autorelease pools cannot be retained or autoreleased') }
	}
}

fn ns_pool_initialize(object u64) {
	mut header := obj_header(object)
	if !header.pool_owned { panic('iOS: autorelease pool requires owned pool metadata') }
	if header.caller_storage { panic('iOS: autorelease pool initialization cannot consume caller-owned storage') }
	if header.pool_initialized { panic('iOS: autorelease pool reinitialization is not implemented') }
	header.pool_thread = u64(C.pthread_self())
	header.pool_token = objc_pool_push_object(object)
	header.pool_initialized = true
}

fn ns_pool_retire(object u64) {
	mut header := obj_header(object)
	if !header.pool_owned || header.pool_thread != u64(C.pthread_self()) { panic('iOS: autorelease pool retirement requires its owner thread') }
	header.pool_token = 0
	objc_release_regular(object)
}

fn ns_pool_release(object u64) bool {
	C.ios_objc_initialize_lock()
	header := ios_runtime.objects[object] or { C.ios_objc_initialize_unlock(); return false }
	if !header.pool_owned { C.ios_objc_initialize_unlock(); return false }
	if !header.pool_initialized { C.ios_objc_initialize_unlock(); return false }
	if header.pool_thread != u64(C.pthread_self()) { panic('iOS: autorelease pool drainage requires its owner thread') }
	token := header.pool_token
	C.ios_objc_initialize_unlock()
	if token == 0 { panic('iOS: autorelease pool drainage is already complete') }
	objc_pool_pop(token)
	return true
}

fn ns_pool_require_inactive(header &ObjHeader) {
	if header.pool_owned && header.pool_token != 0 { panic('iOS: active autorelease pool storage must be drained before destruction') }
}

fn ns_pool_types(name string, meta bool, selector string) ?string {
	if name != 'NSAutoreleasePool' { return none }
	if meta {
		return match selector { 'addObject:' { 'v24@0:8@16' } 'allocWithZone:' { '@24@0:8^{_NSZone=}16' } else { return none } }
	}
	return match selector {
		'init', 'retain', 'autorelease' { '@16@0:8' }
		'initWithCapacity:' { '@24@0:8Q16' }
		'drain' { 'v16@0:8' }
		'release' { 'Vv16@0:8' }
		'addObject:' { 'v24@0:8@16' }
		'retainCount' { 'Q16@0:8' }
		else { return none }
	}
}

fn ns_pool_selector(object u64, selector string) bool {
	meta := object in ios_runtime.classes
	return ns_pool_family(if meta { object } else { read64(object) }) && ns_pool_types('NSAutoreleasePool', meta, selector) != none
}

fn ns_pool_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	if !ns_pool_family(if meta { object } else { read64(object) }) { return false }
	if !meta && selector in ['copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:']! { panic('iOS: autorelease pool copies are not implemented') }
	if ns_pool_types('NSAutoreleasePool', meta, selector) == none { return false }
	if selector == 'addObject:' && frame.x[2] == 0 { panic('iOS: autorelease pool addObject must not be nil') }
	if meta {
		if selector == 'addObject:' { objc_autorelease(frame.x[2]) }
		else { frame.x[0] = objc_allocate(object) }
		return true
	}
	match selector {
		'init', 'initWithCapacity:' { ns_pool_initialize(object) }
		'retain', 'autorelease' { panic('iOS: autorelease pools cannot be retained or autoreleased') }
		'retainCount' { frame.x[0] = 1 }
		'release' { objc_release(object) }
		'drain' { if !ns_pool_release(object) { panic('iOS: autorelease pool drainage requires initialization') } }
		'addObject:' {
			header := obj_header(object)
			if header.pool_thread != u64(C.pthread_self()) || header.pool_token == 0 { panic('iOS: autorelease pool addObject requires an active owner-thread pool') }
			objc_autorelease(frame.x[2])
		}
		else { return false }
	}
	return true
}
