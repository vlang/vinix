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

type DictionaryVariadicSend = fn (u64, u64, u64, u64, u64) u64
type DictionaryVariadicCall = fn (u64, u64, u64, u64, &u64) u64
struct DictionaryVariadicApi { native bool send u64 }

// Real Darwin call for both native Foundation and the guest's message/IMP
// trampolines. Anonymous words live at SP; FP/LR stay above all sixteen words.
@[_naked]
fn dictionary_variadic_call() {
	asm volatile arm64 {
		sub sp, sp, 144
		stp x29, x30, [sp, 128]
		mov x29, sp
		mov x16, x0
		mov x0, x1
		mov x1, x2
		mov x2, x3
		ldp x9, x10, [x4]
		stp x9, x10, [sp]
		ldp x9, x10, [x4, 16]
		stp x9, x10, [sp, 16]
		ldp x9, x10, [x4, 32]
		stp x9, x10, [sp, 32]
		ldp x9, x10, [x4, 48]
		stp x9, x10, [sp, 48]
		ldp x9, x10, [x4, 64]
		stp x9, x10, [sp, 64]
		ldp x9, x10, [x4, 80]
		stp x9, x10, [sp, 80]
		ldp x9, x10, [x4, 96]
		stp x9, x10, [sp, 96]
		ldp x9, x10, [x4, 112]
		stp x9, x10, [sp, 112]
		mov x3, 1
		mov x4, 1
		mov x5, 1
		mov x6, 1
		mov x7, 1
		blr x16
		ldp x29, x30, [sp, 128]
		add sp, sp, 144
		ret
	}
}
fn (api DictionaryVariadicApi) cls(name &char) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name)) } }
	return ios_runtime.names[unsafe { name.vstring() }]
}
fn (api DictionaryVariadicApi) sel(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api DictionaryVariadicApi) msg(object u64, name &char, a u64, b u64, c u64) u64 {
	return unsafe { DictionaryVariadicSend(voidptr(api.send))(object, api.sel(name), a, b, c) }
}
fn (api DictionaryVariadicApi) string(cls &char, text string) u64 {
	return api.msg(api.msg(api.cls(cls), c'alloc', 0, 0, 0), c'initWithBytes:length:encoding:', u64(text.str), u64(text.len), 4)
}
fn (api DictionaryVariadicApi) call(entry u64, cls u64, first u64, words [16]u64) u64 {
	return unsafe { DictionaryVariadicCall(voidptr(dictionary_variadic_call))(entry, cls, api.sel(c'dictionaryWithObjectsAndKeys:'), first, &words[0]) }
}
fn (api DictionaryVariadicApi) pool() u64 {
	$if macos { if api.native { return api.msg(api.cls(c'NSAutoreleasePool'), c'new', 0, 0, 0) } }
	return objc_pool_push()
}
fn (api DictionaryVariadicApi) drain(pool u64) {
	$if macos { if api.native { api.msg(pool, c'drain', 0, 0, 0); return } }
	objc_pool_pop(pool)
}
fn dictionary_variadic_worker(api DictionaryVariadicApi, cls u64, entry u64) {
	winner := if cls == api.cls(c'NSMutableDictionary') { 7 } else { 0 }
	for text in ['', 'é😀', 'a\x00b', 'key'] {
		pool := api.pool()
		mut keys := [8]u64{}
		mut values := [8]u64{}
		mut words := [16]u64{}
		for i in 0 .. 8 {
			keys[i] = api.string(if i == 0 { c'NSMutableString' } else { c'NSString' }, if i in [0, 7]! { text } else { 'key-' + i.str() })
			values[i] = api.string(c'NSMutableString', 'value-' + i.str())
			words[i * 2] = keys[i]
			if i > 0 { words[i * 2 - 1] = values[i] }
		}
		dictionary := api.call(entry, cls, values[0], words)
		assert dictionary != 0 && api.msg(dictionary, c'count', 0, 0, 0) == 7
		assert api.msg(dictionary, c'objectForKey:', keys[7], 0, 0) == values[winner]
		for i in 1 .. 7 { assert api.msg(dictionary, c'objectForKeyedSubscript:', keys[i], 0, 0) == values[i] }
		changed := api.string(c'NSString', 'changed')
		api.msg(keys[0], c'setString:', changed, 0, 0)
		api.msg(values[winner], c'setString:', changed, 0, 0)
		assert api.msg(dictionary, c'objectForKey:', keys[0], 0, 0) == 0
		assert api.msg(dictionary, c'objectForKey:', keys[7], 0, 0) == values[winner]
		assert ctext(api.msg(values[winner], c'UTF8String', 0, 0, 0)) == 'changed'
		api.msg(dictionary, c'retain', 0, 0, 0)
		for i in 0 .. 8 { api.msg(keys[i], c'release', 0, 0, 0); api.msg(values[i], c'release', 0, 0, 0) }
		api.drain(pool)
		lookup := api.string(c'NSString', text)
		stored := api.msg(dictionary, c'objectForKey:', lookup, 0, 0)
		assert stored == values[winner] && ctext(api.msg(stored, c'UTF8String', 0, 0, 0)) == 'changed'
		if api.msg(dictionary, c'isKindOfClass:', api.cls(c'NSMutableDictionary'), 0, 0) != 0 {
			api.msg(dictionary, c'removeObjectForKey:', lookup, 0, 0)
			assert api.msg(dictionary, c'count', 0, 0, 0) == 6
			api.msg(dictionary, c'setObject:forKey:', changed, lookup, 0)
			assert api.msg(dictionary, c'count', 0, 0, 0) == 7
		}
		api.msg(changed, c'release', 0, 0, 0)
		api.msg(lookup, c'release', 0, 0, 0)
		api.msg(dictionary, c'release', 0, 0, 0)
	}
}
fn dictionary_variadic_shared(api DictionaryVariadicApi) {
	pool := api.pool()
	selector := api.sel(c'dictionaryWithObjectsAndKeys:')
	for class_name in [c'NSDictionary', c'NSMutableDictionary']! {
		if api.native { println('native dictionary variadic: ' + ctext(u64(class_name))) }
		cls := api.cls(class_name)
		mut imp := u64(0)
		$if macos { if api.native {
			method := C.class_getClassMethod(voidptr(cls), voidptr(selector))
			assert method != unsafe { nil } && C.class_getInstanceMethod(voidptr(cls), voidptr(selector)) == unsafe { nil }
			assert unsafe { C.method_getTypeEncoding(method).vstring() } == '@24@0:8@16'
			imp = u64(C.method_getImplementation(method))
		} }
		if !api.native {
			method := objc_class_method(cls, selector)
			assert method != 0 && objc_instance_method(cls, selector) == 0
			assert ctext(u64(objc_method_types(method))) == '@24@0:8@16'
			imp = objc_method_imp(method)
		}
		assert imp != 0 && api.msg(cls, c'respondsToSelector:', selector, 0, 0) == 1
		signature := api.msg(cls, c'methodSignatureForSelector:', selector, 0, 0)
		assert api.msg(signature, c'numberOfArguments', 0, 0, 0) == 3
		assert api.msg(signature, c'methodReturnLength', 0, 0, 0) == 8
		assert ctext(api.msg(signature, c'getArgumentTypeAtIndex:', 2, 0, 0)) == '@'
		for entry in [api.send, imp]! {
			empty := api.call(entry, cls, 0, [16]u64{init: 1})
			assert api.msg(empty, c'count', 0, 0, 0) == 0
			assert api.msg(empty, c'respondsToSelector:', selector, 0, 0) == 0
			key := api.msg(api.cls(c'NSNumber'), c'numberWithInteger:', 42, 0, 0)
			value := api.msg(api.cls(c'NSObject'), c'new', 0, 0, 0)
			mut words := [16]u64{init: 1}; words[0] = key; words[1] = 0
			one := api.call(entry, cls, value, words)
			assert api.msg(one, c'count', 0, 0, 0) == 1 && api.msg(one, c'objectForKey:', key, 0, 0) == value
			assert api.msg(one, c'isKindOfClass:', api.cls(c'NSMutableDictionary'), 0, 0) == u64(ctext(u64(class_name)) == 'NSMutableDictionary')
			api.msg(value, c'release', 0, 0, 0)
		}
		mut threads := []thread{}
		for index in 0 .. 8 { threads << spawn dictionary_variadic_worker(api, cls, if index & 1 == 0 { api.send } else { imp }) }
		threads.wait()
	}
	assert api.msg(api.cls(c'NSObject'), c'respondsToSelector:', selector, 0, 0) == 0
	api.drain(pool)
}
fn dictionary_variadic_key_copy(key u64, selector &char, zone u64) u64 {
	assert key != 0 && ctext(u64(selector)) == 'copyWithZone:' && zone == 0
	mut objects := []u64{}
	for _ in 0 .. 1024 { objects << objc_allocate(ios_runtime.names['NSObject']) }
	for object in objects { objc_release(object) }
	return owned_string('copied')
}
fn dictionary_variadic_frame(cls u64, first u64, stack u64) u64 {
	mut frame := RegisterFrame{}
	frame.x[0] = cls; frame.x[1] = u64(c'dictionaryWithObjectsAndKeys:'); frame.x[2] = first
	for i in 3 .. 8 { frame.x[i] = 1 }
	frame.stack = stack
	assert objc_dispatch(mut frame, 0) == 0
	return frame.x[0]
}
fn dictionary_variadic_private() {
	api := DictionaryVariadicApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })}
	pool := api.pool()
	cls := objc_allocate_class(api.cls(c'NSObject'), c'DictionaryVariadicKey', 0)
	assert objc_add_method(cls, objc_selector(c'copyWithZone:'), u64(unsafe { voidptr(dictionary_variadic_key_copy) }), c'@24@0:8^v16')
	objc_register_class(cls)
	key := objc_allocate(cls)
	value := objc_allocate(api.cls(c'NSObject'))
	mut words := [16]u64{}; words[0] = key
	dictionary := api.call(api.send, api.cls(c'NSDictionary'), value, words)
	assert obj_header(value).refs == 2
	lookup := owned_string('copied')
	assert api.msg(dictionary, c'objectForKey:', lookup, 0, 0) == value
	page := usize(C.getpagesize())
	memory := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert memory != u64(-1)
	guard := memory + u64(page)
	assert C.mprotect(voidptr(guard), page, C.PROT_NONE) == 0
	assert api.msg(dictionary_variadic_frame(api.cls(c'NSDictionary'), 0, guard), c'count', 0, 0, 0) == 0
	write64(guard - 16, lookup); write64(guard - 8, 0)
	assert api.msg(dictionary_variadic_frame(api.cls(c'NSDictionary'), value, guard - 16), c'count', 0, 0, 0) == 1
	assert C.munmap(voidptr(memory), page * 2) == 0
	for object in [key, value, lookup]! { objc_release(object) }
	api.drain(pool)
}
fn dictionary_variadic_rejections() {
	cls := ios_runtime.names['NSDictionary']
	key := owned_string('key')
	for mode in ['nil-key', 'null-stack', 'unaligned-stack', 'overflow-stack', 'limit'] {
		mut descriptors := [2]i32{}
		assert C.pipe(unsafe { &descriptors[0] }) == 0
		pid := C.ios_fork(); assert pid >= 0
		if pid == 0 {
			C.close(descriptors[0]); assert C.dup2(descriptors[1], 2) == 2; C.close(descriptors[1])
			mut words := []u64{len: if mode == 'limit' { 131072 } else { 2 }, init: key}
			if mode == 'nil-key' { words[0] = 0 }
			stack := match mode { 'null-stack' { u64(0) } 'unaligned-stack' { u64(1) } 'overflow-stack' { ~u64(7) } else { u64(words.data) } }
			dictionary_variadic_frame(cls, key, stack)
			C._exit(0)
		}
		C.close(descriptors[1]); mut bytes := [16384]u8{}; mut length := 0
		for {
			assert length < bytes.len
			count := C.read(descriptors[0], unsafe { &bytes[length] }, usize(bytes.len - length))
			if count == 0 { break }
			if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }
			assert count > 0; length += int(count)
		}
		C.close(descriptors[0]); mut status := i32(0)
		assert C.ios_waitpid(pid, &status, 0) == pid && status == 256
		output := unsafe { tos(&bytes[0], length) }
		expected := if mode == 'nil-key' { 'nil dictionary entry' } else if mode == 'limit' { 'variadic dictionary exceeds limit' } else { 'invalid variadic dictionary arguments' }
		assert output.contains('iOS: ' + expected) && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), mode + ': ' + output
	}
	objc_release(key)
}
fn test_dictionary_variadic_native() {
	$if macos {
		api := DictionaryVariadicApi{true, u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))}
		assert api.send != 0; dictionary_variadic_shared(api)
		println('IOS-DICTIONARY-VARIADIC-NATIVE: metadata, real Darwin stack calls, IMP, nil termination, duplicates, copied keys, retained values, mutation, ownership and eight workers PASS')
	}
}
fn test_dictionary_variadic_runtime() {
	for _ in 0 .. 2 {
		objc_start()
		dictionary_variadic_shared(DictionaryVariadicApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })})
		dictionary_variadic_private(); dictionary_variadic_rejections()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		objc_stop()
	}
	println('IOS-DICTIONARY-VARIADIC: metadata, real Darwin stack calls, IMP, nil termination, duplicates, copied keys, retained values, mutation, ownership, guarded arguments, copy callback, five rejection cases, eight workers and two balanced lifetimes PASS')
}
