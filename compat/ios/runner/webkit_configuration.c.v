// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Public configuration state measured against the installed macOS WebKit.
// The native inline C++ records are reserved, zero-filled bytes, not WebKit
// engine objects. Private API/C++ access, navigation and script execution are
// outside this profile and never advertised as implemented.
struct WebKitState {
mut:
	refs [6]u64 // Five configuration dependencies and the copied user-agent name.
	flags [8]bool
	values [3]u64
	minimum_font_size f64
}

fn webkit_name(name string) bool {
	return name in ['WKWebViewConfiguration', 'WKPreferences', 'WKUserContentController',
		'WKProcessPool', 'WKWebsiteDataStore', 'WKWebpagePreferences', 'WKUserScript', 'WKContentWorld', 'WKNSArray', 'WKWebView', 'WKBackForwardList']
}

fn webkit_size(name string) u32 {
	return match name {
		'WKWebViewConfiguration' { 592 }
		'WKPreferences' { 152 }
		'WKUserContentController' { 120 }
		'WKProcessPool' { 1456 }
		'WKWebsiteDataStore' { 600 }
		'WKWebpagePreferences' { 496 }
		'WKUserScript' { 128 }
		'WKContentWorld' { 80 }
		'WKNSArray' { 40 }
		'WKWebView' { 1992 }
		'WKBackForwardList' { 88 }
		else { 8 }
	}
}

fn webkit_metadata() {
	for pair in [['WKWebViewConfiguration', '_pageConfiguration']!, ['WKPreferences', '_preferences']!,
		['WKUserContentController', '_userContentControllerProxy']!, ['WKProcessPool', '_processPool']!,
		['WKWebsiteDataStore', '_websiteDataStore']!, ['WKWebpagePreferences', '_websitePolicies']!]! {
		name := pair[0]
		ivar := pair[1]
		mut cls := ios_runtime.classes[ios_runtime.names[name]] or { panic('iOS: missing WebKit class') }
		types := match name {
			'WKWebViewConfiguration' { '{AlignedStorage<API::PageConfiguration, 8UL>="m_storage"{Storage="data"[576C]}}' }
			'WKPreferences' { '{AlignedStorage<WebKit::WebPreferences, 8UL>="m_storage"{Storage="data"[136C]}}' }
			'WKUserContentController' { '{AlignedStorage<WebKit::WebUserContentControllerProxy, 8UL>="m_storage"{Storage="data"[112C]}}' }
			'WKProcessPool' { '{AlignedStorage<WebKit::WebProcessPool, 8UL>="m_storage"{Storage="data"[1424C]}}' }
			'WKWebsiteDataStore' { '{AlignedStorage<WebKit::WebsiteDataStore, 8UL>="m_storage"{Storage="data"[576C]}}' }
			else { '{AlignedStorage<API::WebsitePolicies, 8UL>="m_storage"{Storage="data"[480C]}}' }
		}
		length := match name {
			'WKPreferences' { 136 }
			'WKUserContentController' { 112 }
			'WKProcessPool' { 1424 }
			'WKWebpagePreferences' { 480 }
			else { 576 }
		}
		cls.ivars[ivar] = &ObjIvar{name: ivar.clone(), types: types.clone(), offset: 8, size: u64(length)}
	}
	webkit_ivar('WKWebViewConfiguration', '_limitsNavigationsToAppBoundDomains', 'B', 584, 1)
	webkit_ivar('WKPreferences', '_isLookToScrollEnabled', 'B', 144, 1)
	webkit_ivar('WKWebpagePreferences', '_preferredContentMode', 'q', 488, 8)
	webkit_ivar('WKProcessPool', '_automationDelegate', '{WeakObjCPtr<id<_WKAutomationDelegate>>="m_weakReference"@}', 1432, 8)
	webkit_ivar('WKProcessPool', '_downloadDelegate', '{WeakObjCPtr<id<_WKDownloadDelegate>>="m_weakReference"@}', 1440, 8)
	webkit_ivar('WKProcessPool', '_automationSession', '{RetainPtr<_WKAutomationSession>="m_ptr"@"_WKAutomationSession"}', 1448, 8)
	webkit_ivar('WKWebsiteDataStore', '_delegate', '{WeakObjCPtr<id<_WKWebsiteDataStoreDelegate>>="m_weakReference"@}', 584, 8)
	webkit_ivar('WKWebsiteDataStore', '_proxyConfigurations', '{RetainPtr<NSArray>="m_ptr"@"NSArray"}', 592, 8)
	webkit_ivar('WKUserScript', '_userScript', '{AlignedStorage<API::UserScript, 8UL>="m_storage"{Storage="data"[120C]}}', 8, 120)
	webkit_ivar('WKContentWorld', '_contentWorld', '{AlignedStorage<API::ContentWorld, 8UL>="m_storage"{Storage="data"[72C]}}', 8, 72)
	webkit_ivar('WKNSArray', '_array', '{AlignedStorage<API::Array, 8UL>="m_storage"{Storage="data"[32C]}}', 8, 32)
	webkit_ivar('WKWebView', '_configuration', '{RetainPtr<WKWebViewConfiguration>="m_ptr"@"WKWebViewConfiguration"}', 408, 8)
	webkit_ivar('WKBackForwardList', '_list', '{AlignedStorage<WebKit::WebBackForwardList, 8UL>="m_storage"{Storage="data"[80C]}}', 8, 80)
}

fn webkit_ivar(name string, ivar string, types string, offset i64, size u64) {
	mut cls := ios_runtime.classes[ios_runtime.names[name]] or { panic('iOS: missing WebKit class') }
	cls.ivars[ivar] = &ObjIvar{name: ivar.clone(), types: types.clone(), offset: offset, size: size}
}

fn webkit_object_name(object u64) string {
	mut cls := if object in ios_runtime.classes { object } else { read64(object) }
	for _ in 0 .. 128 {
		info := ios_runtime.classes[cls] or { return '' }
		if webkit_name(info.name) { return info.name }
		cls = info.parent
		if cls == 0 { break }
	}
	return ''
}

fn webkit_initialize(object u64, name string) {
	mut header := obj_header(object)
	if header.webkit != unsafe { nil } { return }
	if header.native_size < webkit_size(name) { panic('iOS: invalid WebKit configuration storage') }
	header.webkit = unsafe { &WebKitState(C.calloc(1, sizeof(WebKitState))) }
	if header.webkit == unsafe { nil } { panic('iOS: cannot allocate WebKit configuration state') }
	match name {
		'WKWebViewConfiguration' { header.webkit.flags[2] = true; header.webkit.flags[5] = true; header.webkit.flags[6] = true }
		'WKPreferences' { header.webkit.flags[0] = true; header.webkit.flags[1] = true; header.webkit.flags[3] = true }
		'WKWebpagePreferences', 'WKWebsiteDataStore' { header.webkit.flags[0] = true }
		else {}
	}
}

fn webkit_dispose(mut header ObjHeader) {
	// Private ownership follows the allocation even after object_setClass.
	if header.webkit == unsafe { nil } { return }
	for value in header.webkit.refs { objc_release(value) }
	C.free(header.webkit)
	header.webkit = unsafe { nil }
}

fn webkit_default_store() u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.webkit_default_store == 0 {
		ios_runtime.webkit_default_store = objc_allocate(ios_runtime.names['WKWebsiteDataStore'])
		webkit_initialize(ios_runtime.webkit_default_store, 'WKWebsiteDataStore')
	}
	return ios_runtime.webkit_default_store
}

fn webkit_stop() {
	object := ios_runtime.webkit_default_store
	ios_runtime.webkit_default_store = 0
	objc_release(object)
	for index in 0 .. ios_runtime.webkit_world_count {
		world := ios_runtime.webkit_worlds[index]
		ios_runtime.webkit_worlds[index] = 0
		objc_release(world)
	}
	ios_runtime.webkit_world_count = 2
}

fn webkit_dependency(object u64, index int) u64 {
	mut state := obj_header(object).webkit
	if state.refs[index] == 0 {
		state.refs[index] = if index == 3 { objc_retain(webkit_default_store()) }
			else { objc_new(ios_runtime.names[['WKPreferences', 'WKProcessPool', 'WKUserContentController',
				'WKWebsiteDataStore', 'WKWebpagePreferences']![index]]) }
	}
	return state.refs[index]
}

fn webkit_copy(object u64, name string) u64 {
	if name == 'WKWebViewConfiguration' {
		// Native copying also materializes previously untouched dependencies.
		for index in 0 .. 5 { webkit_dependency(object, index) }
	}
	result := objc_new(ios_runtime.names[name])
	mut target := obj_header(result).webkit
	source := obj_header(object).webkit
	target.flags = source.flags
	target.values = source.values
	target.minimum_font_size = source.minimum_font_size
	for index, value in source.refs { target.refs[index] = objc_retain(value) }
	if name == 'WKWebViewConfiguration' { unsafe { *(&u8(result + 584)) = u8(target.flags[4]) } }
	return result
}

fn webkit_builtin_types(name string, meta bool, selector string) ?string {
	if !webkit_name(name) { return none }
	if types := webkit_script_types(name, meta, selector) { return types }
	if types := webview_types(name, meta, selector) { return types }
	if meta {
		if name == 'WKWebsiteDataStore' && selector in ['defaultDataStore', 'nonPersistentDataStore'] { return '@16@0:8' }
		return none
	}
	if selector == 'init' && name !in ['WKWebsiteDataStore', 'WKUserScript', 'WKContentWorld', 'WKNSArray', 'WKBackForwardList'] { return '@16@0:8' }
	if name in ['WKWebViewConfiguration', 'WKPreferences'] && selector in ['copy', 'copyWithZone:'] {
		return if selector == 'copy' { '@16@0:8' } else { '@24@0:8^{_NSZone=}16' }
	}
	if name == 'WKWebViewConfiguration' {
		return match selector {
			'preferences', 'processPool', 'userContentController', 'websiteDataStore', 'defaultWebpagePreferences', 'applicationNameForUserAgent', 'webExtensionController' { '@16@0:8' }
			'setPreferences:', 'setProcessPool:', 'setUserContentController:', 'setWebsiteDataStore:', 'setDefaultWebpagePreferences:', 'setApplicationNameForUserAgent:' { 'v24@0:8@16' }
			'supportsAdaptiveImageGlyph', 'suppressesIncrementalRendering', 'allowsAirPlayForMediaPlayback', 'allowsInlinePredictions', 'limitsNavigationsToAppBoundDomains', 'showsSystemScreenTimeBlockingView', 'upgradeKnownHostsToHTTPS' { 'B16@0:8' }
			'setSupportsAdaptiveImageGlyph:', 'setSuppressesIncrementalRendering:', 'setAllowsAirPlayForMediaPlayback:', 'setAllowsInlinePredictions:', 'setLimitsNavigationsToAppBoundDomains:', 'setShowsSystemScreenTimeBlockingView:', 'setUpgradeKnownHostsToHTTPS:' { 'v20@0:8B16' }
			'writingToolsBehavior', 'userInterfaceDirectionPolicy' { 'q16@0:8' }
			'setWritingToolsBehavior:', 'setUserInterfaceDirectionPolicy:' { 'v24@0:8q16' }
			'mediaTypesRequiringUserActionForPlayback' { 'Q16@0:8' }
			'setMediaTypesRequiringUserActionForPlayback:' { 'v24@0:8Q16' }
			else { return none }
		}
	}
	if name == 'WKPreferences' {
		return match selector {
			'minimumFontSize' { 'd16@0:8' }
			'setMinimumFontSize:' { 'v24@0:8d16' }
			'javaScriptEnabled', 'javaScriptCanOpenWindowsAutomatically', 'tabFocusesLinks', 'isTextInteractionEnabled' { 'B16@0:8' }
			'setJavaScriptEnabled:', 'setJavaScriptCanOpenWindowsAutomatically:', 'setTabFocusesLinks:', 'setTextInteractionEnabled:' { 'v20@0:8B16' }
			else { return none }
		}
	}
	if name == 'WKWebpagePreferences' {
		return match selector {
			'allowsContentJavaScript', 'isLockdownModeEnabled' { 'B16@0:8' }
			'setAllowsContentJavaScript:', 'setLockdownModeEnabled:' { 'v20@0:8B16' }
			'preferredContentMode' { 'q16@0:8' }
			'setPreferredContentMode:' { 'v24@0:8q16' }
			else { return none }
		}
	}
	if name == 'WKWebsiteDataStore' && selector == 'isPersistent' { return 'B16@0:8' }
	if name == 'WKUserContentController' {
		if selector == 'addUserScript:' { return 'v24@0:8@16' }
		if selector == 'userScripts' { return '@16@0:8' }
		if selector == 'removeAllUserScripts' { return 'v16@0:8' }
	}
	return none
}

fn webkit_selector(object u64, selector string) bool {
	name := webkit_object_name(object)
	return webkit_builtin_types(name, object in ios_runtime.classes, selector) != none
}

fn webkit_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	name := webkit_object_name(object)
	if name == '' { return false }
	if webkit_script_dispatch(object, name, selector, mut frame) { return true }
	if webview_dispatch(object, name, selector, mut frame) { return true }
	if object in ios_runtime.classes {
		if name == 'WKWebsiteDataStore' && selector == 'defaultDataStore' { frame.x[0] = webkit_default_store(); return true }
		if name == 'WKWebsiteDataStore' && selector == 'nonPersistentDataStore' {
			result := objc_allocate(ios_runtime.names[name])
			webkit_initialize(result, name)
			obj_header(result).webkit.flags[0] = false
			frame.x[0] = objc_autorelease(result)
			return true
		}
		return false
	}
	if selector == 'init' {
		if name in ['WKWebsiteDataStore', 'WKUserScript', 'WKContentWorld', 'WKNSArray'] { panic('iOS: WebKit object requires designated construction') }
		webkit_initialize(object, name)
		frame.x[0] = object
		return true
	}
	// The read-only adapter uses ordinary collection storage, not a WebKit
	// configuration sidecar; its getters continue through Foundation dispatch.
	if name == 'WKNSArray' { return false }
	if selector in ['copy', 'copyWithZone:'] {
		if name !in ['WKWebViewConfiguration', 'WKPreferences'] { panic('iOS: this WebKit object does not implement copying') }
		if obj_header(object).webkit == unsafe { nil } { panic('iOS: WebKit configuration is not initialized') }
		frame.x[0] = webkit_copy(object, name)
		return true
	}
	if webkit_builtin_types(name, false, selector) == none { return false }
	mut state := obj_header(object).webkit
	if state == unsafe { nil } { panic('iOS: WebKit configuration is not initialized') }
	if name == 'WKWebViewConfiguration' {
		for index, pair in [[ 'preferences', 'setPreferences:' ]!, [ 'processPool', 'setProcessPool:' ]!,
			[ 'userContentController', 'setUserContentController:' ]!, [ 'websiteDataStore', 'setWebsiteDataStore:' ]!,
			[ 'defaultWebpagePreferences', 'setDefaultWebpagePreferences:' ]!]! {
			if selector == pair[0] { frame.x[0] = webkit_dependency(object, index); return true }
			if selector == pair[1] {
				value := frame.x[2]
				expected := ['WKPreferences', 'WKProcessPool', 'WKUserContentController', 'WKWebsiteDataStore', 'WKWebpagePreferences']![index]
				if value != 0 && !objc_is_kind(value, ios_runtime.names[expected]) { panic('iOS: WebKit configuration dependency has the wrong class') }
				objc_store_strong(unsafe { &state.refs[index] }, value)
				return true
			}
		}
		for index, pair in [[ 'supportsAdaptiveImageGlyph', 'setSupportsAdaptiveImageGlyph:' ]!,
			[ 'suppressesIncrementalRendering', 'setSuppressesIncrementalRendering:' ]!,
			[ 'allowsAirPlayForMediaPlayback', 'setAllowsAirPlayForMediaPlayback:' ]!,
			[ 'allowsInlinePredictions', 'setAllowsInlinePredictions:' ]!,
			[ 'limitsNavigationsToAppBoundDomains', 'setLimitsNavigationsToAppBoundDomains:' ]!,
			[ 'showsSystemScreenTimeBlockingView', 'setShowsSystemScreenTimeBlockingView:' ]!,
			[ 'upgradeKnownHostsToHTTPS', 'setUpgradeKnownHostsToHTTPS:' ]!]! {
			if selector == pair[0] { frame.x[0] = u64(state.flags[index]); return true }
			if selector == pair[1] {
				state.flags[index] = u8(frame.x[2]) != 0
				if index == 4 { unsafe { *(&u8(object + 584)) = u8(state.flags[index]) } }
				return true
			}
		}
		for index, pair in [[ 'writingToolsBehavior', 'setWritingToolsBehavior:' ]!,
			[ 'userInterfaceDirectionPolicy', 'setUserInterfaceDirectionPolicy:' ]!,
			[ 'mediaTypesRequiringUserActionForPlayback', 'setMediaTypesRequiringUserActionForPlayback:' ]!]! {
			if selector == pair[0] { frame.x[0] = state.values[index]; return true }
			if selector == pair[1] { state.values[index] = frame.x[2]; return true }
		}
		if selector == 'webExtensionController' { frame.x[0] = 0; return true }
		if selector == 'applicationNameForUserAgent' { frame.x[0] = state.refs[5]; return true }
		if selector == 'setApplicationNameForUserAgent:' {
			value := frame.x[2]
			if value != 0 && !objc_is_kind(value, ios_runtime.names['NSString']) { panic('iOS: WebKit user-agent name must be a string') }
			copied := if value == 0 { u64(0) } else { owned_string(string_text(value)) }
			objc_store_strong(unsafe { &state.refs[5] }, copied)
			objc_release(copied)
			return true
		}
	}
	if name == 'WKPreferences' {
		if selector == 'minimumFontSize' { frame_float_return(mut frame, 0, state.minimum_font_size); return true }
		if selector == 'setMinimumFontSize:' { state.minimum_font_size = frame_double(frame, 0); return true }
		for index, pair in [[ 'javaScriptEnabled', 'setJavaScriptEnabled:' ]!,
			[ 'javaScriptCanOpenWindowsAutomatically', 'setJavaScriptCanOpenWindowsAutomatically:' ]!,
			[ 'tabFocusesLinks', 'setTabFocusesLinks:' ]!, [ 'isTextInteractionEnabled', 'setTextInteractionEnabled:' ]!]! {
			if selector == pair[0] { frame.x[0] = u64(state.flags[index]); return true }
			if selector == pair[1] { state.flags[index] = u8(frame.x[2]) != 0; return true }
		}
	}
	if name == 'WKWebpagePreferences' {
		for index, pair in [[ 'allowsContentJavaScript', 'setAllowsContentJavaScript:' ]!, [ 'isLockdownModeEnabled', 'setLockdownModeEnabled:' ]!]! {
			if selector == pair[0] { frame.x[0] = u64(state.flags[index]); return true }
			if selector == pair[1] { state.flags[index] = u8(frame.x[2]) != 0; return true }
		}
		if selector == 'preferredContentMode' { frame.x[0] = read64(object + 488); return true }
		if selector == 'setPreferredContentMode:' { unsafe { *(&u64(object + 488)) = frame.x[2] }; return true }
	}
	if name == 'WKWebsiteDataStore' && selector == 'isPersistent' { frame.x[0] = u64(state.flags[0]); return true }
	return false
}
