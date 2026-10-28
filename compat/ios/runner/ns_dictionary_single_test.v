// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.class_getClassMethod(voidptr, voidptr) voidptr
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.method_getImplementation(voidptr) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dup2(i32, i32) i32

type DictionarySingleSend = fn (u64, u64, u64, u64, u64) u64
struct DictionarySingleApi { native bool send u64 }
fn (api DictionarySingleApi) cls(name &char) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name)) } }
	return ios_runtime.names[unsafe { name.vstring() }]
}
fn (api DictionarySingleApi) sel(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api DictionarySingleApi) msg(object u64, name &char, a u64, b u64, c u64) u64 {
	return unsafe { DictionarySingleSend(voidptr(api.send))(object, api.sel(name), a, b, c) }
}
fn (api DictionarySingleApi) string(cls &char, text string) u64 {
	return api.msg(api.msg(api.cls(cls), c'alloc', 0, 0, 0), c'initWithBytes:length:encoding:', u64(text.str), u64(text.len), 4)
}
fn (api DictionarySingleApi) pool() u64 {
	$if macos { if api.native { return api.msg(api.cls(c'NSAutoreleasePool'), c'new', 0, 0, 0) } }
	return objc_pool_push()
}
fn (api DictionarySingleApi) drain(pool u64) {
	$if macos { if api.native { api.msg(pool, c'drain', 0, 0, 0); return } }
	objc_pool_pop(pool)
}
fn dictionary_single_worker(api DictionarySingleApi, cls u64, imp u64) {
	for text in ['', 'é😀', 'a\x00b', 'key'] {
		pool := api.pool()
		key := api.string(c'NSMutableString', text)
		lookup := api.string(c'NSString', text)
		value := api.string(c'NSMutableString', 'before')
		other := api.string(c'NSString', 'after')
		dictionary := unsafe { DictionarySingleSend(voidptr(imp))(cls, api.sel(c'dictionaryWithObject:forKey:'), value, key, 0) }
		assert dictionary != 0 && api.msg(dictionary, c'count', 0, 0, 0) == 1
		api.msg(key, c'setString:', other, 0, 0)
		api.msg(value, c'setString:', other, 0, 0)
		assert api.msg(dictionary, c'objectForKey:', lookup, 0, 0) == value
		assert api.msg(dictionary, c'objectForKeyedSubscript:', lookup, 0, 0) == value
		assert api.msg(dictionary, c'objectForKey:', key, 0, 0) == 0
		assert ctext(api.msg(value, c'UTF8String', 0, 0, 0)) == 'after'
		api.msg(dictionary, c'retain', 0, 0, 0)
		for object in [key, value, other]! { api.msg(object, c'release', 0, 0, 0) }
		api.drain(pool)
		assert api.msg(dictionary, c'count', 0, 0, 0) == 1
		stored := api.msg(dictionary, c'objectForKey:', lookup, 0, 0)
		assert stored == value && ctext(api.msg(stored, c'UTF8String', 0, 0, 0)) == 'after'
		api.msg(lookup, c'release', 0, 0, 0)
		api.msg(dictionary, c'release', 0, 0, 0)
	}
}
fn dictionary_single_shared(api DictionarySingleApi) {
	pool := api.pool()
	selector := api.sel(c'dictionaryWithObject:forKey:')
	for class_name in [c'NSDictionary', c'NSMutableDictionary']! {
		cls := api.cls(class_name)
		mut imp := u64(0)
		$if macos { if api.native {
			method := C.class_getClassMethod(voidptr(cls), voidptr(selector))
			assert method != unsafe { nil }
			assert unsafe { C.method_getTypeEncoding(method).vstring() } == '@32@0:8@16@24'
			assert C.class_getInstanceMethod(voidptr(cls), voidptr(selector)) == unsafe { nil }
			imp = u64(C.method_getImplementation(method))
		} }
		if !api.native {
			method := objc_class_method(cls, selector)
			assert method != 0 && ctext(u64(objc_method_types(method))) == '@32@0:8@16@24'
			assert objc_instance_method(cls, selector) == 0
			imp = objc_method_imp(method)
		}
		assert imp != 0 && api.msg(cls, c'respondsToSelector:', selector, 0, 0) == 1
		signature := api.msg(cls, c'methodSignatureForSelector:', selector, 0, 0)
		assert signature != 0 && api.msg(signature, c'numberOfArguments', 0, 0, 0) == 4
		assert api.msg(signature, c'methodReturnLength', 0, 0, 0) == 8
		for index in [u64(2), 3]! { assert ctext(api.msg(signature, c'getArgumentTypeAtIndex:', index, 0, 0)) == '@' }
		mut threads := []thread{}
		for _ in 0 .. 8 { threads << spawn dictionary_single_worker(api, cls, imp) }
		threads.wait()
		key := api.msg(api.cls(c'NSNumber'), c'numberWithInteger:', 42, 0, 0)
		lookup := api.msg(api.cls(c'NSNumber'), c'numberWithInteger:', 42, 0, 0)
		value := api.msg(api.cls(c'NSObject'), c'new', 0, 0, 0)
		dictionary := api.msg(cls, c'dictionaryWithObject:forKey:', value, key, 0)
		assert api.msg(dictionary, c'objectForKey:', lookup, 0, 0) == value
		assert api.msg(dictionary, c'respondsToSelector:', selector, 0, 0) == 0
		mutable := ctext(u64(class_name)) == 'NSMutableDictionary'
		assert api.msg(dictionary, c'isKindOfClass:', api.cls(c'NSMutableDictionary'), 0, 0) == u64(mutable)
		if mutable {
			second := api.string(c'NSString', 'second')
			api.msg(dictionary, c'setObject:forKey:', value, second, 0)
			assert api.msg(dictionary, c'count', 0, 0, 0) == 2
			api.msg(dictionary, c'removeObjectForKey:', lookup, 0, 0)
			assert api.msg(dictionary, c'count', 0, 0, 0) == 1
			assert api.msg(dictionary, c'objectForKey:', lookup, 0, 0) == 0
			assert api.msg(dictionary, c'objectForKey:', second, 0, 0) == value
			api.msg(second, c'release', 0, 0, 0)
		}
		api.msg(value, c'release', 0, 0, 0)
	}
	assert api.msg(api.cls(c'NSObject'), c'respondsToSelector:', selector, 0, 0) == 0
	api.drain(pool)
}
fn test_dictionary_single_native() {
	$if macos {
		api := DictionarySingleApi{true, u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))}
		assert api.send != 0
		dictionary_single_shared(api)
		println('IOS-DICTIONARY-SINGLE-NATIVE: metadata, IMP, copied keys, retained values, mutation, ownership and eight workers PASS')
	}
}
fn test_dictionary_single_runtime() {
	for _ in 0 .. 2 {
		objc_start()
		dictionary_single_shared(DictionarySingleApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })})
		dictionary_single_copy_callback()
		dictionary_single_rejections()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		objc_stop()
	}
	println('IOS-DICTIONARY-SINGLE: metadata, IMP, copied keys, retained values, mutation, ownership, copy callback, nil rejection, eight workers and two balanced lifetimes PASS')
}

fn dictionary_single_key_copy(key u64, selector &char, zone u64) u64 {
	assert key != 0 && ctext(u64(selector)) == 'copyWithZone:' && zone == 0
	// Exercise reentry and object-table growth before the factory stores a header.
	mut objects := []u64{}
	for _ in 0 .. 1024 { objects << objc_allocate(ios_runtime.names['NSObject']) }
	for object in objects { objc_release(object) }
	return owned_string('copied')
}
fn dictionary_single_copy_callback() {
	api := DictionarySingleApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })}
	pool := api.pool()
	cls := objc_allocate_class(api.cls(c'NSObject'), c'DictionarySingleKey', 0)
	assert objc_add_method(cls, objc_selector(c'copyWithZone:'), u64(unsafe { voidptr(dictionary_single_key_copy) }), c'@24@0:8^v16')
	objc_register_class(cls)
	key := objc_allocate(cls)
	value := objc_allocate(api.cls(c'NSObject'))
	dictionary := api.msg(api.cls(c'NSDictionary'), c'dictionaryWithObject:forKey:', value, key, 0)
	assert obj_header(value).refs == 2
	lookup := api.string(c'NSString', 'copied')
	assert api.msg(dictionary, c'objectForKey:', lookup, 0, 0) == value
	for object in [key, value, lookup]! { objc_release(object) }
	api.drain(pool)
}
fn dictionary_single_rejections() {
	api := DictionarySingleApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })}
	key := owned_string('key')
	for args in [[u64(0), key]!, [key, u64(0)]!]! {
		mut descriptors := [2]i32{}
		assert C.pipe(unsafe { &descriptors[0] }) == 0
		pid := C.ios_fork()
		assert pid >= 0
		if pid == 0 {
			C.close(descriptors[0])
			assert C.dup2(descriptors[1], 2) == 2
			C.close(descriptors[1])
			api.msg(api.cls(c'NSDictionary'), c'dictionaryWithObject:forKey:', args[0], args[1], 0)
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
		assert output.contains('iOS: nil dictionary entry') && !output.contains('AddressSanitizer') && !output.contains('runtime error:')
	}
	objc_release(key)
}
