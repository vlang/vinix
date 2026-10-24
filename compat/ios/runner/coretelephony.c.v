// SPDX-License-Identifier: GPL-2.0-or-later
module main

// No cellular service is available on Vinix. Expose the public inspection API
// without inventing carriers, radio technologies or service-change events.
fn telephony_ivars() [4]string { return ['_delegate', '_serviceSubscriberCellularProvidersDidUpdateNotifier', '_subscriberCellularProviderDidUpdateNotifier', '_currentRadioAccessTechnology']! }
fn telephony_ivar_types() [4]string { return ['@"<CTTelephonyNetworkInfoDelegate>"', '@?', '@?', '@"NSString"']! }
fn telephony_metadata() {
	mut cls := ios_runtime.classes[ios_runtime.names['CTTelephonyNetworkInfo']] or { panic('iOS: missing telephony class') }
	for i, name in telephony_ivars() {
		cls.ivars[name] = &ObjIvar{name: name.clone(), types: telephony_ivar_types()[i].clone(), offset: i64(8 + i * 8), size: 8}
	}
}
fn telephony_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'CTTelephonyNetworkInfo' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic telephony superclass chain')
}
fn telephony_require_class(cls u64) {
	if telephony_family(cls) && cls != ios_runtime.names['CTTelephonyNetworkInfo'] { panic('iOS: custom telephony subclass construction is not implemented') }
}
// The runtime lock protects provenance, the mirrored body and all field access.
fn telephony_storage(object u64, initialized bool) &ObjHeader {
	header := obj_header(object)
	if !header.telephony_owned || header.destroying || header.destroyed || header.native_size < 40
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 || header.cls != header.allocation_cls
		|| read64(object) != header.allocation_cls || header.allocation_cls != ios_runtime.names['CTTelephonyNetworkInfo'] {
		panic('iOS: telephony requires live owned built-in storage')
	}
	if initialized && !header.telephony_initialized { panic('iOS: telephony requires initialization') }
	if read64(object + 16) != header.fields[0] || read64(object + 24) != header.fields[1] || read64(object + 32) != 0
		|| (!header.telephony_initialized && read64(object + 8) != 0)
		|| (header.telephony_initialized && (object + 8 !in ios_runtime.weak || ios_runtime.weak[object + 8] != read64(object + 8))) {
		panic('iOS: telephony body was changed directly')
	}
	return header
}
fn telephony_initialize(object u64) u64 {
	C.ios_objc_initialize_lock(); defer { C.ios_objc_initialize_unlock() }
	mut header := telephony_storage(object, false)
	if header.telephony_initialized { panic('iOS: telephony is already initialized') }
	objc_store_weak(unsafe { &u64(object + 8) }, 0)
	header.telephony_initialized = true
	return object
}
fn telephony_enter(object u64) {
	C.ios_objc_initialize_lock(); defer { C.ios_objc_initialize_unlock() }
	mut header := telephony_storage(object, true)
	header.telephony_active++; objc_retain(object)
}
fn telephony_leave(object u64) {
	C.ios_objc_initialize_lock()
	mut header := telephony_storage(object, true)
	header.telephony_active--
	C.ios_objc_initialize_unlock(); objc_release(object)
}
fn telephony_retire(header &ObjHeader) {
	C.ios_objc_initialize_lock(); defer { C.ios_objc_initialize_unlock() }
	if header.telephony_owned && header.telephony_active != 0 { panic('iOS: destroying active telephony storage') }
}
fn telephony_dispose(object u64, mut header ObjHeader) {
	if !header.telephony_owned { return }
	objc_destroy_weak(unsafe { &u64(object + 8) })
	unsafe { C.memset(voidptr(object + 8), 0, 32) }
	header.telephony_initialized = false
	// Generic header teardown releases both copied blocks, even after isa changes.
}
fn telephony_set_notifier(object u64, index int, block u64) {
	telephony_enter(object); defer { telephony_leave(object) }
	if block != 0 && !is_block(block) { panic('iOS: telephony notifier requires a block') }
	// Block copy/dispose helpers may call application code. Keep the destination
	// alive, release the lock and revalidate it before publishing the copy.
	copy := block_copy(block)
	C.ios_objc_initialize_lock()
	mut header := telephony_storage(object, true)
	old := header.fields[index]; header.fields[index] = copy
	unsafe { *(&u64(object + 16 + u64(index) * 8)) = copy }
	C.ios_objc_initialize_unlock(); block_release(old)
}
fn telephony_types(name string, meta bool, selector string) ?string {
	if name != 'CTTelephonyNetworkInfo' || meta { return none }
	return match selector {
		'init', 'delegate', 'dataServiceIdentifier', 'subscriberCellularProvider', 'serviceSubscriberCellularProviders', 'serviceCurrentRadioAccessTechnology', 'currentRadioAccessTechnology' { '@16@0:8' }
		'setDelegate:' { 'v24@0:8@16' }
		'serviceSubscriberCellularProvidersDidUpdateNotifier', 'subscriberCellularProviderDidUpdateNotifier' { '@?16@0:8' }
		'setServiceSubscriberCellularProvidersDidUpdateNotifier:', 'setSubscriberCellularProviderDidUpdateNotifier:' { 'v24@0:8@?16' }
		else { none }
	}
}
fn telephony_unsupported(selector string) bool {
	return selector in ['copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding', 'classForCoder', 'radioAccessTechnology', 'serviceSignalStrength', 'serviceCellId']!
}
fn telephony_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	mut owned := telephony_family(cls)
	if !meta {
		C.ios_objc_initialize_lock()
		if header := ios_runtime.objects[object] { owned = owned || header.telephony_owned }
		C.ios_objc_initialize_unlock()
	}
	if !owned { return false }
	if telephony_unsupported(selector) { panic('iOS: telephony option is not implemented') }
	if telephony_types('CTTelephonyNetworkInfo', meta, selector) == none { return false }
	if selector == 'init' { frame.x[0] = telephony_initialize(object); return true }
	if selector.starts_with('set') && selector.ends_with('Notifier:') {
		telephony_set_notifier(object, if selector.starts_with('setService') { 0 } else { 1 }, frame.x[2]); return true
	}
	C.ios_objc_initialize_lock()
	header := telephony_storage(object, true)
	match selector {
		'setDelegate:' { objc_store_weak(unsafe { &u64(object + 8) }, frame.x[2]); frame.x[0] = 0 }
		'delegate' { frame.x[0] = objc_load_weak(unsafe { &u64(object + 8) }) }
		'serviceSubscriberCellularProvidersDidUpdateNotifier' { frame.x[0] = block_retain(header.fields[0]) }
		'subscriberCellularProviderDidUpdateNotifier' { frame.x[0] = block_retain(header.fields[1]) }
		'serviceSubscriberCellularProviders', 'serviceCurrentRadioAccessTechnology' { frame.x[0] = framework_empty_dictionary() }
		else { frame.x[0] = 0 }
	}
	C.ios_objc_initialize_unlock()
	if selector == 'delegate' || selector.ends_with('Notifier') { frame.x[0] = objc_autorelease(frame.x[0]) }
	return true
}
