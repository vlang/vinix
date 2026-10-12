// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct ObjAssociation {
	value u64
	policy u64
}

struct ObjAssociations {
mut:
	entries map[u64]ObjAssociation
}

type ObjCopyWithZone = fn (u64, &char, u64) u64

fn objc_association_copy(value u64) u64 {
	return objc_copy_value(value, false)
}

fn objc_copy_value(value u64, with_zone bool) u64 {
	if is_block(value) { return block_copy(value) }
	cls := read64(value)
	if !with_zone {
		copy_imp := native_method(cls, 'copy')
		if copy_imp != 0 {
			return unsafe { ObjInit(voidptr(copy_imp))(value, &char(objc_selector(c'copy'))) }
		}
	}
	zone_imp := native_method(cls, 'copyWithZone:')
	if zone_imp != 0 {
		return unsafe { ObjCopyWithZone(voidptr(zone_imp))(value, &char(objc_selector(c'copyWithZone:')), 0) }
	}
	if objc_is_kind(value, ios_runtime.names['NSMutableData']) {
		return cf_data_create(0, data_pointer(value), i64(data_length(value)))
	}
	if objc_is_kind(value, ios_runtime.names['NSURLRequest']) { return request_copy(value, false) }
	if objc_is_kind(value, ios_runtime.names['NSSet']) { return ns_set_copy(value, false) }
	if objc_is_kind(value, ios_runtime.names['UIAlertAction']) { return alert_copy_action(value) }
	if objc_is_kind(value, ios_runtime.names['NSURLResponse']) {
		if obj_header(value).response == unsafe { nil } { panic('iOS: response is not initialized') }
		return objc_retain(value)
	}
	if objc_is_kind(value, ios_runtime.names['NSValue']) && !objc_is_kind(value, ios_runtime.names['NSNumber']) {
		if !obj_header(value).value_initialized { panic('iOS: value is not initialized') }
		return objc_retain(value)
	}
	for pair in [['NSMutableArray', 'NSArray']!, ['NSMutableDictionary', 'NSDictionary']!]! {
		if !objc_is_kind(value, ios_runtime.names[pair[0]]) { continue }
		source := obj_header(value)
		copy := objc_allocate(ios_runtime.names[pair[1]])
		mut target := obj_header(copy)
		target.cf_raw_values = source.cf_raw_values
		target.cf_raw_keys = source.cf_raw_keys
		for item in source.items { target.items << if source.cf_raw_values { item } else { objc_retain(item) } }
		for key in source.keys { target.keys << if source.cf_raw_keys { key } else { objc_retain(key) } }
		return copy
	}
	for name in ['NSString', 'NSNumber', 'NSData', 'NSArray', 'NSDictionary', 'NSAttributedString', 'NSURL', 'NSLocale']! {
		if objc_is_kind(value, ios_runtime.names[name]) { return objc_retain(value) }
	}
	panic('iOS: associated value does not implement copying')
}

fn objc_set_associated(object u64, key u64, value u64, policy u64) {
	if object == 0 {
		if value != 0 { panic('iOS: objc_setAssociatedObject requires a nonnil object') }
		return
	}
	if policy !in [u64(0), 1, 3, 0x301, 0x303] { panic('iOS: unsupported Objective-C association policy') }
	// Copy/retain may call app code. Acquire the new value before locking the
	// table; retire the old value after unlocking, once readers see the change.
	owned := if value == 0 || policy == 0 { value }
		else if policy & 3 == 3 { objc_association_copy(value) }
		else { objc_retain(value) }
	C.ios_objc_initialize_lock()
	mut old := ObjAssociation{}
	mut retired := unsafe { &ObjAssociations(nil) }
	if mut set := ios_runtime.associations[object] {
		old = set.entries[key]
		if owned == 0 {
			set.entries.delete(key)
			if set.entries.len == 0 { ios_runtime.associations.delete(object); retired = set }
		} else { set.entries[key] = ObjAssociation{owned, policy} }
	} else if owned != 0 {
		if object !in ios_runtime.objects && object !in ios_runtime.classes && object !in ios_runtime.constants && !is_block(object) {
			panic('iOS: associations require a known Objective-C object')
		}
		mut set := &ObjAssociations{}
		set.entries[key] = ObjAssociation{owned, policy}
		ios_runtime.associations[object] = set
	}
	C.ios_objc_initialize_unlock()
	if retired != unsafe { nil } { unsafe { retired.entries.free() }; C.free(retired) }
	if old.policy & 1 != 0 { objc_release(old.value) }
}

fn objc_get_associated(object u64, key u64) u64 {
	C.ios_objc_initialize_lock()
	set := ios_runtime.associations[object] or { C.ios_objc_initialize_unlock(); return 0 }
	entry := set.entries[key]
	// The atomic policies pin the result while it is protected from replacement.
	// The caller's pool owns that temporary reference after the lock is dropped.
	if entry.policy & 0x100 != 0 { objc_retain(entry.value) }
	C.ios_objc_initialize_unlock()
	return if entry.policy & 0x200 != 0 { objc_autorelease(entry.value) } else { entry.value }
}

fn objc_remove_associated(object u64) {
	C.ios_objc_initialize_lock()
	set := ios_runtime.associations[object] or { C.ios_objc_initialize_unlock(); return }
	ios_runtime.associations.delete(object)
	C.ios_objc_initialize_unlock()
	// Detach the entire set first. Dealloc callbacks can read, replace or add
	// associations without using this retired table or holding its lock.
	for _, entry in set.entries { if entry.policy & 1 != 0 { objc_release(entry.value) } }
	unsafe { set.entries.free() }
	C.free(set)
}

fn objc_associations_stop() {
	for ios_runtime.associations.len > 0 {
		for object, _ in ios_runtime.associations { objc_remove_associated(object); break }
	}
}
