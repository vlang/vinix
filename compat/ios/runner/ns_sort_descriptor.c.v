// SPDX-License-Identifier: GPL-2.0-or-later
module main

type SortSelector = fn (u64, u64, u64) i64
type SortValue = fn (u64, u64, u64) u64
type SortComparator = fn (u64, u64, u64) i64

fn sort_descriptor_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'NSSortDescriptor' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic sort descriptor superclass chain')
}

fn sort_descriptor_require_class(cls u64) {
	if sort_descriptor_family(cls) && cls != ios_runtime.names['NSSortDescriptor'] {
		panic('iOS: custom sort descriptor subclass construction is not implemented')
	}
}

fn sort_descriptor_metadata() {
	mut cls := ios_runtime.classes[ios_runtime.names['NSSortDescriptor']] or { panic('iOS: missing sort descriptor class') }
	for i, name in ['_sortDescriptorFlags', '_key', '_selector', '_selectorOrBlock']! {
		cls.ivars[name] = &ObjIvar{name: name.clone(), types: ['Q', '@"NSString"', ':', '@']![i].clone(), offset: i64(8 + i * 8), size: 8}
	}
}

fn sort_descriptor_state(object u64) &ObjHeader {
	header := obj_header(object)
	if !header.sort_descriptor_owned || header.native_size < 40 || header.destroying || header.destroyed {
		panic('iOS: sort descriptor requires live owned storage')
	}
	return header
}

fn sort_descriptor_types(name string, meta bool, selector string) ?string {
	if name != 'NSSortDescriptor' { return none }
	if meta {
		return match selector {
			'new' { '@16@0:8' }
			'sortDescriptorWithKey:' { '@24@0:8@16' }
			'sortDescriptorWithKey:ascending:' { '@28@0:8@16B24' }
			'sortDescriptorWithKey:ascending:selector:' { '@36@0:8@16B24:28' }
			'sortDescriptorWithKey:ascending:comparator:' { '@36@0:8@16B24@?28' }
			else { return none }
		}
	}
	return match selector {
		'init', 'key', 'copy', 'reversedSortDescriptor' { '@16@0:8' }
		'initWithKey:' { '@24@0:8@16' }
		'initWithKey:ascending:' { '@28@0:8@16B24' }
		'initWithKey:ascending:selector:' { '@36@0:8@16B24:28' }
		'initWithKey:ascending:comparator:' { '@36@0:8@16B24@?28' }
		'ascending' { 'B16@0:8' }
		'selector' { ':16@0:8' }
		'comparator' { '@?16@0:8' }
		'copyWithZone:' { '@24@0:8^{_NSZone=}16' }
		'compareObject:toObject:' { 'q32@0:8@16@24' }
		else { return none }
	}
}

fn sort_descriptor_selector(object u64, selector string) bool {
	meta := object in ios_runtime.classes
	return sort_descriptor_family(if meta { object } else { read64(object) }) && sort_descriptor_types('NSSortDescriptor', meta, selector) != none
}

fn sort_descriptor_unsupported(selector string) bool {
	return selector in ['mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding',
		'allowEvaluation', 'setReverseNullOrder:', 'reverseNullOrder', 'description', 'isEqual:']!
		|| selector.contains('reverseNullOrder:')
}

fn sort_descriptor_initialize(object u64, key u64, ascending bool, selector u64, comparator u64, block bool) {
	C.ios_objc_initialize_lock()
	mut header := sort_descriptor_state(object)
	if header.sort_descriptor_initialized || header.sort_descriptor_initializing {
		panic('iOS: sort descriptor designated reinitialization is not implemented')
	}
	header.sort_descriptor_initializing = true
	C.ios_objc_initialize_unlock()
	// Both copy operations can call application code. Publish the immutable
	// record only after acquiring its owned values, without holding the lock.
	if key != 0 && !objc_is_kind(key, ios_runtime.names['NSString']) { panic('iOS: sort descriptor key must be a string') }
	mut owned_key := if key == 0 { u64(0) } else { objc_copy_value(key, false) }
	if owned_key != 0 && !objc_is_kind(owned_key, ios_runtime.names['NSString']) { panic('iOS: sort descriptor key copy must be a string') }
	if key != 0 && owned_key == 0 { panic('iOS: sort descriptor key copy must not be nil') }
	if owned_key != 0 && string_text(owned_key).len == 0 { objc_release(owned_key); owned_key = 0 }
	if block && (comparator == 0 || !is_block(comparator)) { panic('iOS: sort descriptor comparator must be a block') }
	owned_block := if block { block_copy(comparator) } else { u64(0) }
	C.ios_objc_initialize_lock()
	header = sort_descriptor_state(object)
	header.fields[0] = owned_key
	header.fields[1] = owned_block
	header.valid = ascending
	header.action = selector
	header.sort_descriptor_initialized = true
	header.sort_descriptor_initializing = false
	unsafe {
		*(&u64(object + 8)) = u64(ascending) | if block { u64(2) } else { u64(0) }
		*(&u64(object + 16)) = owned_key
		*(&u64(object + 24)) = selector
		*(&u64(object + 32)) = owned_block
	}
	C.ios_objc_initialize_unlock()
}

// Keep KVC bounded to dictionaries, self, and explicit application KVC.
// Do not guess an ivar's type or call a scalar getter as an object getter.
fn sort_descriptor_value(object u64, key u64) u64 {
	if object == 0 || key == 0 { return objc_retain(object) }
	if native_method(read64(object), 'valueForKeyPath:') != 0 {
		return objc_retain(unsafe { SortValue(voidptr(C.ios_objc_msgsend))(object, objc_selector(c'valueForKeyPath:'), key) })
	}
	text := string_text(key)
	if text.len == 0 || text.len > 4096 { panic('iOS: sort descriptor key path is outside the supported profile') }
	mut value := objc_retain(object)
	mut start := 0
	mut components := 0
	for end in 0 .. text.len + 1 {
		if end != text.len && text[end] != `.` { continue }
		components++
		if components > 64 || end == start { panic('iOS: sort descriptor key path is outside the supported profile') }
		component := unsafe { tos(text.str + start, end - start) }
		start = end + 1
		if value == 0 { return 0 }
		if !objc_is_kind(value, ios_runtime.names['NSDictionary']) {
			if component == 'self' { continue }
			panic('iOS: sort descriptor key paths require dictionaries or application valueForKeyPath:')
		}
		if component[0] == `@` {
			panic('iOS: sort descriptor key paths require dictionaries or application valueForKeyPath:')
		}
		part := owned_string(component)
		next := objc_retain(unsafe { SortValue(voidptr(C.ios_objc_msgsend))(value, objc_selector(c'objectForKey:'), part) })
		objc_release(part)
		objc_release(value)
		value = next
	}
	return value
}

fn sort_descriptor_compare(object u64, left u64, right u64) i64 {
	header := sort_descriptor_state(object)
	if !header.sort_descriptor_initialized { panic('iOS: sort descriptor comparison requires designated initialization') }
	// Keep the descriptor and input objects alive across application callbacks.
	objc_retain(object); objc_retain(left); objc_retain(right)
	defer { objc_release(right); objc_release(left); objc_release(object) }
	a := sort_descriptor_value(left, header.fields[0])
	defer { objc_release(a) }
	b := sort_descriptor_value(right, header.fields[0])
	defer { objc_release(b) }
	mut order := i64(0)
	if a == b { return 0 }
	if a == 0 || b == 0 { order = i64(a != 0) - i64(b != 0) }
	else if header.fields[1] != 0 { order = unsafe { SortComparator(voidptr(read64(header.fields[1] + 16)))(header.fields[1], a, b) } }
	else {
		if header.action == 0 { panic('iOS: sort descriptor comparison selector must not be nil') }
		order = unsafe { SortSelector(voidptr(C.ios_objc_msgsend))(a, header.action, b) }
	}
	return if header.valid { order } else { i64(u64(0) - u64(order)) }
}

fn sort_descriptor_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	if !sort_descriptor_family(if meta { object } else { read64(object) }) { return false }
	if sort_descriptor_unsupported(selector) { panic('iOS: sort descriptor coding, mutable copying, equality, description and reverse-null ordering are not implemented') }
	if sort_descriptor_types('NSSortDescriptor', meta, selector) == none { return false }
	if selector == 'new' && meta { frame.x[0] = objc_new(object); return true }
	if selector.starts_with('initWithKey:') || selector.starts_with('sortDescriptorWithKey:') {
		result := if meta { objc_allocate(object) } else { object }
		block := selector.ends_with('comparator:')
		comparison := if block { u64(0) } else if selector.ends_with('selector:') && frame.x[4] != 0 { objc_selector(unsafe { &char(frame.x[4]) }) } else { objc_selector(c'compare:') }
		ascending := if selector in ['initWithKey:', 'sortDescriptorWithKey:']! { true } else { frame.x[3] & 0xff != 0 }
		sort_descriptor_initialize(result, frame.x[2], ascending, comparison, if block { frame.x[4] } else { u64(0) }, block)
		frame.x[0] = if meta { objc_autorelease(result) } else { result }
		return true
	}
	header := sort_descriptor_state(object)
	match selector {
		'init' {}
		'key' { frame.x[0] = header.fields[0] }
		'ascending' { frame.x[0] = u64(header.valid) }
		'selector' { frame.x[0] = header.action }
		'comparator' { frame.x[0] = header.fields[1] }
		'copy', 'copyWithZone:' { frame.x[0] = objc_retain(object) }
		'reversedSortDescriptor' {
			// A custom key copy can release the source's external owner. Keep
			// its key and comparator alive until the new descriptor owns both.
			objc_retain(object)
			result := objc_allocate(ios_runtime.names['NSSortDescriptor'])
			comparison := if header.action == 0 && header.fields[1] == 0 { objc_selector(c'compare:') } else { header.action }
			sort_descriptor_initialize(result, header.fields[0], !header.valid, comparison, header.fields[1], header.fields[1] != 0)
			frame.x[0] = objc_autorelease(result)
			objc_release(object)
		}
		'compareObject:toObject:' { frame.x[0] = u64(sort_descriptor_compare(object, frame.x[2], frame.x[3])) }
		else { return false }
	}
	return true
}

fn sort_descriptor_dispose(object u64, header &ObjHeader) {
	if !header.sort_descriptor_owned { return }
	// Generic fields release the copied key/block, even after an isa change.
	unsafe { C.memset(voidptr(object + 8), 0, 32) }
}
