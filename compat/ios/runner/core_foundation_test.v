// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFDictionary.h>
	#include <CoreFoundation/CFString.h>
}
#include <dlfcn.h>

fn C.CFDictionaryCreateMutable(voidptr, i64, voidptr, voidptr) voidptr
fn C.CFDictionaryAddValue(voidptr, voidptr, voidptr)
fn C.CFDictionarySetValue(voidptr, voidptr, voidptr)
fn C.CFDictionaryGetCount(voidptr) i64
fn C.CFDictionaryGetValue(voidptr, voidptr) voidptr
fn C.CFRelease(voidptr)
fn C.CFGetRetainCount(voidptr) i64
fn C.CFStringCreateMutable(voidptr, i64) voidptr
fn C.CFStringAppendCString(voidptr, &char, u32)
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32
fn C.CFGetTypeID(voidptr) u64
fn C.CFDictionaryGetTypeID() u64
fn C.CFRetain(voidptr) voidptr

type DictionaryTestAdd = fn (u64, u64, u64)

struct DictionaryTestApi {
	native bool
	@[required]
	add DictionaryTestAdd
	key_callbacks u64
	value_callbacks u64
}

fn (api DictionaryTestApi) create(keys u64, values u64) u64 {
	$if macos {
		if api.native { return u64(C.CFDictionaryCreateMutable(unsafe { nil }, 0, voidptr(keys), voidptr(values))) }
	}
	return cf_dictionary_mutable(0, 0, keys, values)
}

fn (api DictionaryTestApi) text(value string) u64 {
	$if macos {
		if api.native {
			object := C.CFStringCreateMutable(unsafe { nil }, 0)
			C.CFStringAppendCString(object, value.str, 0x08000100)
			return u64(object)
		}
	}
	return owned_string(value)
}

fn (api DictionaryTestApi) refs(object u64) i64 {
	$if macos { if api.native { return C.CFGetRetainCount(voidptr(object)) } }
	return obj_header(object).refs
}

fn (api DictionaryTestApi) release(object u64) {
	$if macos { if api.native { C.CFRelease(voidptr(object)); return } }
	objc_release(object)
}

fn (api DictionaryTestApi) count(object u64) i64 {
	$if macos { if api.native { return C.CFDictionaryGetCount(voidptr(object)) } }
	return cf_array_count(object)
}

fn (api DictionaryTestApi) value(object u64, key u64) u64 {
	$if macos { if api.native { return u64(C.CFDictionaryGetValue(voidptr(object), voidptr(key))) } }
	return cf_dictionary_value(object, key)
}

fn (api DictionaryTestApi) set(object u64, key u64, value u64) {
	$if macos { if api.native { C.CFDictionarySetValue(voidptr(object), voidptr(key), voidptr(value)); return } }
	cf_dictionary_set(object, key, value)
}

fn dictionary_test_native_add(object u64, key u64, value u64) {
	$if macos { C.CFDictionaryAddValue(voidptr(object), voidptr(key), voidptr(value)) }
}

fn dictionary_test_cases(api DictionaryTestApi) {
	for owned_keys in [false, true] {
		for owned_values in [false, true] {
			key := api.text('same key with independently owned string storage')
			equal_key := api.text('same key with independently owned string storage')
			value := api.text('first value')
			ignored := api.text('ignored value')
			assert key != equal_key
			keys := if owned_keys { api.key_callbacks } else { u64(0) }
			values := if owned_values { api.value_callbacks } else { u64(0) }
			dictionary := api.create(keys, values)
			api.add(dictionary, key, value)
			assert api.count(dictionary) == 1
			assert api.refs(key) == if owned_keys { 2 } else { 1 }
			assert api.refs(value) == if owned_values { 2 } else { 1 }
			mutation := if api.native { u64(0) } else { obj_header(dictionary).mutation }
			for _ in 0 .. 20 { api.add(dictionary, key, ignored) }
			assert api.count(dictionary) == 1 && api.value(dictionary, key) == value
			assert api.refs(ignored) == 1
			if !api.native { assert obj_header(dictionary).mutation == mutation }
			api.add(dictionary, equal_key, ignored)
			assert api.count(dictionary) == if owned_keys { 1 } else { 2 }
			assert api.value(dictionary, equal_key) == if owned_keys { value } else { ignored }
			assert api.refs(equal_key) == 1 // Equal keys are not retained or substituted.
			assert api.refs(ignored) == if !owned_keys && owned_values { 2 } else { 1 }
			api.set(dictionary, key, ignored)
			assert api.value(dictionary, key) == ignored && api.refs(value) == 1
			api.release(dictionary)
			for object in [key, equal_key, value, ignored] {
				assert api.refs(object) == 1
				api.release(object)
			}
		}
	}

	// Null pointers are valid entries with null callbacks. A null value must
	// not be confused with an absent key, including after SetValue replaces it.
	raw := api.create(0, 0)
	api.add(raw, 0, 2)
	api.add(raw, 3, 0)
	api.add(raw, 3, 4)
	assert api.count(raw) == 2 && api.value(raw, 0) == 2 && api.value(raw, 3) == 0
	api.set(raw, 0, 0)
	api.add(raw, 0, 5)
	assert api.count(raw) == 2 && api.value(raw, 0) == 0
	for key := u64(16); key < 272; key++ { api.add(raw, key, key + 1000) }
	for key := u64(16); key < 272; key++ { api.add(raw, key, key + 2000) }
	assert api.count(raw) == 258
	for key := u64(16); key < 272; key++ { assert api.value(raw, key) == key + 1000 }
	api.release(raw)
	// Independently raw key/value callback modes also accept a null pointer.
	for raw_key in [false, true] {
		object := api.text('owned member opposite a null raw member')
		dictionary := api.create(if raw_key { u64(0) } else { api.key_callbacks }, if raw_key { api.value_callbacks } else { u64(0) })
		api.add(dictionary, if raw_key { u64(0) } else { object }, if raw_key { object } else { u64(0) })
		assert api.count(dictionary) == 1 && api.refs(object) == 2
		api.release(dictionary)
		assert api.refs(object) == 1
		api.release(object)
	}
}

fn dictionary_test_worker(api DictionaryTestApi) {
	for _ in 0 .. 25 { dictionary_test_cases(api) }
}

fn test_cf_dictionary_add_value_matches_native_ownership_and_pointer_semantics() {
	$if macos {
		keys := unsafe { &C.kCFTypeDictionaryKeyCallBacks }
		values := unsafe { &C.kCFTypeDictionaryValueCallBacks }
		dictionary_test_cases(DictionaryTestApi{native: true, add: dictionary_test_native_add, key_callbacks: u64(keys), value_callbacks: u64(values)})
		println('IOS-CF-DICTIONARY-NATIVE: duplicate and equal keys keep first value without retains; four callback modes, raw null key/value and 258-entry growth match native CoreFoundation')
	}
	for _ in 0 .. 2 {
		objc_start()
		address := runtime_symbol('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', '_CFDictionaryAddValue') or { panic(err) }
		api := DictionaryTestApi{
			add: unsafe { DictionaryTestAdd(voidptr(address)) }
			key_callbacks: cf_callbacks_constant('_kCFTypeDictionaryKeyCallBacks')
			value_callbacks: cf_callbacks_constant('_kCFTypeDictionaryValueCallBacks')
		}
		baseline := ios_runtime.live
		for _ in 0 .. 100 {
			dictionary_test_cases(api)
			assert ios_runtime.live == baseline
		}
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn dictionary_test_worker(api) }
		workers.wait()
		assert ios_runtime.live == baseline
		objc_stop()
		assert ios_runtime.live == 0
	}
	println('IOS-CF-DICTIONARY: native add-if-absent behavior, original key/value ownership, duplicate mutation stability, raw null members, growth, eight independent workers and two clean teardowns')
}

fn dictionary_test_empty_worker() u64 {
	mut result := u64(0)
	for _ in 0 .. 200 {
		object := runtime_symbol('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', '___NSDictionary0__struct') or { panic(err) }
		assert read64(object) == ios_runtime.names['NSDictionary'] // Direct object, not a pointer cell.
		assert cf_type_id(object) == cf_dictionary_id() && cf_array_count(object) == 0
		assert !objc_is_kind(object, ios_runtime.names['NSMutableDictionary'])
		assert cf_dictionary_value(object, 0) == 0
		assert objc_retain(object) == object
		objc_release(object)
		objc_release(object) // Native constant is immortal even without a retain.
		assert obj_header(object).refs == 1
		alias := runtime_symbol('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', '___NSDictionary0__') or { panic(err) }
		assert alias == object
		if result != 0 { assert result == object }
		result = object
	}
	return result
}

fn test_cf_exported_empty_dictionary_is_direct_immutable_immortal_and_cached() {
	$if macos {
		library := C.dlopen('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation'.str, C.RTLD_NOW | C.RTLD_LOCAL)
		assert library != unsafe { nil }
		defer { C.dlclose(library) }
		object := C.dlsym(library, '__NSDictionary0__struct'.str)
		assert object != unsafe { nil }
		assert C.CFGetTypeID(object) == C.CFDictionaryGetTypeID() && C.CFDictionaryGetCount(object) == 0
		for _ in 0 .. 200 { assert C.CFRetain(object) == object; C.CFRelease(object); C.CFRelease(object) }
		assert C.CFDictionaryGetCount(object) == 0 && C.dlsym(library, '__NSDictionary0__struct'.str) == object
		println('IOS-CF-EMPTY-NATIVE: __NSDictionary0__struct is a stable direct empty dictionary object with immortal retain/release behavior')
	}
	for _ in 0 .. 2 {
		objc_start()
		mut workers := []thread u64{}
		for _ in 0 .. 8 { workers << spawn dictionary_test_empty_worker() }
		results := workers.wait()
		for object in results { assert object == results[0] }
		assert ios_runtime.live == 1 && ios_runtime.framework_objects.len == 1 && ios_runtime.framework_data.len == 0
		object := results[0]
		pool := objc_pool_push()
		values := [object]!
		array := cf_array_create(0, u64(unsafe { &values[0] }), 1, cf_callbacks_constant('_kCFTypeArrayCallBacks'))
		objc_autorelease(array)
		objc_autorelease(objc_retain(object))
		objc_pool_pop(pool)
		assert ios_runtime.live == 1 && cf_array_count(object) == 0
		// Leave a collection and a borrowed constant in the root pool to check
		// shutdown order before the cache's final reference is freed.
		objc_autorelease(cf_array_create(0, u64(unsafe { &values[0] }), 1, cf_callbacks_constant('_kCFTypeArrayCallBacks')))
		objc_autorelease(object)
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.empty_dictionary == 0
	}
	println('IOS-CF-EMPTY: direct immutable object, immortal caller references, eight concurrent first lookups, alias identity, autoreleased containers and two clean runtime teardowns')
}

fn test_cf_owned_collections_release_members_and_raw_collections_leave_pointers_alone() {
	objc_start()
	defer { objc_stop() }
	cf_allocator_default()
	array_callbacks := cf_callbacks_constant('_kCFTypeArrayCallBacks')
	key_callbacks := cf_callbacks_constant('_kCFTypeDictionaryKeyCallBacks')
	value_callbacks := cf_callbacks_constant('_kCFTypeDictionaryValueCallBacks')
	baseline := ios_runtime.live
	pool := objc_pool_push()
	for _ in 0 .. 200 {
		key := cf_string_create(0, c'a distinct owned CF key', 0x08000100)
		value := cf_string_bytes(0, u64(c'A\x00Z'), 3, 0x08000100, false)
		assert string_text(value).len == 3
		values := [key, value]!
		array := cf_array_create(0, u64(&values[0]), 2, array_callbacks)
		dictionary := cf_dictionary_mutable(0, 0, key_callbacks, value_callbacks)
		cf_dictionary_set(dictionary, key, value)
		cf_dictionary_set(dictionary, key, value)
		objc_release(key)
		objc_release(value)
		objc_release(array)
		objc_release(dictionary)
		raw := [u64(1), 2, 0]!
		objc_release(cf_array_create(0, u64(&raw[0]), 3, 0))
		raw_dictionary := cf_dictionary_mutable(0, 0, 0, 0)
		cf_dictionary_set(raw_dictionary, 1, 2)
		cf_dictionary_set(raw_dictionary, 1, 3)
		assert cf_dictionary_value(raw_dictionary, 1) == 3
		objc_release(raw_dictionary)
		data := cf_data_mutable(0, 0)
		cf_data_set_length(data, 4096)
		cf_data_set_length(data, 0)
		cf_data_set_length(data, 8192)
		objc_release(data)
		assert ios_runtime.live == baseline
	}
	objc_pool_pop(pool)
	assert ios_runtime.live == baseline
}
