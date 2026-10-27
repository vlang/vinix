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
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.method_getImplementation(voidptr) voidptr
fn C.dlsym(voidptr, &char) voidptr

type BundleInfoSend = fn (u64, u64, u64, u64, u64) u64
type BundleInfoDouble = fn (u64, u64) f64
struct BundleInfoApi { native bool send u64 }
fn (api BundleInfoApi) cls(name string) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name.str)) } }
	return ios_runtime.names[name]
}
fn (api BundleInfoApi) selector(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api BundleInfoApi) msg(object u64, name &char, a u64, b u64, c u64) u64 {
	return unsafe { BundleInfoSend(voidptr(api.send))(object, api.selector(name), a, b, c) }
}
fn (api BundleInfoApi) string(text string) u64 {
	return api.msg(api.msg(api.cls('NSString'), c'alloc', 0, 0, 0), c'initWithBytes:length:encoding:', u64(text.str), u64(text.len), 4)
}
fn (api BundleInfoApi) get(object u64, key string) u64 {
	name := api.string(key)
	value := api.msg(object, c'objectForKey:', name, 0, 0)
	api.msg(name, c'release', 0, 0, 0)
	return value
}
fn (api BundleInfoApi) pool() u64 {
	$if macos { if api.native { return api.msg(api.cls('NSAutoreleasePool'), c'new', 0, 0, 0) } }
	return objc_pool_push()
}
fn (api BundleInfoApi) drain(pool u64) {
	$if macos { if api.native { api.msg(pool, c'drain', 0, 0, 0); return } }
	objc_pool_pop(pool)
}
fn bundle_info_text(api BundleInfoApi, value u64, expected string) {
	assert value != 0
	assert unsafe { (&char(voidptr(api.msg(value, c'UTF8String', 0, 0, 0)))).vstring() } == expected
}
fn bundle_info_worker(api BundleInfoApi, bundle u64, imp u64, identifier_first bool) {
	pool := api.pool()
	for _ in 0 .. 256 {
		if identifier_first { bundle_info_text(api, api.msg(bundle, c'bundleIdentifier', 0, 0, 0), 'org.vinix.notification-checks') }
		dict := api.msg(bundle, c'infoDictionary', 0, 0, 0)
		assert dict != 0 && api.msg(dict, c'isKindOfClass:', api.cls('NSMutableDictionary'), 0, 0) == 1
		assert unsafe { BundleInfoSend(voidptr(imp))(bundle, api.selector(c'infoDictionary'), 0, 0, 0) } == dict
		identifier := api.msg(bundle, c'bundleIdentifier', 0, 0, 0)
		assert api.get(dict, 'CFBundleIdentifier') == identifier
		bundle_info_text(api, identifier, 'org.vinix.notification-checks')
	}
	api.drain(pool)
}
fn bundle_info_shared(api BundleInfoApi) {
	pool := api.pool()
	cls := api.cls('NSBundle'); bundle := api.msg(cls, c'mainBundle', 0, 0, 0)
	assert bundle != 0
	api.msg(bundle, c'retain', 0, 0, 0)
	selector := api.selector(c'infoDictionary')
	assert api.msg(bundle, c'respondsToSelector:', selector, 0, 0) == 1
	assert api.msg(cls, c'respondsToSelector:', selector, 0, 0) == 0
	assert api.msg(bundle, c'respondsToSelector:', api.selector(c'vinixMissingBundleInfoSelector'), 0, 0) == 0
	mut imp := u64(0)
	$if macos { if api.native {
		method := C.class_getInstanceMethod(voidptr(cls), voidptr(selector))
		assert method != unsafe { nil }
		assert unsafe { C.method_getTypeEncoding(method).vstring() } == '@16@0:8'
		imp = u64(C.method_getImplementation(method))
	} }
	if !api.native {
		method := objc_instance_method(cls, selector)
		assert method != 0 && ctext(u64(objc_method_types(method))) == '@16@0:8'
		assert objc_instance_method(read64(cls), selector) == 0
		assert objc_instance_method(cls, api.selector(c'vinixMissingBundleInfoSelector')) == 0
		imp = objc_method_imp(method)
	}
	assert imp != 0
	signature := api.msg(bundle, c'methodSignatureForSelector:', selector, 0, 0)
	assert signature != 0 && api.msg(signature, c'numberOfArguments', 0, 0, 0) == 2
	assert api.msg(signature, c'methodReturnLength', 0, 0, 0) == 8
	assert unsafe { (&char(voidptr(api.msg(signature, c'methodReturnType', 0, 0, 0)))).vstring() } == '@'
	api.drain(pool)
	// Race both properties on an uninitialized cache; losing trees must be freed.
	mut workers := []thread{}
	for i in 0 .. 8 { workers << spawn bundle_info_worker(api, bundle, imp, i % 2 == 0) }
	for worker in workers { worker.wait() }
	dict := api.msg(bundle, c'infoDictionary', 0, 0, 0)
	api.msg(dict, c'retain', 0, 0, 0)
	nested_pool := api.pool()
	bundle_info_worker(api, bundle, imp, false)
	api.drain(nested_pool)
	assert api.msg(bundle, c'infoDictionary', 0, 0, 0) == dict
	api.msg(dict, c'release', 0, 0, 0)
	api.msg(bundle, c'release', 0, 0, 0)
}
fn bundle_info_values(api BundleInfoApi, dict u64) {
	bundle_info_text(api, api.get(dict, 'CFBundleIdentifier'), 'é😀&é')
	nested := api.get(dict, 'nested'); items := api.get(nested, 'items')
	assert api.msg(nested, c'isKindOfClass:', api.cls('NSMutableDictionary'), 0, 0) == 1
	assert api.msg(items, c'isKindOfClass:', api.cls('NSMutableArray'), 0, 0) == 1
	assert api.msg(items, c'count', 0, 0, 0) == 5
	assert api.msg(api.msg(items, c'objectAtIndex:', 0, 0, 0), c'integerValue', 0, 0, 0) == 42
	assert api.msg(api.msg(items, c'objectAtIndex:', 1, 0, 0), c'boolValue', 0, 0, 0) == 1
	assert unsafe { BundleInfoDouble(voidptr(api.send))(api.msg(items, c'objectAtIndex:', 2, 0, 0), api.selector(c'doubleValue')) } == 1.5
	data := api.msg(items, c'objectAtIndex:', 3, 0, 0)
	assert api.msg(data, c'length', 0, 0, 0) == 3
	bytes := unsafe { &u8(voidptr(api.msg(data, c'bytes', 0, 0, 0))) }
	assert unsafe { bytes[0] == 0 && bytes[1] == 1 && bytes[2] == 255 }
	bundle_info_text(api, api.msg(items, c'objectAtIndex:', 4, 0, 0), 'x')
	key := api.string('added'); value := api.string('new')
	api.msg(nested, c'setObject:forKey:', value, key, 0)
	api.msg(items, c'addObject:', value, 0, 0)
	assert api.get(nested, 'added') == value && api.msg(items, c'count', 0, 0, 0) == 6
	api.msg(key, c'release', 0, 0, 0); api.msg(value, c'release', 0, 0, 0)
}
fn bundle_info_runtime_values(root string, api BundleInfoApi) {
	values := ['<dict><key>CFBundleIdentifier</key><string>é😀&amp;é</string><key>nested</key><dict><key>items</key><array><integer>42</integer><true/><real>1.5</real><data>AAH/</data><string>x</string></array></dict></dict>', 'binary', '<dict/>', 'missing', 'malformed', '<array><string>x</string></array>', '<string>x</string>', '<dict><key>CFBundleIdentifier</key><integer>42</integer></dict>']
	path := root + '/Info.plist'
	for order in 0 .. 2 {
		for i, value in values {
			if os.exists(path) { os.rm(path) or { panic(err) } }
			if value == 'binary' {
				bytes := hex.decode('62706c6973743030d20102030b566e65737465645f1012434642756e646c654964656e746966696572d10405556974656d73a5060708090a102a09233ff8000000000000430001ff51786600e9d83dde00002600650301080d14292c32383a3b44484a0000000000000101000000000000000c00000000000000000000000000000057') or { panic(err) }
				os.write_file_array(path, bytes) or { panic(err) }; unsafe { bytes.free() }
			} else if value != 'missing' {
				os.write_file(path, if value == 'malformed' { 'not a plist' } else { '<plist version="1.0">' + value + '</plist>' }) or { panic(err) }
			}
			objc_start(); ios_runtime.bundle = root
			pool := api.pool(); bundle := api.msg(api.cls('NSBundle'), c'mainBundle', 0, 0, 0)
			first := api.msg(bundle, if order == 0 { c'infoDictionary' } else { c'bundleIdentifier' }, 0, 0, 0)
			os.write_file(path, '<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>changed</string></dict></plist>') or { panic(err) }
			dict := api.msg(bundle, c'infoDictionary', 0, 0, 0)
			identifier := api.msg(bundle, c'bundleIdentifier', 0, 0, 0)
			assert dict != 0 && api.msg(dict, c'isKindOfClass:', api.cls('NSMutableDictionary'), 0, 0) == 1
			assert api.msg(dict, c'count', 0, 0, 0) == if i < 2 { u64(2) } else if i == 7 { u64(1) } else { u64(0) }
			assert first == if order == 0 { dict } else { identifier }
			assert api.get(dict, 'CFBundleIdentifier') == identifier
			if i < 2 { bundle_info_values(api, dict) } else if i == 7 { assert api.msg(identifier, c'integerValue', 0, 0, 0) == 42 } else { assert identifier == 0 }
			key := api.string('CFBundleIdentifier'); replacement := api.string('replacement')
			api.msg(dict, c'setObject:forKey:', replacement, key, 0)
			assert api.msg(bundle, c'bundleIdentifier', 0, 0, 0) == replacement
			api.msg(dict, c'removeObjectForKey:', key, 0, 0)
			assert api.msg(bundle, c'bundleIdentifier', 0, 0, 0) == 0
			api.msg(key, c'release', 0, 0, 0); api.msg(replacement, c'release', 0, 0, 0)
			api.drain(pool)
			assert api.msg(bundle, c'infoDictionary', 0, 0, 0) == dict && obj_header(dict).refs == 1
			objc_stop()
			assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		}
	}
}
fn test_bundle_info_native() {
	$if macos {
		api := BundleInfoApi{true, u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))}
		assert api.send != 0
		bundle_info_shared(api)
		println('IOS-BUNDLE-INFO-NATIVE: shared identifier, metadata, signature, direct IMP, eight workers and pool drain PASS')
	}
}
fn test_bundle_info_runtime() {
	root := os.temp_dir() + '/vinix-bundle-info-' + os.getpid().str()
	assert !os.exists(root)
	os.mkdir_all(root) or { panic(err) }
	defer { os.rmdir_all(root) or {} }
	api := BundleInfoApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })}
	bundle_info_runtime_values(root, api)
	for _ in 0 .. 2 {
		os.write_file(root + '/Info.plist', '<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>org.vinix.notification-checks</string></dict></plist>') or { panic(err) }
		objc_start(); ios_runtime.bundle = root
		bundle_info_shared(api)
		assert ios_runtime.live == 4 && ios_runtime.objects.len == 4
		assert obj_header(ios_runtime.bundle_object).refs == 1
		assert obj_header(obj_header(ios_runtime.bundle_object).fields[0]).refs == 1
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-BUNDLE-INFO: XML, binary, values, property order, mutation, metadata, IMP, eight workers and balanced lifetimes PASS')
}
