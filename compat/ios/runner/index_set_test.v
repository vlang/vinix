// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.class_getClassMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.class_getInstanceSize(voidptr) usize
fn C.class_getSuperclass(voidptr) voidptr
fn C.objc_storeWeak(&u64, voidptr) voidptr

type IndexSetFixtureSend = fn (u64, u64, u64, u64, u64) u64
struct IndexSetFixtureApi { native bool send u64 }
fn (api IndexSetFixtureApi) cls(name string) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name.str)) } }
	return ios_runtime.names[name]
}
fn (api IndexSetFixtureApi) selector(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api IndexSetFixtureApi) message(object u64, name &char, a u64, b u64, c u64) u64 {
	return unsafe { IndexSetFixtureSend(voidptr(api.send))(object, api.selector(name), a, b, c) }
}
fn (api IndexSetFixtureApi) pool() u64 {
	$if macos { if api.native { return api.message(api.cls('NSAutoreleasePool'), c'new', 0, 0, 0) } }
	return objc_pool_push()
}
fn (api IndexSetFixtureApi) drain(pool u64) {
	$if macos { if api.native { api.message(pool, c'drain', 0, 0, 0); return } }
	objc_pool_pop(pool)
}
fn (api IndexSetFixtureApi) weak(slot &u64, object u64) {
	$if macos { if api.native { C.objc_storeWeak(slot, unsafe { voidptr(object) }); return } }
	objc_store_weak(slot, object)
}
fn (api IndexSetFixtureApi) destroy_weak(slot &u64) {
	$if macos { if api.native { C.objc_storeWeak(slot, unsafe { nil }); return } }
	objc_destroy_weak(slot)
}
fn (api IndexSetFixtureApi) array(values &u64, count int, mutable bool) u64 {
	return api.message(api.cls(if mutable { 'NSMutableArray' } else { 'NSArray' }), c'arrayWithObjects:count:', u64(values), u64(count), 0)
}
fn index_set_fixture_metadata(api IndexSetFixtureApi) {
	for name in ['NSIndexSet', 'NSMutableIndexSet']! {
		cls := api.cls(name); parent := api.cls(if name == 'NSIndexSet' { 'NSObject' } else { 'NSIndexSet' }); assert cls != 0
		$if macos { if api.native { assert C.class_getInstanceSize(voidptr(cls)) == 32 && u64(C.class_getSuperclass(voidptr(cls))) == parent } }
		if !api.native { assert objc_class_size(cls) == 32 && objc_class_parent(cls) == parent }
	}
	for name, types in {
		'indexSet': '@16@0:8', 'indexSetWithIndex:': '@24@0:8Q16', 'indexSetWithIndexesInRange:': '@32@0:8{_NSRange=QQ}16',
		'init': '@16@0:8', 'initWithIndex:': '@24@0:8Q16', 'initWithIndexesInRange:': '@32@0:8{_NSRange=QQ}16',
		'count': 'Q16@0:8', 'firstIndex': 'Q16@0:8', 'lastIndex': 'Q16@0:8', 'containsIndex:': 'B24@0:8Q16',
		'indexGreaterThanIndex:': 'Q24@0:8Q16', 'indexGreaterThanOrEqualToIndex:': 'Q24@0:8Q16',
		'indexLessThanIndex:': 'Q24@0:8Q16', 'indexLessThanOrEqualToIndex:': 'Q24@0:8Q16',
		'copyWithZone:': '@24@0:8^{_NSZone=}16', 'mutableCopyWithZone:': '@24@0:8^{_NSZone=}16',
		'addIndex:': 'v24@0:8Q16', 'removeIndex:': 'v24@0:8Q16', 'removeAllIndexes': 'v16@0:8',
		'addIndexesInRange:': 'v32@0:8{_NSRange=QQ}16', 'removeIndexesInRange:': 'v32@0:8{_NSRange=QQ}16',
		'objectsAtIndexes:': '@24@0:8@16',
	} {
		meta := name.starts_with('indexSet'); cls := api.cls(if name == 'objectsAtIndexes:' { 'NSArray' } else if name.starts_with('add') || name.starts_with('remove') { 'NSMutableIndexSet' } else { 'NSIndexSet' })
		mut actual := ''
		$if macos { if api.native {
			method := if meta { C.class_getClassMethod(voidptr(cls), voidptr(api.selector(name.str))) } else { C.class_getInstanceMethod(voidptr(cls), voidptr(api.selector(name.str))) }
			assert method != unsafe { nil }; actual = unsafe { C.method_getTypeEncoding(method).vstring() }
		} }
		if !api.native { method := if meta { objc_class_method(cls, u64(name.str)) } else { objc_instance_method(cls, u64(name.str)) }; assert method != 0; actual = ctext(u64(objc_method_types(method))) }
		assert actual == types, name + ': ' + actual
	}
}
fn index_set_fixture_expect(api IndexSetFixtureApi, object u64, values []u64) {
	missing := u64(0x7fffffffffffffff)
	assert api.message(object, c'count', 0, 0, 0) == u64(values.len)
	assert api.message(object, c'firstIndex', 0, 0, 0) == if values.len == 0 { missing } else { values[0] }
	assert api.message(object, c'lastIndex', 0, 0, 0) == if values.len == 0 { missing } else { values.last() }
	mut previous := missing
	for i, value in values {
		assert api.message(object, c'containsIndex:', value, 0, 0) == 1
		assert api.message(object, c'indexGreaterThanOrEqualToIndex:', value, 0, 0) == value
		assert api.message(object, c'indexLessThanOrEqualToIndex:', value, 0, 0) == value
		assert api.message(object, c'indexLessThanIndex:', value, 0, 0) == previous
		assert api.message(object, c'indexGreaterThanIndex:', value, 0, 0) == if i + 1 == values.len { missing } else { values[i + 1] }
		previous = value
	}
}
fn index_set_fixture_shared_values(api IndexSetFixtureApi) {
	pool := api.pool(); index_set_fixture_metadata(api)
	for name in ['NSIndexSet', 'NSMutableIndexSet']! {
		cls := api.cls(name); index_set_fixture_expect(api, api.message(cls, c'indexSet', 0, 0, 0), []u64{})
		index_set_fixture_expect(api, api.message(cls, c'indexSetWithIndex:', 9, 0, 0), [u64(9)])
		index_set_fixture_expect(api, api.message(cls, c'indexSetWithIndexesInRange:', 3, 4, 0), [u64(3), 4, 5, 6])
		index_set_fixture_expect(api, api.message(cls, c'indexSetWithIndexesInRange:', 7, 0, 0), []u64{})
		for selector in [c'init', c'initWithIndex:', c'initWithIndexesInRange:']! {
			object := api.message(api.message(cls, c'alloc', 0, 0, 0), selector, 4, 2, 0)
			index_set_fixture_expect(api, object, if selector == c'init' { []u64{} } else if selector == c'initWithIndex:' { [u64(4)] } else { [u64(4), 5] })
			api.message(object, c'release', 0, 0, 0)
		}
	}
	set := api.message(api.cls('NSMutableIndexSet'), c'new', 0, 0, 0)
	for value in [u64(9), 2, 5, 2, 0, 8, 5]! { api.message(set, c'addIndex:', value, 0, 0) }
	index_set_fixture_expect(api, set, [u64(0), 2, 5, 8, 9]); assert api.message(set, c'containsIndex:', 1, 0, 0) == 0
	assert api.message(set, c'indexGreaterThanIndex:', 3, 0, 0) == 5 && api.message(set, c'indexLessThanIndex:', 4, 0, 0) == 2
	api.message(set, c'addIndexesInRange:', 3, 4, 0); index_set_fixture_expect(api, set, [u64(0), 2, 3, 4, 5, 6, 8, 9])
	api.message(set, c'removeIndexesInRange:', 4, 5, 0); index_set_fixture_expect(api, set, [u64(0), 2, 3, 9])
	api.message(set, c'removeIndex:', 3, 0, 0); api.message(set, c'removeIndex:', 999, 0, 0); index_set_fixture_expect(api, set, [u64(0), 2, 9])
	api.message(set, c'addIndexesInRange:', 0, 0, 0); api.message(set, c'removeIndexesInRange:', 0, 0, 0); index_set_fixture_expect(api, set, [u64(0), 2, 9])
	immutable := api.message(set, c'copy', 0, 0, 0); mutable := api.message(set, c'mutableCopy', 0, 0, 0)
	assert immutable != set && mutable != set && mutable != immutable
	assert api.message(immutable, c'isKindOfClass:', api.cls('NSIndexSet'), 0, 0) != 0 && api.message(immutable, c'isKindOfClass:', api.cls('NSMutableIndexSet'), 0, 0) == 0
	copy := api.message(immutable, c'copyWithZone:', 0, 0, 0); assert copy == immutable; api.message(copy, c'release', 0, 0, 0)
	from_immutable := api.message(immutable, c'mutableCopyWithZone:', 0, 0, 0); assert from_immutable != immutable && api.message(from_immutable, c'isKindOfClass:', api.cls('NSMutableIndexSet'), 0, 0) != 0
	api.message(set, c'removeAllIndexes', 0, 0, 0); index_set_fixture_expect(api, set, []u64{})
	for object in [immutable, mutable, from_immutable]! { index_set_fixture_expect(api, object, [u64(0), 2, 9]) }
	api.message(mutable, c'addIndex:', 4, 0, 0); index_set_fixture_expect(api, mutable, [u64(0), 2, 4, 9]); index_set_fixture_expect(api, immutable, [u64(0), 2, 9])
	for object in [set, immutable, mutable, from_immutable]! { api.message(object, c'release', 0, 0, 0) }
	api.drain(pool)
}
fn index_set_fixture_shared_arrays(api IndexSetFixtureApi) {
	pool := api.pool(); mut values := [api.cls('NSObject'), api.cls('NSString'), api.cls('NSArray'), api.cls('NSNull'), api.cls('NSDictionary')]!
	for mutable in [false, true]! {
		source := api.array(unsafe { &values[0] }, values.len, mutable); set := api.message(api.cls('NSMutableIndexSet'), c'indexSet', 0, 0, 0)
		for index in [u64(4), 0, 2, 4, 0]! { api.message(set, c'addIndex:', index, 0, 0) }
		selected := api.message(source, c'objectsAtIndexes:', set, 0, 0); assert api.message(selected, c'count', 0, 0, 0) == 3
		for i, index in [0, 2, 4]! { assert api.message(selected, c'objectAtIndex:', u64(i), 0, 0) == values[index] }
		api.message(set, c'removeAllIndexes', 0, 0, 0); assert api.message(selected, c'count', 0, 0, 0) == 3
		assert api.message(api.message(source, c'objectsAtIndexes:', set, 0, 0), c'count', 0, 0, 0) == 0
		assert api.message(source, c'count', 0, 0, 0) == 5
	}
	api.drain(pool)
	ownership := api.pool(); a := api.message(api.cls('NSObject'), c'new', 0, 0, 0); b := api.message(api.cls('NSObject'), c'new', 0, 0, 0)
	mut weak_a := u64(0); mut weak_b := u64(0); api.weak(unsafe { &weak_a }, a); api.weak(unsafe { &weak_b }, b)
	mut members := [a, b]!; source := api.array(unsafe { &members[0] }, 2, false); set := api.message(api.cls('NSIndexSet'), c'indexSetWithIndex:', 1, 0, 0)
	selected := api.message(api.message(source, c'objectsAtIndexes:', set, 0, 0), c'retain', 0, 0, 0)
	api.message(a, c'release', 0, 0, 0); api.message(b, c'release', 0, 0, 0); api.drain(ownership)
	assert weak_a == 0 && weak_b == b; assert api.message(selected, c'objectAtIndex:', 0, 0, 0) == b
	api.message(selected, c'release', 0, 0, 0); assert weak_b == 0
	api.destroy_weak(unsafe { &weak_a }); api.destroy_weak(unsafe { &weak_b })
}
fn index_set_fixture_shared(api IndexSetFixtureApi) { index_set_fixture_shared_values(api); index_set_fixture_shared_arrays(api) }

fn index_set_runtime_api() IndexSetFixtureApi { return IndexSetFixtureApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })} }

__global index_set_fixture_mode = ''
__global index_set_fixture_source = u64(0)
__global index_set_fixture_indexes = u64(0)
__global index_set_fixture_fired = false
__global index_set_fixture_weak_source = u64(0)
__global index_set_fixture_weak_indexes = u64(0)
__global index_set_fixture_weak_result = u64(0)
__global index_set_fixture_weak_property = u64(0)
fn index_set_fixture_worker() {
	C.ios_objc_initialize_lock(); C.ios_objc_initialize_unlock()
	if index_set_fixture_source != 0 { objc_release(index_set_fixture_source) }
	if index_set_fixture_indexes != 0 { objc_release(index_set_fixture_indexes) }
}
fn index_set_fixture_constructor(object u64, selector u64) u64 {
	if index_set_fixture_mode == '' || index_set_fixture_fired { return object }
	index_set_fixture_fired = true
	if index_set_fixture_mode in ['copy-release', 'selection-release']! {
		worker := spawn index_set_fixture_worker(); worker.wait()
	}
	if index_set_fixture_mode == 'fail' {
		objc_store_weak(unsafe { &index_set_fixture_weak_result }, object)
		property := objc_new(ios_runtime.names['NSObject']); obj_header(object).fields[1] = property
		objc_store_weak(unsafe { &index_set_fixture_weak_property }, property)
		return 0
	}
	if index_set_fixture_mode == 'constructor-storage' {
		mut state := ns_index_set_storage(object, false); state.initialized = true
	}
	if index_set_fixture_mode == 'constructor-isa' { objc_set_class(object, ios_runtime.names['NSObject']) }
	if index_set_fixture_mode == 'result-storage' { array_append(mut obj_header(object), ios_runtime.names['NSObject']) }
	if index_set_fixture_mode == 'result-isa' { objc_set_class(object, ios_runtime.names['NSObject']) }
	return object
}
fn index_set_fixture_hook(cls u64) {
	assert objc_add_method(cls, u64(c'.cxx_construct'), u64(unsafe { voidptr(index_set_fixture_constructor) }), c'@16@0:8')
}
fn index_set_fixture_runtime_lifetimes(api IndexSetFixtureApi) {
	pool := api.pool(); cls := api.cls('NSIndexSet'); mutable := api.cls('NSMutableIndexSet')
	library := '/System/Library/Frameworks/Foundation.framework/Foundation'
	for name in ['NSIndexSet', 'NSMutableIndexSet']! {
		assert runtime_symbol(library, '_OBJC_CLASS_$_' + name) or { panic(err) } == api.cls(name)
		assert runtime_symbol(library, '_OBJC_METACLASS_$_' + name) or { panic(err) } == read64(api.cls(name))
	}
	assert objc_ivar_offset(objc_find_ivar(cls, c'_indexSetFlags')) == 8 && objc_ivar_offset(objc_find_ivar(cls, c'_internal')) == 16
	// The highest valid Foundation index remains representable without expanding
	// a range to its location. Empty ranges ignore even an out-of-domain start.
	high := api.message(cls, c'indexSetWithIndex:', 0x7ffffffffffffffe, 0, 0)
	index_set_fixture_expect(api, high, [u64(0x7ffffffffffffffe)])
	index_set_fixture_expect(api, api.message(cls, c'indexSetWithIndexesInRange:', u64(-1), 0, 0), []u64{})
	mut guarded := [6]u64{}; guarded[0] = 0x1122334455667788; guarded[5] = 0x8877665544332211
	caller := u64(unsafe { &guarded[1] }); assert objc_construct_instance(mutable, caller) == caller
	assert api.message(caller, c'initWithIndexesInRange:', 3, 4, 0) == caller; index_set_fixture_expect(api, caller, [u64(3), 4, 5, 6])
	objc_set_class(caller, api.cls('NSObject')); assert objc_destruct_instance(caller) == caller
	assert caller !in ios_runtime.objects && guarded[0] == 0x1122334455667788 && guarded[5] == 0x8877665544332211
	for _ in 0 .. 32 {
		object := api.message(mutable, c'new', 0, 0, 0); api.message(object, c'addIndexesInRange:', 1, 128, 0)
		objc_set_class(object, api.cls('NSObject')); objc_release(object)
	}
	// A destination constructor runs outside the lock and may free the source.
	original := api.message(mutable, c'new', 0, 0, 0); api.message(original, c'addIndexesInRange:', 4, 3, 0)
	objc_store_weak(unsafe { &index_set_fixture_weak_source }, original)
	index_set_fixture_hook(cls); index_set_fixture_source = original; index_set_fixture_mode = 'copy-release'; index_set_fixture_fired = false
	copy := api.message(original, c'copy', 0, 0, 0)
	index_set_fixture_mode = ''; index_set_fixture_source = 0
	assert index_set_fixture_fired && index_set_fixture_weak_source == 0; index_set_fixture_expect(api, copy, [u64(4), 5, 6]); objc_release(copy)
	objc_destroy_weak(unsafe { &index_set_fixture_weak_source })
	// Rollback releases sidecars and properties for factory, copy and caller
	// storage construction without overwriting the caller's adjacent bytes.
	valid := api.message(mutable, c'new', 0, 0, 0)
	for operation in 0 .. 3 {
		index_set_fixture_mode = 'fail'; index_set_fixture_fired = false
		result := if operation == 0 { api.message(cls, c'indexSetWithIndex:', 3, 0, 0) } else if operation == 1 { api.message(valid, c'copy', 0, 0, 0) } else { objc_construct_instance(cls, caller) }
		assert result == 0 && index_set_fixture_fired && index_set_fixture_weak_result == 0 && index_set_fixture_weak_property == 0
		objc_destroy_weak(unsafe { &index_set_fixture_weak_result }); objc_destroy_weak(unsafe { &index_set_fixture_weak_property })
		assert guarded[0] == 0x1122334455667788 && guarded[5] == 0x8877665544332211
	}
	index_set_fixture_mode = ''; objc_release(valid)
	// Selected values must survive source/index-set disposal during NSArray's
	// constructor; the result holds only the selected element after drainage.
	inner := api.pool(); element := objc_new(api.cls('NSObject')); mut weak_element := u64(0); objc_store_weak(unsafe { &weak_element }, element)
	mut members := [element, api.cls('NSString')]!
	source := objc_retain(api.array(unsafe { &members[0] }, 2, true)); indexes := objc_retain(api.message(mutable, c'indexSetWithIndex:', 0, 0, 0))
	objc_release(element); api.drain(inner)
	objc_store_weak(unsafe { &index_set_fixture_weak_source }, source); objc_store_weak(unsafe { &index_set_fixture_weak_indexes }, indexes)
	index_set_fixture_hook(api.cls('NSArray')); index_set_fixture_source = source; index_set_fixture_indexes = indexes; index_set_fixture_mode = 'selection-release'; index_set_fixture_fired = false
	selected := api.message(source, c'objectsAtIndexes:', indexes, 0, 0)
	index_set_fixture_mode = ''; index_set_fixture_source = 0; index_set_fixture_indexes = 0
	assert index_set_fixture_fired && index_set_fixture_weak_source == 0 && index_set_fixture_weak_indexes == 0 && weak_element == element
	assert api.message(selected, c'count', 0, 0, 0) == 1 && api.message(selected, c'objectAtIndex:', 0, 0, 0) == element
	objc_destroy_weak(unsafe { &index_set_fixture_weak_source }); objc_destroy_weak(unsafe { &index_set_fixture_weak_indexes })
	result_source := api.array(unsafe { nil }, 0, true); result_indexes := api.message(mutable, c'indexSet', 0, 0, 0)
	index_set_fixture_mode = 'fail'; index_set_fixture_fired = false
	assert api.message(result_source, c'objectsAtIndexes:', result_indexes, 0, 0) == 0 && index_set_fixture_weak_result == 0 && index_set_fixture_weak_property == 0
	objc_destroy_weak(unsafe { &index_set_fixture_weak_result }); objc_destroy_weak(unsafe { &index_set_fixture_weak_property })
	index_set_fixture_mode = ''; api.drain(pool); assert weak_element == 0; objc_destroy_weak(unsafe { &weak_element })
}
fn index_set_fixture_image_array() u64 {
	page := u64(4096); pointer := C.mmap(unsafe { nil }, usize(page), C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANON, -1, 0)
	assert pointer != voidptr(-1); base := u64(pointer)
	unsafe { *(&u64(pointer)) = ios_runtime.names['NSConstantArray']; *(&u64(voidptr(base + 8))) = 3; *(&u64(voidptr(base + 16))) = base + 64
		*(&u64(voidptr(base + 64))) = ios_runtime.names['NSObject']; *(&u64(voidptr(base + 72))) = ios_runtime.names['NSString']; *(&u64(voidptr(base + 80))) = ios_runtime.names['NSArray'] }
	m := ObjMetadata{image: macho.Image{segments: [macho.Segment{name: '__DATA_CONST', address: 0x1000, size: page, filesize: page, prot: 1, sections: [macho.Section{name: '__objc_arrayobj', address: 0x1000, size: 24}]}]}, layout: macho.Layout{base: 0x1000, size: page}, base: base}
	defer { unsafe { m.image.segments[0].sections.free(); m.image.segments.free() } }
	assert C.mprotect(pointer, usize(page), C.PROT_READ) == 0; m.constant_arrays() or { panic(err) }; return base
}
fn test_index_set_runtime() {
	for _ in 0 .. 2 {
		index_set_fixture_mode = ''; index_set_fixture_source = 0; index_set_fixture_indexes = 0
		objc_start(); api := index_set_runtime_api(); index_set_fixture_shared(api); index_set_fixture_runtime_lifetimes(api)
		assert ios_runtime.objects.len == 0 && ios_runtime.live == 0 && ios_runtime.weak.len == 0
		pool := api.pool(); image := index_set_fixture_image_array(); mut before := [88]u8{}; C.memcpy(unsafe { &before[0] }, voidptr(image), before.len)
		indexes := api.message(api.cls('NSMutableIndexSet'), c'indexSet', 0, 0, 0); api.message(indexes, c'addIndex:', 2, 0, 0); api.message(indexes, c'addIndex:', 0, 0, 0)
		selected := api.message(image, c'objectsAtIndexes:', indexes, 0, 0)
		assert api.message(selected, c'count', 0, 0, 0) == 2 && api.message(selected, c'objectAtIndex:', 1, 0, 0) == api.cls('NSArray')
		assert C.memcmp(unsafe { &before[0] }, voidptr(image), before.len) == 0
		api.drain(pool); assert ios_runtime.objects.len == 1; objc_stop(); assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		assert C.munmap(voidptr(image), 4096) == 0
	}
	println('IOS-INDEX-SET: metadata, sorted unique indices, range ABI, independent copies, selected element lifetime, joined-worker constructor snapshots, rollback, guarded storage,32 isa disposal paths, read-only image arrays and two drained runtimes')
}
fn test_index_set_rejections() {
	objc_start(); api := index_set_runtime_api(); cls := api.cls('NSIndexSet'); mutable := api.cls('NSMutableIndexSet')
	for selector in [c'enumerateIndexesUsingBlock:', c'enumerateRangesUsingBlock:', c'initWithIndexSet:', c'containsIndexes:', c'shiftIndexesStartingAtIndex:by:', c'encodeWithCoder:', c'initWithCoder:', c'description', c'isEqual:', c'hash']! { assert !objc_responds(cls, selector) }
	modes := ['raw-count', 'repeat-init', 'immutable-add', 'sentinel-add', 'negative-add', 'sentinel-range', 'overflow-range', 'factory-limit', 'add-limit', 'union-limit', 'high-neighbor', 'subclass', 'caller-subclass', 'spoof', 'isa-change', 'copy-provenance', 'nil-set', 'object-set', 'raw-array', 'subclass-array', 'array-spoof', 'array-isa', 'array-limit', 'index-bounds', 'index-block', 'array-block', 'bulk', 'coding', 'hash', 'equal', 'description', 'constructor-storage', 'constructor-isa', 'result-storage', 'result-isa']!
	for mode in modes {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0; pid := C.ios_fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			pool := api.pool(); set := api.message(mutable, c'new', 0, 0, 0); api.message(set, c'addIndex:', 1, 0, 0)
			mut members := [api.cls('NSObject'), api.cls('NSString')]!; source := api.array(unsafe { &members[0] }, 2, true)
			index_set_fixture_mode = ''; index_set_fixture_fired = false
			match mode {
				'raw-count' { api.message(api.message(cls, c'alloc', 0, 0, 0), c'count', 0, 0, 0) }
				'repeat-init' { api.message(set, c'init', 0, 0, 0) }
				'immutable-add' { api.message(api.message(cls, c'indexSet', 0, 0, 0), c'addIndex:', 2, 0, 0) }
				'sentinel-add', 'negative-add' { api.message(set, c'addIndex:', if mode == 'sentinel-add' { u64(0x7fffffffffffffff) } else { u64(-1) }, 0, 0) }
				'sentinel-range', 'overflow-range' { api.message(set, c'addIndexesInRange:', if mode == 'sentinel-range' { u64(0x7fffffffffffffff) } else { u64(0x7ffffffffffffffe) }, 2, 0) }
				'factory-limit' { api.message(cls, c'indexSetWithIndexesInRange:', 0, 65537, 0) }
				'add-limit' { api.message(set, c'addIndexesInRange:', 0, 65537, 0) }
				'union-limit' { api.message(set, c'addIndexesInRange:', 0, 65536, 0); api.message(set, c'addIndex:', 65536, 0, 0) }
				'high-neighbor' { api.message(set, c'indexGreaterThanIndex:', 0x7fffffffffffffff, 0, 0) }
				'subclass', 'caller-subclass' {
					custom := objc_allocate_class(mutable, c'VinixUnsupportedIndexSet', 0); objc_register_class(custom)
					if mode == 'subclass' { objc_allocate(custom) } else { mut bytes := [4]u64{}; objc_construct_instance(custom, u64(unsafe { &bytes[0] })) }
				}
				'spoof' { object := objc_new(api.cls('NSObject')); objc_set_class(object, mutable); api.message(object, c'count', 0, 0, 0) }
				'isa-change' { objc_set_class(set, api.cls('NSObject')); api.message(set, c'count', 0, 0, 0) }
				'copy-provenance' { objc_set_class(set, api.cls('NSURLRequest')); objc_copy_value(set, false) }
				'nil-set', 'object-set' { api.message(source, c'objectsAtIndexes:', if mode == 'nil-set' { u64(0) } else { objc_new(api.cls('NSObject')) }, 0, 0) }
				'raw-array', 'subclass-array', 'array-spoof', 'array-isa', 'array-limit' {
					mut object := source
					if mode == 'raw-array' { obj_header(source).cf_raw_values = true }
					if mode == 'subclass-array' { custom := objc_allocate_class(api.cls('NSMutableArray'), c'VinixUnsupportedIndexArray', 0); objc_register_class(custom); objc_set_class(source, custom) }
					if mode == 'array-spoof' { object = objc_new(api.cls('NSObject')); objc_set_class(object, api.cls('NSMutableArray')) }
					if mode == 'array-isa' { objc_set_class(source, api.cls('NSArray')) }
					if mode == 'array-limit' { for _ in 0 .. 65537 { obj_header(source).items << api.cls('NSObject') } }
					api.message(object, c'objectsAtIndexes:', set, 0, 0)
				}
				'index-bounds' { api.message(set, c'addIndex:', 2, 0, 0); api.message(source, c'objectsAtIndexes:', set, 0, 0) }
				'index-block', 'array-block', 'bulk', 'coding', 'hash', 'equal', 'description' {
					selector := match mode { 'index-block' { c'enumerateIndexesUsingBlock:' } 'array-block' { c'enumerateObjectsUsingBlock:' } 'bulk' { c'addIndexes:' } 'coding' { c'encodeWithCoder:' } 'hash' { c'hash' } 'equal' { c'isEqual:' } else { c'description' } }
					api.message(if mode == 'array-block' { source } else { set }, selector, set, 0, 0)
				}
				'constructor-storage', 'constructor-isa' {
					index_set_fixture_hook(cls); index_set_fixture_mode = mode
					api.message(set, c'copy', 0, 0, 0)
				}
				'result-storage', 'result-isa' {
					index_set_fixture_hook(api.cls('NSArray')); index_set_fixture_mode = mode
					api.message(source, c'objectsAtIndexes:', set, 0, 0)
				}
				else {}
			}
			api.drain(pool); C._exit(0)
		}
		C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
		for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid
		output := unsafe { tos(&bytes[0], length) }; assert status == 256 && output.contains('iOS:') && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), mode + ': ' + output
	}
	objc_stop(); assert ios_runtime.live == 0
	println('IOS-INDEX-SET-REJECT:35 uninitialized/reinitialized sets, immutable mutation, invalid domain/ranges/limits, custom/spoof/isa storage, invalid selections, callback/bulk/coding methods and constructor changes fail explicitly')
}
fn test_index_set_native() {
	$if macos { api := IndexSetFixtureApi{true, u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))}; assert api.send != 0; index_set_fixture_shared(api); println('IOS-INDEX-SET-NATIVE: exact metadata, range ABI, sorted unique indices, independent immutable/mutable copies and retained ordered array selections') }
}
