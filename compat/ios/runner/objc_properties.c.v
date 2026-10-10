// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn objc_property_get(object u64, selector u64, offset i64, is_atomic bool) u64 {
	_ = selector
	// The runtime reserves offset zero for an isa property; classes are returned
	// without an ownership change, even for an atomic getter.
	if offset == 0 { return objc_object_class(object) }
	if object == 0 { panic('iOS: objc_getProperty requires a nonnil instance') }
	location := unsafe { &u64(object + u64(offset)) }
	if !is_atomic { return unsafe { *location } }
	C.ios_objc_initialize_lock()
	value := objc_retain(unsafe { *location })
	C.ios_objc_initialize_unlock()
	return objc_autorelease(value)
}

fn objc_property_mutable_copy(value u64) u64 {
	cls := read64(value)
	zone_imp := native_method(cls, 'mutableCopyWithZone:')
	if zone_imp != 0 {
		return unsafe { ObjCopyWithZone(voidptr(zone_imp))(value, &char(objc_selector(c'mutableCopyWithZone:')), 0) }
	}
	if objc_is_kind(value, ios_runtime.names['NSData']) {
		length := data_length(value)
		result := cf_data_mutable(0, i64(length))
		cf_data_set_length(result, i64(length))
		if length != 0 { unsafe { C.memcpy(voidptr(data_pointer(result)), voidptr(data_pointer(value)), usize(length)) } }
		return result
	}
	for pair in [['NSArray', 'NSMutableArray']!, ['NSDictionary', 'NSMutableDictionary']!]! {
		if !objc_is_kind(value, ios_runtime.names[pair[0]]) { continue }
		source := obj_header(value)
		result := objc_allocate(ios_runtime.names[pair[1]])
		mut target := obj_header(result)
		target.cf_raw_values = source.cf_raw_values
		target.cf_raw_keys = source.cf_raw_keys
		for item in source.items { target.items << if source.cf_raw_values { item } else { objc_retain(item) } }
		for key in source.keys { target.keys << if source.cf_raw_keys { key } else { objc_retain(key) } }
		return result
	}
	panic('iOS: property value does not implement mutable copying')
}

fn objc_property_set(object u64, selector u64, offset i64, value u64, is_atomic bool, copy_mode i8) {
	_ = selector
	if offset == 0 { objc_set_class(object, value); return }
	if object == 0 { panic('iOS: objc_setProperty requires a nonnil instance') }
	location := unsafe { &u64(object + u64(offset)) }
	// App copy methods execute before locking. Readers see the replacement
	// before the old value's deallocator can reenter a getter or setter.
	owned := if value == 0 { u64(0) }
		else if copy_mode == 2 { objc_property_mutable_copy(value) }
		else if copy_mode != 0 { objc_copy_value(value, true) }
		else { objc_retain(value) }
	if is_atomic { C.ios_objc_initialize_lock() }
	old := unsafe { *location }
	unsafe { *location = owned }
	if is_atomic { C.ios_objc_initialize_unlock() }
	objc_release(old)
}

fn objc_property_atomic(object u64, selector u64, value u64, offset i64) {
	objc_property_set(object, selector, offset, value, true, 0)
}

fn objc_property_atomic_copy(object u64, selector u64, value u64, offset i64) {
	objc_property_set(object, selector, offset, value, true, 1)
}
