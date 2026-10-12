// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math

// A blank UIView frontend, measured against the installed Catalyst WebKit.
// Its reserved 1992-byte record is not a browser engine. The configuration
// slot is the measured RetainPtr at 408; other private C++ bytes stay zero.
struct WebViewState {
mut:
	navigation_delegate u64 // Zeroing weak slots registered with the runtime.
	ui_delegate u64
	user_agent u64 // Optional copied string; nil uses the owned empty string.
	empty_string u64
	history u64
	page_zoom f64 = 1
	allows_navigation_gestures bool
	allows_link_preview bool = true
}

fn webview_types(name string, meta bool, selector string) ?string {
	if meta { return none }
	if name == 'WKBackForwardList' {
		return match selector {
			'backItem', 'currentItem', 'forwardItem', 'backList', 'forwardList' { '@16@0:8' }
			'itemAtIndex:' { '@24@0:8q16' }
			else { return none }
		}
	}
	if name != 'WKWebView' { return none }
	return match selector {
		'init', 'configuration', 'navigationDelegate', 'UIDelegate', 'customUserAgent', 'title', 'URL', 'backForwardList', 'goBack', 'goForward' { '@16@0:8' }
		'initWithFrame:' { '@48@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16' }
		'initWithFrame:configuration:' { '@56@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16@48' }
		'setNavigationDelegate:', 'setUIDelegate:', 'setCustomUserAgent:' { 'v24@0:8@16' }
		'pageZoom', 'estimatedProgress' { 'd16@0:8' }
		'setPageZoom:' { 'v24@0:8d16' }
		'isLoading', 'hasOnlySecureContent', 'canGoBack', 'canGoForward', 'allowsBackForwardNavigationGestures', 'allowsLinkPreview' { 'B16@0:8' }
		'setAllowsBackForwardNavigationGestures:', 'setAllowsLinkPreview:' { 'v20@0:8B16' }
		else { return none }
	}
}

fn webview_initialize(object u64, rect ObjRect, input u64) {
	mut header := obj_header(object)
	if !header.webview_owned || header.native_size < 1992 { panic('iOS: invalid WebKit view storage') }
	if header.webview != unsafe { nil } { panic('iOS: WebKit view reinitialization is not implemented') }
	if input != 0 && (!objc_is_kind(input, ios_runtime.names['WKWebViewConfiguration']) || obj_header(input).webkit == unsafe { nil }) {
		panic('iOS: WebKit view requires an initialized configuration')
	}
	if !math.is_finite(rect.x) || !math.is_finite(rect.y) || !math.is_finite(rect.width) || !math.is_finite(rect.height) {
		panic('iOS: WebKit view frame must be finite')
	}
	configuration := if input == 0 { objc_new(ios_runtime.names['WKWebViewConfiguration']) } else { webkit_copy(input, 'WKWebViewConfiguration') }
	header.webview = unsafe { &WebViewState(C.calloc(1, sizeof(WebViewState))) }
	if header.webview == unsafe { nil } { panic('iOS: cannot allocate WebKit view state') }
	header.webview.page_zoom = 1
	header.webview.allows_link_preview = true
	header.webview.empty_string = owned_string('')
	header.frame = rect
	unsafe { *(&u64(object + 408)) = configuration }
}

fn webview_dispose(object u64, mut header ObjHeader) {
	if header.webview == unsafe { nil } { return }
	objc_destroy_weak(unsafe { &header.webview.navigation_delegate })
	objc_destroy_weak(unsafe { &header.webview.ui_delegate })
	objc_release(read64(object + 408))
	unsafe { *(&u64(object + 408)) = 0 }
	objc_release(header.webview.user_agent)
	objc_release(header.webview.empty_string)
	objc_release(header.webview.history)
	C.free(header.webview)
	header.webview = unsafe { nil }
}

fn webview_history(object u64) u64 {
	mut state := obj_header(object).webview
	if state.history == 0 {
		state.history = objc_allocate(ios_runtime.names['WKBackForwardList'])
		mut history := obj_header(state.history)
		history.web_history = true
		history.fields[0] = objc_allocate(ios_runtime.names['NSArray'])
		obj_header(history.fields[0]).web_history_array = true
	}
	return state.history
}

fn webview_dispatch(object u64, name string, selector string, mut frame RegisterFrame) bool {
	if object in ios_runtime.classes { return false }
	if name == 'WKBackForwardList' {
		if selector == 'init' { panic('iOS: WebKit history requires a view') }
		if webview_types(name, false, selector) == none { return false }
		header := obj_header(object)
		if !header.web_history { panic('iOS: WebKit history is not initialized') }
		frame.x[0] = if selector in ['backList', 'forwardList'] { header.fields[0] } else { u64(0) }
		return true
	}
	if name != 'WKWebView' { return false }
	if selector in ['init', 'initWithFrame:', 'initWithFrame:configuration:'] {
		if selector == 'initWithFrame:configuration:' && frame.x[2] == 0 { panic('iOS: WebKit view configuration must not be nil') }
		rect := if selector == 'init' { ObjRect{} } else { frame_rect(frame) }
		input := if selector == 'initWithFrame:configuration:' { frame.x[2] } else { u64(0) }
		webview_initialize(object, rect, input)
		frame.x[0] = object
		return true
	}
	if webview_types(name, false, selector) == none { return false }
	mut state := obj_header(object).webview
	if state == unsafe { nil } { panic('iOS: WebKit view is not initialized') }
	match selector {
		'configuration' { frame.x[0] = objc_autorelease(webkit_copy(read64(object + 408), 'WKWebViewConfiguration')) }
		'navigationDelegate' { frame.x[0] = objc_autorelease(objc_load_weak(unsafe { &state.navigation_delegate })) }
		'UIDelegate' { frame.x[0] = objc_autorelease(objc_load_weak(unsafe { &state.ui_delegate })) }
		'setNavigationDelegate:' { objc_store_weak(unsafe { &state.navigation_delegate }, frame.x[2]) }
		'setUIDelegate:' { objc_store_weak(unsafe { &state.ui_delegate }, frame.x[2]) }
		'customUserAgent' { frame.x[0] = if state.user_agent == 0 { state.empty_string } else { state.user_agent } }
		'setCustomUserAgent:' {
			value := frame.x[2]
			if value != 0 && !objc_is_kind(value, ios_runtime.names['NSString']) { panic('iOS: WebKit user agent must be a string') }
			copied := if value == 0 { u64(0) } else { owned_string(string_text(value)) }
			objc_store_strong(unsafe { &state.user_agent }, copied)
			objc_release(copied)
		}
		'title' { frame.x[0] = state.empty_string }
		'URL', 'goBack', 'goForward', 'isLoading', 'hasOnlySecureContent', 'canGoBack', 'canGoForward' { frame.x[0] = 0 }
		'estimatedProgress' { frame_float_return(mut frame, 0, 0) }
		'pageZoom' { frame_float_return(mut frame, 0, state.page_zoom) }
		'setPageZoom:' {
			value := frame_double(frame, 0)
			if !math.is_finite(value) || value <= 0 { panic('iOS: WebKit page zoom must be positive and finite') }
			state.page_zoom = value
		}
		'allowsBackForwardNavigationGestures' { frame.x[0] = u64(state.allows_navigation_gestures) }
		'setAllowsBackForwardNavigationGestures:' { state.allows_navigation_gestures = u8(frame.x[2]) != 0 }
		'allowsLinkPreview' { frame.x[0] = u64(state.allows_link_preview) }
		'setAllowsLinkPreview:' { state.allows_link_preview = u8(frame.x[2]) != 0 }
		'backForwardList' { frame.x[0] = webview_history(object) }
		else { return false }
	}
	return true
}
