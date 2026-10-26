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

type ResponderSend = fn (u64, u64, u64) u64
struct ResponderApi { native bool send u64 }

fn (api ResponderApi) selector(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api ResponderApi) message(object u64, name &char, argument u64) u64 {
	return unsafe { ResponderSend(voidptr(api.send))(object, api.selector(name), argument) }
}
fn (api ResponderApi) new(cls u64) u64 {
	object := api.message(api.message(cls, c'alloc', 0), c'init', 0)
	assert object != 0
	return object
}
fn responder_metadata(api ResponderApi, cls u64, object u64, expected u64) {
	selector := api.selector(c'nextResponder')
	assert api.message(object, c'respondsToSelector:', selector) == 1
	assert api.message(cls, c'respondsToSelector:', selector) == 0
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
		imp = objc_method_imp(method)
	}
	assert imp != 0
	signature := api.message(object, c'methodSignatureForSelector:', selector)
	assert signature != 0
	assert api.message(signature, c'numberOfArguments', 0) == 2
	assert api.message(signature, c'methodReturnLength', 0) == 8
	assert ctext(api.message(signature, c'methodReturnType', 0)) == '@'
	assert unsafe { ResponderSend(voidptr(imp))(object, selector, 0) } == expected
}
fn responder_cases(api ResponderApi, view_cls u64, controller_cls u64, responder_cls u64) {
	mut pool := u64(0)
	$if macos { if api.native { pool = api.message(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0) } }
	if !api.native { pool = objc_pool_push() }
	responder := api.new(responder_cls)
	assert api.message(responder, c'nextResponder', 0) == 0
	assert api.message(0, c'nextResponder', 0) == 0
	responder_metadata(api, responder_cls, responder, 0)
	parent := api.new(view_cls)
	other := api.new(view_cls)
	child := api.new(view_cls)
	assert api.message(child, c'nextResponder', 0) == 0
	api.message(parent, c'addSubview:', child)
	assert api.message(child, c'nextResponder', 0) == parent
	responder_metadata(api, view_cls, child, parent)
	api.message(other, c'addSubview:', child)
	assert api.message(child, c'nextResponder', 0) == other
	api.message(child, c'removeFromSuperview', 0)
	assert api.message(child, c'nextResponder', 0) == 0
	controller := api.new(controller_cls)
	assert api.message(controller, c'nextResponder', 0) == 0
	view := api.message(controller, c'view', 0)
	assert view != 0 && api.message(view, c'nextResponder', 0) == controller
	assert api.message(controller, c'nextResponder', 0) == 0
	api.message(parent, c'addSubview:', view)
	api.message(view, c'addSubview:', child)
	assert api.message(child, c'nextResponder', 0) == view
	assert api.message(view, c'nextResponder', 0) == controller
	assert api.message(controller, c'nextResponder', 0) == parent
	responder_metadata(api, controller_cls, controller, parent)
	api.message(view, c'retain', 0)
	api.message(controller, c'setView:', view)
	assert api.message(controller, c'nextResponder', 0) == parent
	assert api.message(view, c'nextResponder', 0) == controller
	api.message(controller, c'setView:', other)
	assert api.message(view, c'nextResponder', 0) == 0
	assert api.message(other, c'nextResponder', 0) == controller
	api.message(parent, c'addSubview:', other)
	assert api.message(controller, c'nextResponder', 0) == parent
	api.message(controller, c'setView:', 0)
	assert api.message(other, c'nextResponder', 0) == 0
	assert api.message(controller, c'nextResponder', 0) == 0
	api.message(controller, c'setView:', other)
	api.message(parent, c'addSubview:', other)
	api.message(controller, c'release', 0)
	// UIKit can defer controller destruction until the autorelease pool drains.
	if api.native { api.message(pool, c'drain', 0) } else { objc_pool_pop(pool) }
	$if macos { if api.native { pool = api.message(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0) } }
	assert api.message(other, c'nextResponder', 0) == parent
	api.message(parent, c'release', 0)
	// Reading nextResponder can itself autorelease a retained parent in UIKit.
	if api.native { api.message(pool, c'drain', 0) }
	assert api.message(other, c'nextResponder', 0) == 0
	assert api.message(view, c'nextResponder', 0) == 0
	assert api.message(child, c'nextResponder', 0) == view
	for object in [view, other, child, responder]! { api.message(object, c'release', 0) }
}
fn responder_application(api ResponderApi, app u64, window_cls u64, responder_cls u64, object_cls u64) {
	// Isolate native selector dispatch: UIWindow.init requires Catalyst app startup.
	window := if api.native { api.message(window_cls, c'alloc', 0) } else { api.new(window_cls) }
	// The native oracle runs without UIApplicationMain; sharedApplication can be nil.
	assert api.message(window, c'nextResponder', 0) == api.message(api.message(app, c'class', 0), c'sharedApplication', 0)
	responder_metadata(api, window_cls, window, api.message(window, c'nextResponder', 0))
	assert api.message(app, c'nextResponder', 0) == 0
	delegate := api.new(responder_cls)
	api.message(app, c'setDelegate:', delegate)
	assert api.message(app, c'nextResponder', 0) == delegate
	plain := api.new(object_cls)
	api.message(app, c'setDelegate:', plain)
	assert api.message(app, c'nextResponder', 0) == 0
	api.message(app, c'setDelegate:', 0)
	for object in [delegate, plain]! { api.message(object, c'release', 0) }
	if !api.native { api.message(window, c'release', 0) }
}
fn test_responder_native() {
	$if macos {
		assert C.dlopen(c'/System/iOSSupport/System/Library/Frameworks/UIKit.framework/UIKit', 2) != unsafe { nil }
		api := ResponderApi{true, u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))}
		assert api.send != 0
		pool := api.message(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0)
		responder_cases(api, u64(C.objc_getClass(c'UIView')), u64(C.objc_getClass(c'UIViewController')), u64(C.objc_getClass(c'UIResponder')))
		// Isolated UIApplication allocation, as in the badge oracle, without app startup.
		app := api.message(u64(C.objc_getClass(c'UIApplication')), c'alloc', 0)
		responder_application(api, app, u64(C.objc_getClass(c'UIWindow')), u64(C.objc_getClass(c'UIResponder')), u64(C.objc_getClass(c'NSObject')))
		api.message(pool, c'drain', 0)
		println('IOS-RESPONDER-NATIVE: view/controller chains, replacement, detached lifetimes, window/application delegates, metadata, signatures and direct IMP PASS')
	}
}
fn test_responder_runtime() {
	for _ in 0 .. 2 {
		objc_start()
		pool := objc_pool_push()
		api := ResponderApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })}
		responder_cases(api, ios_runtime.names['UIView'], ios_runtime.names['UIViewController'], ios_runtime.names['UIResponder'])
		subclass := objc_allocate_class(ios_runtime.names['UIView'], c'VinixResponderView', 0)
		objc_register_class(subclass)
		controller_subclass := objc_allocate_class(ios_runtime.names['UIViewController'], c'VinixResponderController', 0)
		objc_register_class(controller_subclass)
		responder_cases(api, subclass, controller_subclass, ios_runtime.names['UIResponder'])
		ios_runtime.application = objc_allocate(ios_runtime.names['UIApplication'])
		responder_application(api, ios_runtime.application, ios_runtime.names['UIWindow'], ios_runtime.names['UIResponder'], ios_runtime.names['NSObject'])
		responder_window_storyboard(api)
		objc_pool_pop(pool)
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-RESPONDER: shared native cases, subclass inheritance, zeroing weak ownership and two drained runtimes PASS')
}

fn responder_window_storyboard(api ResponderApi) {
	// Exercise both controller-view creation paths and active-window ownership.
	root := storyboard_parse('<document><viewController id="root"><view><subviews><view/></subviews></view></viewController></document>') or { panic(err) }
	controller := storyboard_controller(root, 'id', 'root') or { panic(err) }
	storyboard_node_free(root)
	view := api.message(controller, c'view', 0)
	assert api.message(view, c'nextResponder', 0) == controller
	child := obj_header(view).children[0]
	assert api.message(child, c'nextResponder', 0) == view
	window := api.new(ios_runtime.names['UIWindow'])
	api.message(window, c'setRootViewController:', controller)
	api.message(window, c'makeKeyAndVisible', 0)
	assert api.message(controller, c'nextResponder', 0) == window
	assert api.message(window, c'nextResponder', 0) == ios_runtime.application
	api.message(view, c'retain', 0)
	second := api.new(ios_runtime.names['UIViewController'])
	api.message(window, c'setRootViewController:', second)
	assert api.message(controller, c'nextResponder', 0) == 0
	assert api.message(view, c'nextResponder', 0) == controller
	api.message(controller, c'release', 0)
	assert api.message(view, c'nextResponder', 0) == 0
	assert api.message(child, c'nextResponder', 0) == view
	api.message(view, c'release', 0)
	second_view := api.message(second, c'view', 0)
	assert api.message(second_view, c'nextResponder', 0) == second
	assert api.message(second, c'nextResponder', 0) == window
	api.message(window, c'setRootViewController:', 0)
	assert api.message(second, c'nextResponder', 0) == 0
	api.message(second, c'release', 0)
	api.message(window, c'release', 0)
}
