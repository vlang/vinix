// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Immutable, unescaped name/value pairs. NSURLComponents parsing and encoding
// are separate APIs. Both byte snapshots precede any application constructor.
struct URLQueryItemSnapshot {
	name string
	value string
	has_value bool
}

fn ns_url_query_item_metadata() {
	mut cls := ios_runtime.classes[ios_runtime.names['NSURLQueryItem']] or { panic('iOS: missing NSURLQueryItem') }
	for i, name in ['_name', '_value']! {
		cls.ivars[name] = &ObjIvar{name: name.clone(), types: '@"NSString"'.clone(), offset: i64(8 + i * 8), size: 8}
	}
}

fn ns_url_query_item_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'NSURLQueryItem' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic URL query item superclass chain')
}

fn ns_url_query_item_require_class(cls u64) {
	if ns_url_query_item_family(cls) && cls != ios_runtime.names['NSURLQueryItem'] {
		panic('iOS: custom URL query item construction is not implemented')
	}
}

// Called with the runtime lock held. An isa change never grants storage rights.
fn ns_url_query_item_storage(object u64, initialized bool) &ObjHeader {
	header := obj_header(object)
	if !header.url_query_item_owned || header.destroying || header.destroyed
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 || header.native_size < 24
		|| header.cls != header.allocation_cls || read64(object) != header.allocation_cls
		|| header.allocation_cls != ios_runtime.names['NSURLQueryItem'] {
		panic('iOS: NSURLQueryItem requires live owned query item storage')
	}
	if initialized && !header.url_query_item_initialized { panic('iOS: query item requires initialization') }
	return header
}

fn ns_url_query_item_text(object u64) string {
	if object == 0 { return '' }
	if header := ios_runtime.objects[object] {
		if header.destroying || header.cls != header.allocation_cls || read64(object) != header.allocation_cls
			|| header.allocation_cls !in [ios_runtime.names['NSString'], ios_runtime.names['NSMutableString']]!
			|| (header.mutable_string_owned && !header.mutable_string_initialized) {
			panic('iOS: query item input requires a built-in initialized string')
		}
	}
	text := cf_string_compare_text(object) or { panic('iOS: query item input requires a live UTF8 string') }
	if text.len > 65536 { panic('iOS: query item string exceeds byte limit') }
	return text
}

fn ns_url_query_item_snapshot(name u64, value u64) URLQueryItemSnapshot {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	// Validate both arguments before allocating either snapshot.
	a := ns_url_query_item_text(name)
	b := ns_url_query_item_text(value)
	return URLQueryItemSnapshot{a.clone(), b.clone(), value != 0}
}

fn ns_url_query_item_retire(mut header ObjHeader) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if header.url_query_item_initializing { panic('iOS: destroying an active NSURLQueryItem') }
}

fn ns_url_query_item_dispose(object u64, mut header ObjHeader) {
	if !header.url_query_item_owned { return }
	// Generic field destruction owns the two string references.
	unsafe { C.memset(voidptr(object + 8), 0, 16) }
	header.url_query_item_initialized = false
}

fn ns_url_query_item_failed_init(object u64) u64 {
	C.ios_objc_initialize_lock()
	mut header := ns_url_query_item_storage(object, false)
	if C.ios_ref_change(unsafe { &header.refs }, 0) <= 1 { panic('iOS: query item constructor consumed receiver ownership') }
	if header.caller_storage { panic('iOS: failed query item initializer cannot consume caller-owned storage') }
	header.url_query_item_initializing = false
	C.ios_objc_initialize_unlock()
	// A failed initializer consumes its receiver reference. The commit's pin
	// keeps metadata live until its temporary strings have also been released.
	objc_release(object)
	return 0
}

fn ns_url_query_item_commit(object u64, snapshot URLQueryItemSnapshot) u64 {
	C.ios_objc_initialize_lock()
	mut header := ns_url_query_item_storage(object, false)
	if header.url_query_item_initialized || header.url_query_item_initializing || header.fields[0] != 0 || header.fields[1] != 0 {
		panic('iOS: query item is already initialized or its constructor changed storage')
	}
	header.url_query_item_initializing = true
	objc_retain(object)
	C.ios_objc_initialize_unlock()
	defer { objc_release(object) }
	// owned_string copies its bytes before running application constructors.
	name := owned_string(snapshot.name)
	defer { objc_release(name) }
	if name == 0 { return ns_url_query_item_failed_init(object) }
	value := if snapshot.has_value { owned_string(snapshot.value) } else { u64(0) }
	defer { objc_release(value) }
	if snapshot.has_value && value == 0 { return ns_url_query_item_failed_init(object) }
	C.ios_objc_initialize_lock()
	header = ns_url_query_item_storage(object, false)
	if !header.url_query_item_initializing || header.url_query_item_initialized || header.fields[0] != 0 || header.fields[1] != 0
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 1 {
		panic('iOS: query item string constructor changed destination storage')
	}
	header.fields[0] = objc_retain(name)
	header.fields[1] = objc_retain(value)
	unsafe { *(&u64(object + 8)) = name; *(&u64(object + 16)) = value }
	header.url_query_item_initialized = true
	header.url_query_item_initializing = false
	C.ios_objc_initialize_unlock()
	return object
}

fn ns_url_query_item_initialize(object u64, name u64, value u64) u64 {
	snapshot := ns_url_query_item_snapshot(name, value)
	defer { unsafe { snapshot.name.free(); snapshot.value.free() } }
	return ns_url_query_item_commit(object, snapshot)
}

fn ns_url_query_item_create(cls u64, name u64, value u64) u64 {
	ns_url_query_item_require_class(cls)
	if cls != ios_runtime.names['NSURLQueryItem'] { panic('iOS: query item factory requires NSURLQueryItem') }
	snapshot := ns_url_query_item_snapshot(name, value)
	defer { unsafe { snapshot.name.free(); snapshot.value.free() } }
	object := objc_allocate(cls)
	if object == 0 { return 0 }
	return ns_url_query_item_commit(object, snapshot)
}

fn ns_url_query_item_copy(object u64) u64 {
	C.ios_objc_initialize_lock()
	header := ns_url_query_item_storage(object, true)
	snapshot := ns_url_query_item_snapshot(header.fields[0], header.fields[1])
	C.ios_objc_initialize_unlock()
	defer { unsafe { snapshot.name.free(); snapshot.value.free() } }
	result := objc_allocate(ios_runtime.names['NSURLQueryItem'])
	if result == 0 { return 0 }
	return ns_url_query_item_commit(result, snapshot)
}

fn ns_url_query_item_types(name string, meta bool, selector string) ?string {
	if name != 'NSURLQueryItem' { return none }
	if meta {
		return match selector {
			'queryItemWithName:value:' { '@32@0:8@16@24' }
			else { return none }
		}
	}
	return match selector {
		'initWithName:value:' { '@32@0:8@16@24' }
		'init', 'name', 'value', 'copy' { '@16@0:8' }
		'copyWithZone:' { '@24@0:8^{_NSZone=}16' }
		else { return none }
	}
}

fn ns_url_query_item_unsupported(selector string) bool {
	return selector in ['mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding',
		'isEqual:', 'hash', 'description', 'debugDescription', 'setName:', 'setValue:']!
}

fn ns_url_query_item_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	mut owned := ns_url_query_item_family(cls)
	if !meta {
		C.ios_objc_initialize_lock()
		if header := ios_runtime.objects[object] { owned = owned || header.url_query_item_owned }
		C.ios_objc_initialize_unlock()
	}
	if !owned { return false }
	if ns_url_query_item_unsupported(selector) { panic('iOS: query item option is not implemented') }
	if ns_url_query_item_types('NSURLQueryItem', meta, selector) == none { return false }
	if meta {
		frame.x[0] = objc_autorelease(ns_url_query_item_create(object, frame.x[2], frame.x[3]))
	} else {
		match selector {
			'init', 'initWithName:value:' {
				frame.x[0] = ns_url_query_item_initialize(object, if selector == 'init' { u64(0) } else { frame.x[2] }, if selector == 'init' { u64(0) } else { frame.x[3] })
			}
			'copy', 'copyWithZone:' {
				if selector == 'copyWithZone:' && frame.x[2] != 0 { panic('iOS: query item copy zones are not implemented') }
				frame.x[0] = ns_url_query_item_copy(object)
			}
			else {
				C.ios_objc_initialize_lock()
				header := ns_url_query_item_storage(object, true)
				frame.x[0] = header.fields[if selector == 'name' { 0 } else { 1 }]
				C.ios_objc_initialize_unlock()
			}
		}
	}
	return true
}
