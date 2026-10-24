// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Stable cells are required: the weak registry stores addresses of their slots.
// Support object personality (equality or identity), strong/zeroing-weak memory.
// Other pointer functions, enumeration, copying and coding fail explicitly.
struct MapCell {
mut:
	key u64
	value u64
	hash u64
}
struct MapSnapshot { key u64 value u64 hash u64 index int }
struct FoundationMapTable {
mut:
	initialized bool
	active int
	version u64
	weak_key bool
	weak_value bool
	identity bool
	entries []&MapCell
}
fn ns_map_table_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'NSMapTable' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic map table superclass chain')
}
fn ns_map_table_require_class(cls u64) {
	if ns_map_table_family(cls) && cls != ios_runtime.names['NSMapTable'] { panic('iOS: custom map table subclass construction is not implemented') }
}
fn ns_map_table_install(cls u64, mut header ObjHeader) {
	if cls != ios_runtime.names['NSMapTable'] { return }
	header.map_table = unsafe { &FoundationMapTable(C.calloc(1, sizeof(FoundationMapTable))) }
	if header.map_table == unsafe { nil } { panic('iOS: cannot allocate map table state') }
	header.map_table.entries = []&MapCell{}
	header.map_table.entries.flags |= .noslices
}
// Caller holds the runtime lock. Ownership follows allocation, never isa.
fn ns_map_table_storage(object u64, initialized bool) &FoundationMapTable {
	header := obj_header(object)
	if header.map_table == unsafe { nil } || header.destroying || header.destroyed
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 || header.native_size < 8
		|| header.cls != header.allocation_cls || read64(object) != header.allocation_cls
		|| header.allocation_cls != ios_runtime.names['NSMapTable'] { panic('iOS: map table requires live owned built-in storage') }
	if initialized && !header.map_table.initialized { panic('iOS: map table requires initialization') }
	return header.map_table
}
fn ns_map_table_initialize(object u64, key_options u64, value_options u64, capacity u64) u64 {
	// WeakMemory = 5, ObjectPointerPersonality = 2 << 8 (not weak memory).
	if key_options !in [u64(0), 5, 512, 517]! || value_options !in [u64(0), 5, 512, 517]! {
		panic('iOS: map table pointer options are not implemented')
	}
	if capacity > 4096 { panic('iOS: map table capacity exceeds 4096') }
	C.ios_objc_initialize_lock(); defer { C.ios_objc_initialize_unlock() }
	mut state := ns_map_table_storage(object, false)
	if state.initialized { panic('iOS: map table is already initialized') }
	state.weak_key = key_options & 255 == 5
	state.weak_value = value_options & 255 == 5
	state.identity = key_options & 512 != 0
	state.initialized = true
	return object
}
fn ns_map_table_enter(object u64) {
	C.ios_objc_initialize_lock()
	mut state := ns_map_table_storage(object, true)
	state.active++; objc_retain(object)
	C.ios_objc_initialize_unlock()
}
fn ns_map_table_leave(object u64) {
	C.ios_objc_initialize_lock()
	mut state := ns_map_table_storage(object, true)
	state.active--
	C.ios_objc_initialize_unlock(); objc_release(object)
}
fn ns_map_table_retire(header &ObjHeader) {
	C.ios_objc_initialize_lock(); defer { C.ios_objc_initialize_unlock() }
	if header.map_table != unsafe { nil } && header.map_table.active != 0 { panic('iOS: destroying an active map table') }
}
// Detach weak registrations before freeing a cell; release strong references
// outside the runtime lock so dealloc callbacks can call back into the runtime.
fn ns_map_table_detach(state &FoundationMapTable, cell &MapCell) {
	if state.weak_key { objc_destroy_weak(unsafe { &cell.key }) }
	if state.weak_value { objc_destroy_weak(unsafe { &cell.value }) }
}
fn ns_map_table_free_cells(cells []&MapCell) {
	for cell in cells { objc_release(cell.key); objc_release(cell.value); C.free(cell) }
	unsafe { cells.free() }
}
fn ns_map_table_dispose(mut header ObjHeader) {
	C.ios_objc_initialize_lock()
	state := header.map_table; header.map_table = unsafe { nil }
	if state == unsafe { nil } { C.ios_objc_initialize_unlock(); return }
	for cell in state.entries { ns_map_table_detach(state, cell) }
	C.ios_objc_initialize_unlock()
	ns_map_table_free_cells(state.entries); C.free(state)
}
fn ns_map_table_snapshot(object u64) ([]MapSnapshot, u64, bool) {
	C.ios_objc_initialize_lock(); defer { C.ios_objc_initialize_unlock() }
	state := ns_map_table_storage(object, true)
	mut entries := []MapSnapshot{cap: state.entries.len}
	for i, cell in state.entries {
		key := if state.weak_key { objc_load_weak(unsafe { &cell.key }) } else { objc_retain(cell.key) }
		value := if state.weak_value { objc_load_weak(unsafe { &cell.value }) } else { objc_retain(cell.value) }
		entries << MapSnapshot{key, value, cell.hash, i}
	}
	return entries, state.version, state.identity
}
fn ns_map_table_release_snapshot(entries []MapSnapshot) {
	for entry in entries { objc_release(entry.key); objc_release(entry.value) }
	unsafe { entries.free() }
}
fn ns_map_table_entry(object u64, key u64, value u64, operation string) u64 {
	ns_map_table_enter(object); defer { ns_map_table_leave(object) }
	if key == 0 || (operation == 'set' && value == 0) { return 0 }
	objc_retain(key); defer { objc_release(key) }
	if operation == 'set' { objc_retain(value) }
	defer { if operation == 'set' { objc_release(value) } }
	C.ios_objc_initialize_lock()
	identity := ns_map_table_storage(object, true).identity
	C.ios_objc_initialize_unlock()
	hash := if identity { key } else { ns_set_item_hash(key) }
	for _ in 0 .. 64 {
		entries, version, _ := ns_map_table_snapshot(object)
		mut index := -1
		for entry in entries {
			if entry.key != 0 && entry.value != 0 && entry.hash == hash
				&& (entry.key == key || (!identity && ns_set_item_equal(entry.key, key, 0))) { index = entry.index; break }
		}
		C.ios_objc_initialize_lock()
		mut state := ns_map_table_storage(object, true)
		if state.version != version { C.ios_objc_initialize_unlock(); ns_map_table_release_snapshot(entries); continue }
		mut removed := []&MapCell{cap: state.entries.len}
		mut result := u64(0)
		if operation == 'get' {
			if index >= 0 { result = objc_retain(entries[index].value) }
		} else {
			// Remove the matched cell and dead weak entries before insertion.
			for i := state.entries.len - 1; i >= 0; i-- {
				cell := state.entries[i]
				if i == index || entries[i].key == 0 || entries[i].value == 0 {
					ns_map_table_detach(state, cell); state.entries.delete(i); removed << cell
				}
			}
			if operation == 'set' {
				if state.entries.len >= 4096 { panic('iOS: map table capacity exceeds 4096') }
				mut cell := unsafe { &MapCell(C.calloc(1, sizeof(MapCell))) }
				if cell == unsafe { nil } { panic('iOS: cannot allocate map table entry') }
				cell.hash = hash
				// Foundation preserves the first equal key when replacing a value.
				stored_key := if index >= 0 { entries[index].key } else { key }
				if state.weak_key { objc_store_weak(unsafe { &cell.key }, stored_key) } else { cell.key = objc_retain(stored_key) }
				if state.weak_value { objc_store_weak(unsafe { &cell.value }, value) } else { cell.value = objc_retain(value) }
				state.entries << cell
			}
			state.version++
		}
		C.ios_objc_initialize_unlock()
		ns_map_table_release_snapshot(entries); ns_map_table_free_cells(removed)
		return objc_autorelease(result)
	}
	panic('iOS: map table key callbacks or contention prevented progress')
}
fn ns_map_table_clear(object u64) {
	ns_map_table_enter(object); defer { ns_map_table_leave(object) }
	C.ios_objc_initialize_lock()
	mut state := ns_map_table_storage(object, true)
	removed := state.entries; state.entries = []&MapCell{}; state.entries.flags |= .noslices
	for cell in removed { ns_map_table_detach(state, cell) }
	state.version++
	C.ios_objc_initialize_unlock(); ns_map_table_free_cells(removed)
}
fn ns_map_table_types(name string, meta bool, selector string) ?string {
	if name != 'NSMapTable' { return none }
	if meta {
		return match selector {
			'strongToStrongObjectsMapTable', 'weakToStrongObjectsMapTable', 'strongToWeakObjectsMapTable', 'weakToWeakObjectsMapTable' { '@16@0:8' }
			'mapTableWithKeyOptions:valueOptions:' { '@32@0:8Q16Q24' }
			else { none }
		}
	}
	return match selector {
		'init' { '@16@0:8' }
		'initWithKeyOptions:valueOptions:capacity:' { '@40@0:8Q16Q24Q32' }
		'count' { 'Q16@0:8' }
		'objectForKey:' { '@24@0:8@16' }
		'setObject:forKey:' { 'v32@0:8@16@24' }
		'removeObjectForKey:' { 'v24@0:8@16' }
		'removeAllObjects' { 'v16@0:8' }
		else { none }
	}
}
fn ns_map_table_unsupported(selector string) bool {
	return selector in ['copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:', 'supportsSecureCoding', 'initWithCoder:', 'encodeWithCoder:', 'classForCoder', 'keyPointerFunctions', 'valuePointerFunctions', 'initWithKeyPointerFunctions:valuePointerFunctions:capacity:', 'dictionaryRepresentation', 'keyEnumerator', 'objectEnumerator', 'enumerator', 'allKeys', 'allValues', 'countByEnumeratingWithState:objects:count:', 'mutableDictionary', 'getKeys:values:', 'mapMember:originalKey:value:', 'setItem:forKnownAbsentKey:', 'existingItemForSetItem:forAbsentKey:', 'removeAllItems', 'replaceItem:forExistingKey:', '__capacity', 'setItem:forAbsentKey:', 'setItem:forKey:', 'unownedToStrongObjectsMapTable', 'mapTableWithWeakToStrongObjects', 'mapTableWithStrongToWeakObjects', 'mapTableWithStrongToStrongObjects', 'mapTableWithWeakToWeakObjects']!
}
fn ns_map_table_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	mut owned := ns_map_table_family(cls)
	if !meta {
		C.ios_objc_initialize_lock()
		if header := ios_runtime.objects[object] { owned = owned || header.map_table != unsafe { nil } }
		C.ios_objc_initialize_unlock()
	}
	if !owned { return false }
	if ns_map_table_unsupported(selector) { panic('iOS: map table option is not implemented') }
	if ns_map_table_types('NSMapTable', meta, selector) == none { return false }
	if meta {
		ns_map_table_require_class(object)
		key_options := if selector == 'mapTableWithKeyOptions:valueOptions:' { frame.x[2] } else if selector.starts_with('weakTo') { u64(5) } else { u64(0) }
		value_options := if selector == 'mapTableWithKeyOptions:valueOptions:' { frame.x[3] } else if selector.contains('ToWeak') { u64(5) } else { u64(0) }
		frame.x[0] = objc_autorelease(ns_map_table_initialize(objc_allocate(object), key_options, value_options, 0))
		return true
	}
	match selector {
		'init' { frame.x[0] = ns_map_table_initialize(object, 0, 0, 0) }
		'initWithKeyOptions:valueOptions:capacity:' { frame.x[0] = ns_map_table_initialize(object, frame.x[2], frame.x[3], frame.x[4]) }
		'count' {
			C.ios_objc_initialize_lock(); frame.x[0] = u64(ns_map_table_storage(object, true).entries.len); C.ios_objc_initialize_unlock()
		}
		'removeAllObjects' { ns_map_table_clear(object) }
		else {
			setting := selector == 'setObject:forKey:'
			frame.x[0] = ns_map_table_entry(object, if setting { frame.x[3] } else { frame.x[2] }, if setting { frame.x[2] } else { u64(0) }, if setting { 'set' } else if selector == 'objectForKey:' { 'get' } else { 'remove' })
		}
	}
	return true
}
