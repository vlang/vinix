// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.hex
import os

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.class_getClassMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.method_getImplementation(voidptr) voidptr
fn C.dlsym(voidptr, &char) voidptr

type DictionaryFileSend = fn (u64, u64, u64, u64, u64) u64
type DictionaryFileDouble = fn (u64, u64) f64
struct DictionaryFileApi { native bool send u64 }
fn (api DictionaryFileApi) cls(name string) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name.str)) } }
	return ios_runtime.names[name]
}
fn (api DictionaryFileApi) selector(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api DictionaryFileApi) msg(object u64, name &char, a u64, b u64, c u64) u64 {
	return unsafe { DictionaryFileSend(voidptr(api.send))(object, api.selector(name), a, b, c) }
}
fn (api DictionaryFileApi) string(text string) u64 {
	return api.msg(api.msg(api.cls('NSString'), c'alloc', 0, 0, 0), c'initWithBytes:length:encoding:', u64(text.str), u64(text.len), 4)
}
fn (api DictionaryFileApi) get(object u64, key string) u64 {
	name := api.string(key)
	value := api.msg(object, c'objectForKey:', name, 0, 0)
	api.msg(name, c'release', 0, 0, 0)
	return value
}
fn (api DictionaryFileApi) pool() u64 {
	$if macos { if api.native { return api.msg(api.cls('NSAutoreleasePool'), c'new', 0, 0, 0) } }
	return objc_pool_push()
}
fn (api DictionaryFileApi) drain(pool u64) {
	$if macos { if api.native { api.msg(pool, c'drain', 0, 0, 0); return } }
	objc_pool_pop(pool)
}
fn dictionary_file_values(api DictionaryFileApi, object u64) {
	assert api.msg(object, c'count', 0, 0, 0) == 6
	text := api.get(object, 'é😀')
	assert unsafe { (&char(voidptr(api.msg(text, c'UTF8String', 0, 0, 0)))).vstring() } == 'value'
	array := api.get(object, 'array')
	assert api.msg(array, c'count', 0, 0, 0) == 1
	assert api.msg(api.get(api.get(object, 'dict'), 'x'), c'integerValue', 0, 0, 0) == 42
	assert api.msg(api.get(object, 'bool'), c'boolValue', 0, 0, 0) == 1
	assert unsafe { DictionaryFileDouble(voidptr(api.send))(api.get(object, 'real'), api.selector(c'doubleValue')) } == 1.5
	data := api.get(object, 'data')
	assert api.msg(data, c'length', 0, 0, 0) == 3
	bytes := unsafe { &u8(voidptr(api.msg(data, c'bytes', 0, 0, 0))) }
	assert unsafe { bytes[0] == 0 && bytes[1] == 1 && bytes[2] == 255 }
}
fn dictionary_file_worker(api DictionaryFileApi, path u64, cls u64, imp u64) {
	pool := api.pool()
	for _ in 0 .. 16 {
		result := unsafe { DictionaryFileSend(voidptr(imp))(cls, api.selector(c'dictionaryWithContentsOfFile:'), path, 0, 0) }
		dictionary_file_values(api, result)
	}
	api.drain(pool)
}
fn dictionary_file_shared(api DictionaryFileApi, root string) {
	pool := api.pool()
	for class_name in ['NSDictionary', 'NSMutableDictionary'] {
		cls := api.cls(class_name)
		selector := api.selector(c'dictionaryWithContentsOfFile:')
		assert api.msg(cls, c'respondsToSelector:', selector, 0, 0) == 1
		instance := api.msg(cls, c'dictionary', 0, 0, 0)
		assert api.msg(instance, c'respondsToSelector:', selector, 0, 0) == 0
		mut imp := u64(0)
		$if macos { if api.native {
			method := C.class_getClassMethod(voidptr(cls), voidptr(selector))
			assert method != unsafe { nil }
			assert unsafe { C.method_getTypeEncoding(method).vstring() } == '@24@0:8@16'
			imp = u64(C.method_getImplementation(method))
		} }
		if !api.native {
			method := objc_instance_method(read64(cls), selector)
			assert method != 0 && ctext(u64(objc_method_types(method))) == '@24@0:8@16'
			assert objc_instance_method(cls, selector) == 0
			imp = objc_method_imp(method)
		}
		assert imp != 0
		signature := api.msg(cls, c'methodSignatureForSelector:', selector, 0, 0)
		assert signature != 0 && api.msg(signature, c'numberOfArguments', 0, 0, 0) == 3
		assert api.msg(signature, c'methodReturnLength', 0, 0, 0) == 8
		assert unsafe { (&char(voidptr(api.msg(signature, c'methodReturnType', 0, 0, 0)))).vstring() } == '@'
		for i in 0 .. 9 {
			path := api.string(if i == 8 { root } else { root + '/' + i.str() + '.plist' })
			result := api.msg(cls, c'dictionaryWithContentsOfFile:', path, 0, 0)
			assert (result != 0) == (i in [0, 1, 6])
			if i in [0, 6] {
				dictionary_file_values(api, result)
				mutable := class_name == 'NSMutableDictionary'
				assert api.msg(result, c'isKindOfClass:', api.cls('NSMutableDictionary'), 0, 0) == u64(mutable || i == 0)
				assert api.msg(api.get(result, 'array'), c'isKindOfClass:', api.cls('NSMutableArray'), 0, 0) == 1
				assert api.msg(api.get(result, 'dict'), c'isKindOfClass:', api.cls('NSMutableDictionary'), 0, 0) == u64(mutable || i == 0)
				api.msg(result, c'retain', 0, 0, 0)
				saved := api.pool()
				dictionary_file_worker(api, path, cls, imp)
				api.drain(saved)
				dictionary_file_values(api, result)
				if mutable {
					key := api.string('added'); value := api.string('new')
					api.msg(result, c'setObject:forKey:', value, key, 0)
					api.msg(api.get(result, 'array'), c'addObject:', value, 0, 0)
					api.msg(api.get(result, 'dict'), c'setObject:forKey:', value, key, 0)
					api.msg(key, c'release', 0, 0, 0); api.msg(value, c'release', 0, 0, 0)
					assert api.msg(result, c'count', 0, 0, 0) == 7
					assert api.msg(api.get(result, 'array'), c'count', 0, 0, 0) == 2
				}
				// Each invocation reads a fresh independent tree.
				fresh := api.msg(cls, c'dictionaryWithContentsOfFile:', path, 0, 0)
				assert fresh != result
				dictionary_file_values(api, fresh)
				api.msg(result, c'release', 0, 0, 0)
			} else if i == 1 {
				assert api.msg(result, c'count', 0, 0, 0) == 0
				if class_name == 'NSMutableDictionary' {
					assert api.msg(result, c'isKindOfClass:', api.cls('NSMutableDictionary'), 0, 0) == 1
				}
			}
			api.msg(path, c'release', 0, 0, 0)
		}
		path := api.string(root + '/6.plist')
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn dictionary_file_worker(api, path, cls, imp) }
		for worker in workers { worker.wait() }
		api.msg(path, c'release', 0, 0, 0)
	}
	path := api.string(root + '/0.plist')
	retained := api.msg(api.cls('NSDictionary'), c'dictionaryWithContentsOfFile:', path, 0, 0)
	api.msg(retained, c'retain', 0, 0, 0)
	api.msg(path, c'release', 0, 0, 0)
	api.drain(pool)
	dictionary_file_values(api, retained)
	api.msg(retained, c'release', 0, 0, 0)
}
fn dictionary_file_inputs(root string) {
	os.mkdir_all(root) or { panic(err) }
	values := ['<dict><key>é😀</key><string>value</string><key>array</key><array><string>x</string></array><key>dict</key><dict><key>x</key><integer>42</integer></dict><key>data</key><data>AAH/</data><key>real</key><real>1.5</real><key>bool</key><true/></dict>', '<dict/>', '<array/>', '<string>x</string>', 'malformed', 'missing', 'binary', '']
	for i, value in values {
		path := root + '/' + i.str() + '.plist'
		if value == 'missing' { continue }
		if value == 'binary' {
			bytes := hex.decode('62706c6973743030d601020304050607090a0b0c0d5561727261795464617461547265616c54626f6f6c6300e9d83dde005464696374a1085178430001ff233ff8000000000000095576616c7565d1080e102a08151b20252a3136383a3e47484e510000000000000101000000000000000f00000000000000000000000000000053') or { panic(err) }
			os.write_file_array(path, bytes) or { panic(err) }
			unsafe { bytes.free() }
		} else {
			os.write_file(path, if i in [4, 7] { value } else { '<plist version="1.0">' + value + '</plist>' }) or { panic(err) }
		}
	}
}
fn test_dictionary_file_native() {
	$if macos {
		root := os.temp_dir() + '/vinix-dictionary-file-native-' + os.getpid().str()
		assert !os.exists(root)
		dictionary_file_inputs(root)
		defer { os.rmdir_all(root) or {} }
		api := DictionaryFileApi{true, u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))}
		assert api.send != 0
		dictionary_file_shared(api, root)
		println('IOS-DICTIONARY-FILE-NATIVE: XML, binary, values, mutability, metadata, IMP, eight workers and pool drain PASS')
	}
}
fn test_dictionary_file_runtime() {
	root := os.temp_dir() + '/vinix-dictionary-file-' + os.getpid().str()
	assert !os.exists(root)
	dictionary_file_inputs(root)
	defer { os.rmdir_all(root) or {} }
	api := DictionaryFileApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })}
	for _ in 0 .. 2 {
		objc_start()
		dictionary_file_shared(api, root)
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-DICTIONARY-FILE: XML, binary, Unicode, empty, invalid, missing, mutability, metadata, IMP, eight workers and two balanced lifetimes PASS')
}
