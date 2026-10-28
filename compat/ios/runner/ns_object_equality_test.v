// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.object_getClass(voidptr) voidptr
fn C.sel_registerName(&char) voidptr
fn C.objc_allocateClassPair(voidptr, &char, usize) voidptr
fn C.objc_registerClassPair(voidptr)
fn C.class_addMethod(voidptr, voidptr, voidptr, &char) bool
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getImplementation(voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.method_setImplementation(voidptr, voidptr) voidptr
fn C.dlsym(voidptr, &char) voidptr

type IdentitySend = fn (u64, u64, u64, u64) u64
type IdentityCompare = fn (u64, u64, u64) bool
struct IdentityApi { native bool send u64 root u64 }
struct IdentitySuper { object u64 cls u64 }
__global identity_super_entry u64
__global identity_super_class u64

fn identity_override(object u64, _selector u64, other u64) bool {
	return other != 0 && other != object
}
fn identity_super_override(object u64, selector u64, other u64) bool {
	context := IdentitySuper{object, identity_super_class}
	return unsafe { IdentityCompare(voidptr(identity_super_entry))(u64(&context), selector, other) }
}
fn (api IdentityApi) selector(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return objc_selector(name)
}
fn (api IdentityApi) message(object u64, name &char, a u64) u64 {
	return unsafe { IdentitySend(voidptr(api.send))(object, api.selector(name), a, 0) }
}
fn (api IdentityApi) equal(object u64, other u64) bool {
	return unsafe { IdentityCompare(voidptr(api.send))(object, api.selector(c'isEqual:'), other) }
}
fn (api IdentityApi) method(cls u64) u64 {
	$if macos { if api.native { return u64(C.class_getInstanceMethod(voidptr(cls), voidptr(api.selector(c'isEqual:')))) } }
	return objc_instance_method(cls, api.selector(c'isEqual:'))
}
fn (api IdentityApi) implementation(method u64) u64 {
	$if macos { if api.native { return u64(C.method_getImplementation(voidptr(method))) } }
	return objc_method_imp(method)
}
fn (api IdentityApi) encoding(method u64) string {
	$if macos { if api.native { return ctext(u64(C.method_getTypeEncoding(voidptr(method)))) } }
	return ctext(u64(objc_method_types(method)))
}
fn (api IdentityApi) replace(method u64, imp u64) u64 {
	$if macos { if api.native { return u64(C.method_setImplementation(voidptr(method), voidptr(imp))) } }
	return objc_method_set_imp(method, imp)
}
fn (api IdentityApi) class(name &char) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name)) } }
	return ios_runtime.names[ctext(u64(name))]
}
fn (api IdentityApi) subclass(parent u64, name &char, imp u64) u64 {
	$if macos { if api.native {
		cls := u64(C.objc_allocateClassPair(voidptr(parent), name, 0)); assert cls != 0
		if imp != 0 { assert C.class_addMethod(voidptr(cls), voidptr(api.selector(c'isEqual:')), voidptr(imp), c'B24@0:8@16') }
		C.objc_registerClassPair(voidptr(cls)); return cls
	} }
	cls := objc_allocate_class(parent, name, 0); assert cls != 0
	if imp != 0 { assert objc_add_method(cls, api.selector(c'isEqual:'), imp, c'B24@0:8@16') }
	objc_register_class(cls); return cls
}
fn identity_direct(api IdentityApi, imp u64, left u64, right u64) bool {
	return unsafe { IdentityCompare(voidptr(imp))(left, api.selector(c'isEqual:'), right) }
}

fn identity_shared(api IdentityApi) {
	pool := if api.native { api.message(api.class(c'NSAutoreleasePool'), c'new', 0) } else { objc_pool_push() }
	base := api.subclass(api.root, c'VinixIdentityBase', 0)
	child := api.subclass(base, c'VinixIdentityChild', 0)
	a := api.message(child, c'new', 0); b := api.message(child, c'new', 0)
	assert a != 0 && b != 0 && a != b
	method := api.method(api.root); assert method != 0 && api.method(child) == method
	encoding := api.encoding(method)
	assert encoding == 'B24@0:8@16', encoding
	imp := api.implementation(method); assert imp != 0
	assert api.message(a, c'respondsToSelector:', api.selector(c'isEqual:')) == 1
	for _ in 0 .. 64 {
		assert api.equal(a, a) && !api.equal(a, b) && !api.equal(a, 0) && !api.equal(0, a)
		assert identity_direct(api, imp, a, a) && !identity_direct(api, imp, a, b)
	}
	assert api.equal(base, base) && !api.equal(base, child) && !api.equal(base, 0)
	assert api.message(base, c'respondsToSelector:', api.selector(c'isEqual:')) == 1

	// NSObject's saved IMP uses pointers even on a subclass with value data.
	text := c'long equal string with independent allocations, longer than a native tagged string'
	left := api.message(api.class(c'NSString'), c'stringWithUTF8String:', u64(text))
	right := api.message(api.class(c'NSString'), c'stringWithUTF8String:', u64(text))
	assert left != right && !identity_direct(api, imp, left, right)
	assert identity_direct(api, imp, left, left)
	if !api.native { assert object_equal(left, right) }
	n1 := api.message(api.class(c'NSNumber'), c'numberWithInteger:', 1)
	n2 := api.message(api.class(c'NSNumber'), c'numberWithInteger:', 2)
	assert api.equal(n1, n1) && !api.equal(n1, n2)

	override := u64(unsafe { voidptr(identity_override) })
	custom := api.subclass(base, c'VinixIdentityOverride', override)
	inherited := api.subclass(custom, c'VinixIdentityOverrideChild', 0)
	c := api.message(inherited, c'new', 0)
	assert !api.equal(c, c) && api.equal(c, a) && !api.equal(c, 0)
	assert api.method(custom) == api.method(inherited) && api.method(custom) != method
	assert identity_direct(api, imp, c, c) && !identity_direct(api, imp, c, a)
	assert api.implementation(api.method(custom)) == override

	// Objective-C super sends start at the declared parent, not the receiver.
	identity_super_entry = if api.native { u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSendSuper2')) } else { u64(unsafe { voidptr(C.ios_objc_super) }) }
	identity_super_class = api.subclass(base, c'VinixIdentitySuper', u64(unsafe { voidptr(identity_super_override) }))
	d := api.message(identity_super_class, c'new', 0)
	assert api.equal(d, d) && !api.equal(d, a)

	// Replacement changes inherited messages without changing saved IMPs or
	// overriding a more specific built-in NSNumber implementation.
	assert api.replace(method, override) == imp
	assert !api.equal(a, a) && api.equal(a, b)
	assert !api.equal(n1, n2) && api.equal(n1, n1)
	assert identity_direct(api, imp, a, a) && !identity_direct(api, imp, a, b)
	assert api.replace(method, imp) == override
	assert api.equal(a, a) && !api.equal(a, b)
	for object in [a, b, c, d]! { api.message(object, c'release', 0) }
	if api.native { api.message(pool, c'drain', 0) } else { objc_pool_pop(pool) }
}

fn test_ns_object_equality_native() {
	$if macos {
		identity_shared(IdentityApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend')), root: u64(C.objc_getClass(c'NSObject'))})
		println('IOS-OBJECT-EQUALITY-NATIVE: identity, metadata, inheritance, overrides, saved IMPs, super sends and replacement PASS')
	}
}
fn identity_worker(cls u64, selector u64) {
	for _ in 0 .. 128 {
		a := objc_new(cls); b := objc_new(cls)
		method := objc_instance_method(cls, selector)
		assert method != 0
		imp := objc_method_imp(method)
		assert unsafe { IdentityCompare(voidptr(imp))(a, selector, a) }
		assert !unsafe { IdentityCompare(voidptr(imp))(a, selector, b) }
		objc_release(a); objc_release(b)
	}
}
fn test_ns_object_equality_runtime() {
	for _ in 0 .. 2 {
		objc_start()
		identity_shared(IdentityApi{send: u64(unsafe { voidptr(C.ios_objc_msgsend) }), root: ios_runtime.names['NSObject']})
		cls := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixIdentityConcurrent', 0); objc_register_class(cls)
		selector := objc_selector(c'isEqual:'); mut jobs := []thread{}
		for _ in 0 .. 8 { jobs << spawn identity_worker(cls, selector) }
		jobs.wait()
		for name in ['NSString', 'NSArray', 'NSDictionary', 'NSData', 'NSIndexPath', 'NSURLSessionConfiguration', 'NSProxy', '_TtCs12_SwiftObject']! {
			assert objc_instance_method(ios_runtime.names[name], selector) == 0, name
		}
		assert ios_runtime.live == 0; objc_stop()
	}
	println('IOS-OBJECT-EQUALITY: shared native cases, eight workers, two drained runtimes and unsupported value/root guards PASS')
}
