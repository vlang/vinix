// SPDX-License-Identifier: GPL-2.0-or-later
module main

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
fn C.dlopen(&char, int) voidptr
fn C.dlsym(voidptr, &char) voidptr

type ViewTagSend = fn (u64, u64, u64) u64
struct ViewTagApi { native bool send u64 }

fn (api ViewTagApi) selector(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api ViewTagApi) message(object u64, name &char, argument u64) u64 {
	return unsafe { ViewTagSend(voidptr(api.send))(object, api.selector(name), argument) }
}
fn (api ViewTagApi) view(cls u64) u64 {
	view := api.message(api.message(cls, c'alloc', 0), c'init', 0)
	assert view != 0
	assert api.message(view, c'tag', 0) == 0
	return view
}
fn view_tag_cases(api ViewTagApi, cls u64) {
	root := api.view(cls)
	first := api.view(cls)
	second := api.view(cls)
	leaf := api.view(cls)
	outside := api.view(cls)
	api.message(root, c'addSubview:', first)
	api.message(root, c'addSubview:', second)
	api.message(first, c'addSubview:', leaf)
	assert api.message(root, c'viewWithTag:', 0) == root
	assert api.message(0, c'viewWithTag:', 0) == 0
	assert api.message(root, c'viewWithTag:', 99) == 0
	for value in [i64(1), -1, i64(2147483648), i64(9223372036854775807), i64(-9223372036854775807) - 1]! {
		api.message(leaf, c'setTag:', u64(value))
		assert api.message(leaf, c'tag', 0) == u64(value)
		assert api.message(root, c'viewWithTag:', u64(value)) == leaf
		assert api.message(first, c'viewWithTag:', u64(value)) == leaf
		assert api.message(second, c'viewWithTag:', u64(value)) == 0
		api.message(second, c'setTag:', u64(value))
		assert api.message(root, c'viewWithTag:', u64(value)) == leaf
		api.message(first, c'setTag:', u64(value))
		assert api.message(root, c'viewWithTag:', u64(value)) == first
		api.message(root, c'setTag:', u64(value))
		assert api.message(root, c'viewWithTag:', u64(value)) == root
		api.message(root, c'setTag:', 0)
		api.message(first, c'setTag:', 0)
		api.message(second, c'setTag:', 0)
	}
	api.message(leaf, c'setTag:', 42)
	api.message(leaf, c'removeFromSuperview', 0)
	assert api.message(root, c'viewWithTag:', 42) == 0
	api.message(outside, c'addSubview:', leaf)
	assert api.message(outside, c'viewWithTag:', 42) == leaf
	api.message(second, c'addSubview:', leaf)
	assert api.message(outside, c'viewWithTag:', 42) == 0
	assert api.message(root, c'viewWithTag:', 42) == leaf
	api.message(root, c'setTag:', 43)
	assert api.message(leaf, c'viewWithTag:', 43) == 0
	api.message(leaf, c'setTag:', 0)
	mut deepest := second
	for _ in 0 .. 192 {
		child := api.view(cls)
		api.message(deepest, c'addSubview:', child)
		api.message(child, c'release', 0)
		deepest = child
	}
	api.message(deepest, c'setTag:', 44)
	for _ in 0 .. 256 {
		assert api.message(root, c'viewWithTag:', 44) == deepest
		assert api.message(root, c'viewWithTag:', 45) == 0
	}
	for index, name in [c'viewWithTag:', c'tag', c'setTag:']! {
		selector := api.selector(name)
		assert api.message(root, c'respondsToSelector:', selector) == 1
		assert api.message(cls, c'respondsToSelector:', selector) == 0
		expected := ['@24@0:8q16', 'q16@0:8', 'v24@0:8q16']![index]
		mut imp := u64(0)
		$if macos { if api.native {
			method := C.class_getInstanceMethod(voidptr(cls), voidptr(selector))
			assert method != unsafe { nil }
			assert unsafe { C.method_getTypeEncoding(method).vstring() } == expected
			imp = u64(C.method_getImplementation(method))
		} }
		if !api.native {
			method := objc_instance_method(cls, selector)
			assert method != 0 && ctext(u64(objc_method_types(method))) == expected
			assert objc_instance_method(read64(cls), selector) == 0
			imp = objc_method_imp(method)
		}
		assert imp != 0
		signature := api.message(root, c'methodSignatureForSelector:', selector)
		assert signature != 0
		assert api.message(signature, c'numberOfArguments', 0) == if index == 1 { u64(2) } else { u64(3) }
		assert api.message(signature, c'methodReturnLength', 0) == if index == 2 { u64(0) } else { u64(8) }
		assert ctext(api.message(signature, c'methodReturnType', 0)) == ['@', 'q', 'v']![index]
		if index != 1 { assert ctext(api.message(signature, c'getArgumentTypeAtIndex:', 2)) == 'q' }
		result := unsafe { ViewTagSend(voidptr(imp))(root, selector, 44) }
		if index == 0 { assert result == deepest }
		if index == 1 { assert result == 43 }
		if index == 2 { assert api.message(root, c'tag', 0) == 44 }
	}
	for view in [outside, leaf, second, first, root]! { api.message(view, c'release', 0) }
}
fn test_view_tag_native() {
	$if macos {
		assert C.dlopen(c'/System/iOSSupport/System/Library/Frameworks/UIKit.framework/UIKit', 2) != unsafe { nil }
		api := ViewTagApi{true, u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))}
		assert api.send != 0
		pool := api.message(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0)
		view_tag_cases(api, u64(C.objc_getClass(c'UIView')))
		api.message(pool, c'drain', 0)
		println('IOS-VIEW-TAG-NATIVE: signed tags, receiver-first depth-first lookup, scope, reparenting, deep hierarchy, metadata, signatures and direct IMP PASS')
	}
}
fn test_view_tag_runtime() {
	for _ in 0 .. 2 {
		objc_start()
		pool := objc_pool_push()
		api := ViewTagApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })}
		view_tag_cases(api, ios_runtime.names['UIView'])
		view_tag_cases(api, ios_runtime.names['UIWindow'])
		subclass := objc_allocate_class(ios_runtime.names['UIView'], c'VinixTaggedView', 0)
		objc_register_class(subclass)
		view_tag_cases(api, subclass)
		objc_pool_pop(pool)
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-VIEW-TAG: shared native cases, UIWindow/subclass inheritance, borrowed ownership and two drained runtimes PASS')
}
