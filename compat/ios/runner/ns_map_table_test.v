// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#flag -framework UserNotifications
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.class_getInstanceSize(voidptr) usize
fn C.class_getSuperclass(voidptr) voidptr
fn C.object_getClass(voidptr) voidptr
fn C.class_getInstanceVariable(voidptr, &char) voidptr
fn C.ivar_getOffset(voidptr) isize
fn C.ivar_getTypeEncoding(voidptr) &char
fn C.objc_storeWeak(&u64, voidptr) voidptr
type MapSend = fn (u64, u64, u64, u64, u64, u64) u64
struct MapApi { native bool send u64 }
fn map_api() MapApi { return MapApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })} }
fn (api MapApi) cls(name string) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name.str)) } }
	return ios_runtime.names[name]
}
fn (api MapApi) sel(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api MapApi) msg(object u64, name &char, a u64, b u64, c u64, d u64) u64 {
	return unsafe { MapSend(voidptr(api.send))(object, api.sel(name), a, b, c, d) }
}
fn (api MapApi) release(object u64) { api.msg(object, c'release', 0, 0, 0, 0) }
fn (api MapApi) pool() u64 {
	$if macos { if api.native { return api.msg(api.cls('NSAutoreleasePool'), c'new', 0, 0, 0, 0) } }
	return objc_pool_push()
}
fn (api MapApi) pop(pool u64) {
	$if macos { if api.native { api.msg(pool, c'drain', 0, 0, 0, 0); return } }
	objc_pool_pop(pool)
}
fn (api MapApi) weak(slot &u64, object u64) {
	$if macos { if api.native { C.objc_storeWeak(slot, unsafe { voidptr(object) }); return } }
	objc_store_weak(slot, object)
}
fn (api MapApi) weak_destroy(slot &u64) {
	$if macos { if api.native { C.objc_storeWeak(slot, unsafe { nil }); return } }
	objc_destroy_weak(slot)
}
fn (api MapApi) string(value string, mutable bool) u64 {
	return api.msg(api.msg(api.cls(if mutable { 'NSMutableString' } else { 'NSString' }), c'alloc', 0, 0, 0, 0), c'initWithBytes:length:encoding:', u64(value.str), u64(value.len), 4, 0)
}
fn (api MapApi) text(object u64) string {
	assert object != 0
	length := api.msg(object, c'lengthOfBytesUsingEncoding:', 4, 0, 0, 0)
	bytes := api.msg(object, c'UTF8String', 0, 0, 0, 0); assert bytes != 0
	return if length == 0 { '' } else { unsafe { tos(&u8(voidptr(bytes)), int(length)) } }
}
fn map_metadata(api MapApi) {
	cls := api.cls('NSMapTable'); assert cls != 0
	$if macos { if api.native { assert C.class_getInstanceSize(voidptr(cls)) == 8 && u64(C.class_getSuperclass(voidptr(cls))) == api.cls('NSObject') } }
	if !api.native { assert objc_class_size(cls) == 8 && objc_class_parent(cls) == api.cls('NSObject') }
	for meta in [false, true]! {
		for selector in ['init', 'initWithKeyOptions:valueOptions:capacity:', 'count', 'objectForKey:', 'setObject:forKey:', 'removeObjectForKey:', 'removeAllObjects', 'mapTableWithKeyOptions:valueOptions:', 'strongToStrongObjectsMapTable', 'weakToStrongObjectsMapTable', 'strongToWeakObjectsMapTable', 'weakToWeakObjectsMapTable']! {
			expected := ns_map_table_types('NSMapTable', meta, selector) or { continue }; mut actual := ''
			$if macos { if api.native {
				owner := if meta { u64(C.object_getClass(voidptr(cls))) } else { cls }
				method := C.class_getInstanceMethod(voidptr(owner), voidptr(api.sel(selector.str)))
				assert method != unsafe { nil }; actual = unsafe { C.method_getTypeEncoding(method).vstring() }
			} }
			if !api.native { method := objc_instance_method(if meta { read64(cls) } else { cls }, u64(selector.str)); assert method != 0; actual = ctext(u64(objc_method_types(method))) }
			assert actual == expected, selector + ': ' + actual
		}
	}
}
fn map_shared(api MapApi) {
	pool := api.pool(); map_metadata(api); cls := api.cls('NSMapTable')
	for factory in [c'new', c'strongToStrongObjectsMapTable', c'weakToStrongObjectsMapTable', c'strongToWeakObjectsMapTable', c'weakToWeakObjectsMapTable']! {
		inner := api.pool(); table := api.msg(cls, factory, 0, 0, 0, 0)
		if factory != c'new' { api.msg(table, c'retain', 0, 0, 0, 0) }
		assert api.msg(table, c'count', 0, 0, 0, 0) == 0
		key := api.msg(api.cls('NSObject'), c'new', 0, 0, 0, 0); value := api.msg(api.cls('NSObject'), c'new', 0, 0, 0, 0)
		mut wk := u64(0); mut wv := u64(0); api.weak(unsafe { &wk }, key); api.weak(unsafe { &wv }, value)
		api.msg(table, c'setObject:forKey:', value, key, 0, 0)
		api.msg(table, c'setObject:forKey:', value, 0, 0, 0); api.msg(table, c'setObject:forKey:', 0, key, 0, 0)
		assert api.msg(table, c'count', 0, 0, 0, 0) == 1 && api.msg(table, c'objectForKey:', key, 0, 0, 0) == value
		assert api.msg(table, c'objectForKey:', 0, 0, 0, 0) == 0; api.msg(table, c'removeObjectForKey:', 0, 0, 0, 0)
		api.pop(inner); api.release(key); api.release(value)
		weak_key := factory in [c'weakToStrongObjectsMapTable', c'weakToWeakObjectsMapTable']!
		weak_value := factory in [c'strongToWeakObjectsMapTable', c'weakToWeakObjectsMapTable']!
		assert (wk == 0) == weak_key && (wv == 0) == weak_value
		lookup_pool := api.pool()
		if wk != 0 { assert (api.msg(table, c'objectForKey:', key, 0, 0, 0) == 0) == weak_value }
		api.pop(lookup_pool)
		api.msg(table, c'removeAllObjects', 0, 0, 0, 0)
		assert api.msg(table, c'count', 0, 0, 0, 0) == 0
		assert wk == 0 && wv == 0
		api.weak_destroy(unsafe { &wk }); api.weak_destroy(unsafe { &wv }); api.release(table)
	}
	for key_options in [u64(0), 5, 512, 517]! {
		for value_options in [u64(0), 5, 512, 517]! {
			inner := api.pool()
			table := api.msg(api.msg(cls, c'alloc', 0, 0, 0, 0), c'initWithKeyOptions:valueOptions:capacity:', key_options, value_options, 2, 0)
			a := api.string('equal', true); b := api.string('equal', true)
			first := api.msg(api.cls('NSObject'), c'new', 0, 0, 0, 0); second := api.msg(api.cls('NSObject'), c'new', 0, 0, 0, 0)
			api.msg(table, c'setObject:forKey:', first, a, 0, 0)
			assert api.msg(table, c'objectForKey:', b, 0, 0, 0) == if key_options & 512 != 0 { u64(0) } else { first }
			api.msg(table, c'setObject:forKey:', second, b, 0, 0)
			assert api.msg(table, c'count', 0, 0, 0, 0) == if key_options & 512 != 0 { u64(2) } else { u64(1) }
			assert api.msg(table, c'objectForKey:', a, 0, 0, 0) == if key_options & 512 != 0 { first } else { second }
			api.msg(table, c'removeObjectForKey:', b, 0, 0, 0); assert api.msg(table, c'objectForKey:', b, 0, 0, 0) == 0
			api.msg(table, c'removeAllObjects', 0, 0, 0, 0)
			for item in [a, b, first, second, table]! { api.release(item) }; api.pop(inner)
		}
	}
	// Equal replacement retains the original key, not the replacement key.
	table := api.msg(cls, c'new', 0, 0, 0, 0); a := api.string('original', true); b := api.string('original', true)
	value := api.msg(api.cls('NSObject'), c'new', 0, 0, 0, 0)
	mut wa := u64(0); mut wb := u64(0); api.weak(unsafe { &wa }, a); api.weak(unsafe { &wb }, b)
	api.msg(table, c'setObject:forKey:', value, a, 0, 0); api.msg(table, c'setObject:forKey:', value, b, 0, 0)
	api.release(a); api.release(b); assert wa != 0 && wb == 0
	api.msg(table, c'removeAllObjects', 0, 0, 0, 0); assert wa == 0
	api.weak_destroy(unsafe { &wa }); api.weak_destroy(unsafe { &wb }); api.release(value); api.release(table)
	// Factory options have the same semantics as the designated initializer.
	factory_table := api.msg(cls, c'mapTableWithKeyOptions:valueOptions:', 512, 5, 0, 0)
	assert api.msg(factory_table, c'count', 0, 0, 0, 0) == 0
	api.pop(pool)
}
fn map_thread(api MapApi, table u64, index int) {
	pool := api.pool(); key := api.string('thread-' + index.str(), false); value := api.msg(api.cls('NSObject'), c'new', 0, 0, 0, 0)
	for _ in 0 .. 100 { api.msg(table, c'setObject:forKey:', value, key, 0, 0); assert api.msg(table, c'objectForKey:', key, 0, 0, 0) == value; api.msg(table, c'removeObjectForKey:', key, 0, 0, 0) }
	api.release(key); api.release(value); api.pop(pool)
}
__global map_callback_table = u64(0)
__global map_callback_mutate = false
__global map_callback_deallocs = 0
fn map_lock_worker() { C.ios_objc_initialize_lock(); C.ios_objc_initialize_unlock() }
fn map_hash(_object u64, _selector &char) u64 { worker := spawn map_lock_worker(); worker.wait(); return 7 }
fn map_equal(_object u64, _selector &char, _other u64) bool {
	worker := spawn map_lock_worker(); worker.wait()
	if map_callback_mutate { map_callback_mutate = false; map_api().msg(map_callback_table, c'removeAllObjects', 0, 0, 0, 0) }
	return true
}
fn map_dealloc(_object u64, _selector &char) {
	worker := spawn map_lock_worker(); worker.wait(); map_callback_deallocs++
	if map_callback_table != 0 { assert map_api().msg(map_callback_table, c'count', 0, 0, 0, 0) == 0 }
}
fn map_override(_object u64, _selector &char) u64 { return 99 }
fn map_runtime(api MapApi) {
	cls := api.cls('NSMapTable'); library := '/System/Library/Frameworks/Foundation.framework/Foundation'
	assert runtime_symbol(library, '_OBJC_CLASS_$_NSMapTable') or { panic(err) } == cls
	assert runtime_symbol(library, '_OBJC_METACLASS_$_NSMapTable') or { panic(err) } == read64(cls)
	pool := api.pool(); table := api.msg(cls, c'new', 0, 0, 0, 0)
	mut threads := []thread{}
	for i in 0 .. 4 { threads << spawn map_thread(api, table, i) }; threads.wait()
	assert api.msg(table, c'count', 0, 0, 0, 0) == 0
	probe := objc_allocate_class(api.cls('NSObject'), c'MapCallbackProbe', 0); assert probe != 0
	assert objc_add_method(probe, u64(c'hash'), u64(unsafe { voidptr(map_hash) }), c'Q16@0:8')
	assert objc_add_method(probe, u64(c'isEqual:'), u64(unsafe { voidptr(map_equal) }), c'B24@0:8@16')
	assert objc_add_method(probe, u64(c'dealloc'), u64(unsafe { voidptr(map_dealloc) }), c'v16@0:8'); objc_register_class(probe)
	map_callback_table = table; map_callback_deallocs = 0
	a := objc_new(probe); b := objc_new(probe)
	api.msg(table, c'setObject:forKey:', a, a, 0, 0); map_callback_mutate = true
	assert api.msg(table, c'objectForKey:', b, 0, 0, 0) == 0
	api.release(b)
	api.msg(table, c'setObject:forKey:', a, a, 0, 0); api.release(a)
	api.msg(table, c'removeAllObjects', 0, 0, 0, 0); assert map_callback_deallocs == 2; map_callback_table = 0
	for selector in [c'copy', c'mutableCopy', c'initWithCoder:', c'encodeWithCoder:', c'keyEnumerator', c'dictionaryRepresentation', c'keyPointerFunctions']! { assert !objc_responds(table, selector) && objc_instance_method(cls, u64(selector)) == 0 }
	objc_set_class(table, api.cls('NSObject')); api.release(table); api.pop(pool)
	// The ABI has only isa; both adjacent guard words must survive.
	mut guarded := [u64(0x1122334455667788), 0, 0x8877665544332211]!
	caller := u64(unsafe { &guarded[1] }); assert objc_construct_instance(cls, caller) == caller && ns_map_table_initialize(caller, 5, 5, 0) == caller
	key := objc_new(api.cls('NSObject')); api.msg(caller, c'setObject:forKey:', key, key, 0, 0)
	assert objc_destruct_instance(caller) == caller && caller !in ios_runtime.objects
	api.release(key); assert guarded[0] == 0x1122334455667788 && guarded[2] == 0x8877665544332211
	// Owned storage must still be disposed after isa changes, including weak slots.
	weak_pool := api.pool()
	weak_table := api.msg(cls, c'weakToWeakObjectsMapTable', 0, 0, 0, 0); api.msg(weak_table, c'retain', 0, 0, 0, 0)
	weak_key := objc_new(api.cls('NSObject')); api.msg(weak_table, c'setObject:forKey:', weak_key, weak_key, 0, 0)
	objc_set_class(weak_table, api.cls('NSObject')); api.release(weak_table); api.pop(weak_pool); api.release(weak_key)
	assert objc_add_method(cls, u64(c'allKeys'), u64(unsafe { voidptr(map_override) }), c'@16@0:8')
	override := api.msg(cls, c'new', 0, 0, 0, 0); assert objc_responds(override, c'allKeys') && api.msg(override, c'allKeys', 0, 0, 0, 0) == 99; api.release(override)
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.weak.len == 0
}
fn test_ns_map_table() {
	$if macos { native_send := C.dlsym(voidptr(i64(-2)), c'objc_msgSend'); assert native_send != unsafe { nil }; map_shared(MapApi{true, u64(native_send)}); println('IOS-MAP-TABLE-NATIVE: layout, encodings, nil handling, equality/identity, original keys and strong/weak options PASS') }
	for _ in 0 .. 2 { objc_start(); system_data_start()!; api := map_api(); map_shared(api); map_runtime(api); objc_stop(); assert ios_runtime.live == 0; system_data_stop() }
	println('IOS-MAP-TABLE: native parity, concurrency, reentrant callbacks, weak cleanup, guarded storage, isa cleanup and two balanced lifetimes PASS')
}
fn test_ns_map_table_rejections() {
	objc_start(); system_data_start()!; api := map_api()
	modes := ['raw', 'spoof', 'isa', 'raw-isa', 'subclass', 'caller-subclass', 'key-options', 'value-options', 'capacity', 'overflow', 'reinit', 'associated-copy', 'active-destroy', 'copy', 'mutableCopy', 'encodeWithCoder:', 'initWithCoder:', 'keyPointerFunctions', 'valuePointerFunctions', 'initWithKeyPointerFunctions:valuePointerFunctions:capacity:', 'dictionaryRepresentation', 'keyEnumerator', 'objectEnumerator', 'enumerator', 'allKeys', 'allValues', 'countByEnumeratingWithState:objects:count:']!
	for mode in modes {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0; pid := C.ios_fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1]); cls := api.cls('NSMapTable'); object := api.msg(cls, c'new', 0, 0, 0, 0)
			match mode {
				'raw' { api.msg(objc_allocate(cls), c'count', 0, 0, 0, 0) }
				'spoof' { fake := objc_new(api.cls('NSObject')); objc_set_class(fake, cls); api.msg(fake, c'count', 0, 0, 0, 0) }
				'isa', 'raw-isa' { if mode == 'isa' { objc_set_class(object, api.cls('NSObject')) } else { unsafe { *(&u64(object)) = api.cls('NSObject') } }; api.msg(object, c'count', 0, 0, 0, 0) }
				'subclass', 'caller-subclass' { custom := objc_allocate_class(cls, c'UnsupportedMapTable', 0); objc_register_class(custom); if mode == 'subclass' { objc_allocate(custom) } else { mut storage := u64(0); objc_construct_instance(custom, u64(unsafe { &storage })) } }
				'key-options', 'value-options', 'capacity' { ns_map_table_initialize(objc_allocate(cls), if mode == 'key-options' { u64(65536) } else { u64(0) }, if mode == 'value-options' { u64(256) } else { u64(0) }, if mode == 'capacity' { u64(4097) } else { u64(0) }) }
				'overflow' { for _ in 0 .. 4097 { key := objc_new(api.cls('NSObject')); api.msg(object, c'setObject:forKey:', object, key, 0, 0); api.release(key) } }
				'reinit' { ns_map_table_initialize(object, 0, 0, 0) }
				'associated-copy' { objc_copy_value(object, false) }
				'active-destroy' { ns_map_table_enter(object); objc_destruct_instance(object) }
				else { api.msg(object, mode.str, 0, 0, 0, 0) }
			}
			C._exit(0)
		}
		C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
		for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid
		output := unsafe { tos(&bytes[0], length) }; assert status == 256 && output.contains('iOS:') && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), mode + ': ' + output
	}
	objc_stop(); assert ios_runtime.live == 0; system_data_stop()
	println('IOS-MAP-TABLE-REJECT: ' + modes.len.str() + ' invalid storage, subclasses, options, capacity, copies and unsupported APIs PASS')
}
