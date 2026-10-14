// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftObjectTypeQuery {
	metadata u64
	cls u64
}

fn swift_object_type_query(owner u64) !SwiftObjectTypeQuery {
	if owner == 0 || owner & 0x8000000000000000 != 0 {
		return error('iOS: nil and tagged Swift object type lookup are not implemented')
	}
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if swift_main_actor_is_singleton_locked(owner) || swift_main_executor_is_singleton_locked(owner) {
		return SwiftObjectTypeQuery{ metadata: read64(owner) }
	}
	if storage := ios_runtime.swift_heap[owner] {
		metadata := storage.metadata
		if read64(owner) != metadata { return error('iOS: Swift object type has mismatched heap metadata') }
		kind := read64(metadata)
		if (kind != 0 && kind <= 0x7ff) || read64(metadata + 32) & 2 == 0 {
			return error('iOS: Swift heap contexts are not class objects')
		}
		// A null nominal descriptor marks an artificial subclass. Native Swift
		// walks its superclass chain; that path needs separately checked metadata.
		if read64(metadata + 64) == 0 { return error('iOS: artificial Swift subclasses are not implemented') }
		return SwiftObjectTypeQuery{ metadata: metadata }
	}
	mut cls := u64(0)
	if header := ios_runtime.objects[owner] {
		if header.destroyed || read64(owner) != header.cls { return error('iOS: Swift object type has invalid ObjC storage') }
		// dealloc may borrow its type with refs == 0 while storage is still live.
		cls = header.cls
	} else if owner in ios_runtime.constants {
		cls = read64(owner)
	} else {
		// Do not read unknown pointers or expose private String/Array descriptors
		// as Swift type metadata. A registry entry establishes readable storage.
		return error('iOS: Swift object type requires a registered class instance')
	}
	info := ios_runtime.classes[cls] or { return error('iOS: Swift object type has an unregistered class') }
	if info.meta || (info.dynamic && !info.registered) { return error('iOS: Swift object type has an invalid instance class') }
	if read64(cls + 32) & 2 != 0 {
		if read64(cls + 64) == 0 { return error('iOS: artificial Swift subclasses are not implemented') }
		return SwiftObjectTypeQuery{ metadata: cls }
	}
	return SwiftObjectTypeQuery{ cls: cls }
}

fn swift_object_type_checked(owner u64) !u64 {
	query := swift_object_type_query(owner)!
	if query.metadata != 0 { return query.metadata }
	// Darwin asks an ObjC instance for its formal class. App code may reenter
	// or await another registry user; do not hold the lock across this method.
	objc_initialize(query.cls)
	method := native_method(query.cls, 'class')
	cls := if method != 0 { unsafe { ObjInit(voidptr(method))(owner, &char(objc_selector(c'class'))) } } else { query.cls }
	metadata := swift_objc_metadata_checked(cls)!
	if read64(metadata) != 0x305 && read64(metadata + 64) == 0 {
		return error('iOS: artificial Swift subclasses are not implemented')
	}
	return metadata
}

fn swift_object_type(owner u64) u64 {
	return swift_object_type_checked(owner) or { panic(err) }
}

fn swift_object_type_symbol(symbol string) ?u64 {
	if symbol == '_swift_dynamicCastObjCClass' { return u64(unsafe { voidptr(swift_dynamic_cast_objc_class) }) }
	if symbol == '_swift_dynamicCast' { return u64(unsafe { voidptr(swift_dynamic_cast) }) }
	if symbol == '_swift_getObjectType' { return u64(unsafe { voidptr(swift_object_type) }) }
	return none
}
