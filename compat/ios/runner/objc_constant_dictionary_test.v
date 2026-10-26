// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os
import crypto.sha256

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
	#include <CoreFoundation/CFString.h>
	#include <CoreFoundation/CFDictionary.h>
	#include <CoreFoundation/CFArray.h>
}
#include <dlfcn.h>
fn C.dlopen(&char, int) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) int
fn C.sel_registerName(&char) voidptr
fn C.objc_getClass(&char) voidptr
fn C.class_getSuperclass(voidptr) voidptr
fn C.class_getInstanceSize(voidptr) usize
fn C.CFStringCreateMutable(voidptr, i64) voidptr
fn C.CFStringAppendCString(voidptr, &char, u32)
fn C.CFDictionaryGetValue(voidptr, voidptr) voidptr
fn C.CFDictionaryGetCount(voidptr) i64
fn C.CFDictionarySetValue(voidptr, voidptr, voidptr)
fn C.CFArrayGetCount(voidptr) i64
fn C.CFArrayGetValueAtIndex(voidptr, i64) voidptr
fn C.CFRelease(voidptr)
fn C.CFRetain(voidptr) voidptr
fn C.CFGetRetainCount(voidptr) i64
fn C.dup2(i32, i32) i32
type ConstantDictionarySend = fn (u64, u64, u64, u64, u64) u64
type ConstantDictionaryPush = fn () u64
type ConstantDictionaryPop = fn (u64)

struct ConstantDictionaryApi {
	native bool
	send u64
	push u64
	pop u64
}
fn (api ConstantDictionaryApi) message(object u64, selector &char, a u64, b u64, c u64) u64 {
	$if macos {
		if api.native {
			return unsafe { ConstantDictionarySend(voidptr(api.send))(object, u64(C.sel_registerName(selector)), a, b, c) }
		}
	}
	mut frame := RegisterFrame{}
	frame.x[0] = object; frame.x[1] = u64(selector)
	frame.x[2] = a; frame.x[3] = b; frame.x[4] = c
	assert objc_dispatch(mut frame, 0) == 0
	return frame.x[0]
}
fn (api ConstantDictionaryApi) count(object u64) i64 {
	$if macos { if api.native { return C.CFDictionaryGetCount(voidptr(object)) } }
	return i64(cf_array_count(object))
}
fn (api ConstantDictionaryApi) value(object u64, key u64) u64 {
	$if macos { if api.native { return u64(C.CFDictionaryGetValue(voidptr(object), voidptr(key))) } }
	return cf_dictionary_value(object, key)
}
fn (api ConstantDictionaryApi) array_count(object u64) i64 {
	$if macos { if api.native { return C.CFArrayGetCount(voidptr(object)) } }
	return i64(cf_array_count(object))
}
fn (api ConstantDictionaryApi) array_value(object u64, index int) u64 {
	$if macos { if api.native { return u64(C.CFArrayGetValueAtIndex(voidptr(object), index)) } }
	return cf_array_value(object, index)
}
fn (api ConstantDictionaryApi) text(value &char) u64 {
	$if macos {
		if api.native {
			object := C.CFStringCreateMutable(unsafe { nil }, 0)
			C.CFStringAppendCString(object, value, 0x08000100)
			return u64(object)
		}
	}
	return owned_string(ctext(u64(value)))
}
fn (api ConstantDictionaryApi) release(object u64) {
	$if macos { if api.native { C.CFRelease(voidptr(object)); return } }
	objc_release(object)
}
fn (api ConstantDictionaryApi) pool() u64 {
	$if macos { if api.native { return unsafe { ConstantDictionaryPush(voidptr(api.push))() } } }
	return objc_pool_push()
}
fn (api ConstantDictionaryApi) drain(pool u64) {
	$if macos { if api.native { unsafe { ConstantDictionaryPop(voidptr(api.pop))(pool) }; return } }
	objc_pool_pop(pool)
}

fn (api ConstantDictionaryApi) cls(name &char) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name)) } }
	return ios_runtime.names[ctext(u64(name))]
}

fn (api ConstantDictionaryApi) responds(object u64, name &char) bool {
	mut selector := u64(name)
	$if macos { if api.native { selector = u64(C.sel_registerName(name)) } }
	return api.message(object, c'respondsToSelector:', selector, 0, 0) != 0
}

fn dictionary_snapshot_cases(api ConstantDictionaryApi) {
	for mutable in [false, true]! {
		pool := api.pool()
		keys := [api.text(c'alpha'), api.text(c'beta'), api.text(c'gamma')]!
		values := [api.text(c'first'), api.text(c'second')]!
		entries := [values[0], values[1], values[0]]!
		cls := api.cls(if mutable { c'NSMutableDictionary' } else { c'NSDictionary' })
		dictionary := api.message(cls, c'dictionaryWithObjects:forKeys:count:', u64(unsafe { &entries[0] }), u64(unsafe { &keys[0] }), 3)
		assert api.responds(dictionary, c'allKeys') && api.responds(dictionary, c'allValues')
		assert !api.responds(cls, c'allKeys') && !api.responds(cls, c'allValues')
		unrelated := api.message(api.cls(c'NSObject'), c'new', 0, 0, 0)
		assert !api.responds(unrelated, c'allKeys') && !api.responds(unrelated, c'allValues')
		api.release(unrelated)
		all_keys := api.message(dictionary, c'allKeys', 0, 0, 0)
		all_values := api.message(dictionary, c'allValues', 0, 0, 0)
		for array in [all_keys, all_values]! {
			assert api.array_count(array) == 3
			assert api.message(array, c'isKindOfClass:', api.cls(c'NSArray'), 0, 0) == 1
			api.message(array, c'retain', 0, 0, 0)
		}
		// No ordering guarantee; preserve duplicate values and object identity.
		mut occurrences := [2]int{}
		mut key_occurrences := [3]int{}
		for i in 0 .. 3 {
			key := api.array_value(all_keys, i)
			mut matches := 0
			for j, expected in keys {
				if api.message(key, c'isEqualToString:', expected, 0, 0) != 0 { matches++; key_occurrences[j]++ }
			}
			assert matches == 1
			value := api.array_value(all_values, i)
			assert value in values
			occurrences[if value == values[0] { 0 } else { 1 }]++
		}
		assert occurrences[0] == 2 && occurrences[1] == 1
		for count in key_occurrences { assert count == 1 }
		if mutable {
			api.message(dictionary, c'removeAllObjects', 0, 0, 0)
			assert api.count(dictionary) == 0
			assert api.array_count(all_keys) == 3 && api.array_count(all_values) == 3
		}
		for key in keys { api.release(key) }
		for value in values { api.release(value) }
		api.drain(pool)
		// Both the dictionary and its original owners have gone away.
		assert api.array_count(all_keys) == 3 && api.array_count(all_values) == 3
		for i in 0 .. 3 {
			assert api.message(api.array_value(all_keys, i), c'length', 0, 0, 0) >= 4
			assert api.message(api.array_value(all_values, i), c'length', 0, 0, 0) >= 5
		}
		api.release(all_keys); api.release(all_values)
		pool_empty := api.pool()
		empty := api.message(cls, c'dictionary', 0, 0, 0)
		assert api.array_count(api.message(empty, c'allKeys', 0, 0, 0)) == 0
		assert api.array_count(api.message(empty, c'allValues', 0, 0, 0)) == 0
		api.drain(pool_empty)
	}
}

fn test_dictionary_snapshots_native_and_runtime() {
	$if macos {
		objc := C.dlopen(c'/usr/lib/libobjc.A.dylib', 2)
		assert objc != unsafe { nil }
		api := ConstantDictionaryApi{native: true, send: u64(C.dlsym(objc, c'objc_msgSend')), push: u64(C.dlsym(objc, c'objc_autoreleasePoolPush')), pop: u64(C.dlsym(objc, c'objc_autoreleasePoolPop'))}
		dictionary_snapshot_cases(api)
		assert C.dlclose(objc) == 0
		println('IOS-DICTIONARY-SNAPSHOT-NATIVE: empty/populated immutable/mutable dictionaries, unordered keys, duplicate value identities, selector scope and snapshots surviving mutation, owner release and pool drain PASS')
	}
	objc_start()
	for _ in 0 .. 20 {
		dictionary_snapshot_cases(ConstantDictionaryApi{})
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	objc_stop()
	println('IOS-DICTIONARY-SNAPSHOT: empty/populated immutable/mutable dictionaries, unordered keys, duplicate value identities, selector scope and snapshots surviving mutation, owner release and pool drain PASS')
}

fn constant_dictionary_cases(api ConstantDictionaryApi, object u64, keys [3]u64, values [3]u64) {
	pool := api.pool()
	assert api.count(object) == 3 && api.message(object, c'count', 0, 0, 0) == 3
	for i, key in keys {
		assert api.value(object, key) == values[i]
		assert api.message(object, c'objectForKey:', key, 0, 0) == values[i]
		assert api.message(object, c'objectForKeyedSubscript:', key, 0, 0) == values[i]
	}
	equal := api.text(c'beta')
	missing := api.text(c'not a member')
	assert equal != keys[1] && api.value(object, equal) == values[1]
	assert api.value(object, missing) == 0 && api.message(object, c'objectForKey:', 0, 0, 0) == 0
	api.release(equal); api.release(missing)
	for limit in [u64(0), 1, 3, 5]! {
		mut out_keys := [u64(0xfeed), 0xfeed, 0xfeed, 0xcafe]!
		mut out_values := [u64(0xfeed), 0xfeed, 0xfeed, 0xcafe]!
		api.message(object, c'getObjects:andKeys:count:', u64(unsafe { &out_values[0] }), u64(unsafe { &out_keys[0] }), limit)
		for i in 0 .. 3 {
			assert out_keys[i] == keys[i] && out_values[i] == values[i]
		}
		assert out_keys[3] == 0xcafe && out_values[3] == 0xcafe
		api.message(object, c'getObjects:andKeys:count:', 0, 0, limit)
	}
	all_keys := api.message(object, c'allKeys', 0, 0, 0)
	all_values := api.message(object, c'allValues', 0, 0, 0)
	assert api.array_count(all_keys) == 3 && api.array_count(all_values) == 3
	for i in 0 .. 3 { assert api.array_value(all_keys, i) == keys[i] && api.array_value(all_values, i) == values[i] }
	for batch in [u64(1), 2, 5]! {
		mut state := [8]u64{}
		mut buffer := [u64(0), 0, 0, 0xcafe]!
		mut index := 0
		for _ in 0 .. 5 {
			count := api.message(object, c'countByEnumeratingWithState:objects:count:', u64(unsafe { &state[0] }), u64(unsafe { &buffer[0] }), batch)
			assert count <= batch && count <= 3 && buffer[3] == 0xcafe
			if count == 0 { break }
			assert state[1] != 0 && state[2] != 0
			for i := u64(0); i < count; i++ { assert read64(state[1] + i * 8) == keys[index]; index++ }
		}
		assert index == 3
	}
	for selector in [c'copy', c'copyWithZone:']! { assert api.message(object, selector, 0, 0, 0) == object; api.release(object) }
	for selector in [c'mutableCopy', c'mutableCopyWithZone:']! {
		copy := api.message(object, selector, 0, 0, 0)
		assert copy != object && api.count(copy) == 3 && api.value(copy, keys[1]) == values[1]
		$if macos { if api.native { C.CFDictionarySetValue(voidptr(copy), voidptr(keys[1]), voidptr(values[0])) } else { cf_dictionary_set(copy, keys[1], values[0]) } }
		$else { cf_dictionary_set(copy, keys[1], values[0]) }
		assert api.value(copy, keys[1]) == values[0] && api.value(object, keys[1]) == values[1]
		api.release(copy)
	}
	for _ in 0 .. 20 { assert api.message(object, c'retain', 0, 0, 0) == object; api.release(object); api.release(object) }
	assert api.message(object, c'autorelease', 0, 0, 0) == object
	api.drain(pool)
	assert api.count(object) == 3 && api.value(object, keys[2]) == values[2]
}

fn test_constant_dictionary_native_layout_and_methods() {
	$if macos {
		core := C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', 2)
		objc := C.dlopen(c'/usr/lib/libobjc.A.dylib', 2)
		assert core != unsafe { nil } && objc != unsafe { nil }
		cls := u64(C.dlsym(core, c'OBJC_CLASS_$_NSConstantDictionary'))
		assert cls != 0 && C.class_getInstanceSize(voidptr(cls)) == 40
		assert C.class_getSuperclass(voidptr(cls)) == C.dlsym(core, c'OBJC_CLASS_$_NSDictionary')
		api := ConstantDictionaryApi{native: true, send: u64(C.dlsym(objc, c'objc_msgSend')), push: u64(C.dlsym(objc, c'objc_autoreleasePoolPush')), pop: u64(C.dlsym(objc, c'objc_autoreleasePoolPop'))}
		keys := [api.text(c'alpha'), api.text(c'beta'), api.text(c'gamma')]!
		values := [api.text(c'first'), api.text(c'second'), api.text(c'third')]!
		mut record := [cls, u64(1), 3, u64(unsafe { &keys[0] }), u64(unsafe { &values[0] })]!
		object := u64(unsafe { &record[0] })
		for _ in 0 .. 10 { constant_dictionary_cases(api, object, keys, values) }
		assert record[0] == cls && record[1] == 1 && record[2] == 3
		for key in keys { assert C.CFGetRetainCount(voidptr(key)) == 1; api.release(key) }
		for value in values { assert C.CFGetRetainCount(voidptr(value)) == 1; api.release(value) }
		assert C.dlclose(objc) == 0 && C.dlclose(core) == 0
		println('IOS-CONSTANT-DICTIONARY-NATIVE: forty-byte sorted-key record, CF/ObjC lookups, equal/nil/missing keys, full extraction with ignored count hint and guarded buffers, arrays, batched enumeration, immortal copies and independent mutable copies passed')
	}
}

fn constant_dictionary_fixture(base u64, page u64) ObjMetadata {
	for i, text in [c'alpha', c'beta', c'gamma', c'first', c'second', c'third']! {
		object := base + 512 + u64(i) * 32
		bytes := base + 1024 + u64(i) * 32
		unsafe {
			*(&u64(object)) = ios_runtime.names['NSString']
			*(&u64(object + 8)) = 0x7c8
			*(&u64(object + 16)) = bytes
			*(&u64(object + 24)) = u64(ctext(u64(text)).len)
			C.memcpy(voidptr(bytes), text, usize(ctext(u64(text)).len + 1))
			*(&u64(base + 256 + u64(i) * 8)) = object
		}
	}
	for i in 0 .. 3 {
		object := base + u64(i) * 40
		unsafe {
			*(&u64(object)) = ios_runtime.names['NSConstantDictionary']
			*(&u64(object + 8)) = 1
			*(&u64(object + 16)) = if i == 0 { u64(3) } else if i == 1 { u64(0) } else { u64(1) }
			*(&u64(object + 24)) = base + 256
			*(&u64(object + 32)) = if i == 2 { base + 320 } else { base + 280 }
		}
	}
	unsafe { *(&u64(base + 320)) = base }
	return ObjMetadata{
		image: macho.Image{segments: [macho.Segment{name: '__DATA_CONST', address: 0x1000, size: page, filesize: page, prot: 1, sections: [macho.Section{name: '__objc_dictobj', address: 0x1000, size: 120}, macho.Section{name: '__cfstring', address: 0x1200, size: 192}]}]}
		layout: macho.Layout{base: 0x1000, size: page}
		base: base
	}
}
fn constant_dictionary_register(m ObjMetadata) {
	for _ in 0 .. 20 { m.constant_dictionaries() or { panic(err) } }
}
fn constant_dictionary_reject_mutation(object u64, key u64, value u64) {
	for operation in 0 .. 3 {
		mut descriptors := [2]i32{}
		assert C.pipe(unsafe { &descriptors[0] }) == 0
		pid := C.ios_fork()
		assert pid >= 0
		if pid == 0 {
			C.close(descriptors[0])
			assert C.dup2(descriptors[1], 2) == 2
			C.close(descriptors[1])
			match operation {
				0 { cf_dictionary_set(object, key, value) }
				1 { ConstantDictionaryApi{}.message(object, c'setObject:forKeyedSubscript:', value, key, 0) }
				else { objc_destruct_instance(object) }
			}
			C._exit(0)
		}
		C.close(descriptors[1])
		mut bytes := [16384]u8{}
		mut length := 0
		for {
			assert length < bytes.len
			count := C.read(descriptors[0], unsafe { &bytes[length] }, usize(bytes.len - length))
			if count == 0 { break }
			if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }
			assert count > 0
			length += int(count)
		}
		C.close(descriptors[0])
		mut status := i32(0)
		assert C.ios_waitpid(pid, &status, 0) == pid && status == 256
		output := unsafe { tos(&bytes[0], length) }
		expected := ['CFDictionarySetValue requires a mutable dictionary', 'mutation of an immutable image dictionary', 'cannot destruct image dictionary storage']![operation]
		assert output.contains(expected) && !output.contains('runtime error:') && !output.contains('AddressSanitizer')
	}
}
fn test_constant_dictionary_readonly_image_registration_and_lifetimes() {
	for _ in 0 .. 2 {
		objc_start()
		page := u64(C.getpagesize())
		base := u64(C.mmap(unsafe { nil }, usize(page), C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
		assert base != u64(-1)
		m := constant_dictionary_fixture(base, page)
		for i in 0 .. 6 { object := base + 512 + u64(i) * 32; m.constant_string(object) or { panic(err) }; ios_runtime.constants[object] = true }
		assert C.mprotect(voidptr(base), usize(page), C.PROT_READ) == 0
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn constant_dictionary_register(m) }
		workers.wait()
		unsafe { workers.free() }
		objc_register_image(m.image, m.layout, base) or { panic(err) }
		assert ios_runtime.live == 3 && ios_runtime.objects.len == 3
		cls := runtime_symbol('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', '_OBJC_CLASS_$_NSConstantDictionary') or { panic(err) }
		assert cls == ios_runtime.names['NSConstantDictionary'] && objc_class_size(cls) == 40
		for i, pair in [[c'_options', c'Q']!, [c'_count', c'Q']!, [c'_keys', c'r^@']!, [c'_objects', c'r^@']!]! {
			ivar := objc_find_ivar(cls, pair[0]); assert ivar != 0 && objc_ivar_offset(ivar) == i64((i + 1) * 8)
			assert ctext(u64(objc_ivar_types(ivar))) == ctext(u64(pair[1]))
		}
		assert runtime_symbol('/System/Library/Frameworks/Foundation.framework/Foundation', '_OBJC_CLASS_$_NSConstantDictionary') or { panic(err) } == cls
		assert runtime_symbol('/usr/lib/libobjc.A.dylib', '_OBJC_METACLASS_$_NSConstantDictionary') or { panic(err) } == read64(cls)
		assert objc_is_kind(base, ios_runtime.names['NSDictionary']) && !objc_is_kind(base, ios_runtime.names['NSMutableDictionary'])
		assert cf_type_id(base) == cf_dictionary_id() && cf_array_count(base + 40) == 0
		assert cf_dictionary_value(base + 80, base + 512) == base
		assert !objc_responds(base, c'setObject:forKey:') && objc_responds(base, c'mutableCopyWithZone:')
		keys := [base + 512, base + 544, base + 576]!
		values := [base + 608, base + 640, base + 672]!
		mut snapshot := [15]u64{}
		for i in 0 .. 15 { snapshot[i] = read64(base + u64(i) * 8) }
		for _ in 0 .. 100 { constant_dictionary_cases(ConstantDictionaryApi{}, base, keys, values); assert ios_runtime.live == 3 }
		constant_dictionary_reject_mutation(base, keys[0], values[0])
		for i in 0 .. 15 { assert snapshot[i] == read64(base + u64(i) * 8) }
		for i in 0 .. 3 { assert obj_header(base + u64(i) * 40).refs == 1 }
		// Root pool users must drain before the image's metadata is retired.
		objc_autorelease(base)
		array := objc_allocate(ios_runtime.names['NSArray']); array_append(mut obj_header(array), base)
		objc_autorelease(array)
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.image_dictionaries == 0
		for i in 0 .. 15 { assert snapshot[i] == read64(base + u64(i) * 8) }
		assert C.munmap(voidptr(base), usize(page)) == 0
	}
	println('IOS-CONSTANT-DICTIONARY: read-only image registration, bounded native behavior, nested/empty records, class identity, eight concurrent registrations, unchanged bytes and two drained lifetimes passed')
}

fn test_constant_dictionary_invalid_image_records_do_not_publish_metadata() {
	objc_start()
	page := u64(C.getpagesize())
	base := u64(C.calloc(1, usize(page)))
	assert base != 0
	owned := objc_allocate(ios_runtime.names['NSObject'])
	disposable := objc_allocate_class(ios_runtime.names['NSObject'], c'DisposableDictionaryMember', 0)
	objc_register_class(disposable)
	for trial in 0 .. 17 {
		m := constant_dictionary_fixture(base, page)
		for i in 0 .. 6 { ios_runtime.constants[base + 512 + u64(i) * 32] = true }
		bad := base + 40 // A valid first record must not be published first.
		unsafe {
			*(&u64(bad + 16)) = 1
			match trial {
				0 { *(&u64(bad)) = 1 }
				1 { *(&u64(bad + 8)) = 0 }
				2 { *(&u64(bad + 8)) = 2 }
				3 { *(&u64(bad + 16)) = 65537 }
				4 { *(&u64(bad + 16)) = ~u64(0) }
				5 { *(&u64(bad + 24)) = 0 }
				6 { *(&u64(bad + 24)) = base + page - 4 }
				7 { *(&u64(bad + 24)) = base + page }
				8 { *(&u64(bad + 32)) = 0 }
				9 { *(&u64(bad + 32)) = base + 281 }
				10 { *(&u64(bad + 32)) = base + page }
				11 { *(&u64(base + 256)) = 1 }
				12 { *(&u64(base + 280)) = 0 }
				13 { *(&u64(base + 280)) = 1 }
				14 { *(&u64(base + 256)) = base + 608; *(&u64(base + 608)) = ios_runtime.names['NSObject'] }
				15 { *(&u64(base + 280)) = owned }
				16 { *(&u64(base + 280)) = disposable }
				else {}
			}
		}
		mut rejected := false
		m.constant_dictionaries() or { assert err.msg().contains('dictionary') || err.msg().contains('metadata'); rejected = true }
		assert rejected && ios_runtime.live == 1 && ios_runtime.objects.len == 1 && ios_runtime.image_dictionaries == 0 && obj_header(owned).refs == 1
	}
	for size in [u64(39), 121, 40 * 4097]! {
		mut m := constant_dictionary_fixture(base, page)
		m = ObjMetadata{image: macho.Image{segments: [macho.Segment{name: '__DATA', address: 0x1000, size: page, filesize: page, prot: 1, sections: [macho.Section{name: '__objc_dictobj', address: 0x1000, size: size}]}]}, layout: m.layout, base: base}
		mut rejected := false
		m.constant_dictionaries() or { assert err.msg().contains('section'); rejected = true }
		assert rejected && ios_runtime.live == 1
	}
	objc_release(owned)
	objc_dispose_class(disposable)
	objc_stop()
	C.free(voidptr(base))
	println('IOS-CONSTANT-DICTIONARY-INVALID: malformed class/options/count/arrays/member pointers and section bounds rejected before dictionary metadata publication')
}

fn constant_dictionary_fixture_resolve(_ string, symbol string) !u64 {
	if symbol == '_OBJC_CLASS_$_NSConstantDictionary' { return ios_runtime.names['NSConstantDictionary'] }
	if symbol == '_OBJC_CLASS_$_NSConstantArray' { return ios_runtime.names['NSConstantArray'] }
	if symbol == '_OBJC_CLASS_$_NSConstantIntegerNumber' { return ios_runtime.names['NSConstantIntegerNumber'] }
	if symbol == '___CFConstantStringClassReference' { return ios_runtime.names['NSString'] }
	// Other fixups are inspected/rebased but never used or executed by this
	// metadata-only fixture. Required runtime bindings remain checked by probe.
	return 0
}
fn test_constant_dictionary_records_from_supplied_image() {
	path := os.getenv('VINIX_IOS_CONSTANT_DICT_IMAGE')
	if path == '' { return }
	data := os.read_bytes(path) or { panic(err) }
	defer { unsafe { data.free() } }
	image := macho.parse(data) or { panic(err) }
	page := u64(C.getpagesize())
	layout := image.layout(page) or { panic(err) }
	objc_start()
	base := u64(C.mmap(unsafe { nil }, usize(layout.size), C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert base != u64(-1)
	for segment in image.segments {
		if segment.filesize != 0 { unsafe { C.memcpy(voidptr(base + segment.address - layout.base), &data[int(segment.fileoff)], usize(segment.filesize)) } }
	}
	fixups := image.plan_fixups(layout, base, constant_dictionary_fixture_resolve) or { panic(err) }
	for fixup in fixups { unsafe { *(&u64(base + fixup.offset)) = fixup.value } }
	unsafe { fixups.free() }
	m := ObjMetadata{image: image, layout: layout, base: base}
	for segment in image.segments {
		for section in segment.sections {
			if section.name != '__cfstring' { continue }
			assert section.size % 32 == 0
			for offset := u64(0); offset < section.size; offset += 32 {
				object := base + section.address - layout.base + offset
				m.constant_string(object) or { panic(err) }
				ios_runtime.constants[object] = true
			}
		}
	}
	assert C.mprotect(voidptr(base), usize(layout.size), C.PROT_READ) == 0
	m.constant_dictionaries() or { panic(err) }
	mut count := 0
	mut arrays := u64(0)
	mut integers := u64(0)
	for segment in image.segments {
		for section in segment.sections {
			if section.name == '__objc_arrayobj' { arrays += section.size / 24 }
			if section.name == '__objc_intobj' { integers += section.size / 24 }
			if section.name != '__objc_dictobj' { continue }
			for offset := u64(0); offset < section.size; offset += 40 {
				object := base + section.address - layout.base + offset
				header := obj_header(object)
				assert header.image_dictionary && header.keys.len == 1 && header.items.len == 1
				assert cf_array_count(object) == 1 && cf_dictionary_value(object, header.keys[0]) == header.items[0]
				equal_key := owned_string(string_text(header.keys[0]))
				assert cf_dictionary_value(object, equal_key) == header.items[0]
				objc_release(equal_key)
				assert objc_retain(object) == object; objc_release(object)
				count++
			}
		}
	}
	assert count == 3 && ios_runtime.live == 3 + i64(arrays + integers)
	objc_stop()
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.image_dictionaries == 0 && ios_runtime.image_arrays == 0 && ios_runtime.image_integers == 0
	assert C.munmap(voidptr(base), usize(layout.size)) == 0
	println('IOS-CONSTANT-DICTIONARY-IMAGE: three actual read-only image records rebased and registered, equal-key lookups passed and metadata retired; input SHA256=${sha256.sum(data).hex()}; no app code executed')
}
