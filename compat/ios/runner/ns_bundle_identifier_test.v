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

type BundleIdentifierSend = fn (u64, u64, u64) u64
struct BundleIdentifierApi { native bool send u64 }

fn (api BundleIdentifierApi) cls() u64 {
	$if macos { if api.native { return u64(C.objc_getClass(c'NSBundle')) } }
	return ios_runtime.names['NSBundle']
}
fn (api BundleIdentifierApi) selector(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api BundleIdentifierApi) message(object u64, name &char, argument u64) u64 {
	return unsafe { BundleIdentifierSend(voidptr(api.send))(object, api.selector(name), argument) }
}
fn (api BundleIdentifierApi) pool() u64 {
	$if macos { if api.native { return api.message(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0) } }
	return objc_pool_push()
}
fn (api BundleIdentifierApi) drain(pool u64) {
	$if macos { if api.native { api.message(pool, c'drain', 0); return } }
	objc_pool_pop(pool)
}
fn identifier_text(api BundleIdentifierApi, value u64, expected string) {
	assert value != 0
	assert unsafe { (&char(voidptr(api.message(value, c'UTF8String', 0)))).vstring() } == expected
}
fn identifier_worker(api BundleIdentifierApi, bundle u64, imp u64) {
	pool := api.pool()
	for _ in 0 .. 256 {
		assert api.message(api.cls(), c'mainBundle', 0) == bundle
		value := api.message(bundle, c'bundleIdentifier', 0)
		identifier_text(api, value, 'org.vinix.notification-checks')
		assert unsafe { BundleIdentifierSend(voidptr(imp))(bundle, api.selector(c'bundleIdentifier'), 0) } == value
	}
	api.drain(pool)
}
fn identifier_shared(api BundleIdentifierApi) {
	pool := api.pool()
	cls := api.cls(); bundle := api.message(cls, c'mainBundle', 0)
	assert bundle != 0
	api.message(bundle, c'retain', 0)
	assert api.message(bundle, c'respondsToSelector:', api.selector(c'bundleIdentifier')) == 1
	assert api.message(cls, c'respondsToSelector:', api.selector(c'bundleIdentifier')) == 0
	assert api.message(bundle, c'respondsToSelector:', api.selector(c'vinixMissingIdentifierSelector')) == 0
	mut imp := u64(0)
	$if macos { if api.native {
		method := C.class_getInstanceMethod(voidptr(cls), voidptr(api.selector(c'bundleIdentifier')))
		assert method != unsafe { nil }
		assert unsafe { C.method_getTypeEncoding(method).vstring() } == '@16@0:8'
		imp = u64(C.method_getImplementation(method))
	} }
	if !api.native {
		method := objc_instance_method(cls, api.selector(c'bundleIdentifier'))
		assert method != 0 && ctext(u64(objc_method_types(method))) == '@16@0:8'
		assert objc_instance_method(read64(cls), api.selector(c'bundleIdentifier')) == 0
		assert objc_instance_method(cls, api.selector(c'vinixMissingIdentifierSelector')) == 0
		imp = objc_method_imp(method)
	}
	assert imp != 0
	signature := api.message(bundle, c'methodSignatureForSelector:', api.selector(c'bundleIdentifier'))
	assert signature != 0 && api.message(signature, c'numberOfArguments', 0) == 2
	assert api.message(signature, c'methodReturnLength', 0) == 8
	assert unsafe { (&char(voidptr(api.message(signature, c'methodReturnType', 0)))).vstring() } == '@'
	api.drain(pool)
	// The first identifier read races across workers, before a cached value exists.
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn identifier_worker(api, bundle, imp) }
	for worker in workers { worker.wait() }
	value := api.message(bundle, c'bundleIdentifier', 0)
	api.message(value, c'retain', 0)
	pool_after := api.pool()
	identifier_worker(api, bundle, imp)
	api.drain(pool_after)
	assert api.message(bundle, c'bundleIdentifier', 0) == value
	identifier_text(api, value, 'org.vinix.notification-checks')
	api.message(value, c'release', 0)
	api.message(bundle, c'release', 0)
}
fn identifier_xml(value string) string {
	return '<plist version="1.0"><dict>' + if value == '' { '' } else { '<key>CFBundleIdentifier</key>' + value } + '</dict></plist>'
}
fn identifier_runtime_values(root string, api BundleIdentifierApi) {
	values := ['<string>org.vinix.example</string>', '<string></string>', '<string>é😀&amp;é</string>', '<integer>42</integer>', '<true/>', '<array><string>x</string></array>', '<dict><key>x</key><string>y</string></dict>', '', 'malformed', 'missing', 'binary']
	path := root + '/Info.plist'
	for i, value in values {
		if os.exists(path) { os.rm(path) or { panic(err) } }
		if value == 'binary' {
			bytes := hex.decode('62706c6973743030d101025f1012434642756e646c654964656e7469666965725f10106f72672e76696e69782e62696e617279080b200000000000000101000000000000000300000000000000000000000000000033') or { panic(err) }
			os.write_file_array(path, bytes) or { panic(err) }
			unsafe { bytes.free() }
		} else if value != 'missing' {
			os.write_file(path, if value == 'malformed' { 'not a plist' } else { identifier_xml(value) }) or { panic(err) }
		}
		objc_start(); ios_runtime.bundle = root
		pool := api.pool()
		bundle := api.message(api.cls(), c'mainBundle', 0)
		result := api.message(bundle, c'bundleIdentifier', 0)
		match i {
			0 { identifier_text(api, result, 'org.vinix.example') }
			1 { identifier_text(api, result, '') }
			2 { identifier_text(api, result, 'é😀&é') }
			3 { assert api.message(result, c'integerValue', 0) == 42 }
			4 { assert api.message(result, c'boolValue', 0) == 1 }
			5 {
				assert api.message(result, c'count', 0) == 1
				identifier_text(api, api.message(result, c'objectAtIndex:', 0), 'x')
			}
			6 {
				assert api.message(result, c'count', 0) == 1
				key := owned_string('x')
				identifier_text(api, api.message(result, c'objectForKey:', key), 'y')
				objc_release(key)
			}
			10 { identifier_text(api, result, 'org.vinix.binary') }
			else { assert result == 0 }
		}
		os.write_file(path, identifier_xml('<string>changed</string>')) or { panic(err) }
		api.drain(pool)
		assert api.message(bundle, c'bundleIdentifier', 0) == result
		if i == 0 { assert obj_header(result).refs == 1 }
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
}
fn test_bundle_identifier_native() {
	$if macos {
		api := BundleIdentifierApi{true, u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))}
		assert api.send != 0
		identifier_shared(api)
		println('IOS-BUNDLE-IDENTIFIER-NATIVE: main bundle, metadata, signature, direct IMP, eight workers and pool drain PASS')
	}
}
fn test_bundle_identifier_runtime() {
	root := os.join_path(os.temp_dir(), 'vinix-bundle-identifier-' + os.getpid().str())
	assert !os.exists(root)
	os.mkdir_all(root) or { panic(err) }
	defer { os.rmdir_all(root) or {}; unsafe { root.free() } }
	api := BundleIdentifierApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })}
	identifier_runtime_values(root, api)
	for _ in 0 .. 2 {
		os.write_file(root + '/Info.plist', identifier_xml('<string>org.vinix.notification-checks</string>')) or { panic(err) }
		objc_start(); ios_runtime.bundle = root
		identifier_shared(api)
		assert ios_runtime.live == 4 && ios_runtime.objects.len == 4
		assert obj_header(ios_runtime.bundle_object).refs == 1
		assert obj_header(obj_header(ios_runtime.bundle_object).fields[0]).refs == 1
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-BUNDLE-IDENTIFIER: XML, binary, Unicode, empty, non-string, absent, malformed, cache, metadata, IMP, eight workers and two balanced lifetimes PASS')
}
