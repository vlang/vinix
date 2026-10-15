// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn swift_data_bridge_is_zero(object u64) bool {
	return object != 0 && ios_runtime != unsafe { nil }
		&& object == C.ios_load_pointer(unsafe { &ios_runtime.swift_data_zero })
}

fn swift_data_bridge_zero() u64 {
	C.ios_objc_initialize_lock()
	existing := ios_runtime.swift_data_zero
	C.ios_objc_initialize_unlock()
	if existing != 0 { return existing }
	// Initialize candidates and destroy losers without a registry lock across
	// guest callbacks. Only the completely constructed winner becomes immortal.
	candidate := objc_allocate(ios_runtime.names['_NSZeroData'])
	C.ios_objc_initialize_lock()
	mut result := ios_runtime.swift_data_zero
	if result == 0 {
		result = candidate
		C.ios_store_pointer(unsafe { &ios_runtime.swift_data_zero }, candidate)
	}
	C.ios_objc_initialize_unlock()
	if result != candidate { objc_release(candidate) }
	return result
}

fn swift_data_bridge_checked(first u64, second u64) !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return error('iOS: Swift Data bridge outside runtime lifetime')
	}
	match second >> 62 {
		3 { return swift_data_bridge_zero() }
		0 {
			count := (second >> 48) & 0xff
			if count > 14 { return error('iOS: invalid inline Swift Data length') }
			if count == 0 { return swift_data_bridge_zero() }
			cls := ios_runtime.names['_NSInlineData']
			objc_initialize(cls)
			object := u64(C.calloc(1, usize(16 + count)))
			if object == 0 { return error('iOS: cannot allocate inline NSData') }
			objc_install_storage(cls, object, false)
			unsafe { *(&u64(object + 8)) = count }
			words := u64(C.__builtin_alloca(16))
			unsafe { *(&SwiftDataWords(words)) = SwiftDataWords{ first: first, second: second } }
			C.memcpy(voidptr(object + 16), voidptr(words), usize(count))
			mut header := obj_header(object)
			header.external_data = object + 16
			header.external_size = count
			return object
		}
		1 {
			start := i64(i32(u32(first)))
			end := i64(i32(u32(first >> 32)))
			// Native empty slices ignore their storage word entirely.
			if start == end { return swift_data_bridge_zero() }
			if start < 0 || end < start { return error('iOS: invalid Swift Data slice range') }
			owner := second & u64(0x3fffffffffffffff)
			C.ios_objc_initialize_lock()
			storage := ios_runtime.swift_heap[owner] or {
				C.ios_objc_initialize_unlock()
				return error('iOS: Swift Data bridge requires registered snapshot storage')
			}
			if storage.deiniting || storage.size != 65 || storage.mask != 7
				|| ios_runtime.swift_foundation_arena == 0
				|| storage.metadata != ios_runtime.swift_foundation_arena + u64(C.getpagesize()) + 400
				|| read64(owner) != storage.metadata || read64(owner + 24) > 16777216
				|| u64(end) > read64(owner + 24) || read64(owner + 16) == 0
				|| read64(owner + 32) != 0 || read64(owner + 40) != 0 || read64(owner + 56) != 0 {
				C.ios_objc_initialize_unlock()
				return error('iOS: unsupported Swift Data snapshot layout or range')
			}
			bytes := read64(owner + 16) + u64(start)
			swift_retain(owner)
			C.ios_objc_initialize_unlock()
			object := objc_allocate(ios_runtime.names['Foundation.__NSSwiftData'])
			mut header := obj_header(object)
			header.external_data = bytes
			header.external_size = u64(end - start)
			header.swift_data_owner = owner
			return object
		}
		else { return error('iOS: large-range Swift Data bridging is not implemented') }
	}
}

fn swift_data_bridge(first u64, second u64) u64 {
	return swift_data_bridge_checked(first, second) or { panic(err) }
}

fn swift_data_bridge_dispose(mut header ObjHeader) {
	owner := header.swift_data_owner
	if owner == 0 { return }
	header.swift_data_owner = 0
	header.external_data = 0
	header.external_size = 0
	// Native stored-property destruction precedes association callbacks.
	// The last Swift release may reenter; never hold the registry lock here.
	swift_release(owner)
}

fn swift_data_bridge_stop() {
	C.ios_objc_initialize_lock()
	object := ios_runtime.swift_data_zero
	C.ios_store_pointer(unsafe { &ios_runtime.swift_data_zero }, 0)
	C.ios_objc_initialize_unlock()
	objc_release(object)
}

fn swift_data_bridge_types(name string, meta bool, selector string) ?string {
	if meta || name !in ['_NSZeroData', '_NSInlineData', 'Foundation.__NSSwiftData']! {
		return none
	}
	return match selector {
		'length', 'retainCount' { 'Q16@0:8' }
		'bytes' { '^v16@0:8' }
		'copy', 'mutableCopy' { '@16@0:8' }
		'copyWithZone:', 'mutableCopyWithZone:' { '@24@0:8^{_NSZone=}16' }
		else { return none }
	}
}

fn swift_data_bridge_selector(object u64, selector string) bool {
	if object == 0 { return false }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if object !in ios_runtime.objects { return false }
	cls := read64(object)
	info := ios_runtime.classes[cls] or { return false }
	return swift_data_bridge_types(info.name, false, selector) != none
}

fn swift_data_bridge_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	if !swift_data_bridge_selector(object, selector) { return false }
	match selector {
		'length' { frame.x[0] = data_length(object) }
		'bytes' {
			frame.x[0] = if swift_data_bridge_is_zero(object) {
				u64(0)
			} else {
				data_pointer(object)
			}
		}
		'retainCount' {
			frame.x[0] = if swift_data_bridge_is_zero(object) {
				u64(-1)
			} else {
				u64(C.ios_ref_change(unsafe { &obj_header(object).refs }, 0))
			}
		}
		'copy', 'copyWithZone:' { frame.x[0] = objc_retain(object) }
		'mutableCopy', 'mutableCopyWithZone:' { frame.x[0] = objc_property_mutable_copy(object) }
		else { return false }
	}
	return true
}
