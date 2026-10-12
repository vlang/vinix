// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Abstract Foundation set classes are eight bytes. Membership uses the
// existing owned, noslices object array rather than private class-cluster ivars.
type SetEqualImp = fn (u64, u64, u64) bool
type SetHashImp = fn (u64, u64) u64

fn ns_set_name(cls u64) string {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return '' }
		if info.name in ['NSSet', 'NSMutableSet'] { return info.name }
		current = info.parent
		if current == 0 { return '' }
	}
	panic('iOS: cyclic set superclass chain')
}

fn ns_set_types(name string, meta bool, selector string) ?string {
	if name !in ['NSSet', 'NSMutableSet'] { return none }
	if meta {
		return match selector {
			'set' { '@16@0:8' }
			'setWithObject:', 'setWithArray:', 'setWithSet:' { '@24@0:8@16' }
			'setWithObjects:count:' { '@32@0:8r^@16Q24' }
			'setWithCapacity:' { if name == 'NSMutableSet' { '@24@0:8Q16' } else { return none } }
			else { return none }
		}
	}
	match selector {
		'init', 'copy', 'mutableCopy', 'anyObject', 'allObjects' { return '@16@0:8' }
		'initWithArray:', 'initWithSet:', 'member:' { return '@24@0:8@16' }
		'initWithObjects:count:' { return '@32@0:8r^@16Q24' }
		'copyWithZone:', 'mutableCopyWithZone:' { return '@24@0:8^{_NSZone=}16' }
		'count', 'hash' { return 'Q16@0:8' }
		'containsObject:', 'isEqualToSet:', 'isEqual:', 'isSubsetOfSet:', 'intersectsSet:' { return 'B24@0:8@16' }
		'countByEnumeratingWithState:objects:count:' { return 'Q40@0:8^{?=Q^@^Q[5Q]}16^@24Q32' }
		else {}
	}
	if name != 'NSMutableSet' { return none }
	return match selector {
		'initWithCapacity:' { '@24@0:8Q16' }
		'addObject:', 'removeObject:', 'addObjectsFromArray:', 'unionSet:', 'minusSet:', 'intersectSet:', 'setSet:' { 'v24@0:8@16' }
		'removeAllObjects' { 'v16@0:8' }
		else { return none }
	}
}

fn ns_set_selector(object u64, selector string) bool {
	meta := object in ios_runtime.classes
	return ns_set_types(ns_set_name(if meta { object } else { read64(object) }), meta, selector) != none
}

fn ns_set_header(object u64) &ObjHeader {
	header := obj_header(object)
	if !header.set_owned || !header.set_initialized { panic('iOS: set is not initialized') }
	return header
}

fn ns_set_initialize(object u64, capacity u64) {
	mut header := obj_header(object)
	if !header.set_owned || header.set_initialized { panic('iOS: set reinitialization is not implemented') }
	if capacity > 4096 { panic('iOS: set capacity exceeds 4096') }
	header.set_initialized = true
}

fn ns_set_item_hash(value u64) u64 {
	imp := native_method(read64(value), 'hash')
	if imp != 0 { return unsafe { SetHashImp(voidptr(imp))(value, objc_selector(c'hash')) } }
	if objc_is_kind(value, ios_runtime.names['NSValue']) && !objc_is_kind(value, ios_runtime.names['NSNumber']) { return 0 } // Equal byte/type boxes share a hash bucket.
	return cf_hash(value)
}

fn ns_set_item_equal(left u64, right u64, depth int) bool {
	if left == right { return true }
	imp := native_method(read64(left), 'isEqual:')
	if imp != 0 { return unsafe { SetEqualImp(voidptr(imp))(left, objc_selector(c'isEqual:'), right) } }
	return cf_equal_depth(left, right, depth + 1)
}

fn ns_set_index(object u64, value u64, depth int) int {
	if value == 0 { return -1 }
	if depth > 64 { panic('iOS: set equality exceeds nesting limit') }
	mut header := ns_set_header(object)
	if header.set_reading >= 64 { panic('iOS: recursive set membership exceeds limit') }
	header.set_reading++
	objc_retain(object); objc_retain(value)
	defer { header.set_reading--; objc_release(value); objc_release(object) }
	hash := ns_set_item_hash(value)
	for i, candidate in header.items {
		if ns_set_item_hash(candidate) == hash && ns_set_item_equal(candidate, value, depth) { return i }
	}
	return -1
}

fn ns_set_insert(object u64, value u64) {
	if value == 0 { panic('iOS: nil set member') }
	objc_retain(value)
	defer { objc_release(value) }
	if ns_set_index(object, value, 0) >= 0 { return }
	mut header := ns_set_header(object)
	if header.items.len == 4096 { panic('iOS: set member limit exceeded') }
	array_append(mut header, value)
}

fn ns_set_copy(object u64, mutable bool) u64 {
	source := ns_set_header(object)
	if !mutable && !source.set_mutable { return objc_retain(object) }
	copy := objc_new(ios_runtime.names[if mutable { 'NSMutableSet' } else { 'NSSet' }])
	mut target := ns_set_header(copy)
	for item in source.items { array_append(mut target, item) }
	return copy
}

fn ns_set_input(value u64, array bool) {
	if value == 0 { return }
	if !objc_is_kind(value, ios_runtime.names[if array { 'NSArray' } else { 'NSSet' }]) { panic('iOS: set operation requires the expected collection type') }
	header := obj_header(value)
	if header.cf_raw_values || header.items.len > 4096 { panic('iOS: set input exceeds the object member profile') }
	if !array { ns_set_header(value) }
}

fn ns_set_load(object u64, input u64, array bool) {
	ns_set_input(input, array)
	if input == 0 { return }
	mut source := obj_header(input)
	source.set_reading++
	objc_retain(input)
	defer { source.set_reading--; objc_release(input) }
	version := source.mutation
	for item in source.items {
		ns_set_insert(object, item)
		if source.mutation != version { panic('iOS: set input changed during membership callback') }
	}
}

fn ns_set_equal(left u64, right u64, depth int) bool {
	if right == 0 || !objc_is_kind(right, ios_runtime.names['NSSet']) { return false }
	a := ns_set_header(left); b := ns_set_header(right)
	if a.items.len != b.items.len { return false }
	return ns_set_relation(left, right, false, depth)
}

fn ns_set_relation(left u64, right u64, intersects bool, depth int) bool {
	ns_set_input(right, false)
	mut source := ns_set_header(left)
	if right == 0 { return !intersects && source.items.len == 0 }
	source.set_reading++
	objc_retain(left); objc_retain(right)
	defer { source.set_reading--; objc_release(right); objc_release(left) }
	for item in source.items {
		found := ns_set_index(right, item, depth) >= 0
		if intersects && found { return true }
		if !intersects && !found { return false }
	}
	return !intersects
}

fn ns_set_mutate(object u64, selector string, input u64) {
	mut header := ns_set_header(object)
	if !header.set_mutable { panic('iOS: mutation of an immutable set') }
	if header.set_mutating || header.set_reading != 0 { panic('iOS: reentrant set mutation is not implemented') }
	header.set_mutating = true
	objc_retain(object)
	defer { header.set_mutating = false; objc_release(object) }
	header.mutation++ // Native also invalidates enumeration for duplicate/missing members.
	if selector == 'addObject:' { ns_set_insert(object, input); return }
	if selector == 'removeObject:' {
		if input == 0 { panic('iOS: nil set member') }
		index := ns_set_index(object, input, 0)
		if index >= 0 { collection_remove(mut header, index) }
		return
	}
	if selector == 'removeAllObjects' { for header.items.len > 0 { collection_remove(mut header, header.items.len - 1) }; return }
	if selector == 'addObjectsFromArray:' { ns_set_load(object, input, true); return }
	ns_set_input(input, false)
	if input == object {
		if selector == 'minusSet:' { for header.items.len > 0 { collection_remove(mut header, header.items.len - 1) } }
		return
	}
	if selector in ['unionSet:', 'setSet:'] {
		if selector == 'setSet:' { for header.items.len > 0 { collection_remove(mut header, header.items.len - 1) } }
		ns_set_load(object, input, false)
		return
	}
	if input == 0 {
		if selector == 'intersectSet:' { for header.items.len > 0 { collection_remove(mut header, header.items.len - 1) } }
		return
	}
	mut source := ns_set_header(input)
	source.set_reading++; objc_retain(input)
	defer { source.set_reading--; objc_release(input) }
	for i := header.items.len - 1; i >= 0; i-- {
		found := ns_set_index(input, header.items[i], 0) >= 0
		if found == (selector == 'minusSet:') { collection_remove(mut header, i) }
	}
}

fn ns_set_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	name := ns_set_name(if meta { object } else { read64(object) })
	if name == '' { return false }
	mutates := selector in ['addObject:', 'removeObject:', 'removeAllObjects', 'addObjectsFromArray:', 'unionSet:', 'minusSet:', 'intersectSet:', 'setSet:']
	if !meta && mutates { ns_set_mutate(object, selector, frame.x[2]); return true }
	if ns_set_types(name, meta, selector) == none {
		// Do not fall through to Foundation's array operations on a set.
		if !meta && selector in ['firstObject', 'objectAtIndex:', 'objectAtIndexedSubscript:', 'setObject:atIndexedSubscript:', 'removeObjectAtIndex:'] { panic('iOS: array indexing is not supported on sets') }
		if !meta && selector in ['objectForKey:', 'objectForKeyedSubscript:', 'setObject:forKey:', 'setObject:forKeyedSubscript:', 'removeObjectForKey:'] { panic('iOS: dictionary operations are not supported on sets') }
		return false
	}
	if meta || selector.starts_with('init') {
		value := if meta { objc_allocate(object) } else { object }
		capacity := if selector in ['setWithCapacity:', 'initWithCapacity:'] { frame.x[2] } else { u64(0) }
		ns_set_initialize(value, capacity)
		match selector {
			'setWithObject:' { ns_set_insert(value, frame.x[2]) }
			'setWithArray:', 'initWithArray:' { ns_set_load(value, frame.x[2], true) }
			'setWithSet:', 'initWithSet:' { ns_set_load(value, frame.x[2], false) }
			'setWithObjects:count:', 'initWithObjects:count:' {
				if frame.x[3] > 4096 || (frame.x[2] == 0 && frame.x[3] != 0) { panic('iOS: invalid set object buffer') }
				for i := u64(0); i < frame.x[3]; i++ { ns_set_insert(value, read64(frame.x[2] + i * 8)) }
			}
			else {}
		}
		frame.x[0] = if meta { objc_autorelease(value) } else { value }
		return true
	}
	objc_retain(object)
	defer { objc_release(object) }
	header := ns_set_header(object)
	match selector {
		'copy', 'copyWithZone:' { frame.x[0] = ns_set_copy(object, false) }
		'mutableCopy', 'mutableCopyWithZone:' { frame.x[0] = ns_set_copy(object, true) }
		'count', 'hash' { frame.x[0] = u64(header.items.len) }
		'member:', 'containsObject:' { index := ns_set_index(object, frame.x[2], 0); frame.x[0] = if selector == 'containsObject:' { u64(index >= 0) } else if index < 0 { u64(0) } else { objc_retain_autorelease(header.items[index]) } }
		'anyObject' { frame.x[0] = if header.items.len == 0 { u64(0) } else { header.items[0] } }
		'allObjects' {
			array := objc_allocate(ios_runtime.names['NSArray']); mut target := obj_header(array); target.json_immutable = true
			for item in header.items { array_append(mut target, item) }
			frame.x[0] = objc_autorelease(array)
		}
		'isEqual:', 'isEqualToSet:' { frame.x[0] = u64(ns_set_equal(object, frame.x[2], 0)) }
		'isSubsetOfSet:', 'intersectsSet:' { frame.x[0] = u64(ns_set_relation(object, frame.x[2], selector == 'intersectsSet:', 0)) }
		'countByEnumeratingWithState:objects:count:' {
			if frame.x[2] == 0 || (frame.x[3] == 0 && frame.x[4] != 0) { panic('iOS: invalid set enumeration buffer') }
			return false // Existing fast-enumeration storage and mutation pointer.
		}
		else { return false }
	}
	return true
}
