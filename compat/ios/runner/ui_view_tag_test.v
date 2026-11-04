// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math

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
fn C.objc_allocateClassPair(voidptr, &char, usize) voidptr
fn C.objc_registerClassPair(voidptr)
fn C.dlopen(&char, int) voidptr
fn C.dlsym(voidptr, &char) voidptr

type ViewTagSend = fn (u64, u64, u64) u64
type ViewClearGet = fn (u64, u64) bool
type ViewClearSet = fn (u64, u64, bool)
type ScreenRectGet = fn (u64, u64) ObjRect
type ScreenScaleGet = fn (u64, u64) f64
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

fn view_clear_cases(api ViewTagApi, cls u64) {
	first := api.view(cls); second := api.view(cls)
	get := api.selector(c'clearsContextBeforeDrawing')
	set := api.selector(c'setClearsContextBeforeDrawing:')
	assert u8(api.message(first, c'clearsContextBeforeDrawing', 0)) == 1;
	assert u8(api.message(second, c'clearsContextBeforeDrawing', 0)) == 1;
	// Darwin's BOOL argument occupies w2: only bits above that slot are padding.
	for value in [u64(0), 1, u64(1) << 32, (u64(1) << 32) | 1, u64(0xffffffff) << 32, (u64(0xffffffff) << 32) | 1]! {
		api.message(first, c'setClearsContextBeforeDrawing:', value)
		assert u8(api.message(first, c'clearsContextBeforeDrawing', 0)) == u8(value);
		assert u8(api.message(second, c'clearsContextBeforeDrawing', 0)) == 1;
	}
	api.message(first, c'setClearsContextBeforeDrawing:', 0)
	api.message(second, c'addSubview:', first)
	assert u8(api.message(first, c'clearsContextBeforeDrawing', 0)) == 0;
	api.message(first, c'removeFromSuperview', 0)
	for i, selector in [get, set]! {
		assert api.message(first, c'respondsToSelector:', selector) == 1;
		assert api.message(cls, c'respondsToSelector:', selector) == 0;
		mut types := ''; mut imp := u64(0)
		$if macos { if api.native {
			method := C.class_getInstanceMethod(voidptr(cls), voidptr(selector))
			assert method != unsafe { nil };
			types = ctext(u64(C.method_getTypeEncoding(method))); imp = u64(C.method_getImplementation(method))
		} }
		if !api.native {
			method := objc_instance_method(cls, selector)
			assert method != 0 && objc_instance_method(read64(cls), selector) == 0;
			types = ctext(u64(objc_method_types(method))); imp = objc_method_imp(method)
		}
		assert types == if i == 0 { 'B16@0:8' } else { 'v20@0:8B16' };
		assert imp != 0;
		signature := api.message(first, c'methodSignatureForSelector:', selector)
		assert signature != 0;
		assert api.message(signature, c'numberOfArguments', 0) == if i == 0 { u64(2) } else { u64(3) };
		assert api.message(signature, c'methodReturnLength', 0) == if i == 0 { u64(1) } else { u64(0) };
		assert ctext(api.message(signature, c'methodReturnType', 0)) == if i == 0 { 'B' } else { 'v' };
		if i == 0 { assert !unsafe { ViewClearGet(voidptr(imp))(first, selector) }; }
		else {
			assert ctext(api.message(signature, c'getArgumentTypeAtIndex:', 2)) == 'B';
			unsafe { ViewClearSet(voidptr(imp))(first, selector, true) }
			assert u8(api.message(first, c'clearsContextBeforeDrawing', 0)) == 1;
		}
	}
	api.message(first, c'release', 0); api.message(second, c'release', 0)
}

fn screen_geometry_cases(api ViewTagApi, cls u64) u64 {
	screen := api.message(cls, c'mainScreen', 0)
	assert screen != 0 && api.message(cls, c'mainScreen', 0) == screen;
	mut native_rect := ObjRect{}
	for index, name in [c'bounds', c'nativeBounds', c'scale', c'nativeScale']! {
		selector := api.selector(name)
		assert api.message(screen, c'respondsToSelector:', selector) == 1;
		mut method := u64(0); mut imp := u64(0); mut types := ''
		$if macos { if api.native {
			method = u64(C.class_getInstanceMethod(unsafe { voidptr(cls) }, unsafe { voidptr(selector) }))
			assert method != 0;
			imp = u64(C.method_getImplementation(unsafe { voidptr(method) }))
			types = ctext(u64(C.method_getTypeEncoding(unsafe { voidptr(method) })))
		} }
		if !api.native {
			method = objc_instance_method(cls, selector)
			assert method != 0 && objc_instance_method(ios_runtime.names['NSObject'], selector) == 0;
			assert objc_class_method(cls, selector) == 0;
			imp = objc_method_imp(method); types = ctext(u64(objc_method_types(method)))
		}
		assert imp != 0;
		if index < 2 {
			assert types == '{CGRect={CGPoint=dd}{CGSize=dd}}16@0:8';
			// NSMethodSignature's existing runtime profile is scalar-only.
			// Verify aggregate metadata and the actual HFA call directly here.
			if api.native {
				signature := api.message(screen, c'methodSignatureForSelector:', selector)
				assert signature != 0 && api.message(signature, c'numberOfArguments', 0) == 2;
				assert api.message(signature, c'methodReturnLength', 0) == 32;
			}
			via_message := unsafe { ScreenRectGet(voidptr(api.send))(screen, selector) }
			via_imp := unsafe { ScreenRectGet(voidptr(imp))(screen, selector) }
			assert via_message == via_imp && via_imp.x == 0 && via_imp.y == 0;
			assert math.is_finite(via_imp.width) && math.is_finite(via_imp.height) && via_imp.width > 0 && via_imp.height > 0;
			if index == 1 { native_rect = via_imp }
		} else {
			assert types == 'd16@0:8';
			signature := api.message(screen, c'methodSignatureForSelector:', selector)
			assert signature != 0 && api.message(signature, c'numberOfArguments', 0) == 2;
			assert api.message(signature, c'methodReturnLength', 0) == 8;
			scale := unsafe { ScreenScaleGet(voidptr(api.send))(screen, selector) }
			assert scale == unsafe { ScreenScaleGet(voidptr(imp))(screen, selector) } && scale > 0 && math.is_finite(scale);
			if !api.native { assert scale == 1; }
		}
	}
	if !api.native { assert native_rect == ObjRect{0, 0, 390, 680}; }
	return screen
}

fn screen_geometry_runtime(api ViewTagApi) {
	cls := ios_runtime.names['UIScreen']
	screen := screen_geometry_cases(api, cls)
	subclass := objc_allocate_class(cls, c'VinixScreenGeometryFixture', 0)
	objc_register_class(subclass)
	assert screen_geometry_cases(api, subclass) == screen;
	// Raw ABI lanes: CGRect is a four-double HFA, not an indirect x8 result.
	mut guarded := [u64(0x1234), 0x5678, 0x9abc, 0xdef0, 0x4321, 0x8765]!
	mut frame := RegisterFrame{}
	frame.x[0] = screen; frame.x[1] = u64(c'nativeBounds'); frame.x[8] = u64(unsafe { &guarded[1] })
	for i in 0 .. frame.q.len { frame.q[i] = ~u64(0) }
	assert objc_dispatch(mut frame, 0) == 0;
	assert frame_double(&frame, 0) == 0 && frame_double(&frame, 1) == 0 && frame_double(&frame, 2) == 390 && frame_double(&frame, 3) == 680;
	for i in 0 .. 4 { assert frame.q[i * 2 + 1] == 0; }
	assert guarded == [u64(0x1234), 0x5678, 0x9abc, 0xdef0, 0x4321, 0x8765]!;
	window := objc_new(ios_runtime.names['UIWindow'])
	api.message(window, c'makeKeyAndVisible', 0)
	for size in [[640, 360]!, [320, 720]!, [1024, 768]!]! {
		ui_layout(size[0], size[1])
		assert obj_header(window).frame.width == f64(size[0]) && obj_header(window).frame.height == f64(size[1]);
		assert screen_geometry_cases(api, cls) == screen;
	}
	objc_release(window)
}
fn test_view_tag_native() {
	$if macos {
		assert C.dlopen(c'/System/iOSSupport/System/Library/Frameworks/UIKit.framework/UIKit', 2) != unsafe { nil }
		api := ViewTagApi{true, u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))}
		assert api.send != 0
		pool := api.message(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0)
		screen_geometry_cases(api, u64(C.objc_getClass(c'UIScreen')))
		view_tag_cases(api, u64(C.objc_getClass(c'UIView')))
		view_clear_cases(api, u64(C.objc_getClass(c'UIView')))
		clear_subclass := C.objc_allocateClassPair(C.objc_getClass(c'UIView'), c'VinixNativeClearView', 0)
		assert clear_subclass != unsafe { nil };
		C.objc_registerClassPair(clear_subclass)
		view_clear_cases(api, u64(clear_subclass))
		// UIWindow construction requires an application scene. Its inherited
		// method identity can still be checked without creating a native window.
		for name in [c'clearsContextBeforeDrawing', c'setClearsContextBeforeDrawing:']! {
			selector := C.sel_registerName(name)
			base := C.class_getInstanceMethod(C.objc_getClass(c'UIView'), selector)
			window := C.class_getInstanceMethod(C.objc_getClass(c'UIWindow'), selector)
			assert base != unsafe { nil } && window != unsafe { nil };
			assert C.method_getImplementation(base) == C.method_getImplementation(window);
		}
		api.message(pool, c'drain', 0)
		println('IOS-VIEW-TAG-NATIVE: signed tags, receiver-first depth-first lookup, scope, reparenting, deep hierarchy, metadata, signatures and direct IMP PASS')
		println('IOS-VIEW-CLEAR-NATIVE: default YES, independent state, BOOL register width, hierarchy, metadata, signatures and direct IMP PASS')
		println('IOS-SCREEN-NATIVE: CGRect/double returns, positive screen geometry, method metadata, signatures and direct IMP PASS')
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
		view_clear_cases(api, ios_runtime.names['UIView'])
		view_clear_cases(api, ios_runtime.names['UIWindow'])
		view_clear_cases(api, subclass)
		screen_geometry_runtime(api)
		objc_pool_pop(pool)
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-VIEW-TAG: shared native cases, UIWindow/subclass inheritance, borrowed ownership and two drained runtimes PASS')
	println('IOS-VIEW-CLEAR: shared native property cases, UIWindow/subclass inheritance and two drained runtimes PASS')
	println('IOS-SCREEN: fixed portrait native pixels, scale one, CGRect HFA guards, inherited metadata, window resize independence and two clean lifetimes PASS')
}
