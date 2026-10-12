// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#flag -framework WebKit
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
type ViewSend = fn (u64, u64, u64, u64) u64
type ViewRectInit = fn (u64, u64, ObjRect, u64) u64
type ViewRectGet = fn (u64, u64) ObjRect
type ViewDoubleGet = fn (u64, u64) f64
type ViewDoubleSet = fn (u64, u64, f64)

struct ViewApi {
	native bool
	send u64
	view u64
	configuration u64
	string_class u64
	root_class u64
}
fn (api ViewApi) selector(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api ViewApi) message(object u64, name &char, a u64, b u64) u64 {
	return unsafe { ViewSend(voidptr(api.send))(object, api.selector(name), a, b) }
}
fn (api ViewApi) initialize(object u64, name &char, rect ObjRect, configuration u64) u64 {
	return unsafe { ViewRectInit(voidptr(api.send))(object, api.selector(name), rect, configuration) }
}
fn (api ViewApi) rect(object u64) ObjRect { return unsafe { ViewRectGet(voidptr(api.send))(object, api.selector(c'frame')) } }
fn (api ViewApi) number(object u64, selector &char) f64 { return unsafe { ViewDoubleGet(voidptr(api.send))(object, api.selector(selector)) } }
fn (api ViewApi) set_number(object u64, selector &char, value f64) { unsafe { ViewDoubleSet(voidptr(api.send))(object, api.selector(selector), value) } }
fn (api ViewApi) string_value(value &char) u64 { return api.message(api.string_class, c'stringWithUTF8String:', u64(value), 0) }
fn (api ViewApi) text(object u64) string { assert object != 0; return ctext(api.message(object, c'UTF8String', 0, 0)) }
fn (api ViewApi) release(object u64) { api.message(object, c'release', 0, 0) }
fn (api ViewApi) retain(object u64) u64 { return api.message(object, c'retain', 0, 0) }
fn (api ViewApi) pool() u64 {
	$if macos { if api.native { return api.message(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0, 0) } }
	return objc_pool_push()
}
fn (api ViewApi) drain(pool u64) {
	$if macos { if api.native { api.release(pool); return } }
	objc_pool_pop(pool)
}

fn webview_cases(api ViewApi) {
	pool := api.pool()
	config := api.message(api.configuration, c'new', 0, 0)
	api.message(config, c'setSuppressesIncrementalRendering:', 1, 0)
	view := api.initialize(api.message(api.view, c'alloc', 0, 0), c'initWithFrame:configuration:', ObjRect{1, 2, 320, 240}, config)
	assert view != 0
	assert api.rect(view) == ObjRect{1, 2, 320, 240}
	api.message(config, c'setSuppressesIncrementalRendering:', 0, 0)
	first := api.message(view, c'configuration', 0, 0)
	second := api.message(view, c'configuration', 0, 0)
	assert first != config && second != config && first != second
	assert api.message(first, c'suppressesIncrementalRendering', 0, 0) == 1
	api.message(first, c'setSuppressesIncrementalRendering:', 0, 0)
	assert api.message(api.message(view, c'configuration', 0, 0), c'suppressesIncrementalRendering', 0, 0) == 1
	assert api.message(first, c'userContentController', 0, 0) == api.message(config, c'userContentController', 0, 0)
	assert api.message(view, c'navigationDelegate', 0, 0) == 0 && api.message(view, c'UIDelegate', 0, 0) == 0
	assert api.text(api.message(view, c'customUserAgent', 0, 0)) == ''
	assert api.text(api.message(view, c'title', 0, 0)) == ''
	assert api.message(view, c'URL', 0, 0) == 0
	for selector in [c'isLoading', c'hasOnlySecureContent', c'canGoBack', c'canGoForward', c'allowsBackForwardNavigationGestures']! {
		assert api.message(view, selector, 0, 0) == 0
	}
	assert api.message(view, c'allowsLinkPreview', 0, 0) == 1
	assert api.number(view, c'pageZoom') == 1 && api.number(view, c'estimatedProgress') == 0
	api.set_number(view, c'setPageZoom:', 1.5)
	assert api.number(view, c'pageZoom') == 1.5
	api.message(view, c'setAllowsLinkPreview:', 0, 0)
	api.message(view, c'setAllowsBackForwardNavigationGestures:', 1, 0)
	assert api.message(view, c'allowsLinkPreview', 0, 0) == 0 && api.message(view, c'allowsBackForwardNavigationGestures', 0, 0) == 1
	api.message(view, c'setCustomUserAgent:', api.string_value(c'fixture-agent'), 0)
	assert api.text(api.message(view, c'customUserAgent', 0, 0)) == 'fixture-agent'
	api.message(view, c'setCustomUserAgent:', 0, 0)
	assert api.text(api.message(view, c'customUserAgent', 0, 0)) == ''
	delegate := api.message(api.root_class, c'new', 0, 0)
	weak_pool := api.pool()
	api.message(view, c'setNavigationDelegate:', delegate, 0)
	api.message(view, c'setUIDelegate:', delegate, 0)
	assert api.message(view, c'navigationDelegate', 0, 0) == delegate && api.message(view, c'UIDelegate', 0, 0) == delegate
	api.drain(weak_pool)
	api.release(delegate)
	assert api.message(view, c'navigationDelegate', 0, 0) == 0 && api.message(view, c'UIDelegate', 0, 0) == 0
	history := api.retain(api.message(view, c'backForwardList', 0, 0))
	assert history == api.message(view, c'backForwardList', 0, 0)
	for selector in [c'backItem', c'currentItem', c'forwardItem']! { assert api.message(history, selector, 0, 0) == 0 }
	for index in [u64(0), 1, u64(-1)]! { assert api.message(history, c'itemAtIndex:', index, 0) == 0 }
	for selector in [c'backList', c'forwardList']! { assert api.message(api.message(history, selector, 0, 0), c'count', 0, 0) == 0 }
	for selector in [c'goBack', c'goForward']! { assert api.message(view, selector, 0, 0) == 0 }
	api.release(view)
	api.release(config)
	assert api.message(api.message(history, c'backList', 0, 0), c'count', 0, 0) == 0
	api.release(history)
	default_view := api.initialize(api.message(api.view, c'alloc', 0, 0), c'initWithFrame:', ObjRect{0, 0, 40, 50}, 0)
	assert api.rect(default_view) == ObjRect{0, 0, 40, 50}
	assert api.message(default_view, c'configuration', 0, 0) != 0
	api.release(default_view)
	api.drain(pool)
}

fn test_webview_native_blank_properties() {
	$if macos {
		api := ViewApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend')),
			view: u64(C.objc_getClass(c'WKWebView')), configuration: u64(C.objc_getClass(c'WKWebViewConfiguration')),
			string_class: u64(C.objc_getClass(c'NSString')), root_class: u64(C.objc_getClass(c'NSObject'))}
		webview_cases(api)
		pool := api.pool()
		view := api.message(api.view, c'new', 0, 0)
		mutable := api.message(u64(C.objc_getClass(c'NSMutableString')), c'stringWithUTF8String:', u64(c'original-agent'), 0)
		api.message(view, c'setCustomUserAgent:', mutable, 0)
		api.message(mutable, c'appendString:', api.string_value(c'-changed'), 0)
		assert api.text(api.message(view, c'customUserAgent', 0, 0)) == 'original-agent'
		api.release(view)
		api.drain(pool)
		println('IOS-WEBVIEW-NATIVE: blank frame, fresh configuration copies, shared dependencies, copied agent, zeroing delegates, FP properties and retained empty history passed')
	}
}

fn test_webview_runtime_ownership() {
	for _ in 0 .. 2 {
		objc_start()
		api := ViewApi{send: u64(unsafe { voidptr(C.ios_objc_builtin) }), view: ios_runtime.names['WKWebView'],
			configuration: ios_runtime.names['WKWebViewConfiguration'], string_class: ios_runtime.names['NSString'], root_class: ios_runtime.names['NSObject']}
		assert objc_class_parent(api.view) == ios_runtime.names['UIView'] && objc_class_size(api.view) == 1992
		assert objc_class_size(ios_runtime.names['WKBackForwardList']) == 88
		assert objc_ivar_offset(objc_find_ivar(api.view, c'_configuration')) == 408
		assert ctext(u64(objc_method_types(objc_instance_method(api.view, u64(c'initWithFrame:configuration:'))))) == '@56@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16@48'
		assert runtime_symbol('/System/Library/Frameworks/WebKit.framework/WebKit', '_OBJC_CLASS_$_WKWebView') or { panic(err) } == api.view
		webview_cases(api)
		assert ios_runtime.live == 1
		for _ in 0 .. 100 {
			pool := api.pool()
			view := objc_new(api.view)
			delegate := objc_new(api.root_class)
			api.message(view, c'setNavigationDelegate:', delegate, 0)
			api.message(view, c'setUIDelegate:', delegate, 0)
			agent := owned_string('mutable-agent')
			api.message(view, c'setCustomUserAgent:', agent, 0)
			unsafe { obj_header(agent).text[0] = char(`z`) }
			assert api.text(api.message(view, c'customUserAgent', 0, 0)) == 'mutable-agent'
			objc_release(agent)
			api.message(view, c'setCustomUserAgent:', api.message(view, c'customUserAgent', 0, 0), 0)
			api.retain(api.message(view, c'backForwardList', 0, 0))
			history := api.message(view, c'backForwardList', 0, 0)
			api.message(view, c'configuration', 0, 0)
			objc_set_class(view, api.root_class)
			objc_release(view)
			objc_release(delegate) // Removed weak slots must not point into freed state.
			assert api.message(api.message(history, c'forwardList', 0, 0), c'count', 0, 0) == 0
			objc_set_class(history, api.root_class)
			objc_release(history)
			api.drain(pool)
			assert ios_runtime.live == 1 && ios_runtime.weak.len == 0
		}
		storage := u64(C.calloc(1, 1992))
		assert objc_construct_instance(api.view, storage) == storage
		assert api.initialize(storage, c'initWithFrame:', ObjRect{0, 0, 80, 60}, 0) == storage
		assert read64(storage + 408) != 0
		assert objc_destruct_instance(storage) == storage && read64(storage + 408) == 0
		C.free(unsafe { voidptr(storage) })
		assert ios_runtime.live == 1
		view := objc_new(api.view)
		for selector in [c'loadRequest:', c'loadHTMLString:baseURL:', c'evaluateJavaScript:completionHandler:', c'reload', c'_apiObject', c'initWithCoder:']! {
			assert !objc_responds(view, selector) && objc_instance_method(api.view, u64(selector)) == 0
		}
		objc_release(view)
		webkit_stop()
		assert ios_runtime.live == 0
		objc_stop()
	}
	println('IOS-WEBVIEW: shared blank-view fixtures, Catalyst record/reference-slot metadata, zeroing weak and copied values, 100 isa-change releases and caller storage passed')
}

fn test_webview_profile_rejections() {
	objc_start()
	api := ViewApi{send: u64(unsafe { voidptr(C.ios_objc_builtin) }), view: ios_runtime.names['WKWebView'], root_class: ios_runtime.names['NSObject']}
	wrong := objc_new(ios_runtime.names['NSNumber'])
	for operation in 0 .. 7 {
		mut descriptors := [2]i32{}
		assert C.pipe(unsafe { &descriptors[0] }) == 0
		pid := C.ios_fork()
		assert pid >= 0
		if pid == 0 {
			C.close(descriptors[0]); assert C.dup2(descriptors[1], 2) == 2; C.close(descriptors[1])
			view := objc_allocate(api.view)
			match operation {
				0 { api.initialize(view, c'initWithFrame:configuration:', ObjRect{}, wrong) }
				1 { api.initialize(view, c'initWithFrame:configuration:', ObjRect{}, 0) }
				else {
					api.message(view, c'init', 0, 0)
					match operation {
						2 { api.message(view, c'setCustomUserAgent:', wrong, 0) }
						3 { api.set_number(view, c'setPageZoom:', 0) }
						4 { api.message(view, c'loadRequest:', 0, 0) }
						5 { api.message(view, c'_apiObject', 0, 0) }
						else {
							history := api.message(view, c'backForwardList', 0, 0)
							api.message(api.message(history, c'backList', 0, 0), c'addObject:', wrong, 0)
						}
					}
				}
			}
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
		assert output.contains(['WebKit view requires an initialized configuration', 'WebKit view configuration must not be nil',
			'WebKit user agent must be a string', 'WebKit page zoom must be positive and finite',
			'unimplemented Objective-C method WKWebView loadRequest:', 'unimplemented Objective-C method WKWebView _apiObject',
			'mutation of a read-only WebKit history array']![operation]), output
		assert !output.contains('AddressSanitizer') && !output.contains('runtime error:')
	}
	objc_release(wrong)
	webkit_stop()
	assert ios_runtime.live == 0
	objc_stop()
	println('IOS-WEBVIEW-REJECT: invalid/nil configuration, wrong agent, invalid zoom, unavailable navigation/private engine and history mutation fail explicitly')
}
