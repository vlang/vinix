// SPDX-License-Identifier: GPL-2.0-or-later
module main

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

type BundleReceiptSend = fn (u64, u64, u64) u64
struct BundleReceiptApi { native bool send u64 }

fn (api BundleReceiptApi) cls() u64 {
	$if macos { if api.native { return u64(C.objc_getClass(c'NSBundle')) } }
	return ios_runtime.names['NSBundle']
}
fn (api BundleReceiptApi) selector(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api BundleReceiptApi) message(object u64, name &char, argument u64) u64 {
	return unsafe { BundleReceiptSend(voidptr(api.send))(object, api.selector(name), argument) }
}
fn (api BundleReceiptApi) pool() u64 {
	$if macos { if api.native { return api.message(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0) } }
	return objc_pool_push()
}
fn (api BundleReceiptApi) drain(pool u64) {
	$if macos { if api.native { api.message(pool, c'drain', 0); return } }
	objc_pool_pop(pool)
}
fn receipt_result(api BundleReceiptApi, bundle u64, url u64) {
	if !api.native { assert url == 0; return }
	// macOS app bundles return the receipt location even without a receipt.
	assert url != 0 && api.message(url, c'isFileURL', 0) == 1
	path := unsafe { (&char(voidptr(api.message(api.message(url, c'path', 0), c'UTF8String', 0)))).vstring() }
	bundle_path := unsafe { (&char(voidptr(api.message(api.message(bundle, c'bundlePath', 0), c'UTF8String', 0)))).vstring() }
	assert path == os.join_path(bundle_path, 'Contents', '_MASReceipt', 'receipt')
	assert !os.exists(path)
}
fn receipt_worker(api BundleReceiptApi, bundle u64, imp u64) {
	pool := api.pool()
	for _ in 0 .. 256 {
		assert api.message(api.cls(), c'mainBundle', 0) == bundle
		receipt_result(api, bundle, api.message(bundle, c'appStoreReceiptURL', 0))
		receipt_result(api, bundle, unsafe { BundleReceiptSend(voidptr(imp))(bundle, api.selector(c'appStoreReceiptURL'), 0) })
	}
	api.drain(pool)
}
fn receipt_shared(api BundleReceiptApi) {
	pool := api.pool()
	cls := api.cls(); bundle := api.message(cls, c'mainBundle', 0)
	assert bundle != 0
	api.message(bundle, c'retain', 0)
	assert api.message(bundle, c'respondsToSelector:', api.selector(c'appStoreReceiptURL')) == 1
	assert api.message(cls, c'respondsToSelector:', api.selector(c'appStoreReceiptURL')) == 0
	assert api.message(bundle, c'respondsToSelector:', api.selector(c'vinixMissingReceiptSelector')) == 0
	mut imp := u64(0)
	$if macos { if api.native {
		method := C.class_getInstanceMethod(voidptr(cls), voidptr(api.selector(c'appStoreReceiptURL')))
		assert method != unsafe { nil }
		assert unsafe { C.method_getTypeEncoding(method).vstring() } == '@16@0:8'
		imp = u64(C.method_getImplementation(method))
	} }
	if !api.native {
		method := objc_instance_method(cls, api.selector(c'appStoreReceiptURL'))
		assert method != 0 && ctext(u64(objc_method_types(method))) == '@16@0:8'
		assert objc_instance_method(read64(cls), api.selector(c'appStoreReceiptURL')) == 0
		assert objc_instance_method(cls, api.selector(c'vinixMissingReceiptSelector')) == 0
		imp = objc_method_imp(method)
	}
	assert imp != 0
	signature := api.message(bundle, c'methodSignatureForSelector:', api.selector(c'appStoreReceiptURL'))
	assert signature != 0 && api.message(signature, c'numberOfArguments', 0) == 2
	assert api.message(signature, c'methodReturnLength', 0) == 8
	assert unsafe { (&char(voidptr(api.message(signature, c'methodReturnType', 0)))).vstring() } == '@'
	receipt_worker(api, bundle, imp)
	api.drain(pool)
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn receipt_worker(api, bundle, imp) }
	for worker in workers { worker.wait() }
	assert api.message(api.cls(), c'mainBundle', 0) == bundle
	api.message(bundle, c'release', 0)
}
fn test_bundle_receipt_native() {
	$if macos {
		api := BundleReceiptApi{true, u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))}
		assert api.send != 0
		receipt_shared(api)
		println('IOS-BUNDLE-RECEIPT-NATIVE: bundled missing receipt URL, instance metadata, signature, direct IMP, eight workers and pool drain PASS')
	}
}
fn test_bundle_receipt_runtime() {
	for _ in 0 .. 2 {
		objc_start()
		api := BundleReceiptApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })}
		receipt_shared(api)
		assert ios_runtime.live == 1 && ios_runtime.objects.len == 1
		assert ios_runtime.bundle_object != 0 && obj_header(ios_runtime.bundle_object).refs == 1
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-BUNDLE-RECEIPT: unavailable receipt nil, instance metadata, signature, direct IMP, eight workers, pool drain and two balanced lifetimes PASS')
}
