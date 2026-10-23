// SPDX-License-Identifier: GPL-2.0-or-later
module main

// AppsFlyer's selected caller collects array positions. Keep sorted, unique
// unsigned indices in owned storage; the public 32-byte layout is metadata only.
// The bounded profile stores at most 65536 indices and does not run blocks.
struct FoundationIndexSet {
mut:
	indices []u64
	initialized bool
}

const ns_index_set_not_found = u64(0x7fffffffffffffff)

fn ns_index_set_metadata() {
	mut cls := ios_runtime.classes[ios_runtime.names['NSIndexSet']] or { panic('iOS: missing NSIndexSet') }
	cls.ivars['_indexSetFlags'] = &ObjIvar{name: '_indexSetFlags'.clone(), types: '{?="_hasSingleRange"b1"_hasBitfield"b1"_reservedArrayBinderController"b30}'.clone(), offset: 8, size: 4}
	cls.ivars['_internal'] = &ObjIvar{name: '_internal'.clone(), types: '(?="_singleRange"{?="_range"{_NSRange="location"Q"length"Q}}"_multipleRanges"{?="_data"^v"_reserved"^v}"_singleBitfield"{?="_bitfield"Q})'.clone(), offset: 16, size: 16}
}

fn ns_index_set_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'NSIndexSet' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic index set superclass chain')
}

fn ns_index_set_require_class(cls u64) {
	if ns_index_set_family(cls) && cls !in [ios_runtime.names['NSIndexSet'], ios_runtime.names['NSMutableIndexSet']]! {
		panic('iOS: custom index set subclass construction is not implemented')
	}
}

fn ns_index_set_install(cls u64, mut header ObjHeader) {
	if cls !in [ios_runtime.names['NSIndexSet'], ios_runtime.names['NSMutableIndexSet']]! { return }
	header.index_set = unsafe { &FoundationIndexSet(C.calloc(1, sizeof(FoundationIndexSet))) }
	if header.index_set == unsafe { nil } { panic('iOS: cannot allocate index set state') }
	header.index_set.indices = []u64{}
	header.index_set.indices.flags |= .noslices
}

// Called under the Objective-C lock. An isa change never grants storage rights.
fn ns_index_set_state(object u64) &FoundationIndexSet {
	return ns_index_set_storage(object, true)
}

fn ns_index_set_storage(object u64, initialized bool) &FoundationIndexSet {
	header := obj_header(object)
	state := header.index_set
	if state == unsafe { nil } || header.destroying || header.destroyed
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 || header.native_size < 32
		|| header.cls != header.allocation_cls || read64(object) != header.allocation_cls
		|| header.allocation_cls !in [ios_runtime.names['NSIndexSet'], ios_runtime.names['NSMutableIndexSet']]! {
		panic('iOS: NSIndexSet requires live owned index set storage')
	}
	if initialized && !state.initialized { panic('iOS: index set requires initialization') }
	return state
}

fn ns_index_set_dispose(mut header ObjHeader) {
	state := header.index_set
	header.index_set = unsafe { nil }
	if state != unsafe { nil } { unsafe { state.indices.free() }; C.free(state) }
}

fn ns_index_set_range(location u64, length u64) {
	if length != 0 && (location >= ns_index_set_not_found || length > ns_index_set_not_found - location) {
		panic('iOS: index set range exceeds supported index domain')
	}
}

fn ns_index_set_initialize(object u64, location u64, length u64) u64 {
	ns_index_set_range(location, length)
	if length > 65536 { panic('iOS: index set exceeds index limit') }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut state := ns_index_set_storage(object, false)
	if state.initialized { panic('iOS: index set is already initialized') }
	if state.indices.len != 0 { panic('iOS: index set initializer found unexpected storage') }
	for offset := u64(0); offset < length; offset++ { state.indices << location + offset }
	state.initialized = true
	return object
}

fn ns_index_set_position(state &FoundationIndexSet, index u64) int {
	mut low := 0
	mut high := state.indices.len
	for low < high {
		mid := low + (high - low) / 2
		if state.indices[mid] < index { low = mid + 1 } else { high = mid }
	}
	return low
}

fn ns_index_set_insert(mut state FoundationIndexSet, index u64) {
	if index >= ns_index_set_not_found { panic('iOS: index set index exceeds supported index domain') }
	position := ns_index_set_position(state, index)
	if position < state.indices.len && state.indices[position] == index { return }
	if state.indices.len == 65536 { panic('iOS: index set exceeds index limit') }
	// insert's voidptr argument must not move a scalar into an unfreed box.
	state.indices << index
	for i := state.indices.len - 1; i > position; i-- { state.indices[i] = state.indices[i - 1] }
	state.indices[position] = index
}

// Snapshot integers before allocation, which can invoke application constructors.
// No source object, sidecar pointer or borrowed array survives that callback.
fn ns_index_set_copy(object u64, mutable bool) u64 {
	C.ios_objc_initialize_lock()
	state := ns_index_set_state(object)
	if !mutable && read64(object) == ios_runtime.names['NSIndexSet'] {
		objc_retain(object)
		C.ios_objc_initialize_unlock()
		return object
	}
	mut indices := []u64{cap: state.indices.len}
	indices.flags |= .noslices
	for index in state.indices { indices << index }
	C.ios_objc_initialize_unlock()
	defer { unsafe { indices.free() } }
	result := objc_allocate(ios_runtime.names[if mutable { 'NSMutableIndexSet' } else { 'NSIndexSet' }])
	if result == 0 { return 0 }
	C.ios_objc_initialize_lock()
	mut target := ns_index_set_storage(result, false)
	if target.initialized || target.indices.len != 0 { panic('iOS: index set copy constructor changed its storage') }
	for index in indices { target.indices << index }
	target.initialized = true
	C.ios_objc_initialize_unlock()
	return result
}

fn ns_index_set_objects(object u64, indexes u64) u64 {
	C.ios_objc_initialize_lock()
	source := ns_predicate_array_state(object, false)
	state := ns_index_set_state(indexes)
	mut values := []u64{cap: state.indices.len}
	values.flags |= .noslices
	for index in state.indices {
		if index >= u64(source.items.len) { panic('iOS: objectsAtIndexes index out of range') }
		values << objc_retain(source.items[int(index)])
	}
	C.ios_objc_initialize_unlock()
	defer {
		for value in values { objc_release(value) }
		unsafe { values.free() }
	}
	result := objc_allocate(ios_runtime.names['NSArray'])
	if result == 0 { return 0 }
	C.ios_objc_initialize_lock()
	mut target := ns_predicate_array_state(result, false)
	if target.items.len != 0 { panic('iOS: index selection constructor changed its storage') }
	for value in values { array_append(mut target, value) }
	C.ios_objc_initialize_unlock()
	return objc_autorelease(result)
}

fn ns_index_set_types(name string, meta bool, selector string) ?string {
	if !meta && name in ['NSArray', 'NSMutableArray', 'NSConstantArray', 'WKNSArray']! && selector == 'objectsAtIndexes:' { return '@24@0:8@16' }
	if name !in ['NSIndexSet', 'NSMutableIndexSet']! { return none }
	if meta {
		return match selector {
			'indexSet' { '@16@0:8' }
			'indexSetWithIndex:' { '@24@0:8Q16' }
			'indexSetWithIndexesInRange:' { '@32@0:8{_NSRange=QQ}16' }
			else { return none }
		}
	}
	if name == 'NSMutableIndexSet' {
		match selector {
			'addIndex:', 'removeIndex:' { return 'v24@0:8Q16' }
			'addIndexesInRange:', 'removeIndexesInRange:' { return 'v32@0:8{_NSRange=QQ}16' }
			'removeAllIndexes' { return 'v16@0:8' }
			else {}
		}
	}
	return match selector {
		'init', 'copy', 'mutableCopy' { '@16@0:8' }
		'initWithIndex:' { '@24@0:8Q16' }
		'initWithIndexesInRange:' { '@32@0:8{_NSRange=QQ}16' }
		'copyWithZone:', 'mutableCopyWithZone:' { '@24@0:8^{_NSZone=}16' }
		'count', 'firstIndex', 'lastIndex' { 'Q16@0:8' }
		'containsIndex:' { 'B24@0:8Q16' }
		'indexGreaterThanIndex:', 'indexGreaterThanOrEqualToIndex:', 'indexLessThanIndex:', 'indexLessThanOrEqualToIndex:' { 'Q24@0:8Q16' }
		else { return none }
	}
}

fn ns_index_set_unsupported(selector string) bool {
	return selector in ['initWithIndexSet:', 'initWithIndexes:count:', 'indexSetWithIndexes:count:', 'initWithBitfield:', 'indexSetWithBitfield:',
		'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding', 'description', 'isEqual:', 'isEqualToIndexSet:', 'hash',
		'containsIndexes:', 'containsIndexesInRange:', 'intersectsIndexesInRange:', 'countOfIndexesInRange:', 'getIndexes:maxCount:inIndexRange:',
		'enumerateIndexesUsingBlock:', 'enumerateIndexesWithOptions:usingBlock:', 'enumerateIndexesInRange:options:usingBlock:',
		'enumerateRangesUsingBlock:', 'enumerateRangesWithOptions:usingBlock:', 'enumerateRangesInRange:options:usingBlock:',
		'indexPassingTest:', 'indexWithOptions:passingTest:', 'indexInRange:options:passingTest:', 'indexesPassingTest:', 'indexesWithOptions:passingTest:', 'indexesInRange:options:passingTest:',
		'addIndexes:', 'removeIndexes:', 'addIndexes:count:', 'addIndexesFromIndexSet:', 'removeIndexesFromIndexSet:', 'shiftIndexesStartingAtIndex:by:',
		'removeIndexesPassingTest:', 'removeIndexesWithOptions:passingTest:', 'removeIndexesInRange:options:passingTest:']!
}

fn ns_index_set_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	mut owned := ns_index_set_family(cls)
	if !meta {
		C.ios_objc_initialize_lock()
		if header := ios_runtime.objects[object] { owned = owned || header.index_set != unsafe { nil } }
		C.ios_objc_initialize_unlock()
	}
	if !owned {
		if !meta && selector == 'objectsAtIndexes:' && objc_is_kind(object, ios_runtime.names['NSArray']) {
			frame.x[0] = ns_index_set_objects(object, frame.x[2]); return true
		}
		return false
	}
	if ns_index_set_unsupported(selector) { panic('iOS: index set option is not implemented') }
	mutable := cls == ios_runtime.names['NSMutableIndexSet']
	name := if mutable { 'NSMutableIndexSet' } else { 'NSIndexSet' }
	if !mutable && selector in ['addIndex:', 'removeIndex:', 'addIndexesInRange:', 'removeIndexesInRange:', 'removeAllIndexes']! {
		panic('iOS: index set mutation requires NSMutableIndexSet')
	}
	if ns_index_set_types(name, meta, selector) == none { return false }
	if !meta && selector in ['copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:']! {
		frame.x[0] = ns_index_set_copy(object, selector.starts_with('mutableCopy')); return true
	}
	if meta {
		ns_index_set_require_class(object)
		// Validate before allocation; reject huge constructors without expanding.
		location := if selector == 'indexSet' { u64(0) } else { frame.x[2] }
		length := if selector == 'indexSet' { u64(0) } else if selector == 'indexSetWithIndex:' { u64(1) } else { frame.x[3] }
		ns_index_set_range(location, length)
		if length > 65536 { panic('iOS: index set exceeds index limit') }
		result := objc_allocate(object)
		if result == 0 { frame.x[0] = 0; return true }
		C.ios_objc_initialize_lock()
		mut state := ns_index_set_storage(result, false)
		if state.initialized || state.indices.len != 0 { panic('iOS: index set constructor changed its storage') }
		for offset := u64(0); offset < length; offset++ { state.indices << location + offset }
		state.initialized = true
		C.ios_objc_initialize_unlock()
		frame.x[0] = objc_autorelease(result)
		return true
	}
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	initializing := selector in ['init', 'initWithIndex:', 'initWithIndexesInRange:']!
	mut state := ns_index_set_storage(object, !initializing)
	index := frame.x[2]
	if selector in ['indexGreaterThanIndex:', 'indexGreaterThanOrEqualToIndex:', 'indexLessThanIndex:', 'indexLessThanOrEqualToIndex:']! && index >= ns_index_set_not_found {
		panic('iOS: index set neighbor query exceeds supported index domain')
	}
	position := ns_index_set_position(state, index)
	match selector {
		'init', 'initWithIndex:', 'initWithIndexesInRange:' {
			location := if selector == 'init' { u64(0) } else { index }
			length := if selector == 'init' { u64(0) } else if selector == 'initWithIndex:' { u64(1) } else { frame.x[3] }
			frame.x[0] = ns_index_set_initialize(object, location, length)
		}
		'count' { frame.x[0] = u64(state.indices.len) }
		'firstIndex' { frame.x[0] = if state.indices.len == 0 { ns_index_set_not_found } else { state.indices[0] } }
		'lastIndex' { frame.x[0] = if state.indices.len == 0 { ns_index_set_not_found } else { state.indices.last() } }
		'containsIndex:' { frame.x[0] = u64(position < state.indices.len && state.indices[position] == index) }
		'indexGreaterThanIndex:', 'indexGreaterThanOrEqualToIndex:' {
			p := position + if selector == 'indexGreaterThanIndex:' && position < state.indices.len && state.indices[position] == index { 1 } else { 0 }
			frame.x[0] = if p == state.indices.len { ns_index_set_not_found } else { state.indices[p] }
		}
		'indexLessThanIndex:', 'indexLessThanOrEqualToIndex:' {
			p := position + if selector == 'indexLessThanOrEqualToIndex:' && position < state.indices.len && state.indices[position] == index { 1 } else { 0 }
			frame.x[0] = if p == 0 { ns_index_set_not_found } else { state.indices[p - 1] }
		}
		'addIndex:' { ns_index_set_insert(mut state, index); frame.x[0] = 0 }
		'removeIndex:' {
			if position < state.indices.len && state.indices[position] == index { state.indices.delete(position) }
			frame.x[0] = 0
		}
		'removeAllIndexes' { state.indices.clear(); frame.x[0] = 0 }
		'addIndexesInRange:', 'removeIndexesInRange:' {
			length := frame.x[3]
			ns_index_set_range(index, length)
			if selector == 'addIndexesInRange:' {
				if length > 65536 { panic('iOS: index set exceeds index limit') }
				end := ns_index_set_position(state, index + length)
				if u64(state.indices.len - (end - position)) + length > 65536 { panic('iOS: index set exceeds index limit') }
				for offset := u64(0); offset < length; offset++ { ns_index_set_insert(mut state, index + offset) }
			} else if length != 0 {
				end := ns_index_set_position(state, index + length)
				state.indices.delete_many(position, end - position)
			}
			frame.x[0] = 0
		}
		else { return false }
	}
	return true
}
