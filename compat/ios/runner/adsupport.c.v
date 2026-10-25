// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Vinix has no advertising tracking authorization or device advertising ID.
// Report disabled tracking and the documented all-zero NSUUID.
fn adsupport_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'ASIdentifierManager' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic advertising manager superclass chain')
}
fn adsupport_require_class(cls u64) {
	if adsupport_family(cls) && cls != ios_runtime.names['ASIdentifierManager'] { panic('iOS: custom advertising manager subclass construction is not implemented') }
}
// Caller holds the recursive runtime lock. No user callbacks under that lock.
fn adsupport_storage(object u64) &ObjHeader {
	header := obj_header(object)
	if !header.adsupport_owned || header.releasing || header.destroying || header.destroyed || header.native_size != 8
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 || header.cls != header.allocation_cls
		|| read64(object) != header.allocation_cls || header.allocation_cls != ios_runtime.names['ASIdentifierManager'] {
		panic('iOS: advertising manager requires live owned built-in storage')
	}
	return header
}
fn adsupport_initialize(object u64) u64 {
	C.ios_objc_initialize_lock(); defer { C.ios_objc_initialize_unlock() }
	adsupport_storage(object)
	return object
}
fn adsupport_shared() u64 {
	C.ios_objc_initialize_lock()
	if ios_runtime.adsupport_retired { panic('iOS: advertising manager cache is retired') }
	if ios_runtime.adsupport_manager != 0 {
		object := ios_runtime.adsupport_manager; adsupport_storage(object)
		C.ios_objc_initialize_unlock(); return object
	}
	C.ios_objc_initialize_unlock()
	// +initialize and C++ constructors can reenter the factory on another thread.
	candidate := objc_new(ios_runtime.names['ASIdentifierManager'])
	C.ios_objc_initialize_lock()
	if ios_runtime.adsupport_retired { panic('iOS: advertising manager cache is retired') }
	adsupport_storage(candidate)
	if ios_runtime.adsupport_manager == 0 { ios_runtime.adsupport_manager = candidate }
	object := ios_runtime.adsupport_manager; adsupport_storage(object)
	C.ios_objc_initialize_unlock()
	if candidate != object { objc_release(candidate) }
	return object
}
fn adsupport_stop() {
	C.ios_objc_initialize_lock()
	ios_runtime.adsupport_retired = true
	object := ios_runtime.adsupport_manager; ios_runtime.adsupport_manager = 0
	C.ios_objc_initialize_unlock()
	objc_release(object)
}
fn adsupport_retire(object u64, header &ObjHeader) {
	C.ios_objc_initialize_lock(); defer { C.ios_objc_initialize_unlock() }
	if header.adsupport_owned && (header.adsupport_active != 0 || object == ios_runtime.adsupport_manager) {
		panic('iOS: destroying active or cached advertising manager storage')
	}
}
fn adsupport_identifier(object u64) u64 {
	C.ios_objc_initialize_lock()
	mut header := adsupport_storage(object)
	header.adsupport_active++; objc_retain(object)
	C.ios_objc_initialize_unlock()
	// UUID allocation can run application constructors. Retain the receiver and
	// reject explicit destruction until the callback and final validation finish.
	uuid := objc_allocate(ios_runtime.names['NSUUID'])
	ns_uuid_initialize(uuid, 0, false)
	C.ios_objc_initialize_lock()
	mut current := adsupport_storage(object); current.adsupport_active--
	C.ios_objc_initialize_unlock()
	objc_release(object)
	return objc_autorelease(uuid)
}
fn adsupport_types(name string, meta bool, selector string) ?string {
	if name != 'ASIdentifierManager' { return none }
	if meta {
		if selector == 'sharedManager' { return '@16@0:8' }
		return none
	}
	return match selector {
		'init', 'advertisingIdentifier' { '@16@0:8' }
		'isAdvertisingTrackingEnabled' { 'B16@0:8' }
		else { none }
	}
}
fn adsupport_unsupported(selector string) bool {
	return selector in ['copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding', 'classForCoder', 'clearAdvertisingIdentifier', 'isUserOptedIn']!
}
fn adsupport_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	mut owned := adsupport_family(cls)
	if !meta {
		C.ios_objc_initialize_lock()
		if header := ios_runtime.objects[object] { owned = owned || header.adsupport_owned }
		C.ios_objc_initialize_unlock()
	}
	if !owned { return false }
	if adsupport_unsupported(selector) { panic('iOS: advertising manager option is not implemented') }
	if adsupport_types('ASIdentifierManager', meta, selector) == none { return false }
	if meta { adsupport_require_class(object); frame.x[0] = adsupport_shared() }
	else if selector == 'advertisingIdentifier' { frame.x[0] = adsupport_identifier(object) }
	else { adsupport_initialize(object); frame.x[0] = if selector == 'init' { object } else { u64(0) } }
	return true
}
