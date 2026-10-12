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
fn C.class_getInstanceSize(voidptr) usize
fn C.dlsym(voidptr, &char) voidptr

type WebKitSend = fn (u64, u64, u64, u64) u64
type WebKitDoubleGet = fn (u64, u64) f64
type WebKitDoubleSet = fn (u64, u64, f64)

struct WebKitApi {
	native bool
	send u64
	configuration u64
	preferences u64
	process_pool u64
	content_controller u64
	data_store u64
	webpage_preferences u64
	string_class u64
}

fn (api WebKitApi) selector(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}

fn (api WebKitApi) message(object u64, name &char, a u64, b u64) u64 {
	return unsafe { WebKitSend(voidptr(api.send))(object, api.selector(name), a, b) }
}

fn (api WebKitApi) number(object u64, name &char) f64 {
	return unsafe { WebKitDoubleGet(voidptr(api.send))(object, api.selector(name)) }
}

fn (api WebKitApi) set_number(object u64, name &char, value f64) {
	unsafe { WebKitDoubleSet(voidptr(api.send))(object, api.selector(name), value) }
}

fn (api WebKitApi) text(object u64) string {
	return ctext(api.message(object, c'UTF8String', 0, 0))
}

fn webkit_cases(api WebKitApi) {
	config := api.message(api.message(api.configuration, c'alloc', 0, 0), c'init', 0, 0)
	other := api.message(api.configuration, c'new', 0, 0)
	assert config != 0 && config != other
	// Copy before any dependency getter: native copying shares lazy defaults.
	duplicate := api.message(config, c'copyWithZone:', 0, 0)
	for index, pair in [[c'preferences', c'setPreferences:']!, [c'processPool', c'setProcessPool:']!,
		[c'userContentController', c'setUserContentController:']!, [c'websiteDataStore', c'setWebsiteDataStore:']!,
		[c'defaultWebpagePreferences', c'setDefaultWebpagePreferences:']!]! {
		value := api.message(config, pair[0], 0, 0)
		assert value != 0 && value == api.message(config, pair[0], 0, 0)
		assert value == api.message(duplicate, pair[0], 0, 0)
		assert (value == api.message(other, pair[0], 0, 0)) == (index == 3)
		api.message(config, pair[1], 0, 0)
		replacement := api.message(config, pair[0], 0, 0)
		assert replacement != 0 && (replacement == value) == (index == 3)
		assert api.message(duplicate, pair[0], 0, 0) == value
		api.message(config, pair[1], value, 0)
		assert api.message(config, pair[0], 0, 0) == value
	}
	for index, pair in [[c'supportsAdaptiveImageGlyph', c'setSupportsAdaptiveImageGlyph:']!,
		[c'suppressesIncrementalRendering', c'setSuppressesIncrementalRendering:']!,
		[c'allowsAirPlayForMediaPlayback', c'setAllowsAirPlayForMediaPlayback:']!,
		[c'allowsInlinePredictions', c'setAllowsInlinePredictions:']!,
		[c'limitsNavigationsToAppBoundDomains', c'setLimitsNavigationsToAppBoundDomains:']!,
		[c'showsSystemScreenTimeBlockingView', c'setShowsSystemScreenTimeBlockingView:']!,
		[c'upgradeKnownHostsToHTTPS', c'setUpgradeKnownHostsToHTTPS:']!]! {
		initial := [u64(0), 0, 1, 0, 0, 1, 1]![index]
		assert api.message(config, pair[0], 0, 0) == initial
		api.message(config, pair[1], 1 - initial, 0)
		assert api.message(config, pair[0], 0, 0) == 1 - initial
		assert api.message(duplicate, pair[0], 0, 0) == initial
		api.message(config, pair[1], initial, 0)
	}
	for pair in [[c'writingToolsBehavior', c'setWritingToolsBehavior:']!,
		[c'userInterfaceDirectionPolicy', c'setUserInterfaceDirectionPolicy:']!,
		[c'mediaTypesRequiringUserActionForPlayback', c'setMediaTypesRequiringUserActionForPlayback:']!]! {
		assert api.message(config, pair[0], 0, 0) == 0
		api.message(config, pair[1], 1, 0)
		assert api.message(config, pair[0], 0, 0) == 1
		assert api.message(duplicate, pair[0], 0, 0) == 0
	}
	assert api.message(config, c'applicationNameForUserAgent', 0, 0) == 0
	agent := api.message(api.string_class, c'stringWithUTF8String:', u64(c'VinixFixture'), 0)
	api.message(config, c'setApplicationNameForUserAgent:', agent, 0)
	assert api.text(api.message(config, c'applicationNameForUserAgent', 0, 0)) == 'VinixFixture'
	copy_after := api.message(config, c'copy', 0, 0)
	api.message(config, c'setApplicationNameForUserAgent:', 0, 0)
	assert api.message(config, c'applicationNameForUserAgent', 0, 0) == 0
	assert api.text(api.message(copy_after, c'applicationNameForUserAgent', 0, 0)) == 'VinixFixture'
	assert api.message(config, c'webExtensionController', 0, 0) == 0
	prefs := api.message(config, c'preferences', 0, 0)
	assert api.number(prefs, c'minimumFontSize') == 0
	api.set_number(prefs, c'setMinimumFontSize:', 14.5)
	assert api.number(prefs, c'minimumFontSize') == 14.5
	assert api.number(api.message(duplicate, c'preferences', 0, 0), c'minimumFontSize') == 14.5
	for index, pair in [[c'javaScriptEnabled', c'setJavaScriptEnabled:']!,
		[c'javaScriptCanOpenWindowsAutomatically', c'setJavaScriptCanOpenWindowsAutomatically:']!,
		[c'tabFocusesLinks', c'setTabFocusesLinks:']!, [c'isTextInteractionEnabled', c'setTextInteractionEnabled:']!]! {
		initial := [u64(1), 1, 0, 1]![index]
		assert api.message(prefs, pair[0], 0, 0) == initial
		api.message(prefs, pair[1], 1 - initial, 0)
		assert api.message(prefs, pair[0], 0, 0) == 1 - initial
	}
	prefs_copy := api.message(prefs, c'copy', 0, 0)
	assert prefs_copy != prefs && api.number(prefs_copy, c'minimumFontSize') == 14.5
	api.set_number(prefs, c'setMinimumFontSize:', 20)
	assert api.number(prefs_copy, c'minimumFontSize') == 14.5
	webpage := api.message(config, c'defaultWebpagePreferences', 0, 0)
	assert api.message(webpage, c'allowsContentJavaScript', 0, 0) == 1
	assert api.message(webpage, c'isLockdownModeEnabled', 0, 0) == 0
	assert api.message(webpage, c'preferredContentMode', 0, 0) == 0
	api.message(webpage, c'setAllowsContentJavaScript:', 0, 0)
	api.message(webpage, c'setLockdownModeEnabled:', 1, 0)
	api.message(webpage, c'setPreferredContentMode:', 1, 0)
	assert api.message(webpage, c'allowsContentJavaScript', 0, 0) == 0
	assert api.message(webpage, c'isLockdownModeEnabled', 0, 0) == 1
	assert api.message(webpage, c'preferredContentMode', 0, 0) == 1
	store := api.message(api.data_store, c'defaultDataStore', 0, 0)
	assert store == api.message(config, c'websiteDataStore', 0, 0)
	assert api.message(store, c'isPersistent', 0, 0) == 1
	temporary := api.message(api.data_store, c'nonPersistentDataStore', 0, 0)
	assert temporary != store && api.message(temporary, c'isPersistent', 0, 0) == 0
	api.message(config, c'setWebsiteDataStore:', temporary, 0)
	assert api.message(config, c'websiteDataStore', 0, 0) == temporary
	api.message(config, c'setWebsiteDataStore:', 0, 0)
	assert api.message(config, c'websiteDataStore', 0, 0) == store
	controller := api.message(config, c'userContentController', 0, 0)
	assert api.message(api.message(controller, c'userScripts', 0, 0), c'count', 0, 0) == 0
	api.message(controller, c'removeAllUserScripts', 0, 0)
	for object in [prefs_copy, copy_after, duplicate, other, config]! { api.message(object, c'release', 0, 0) }
}

fn test_webkit_native_configuration() {
	$if macos {
		pool := u64(C.objc_getClass(c'NSAutoreleasePool'))
		api := WebKitApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend')),
			configuration: u64(C.objc_getClass(c'WKWebViewConfiguration')), preferences: u64(C.objc_getClass(c'WKPreferences')),
			process_pool: u64(C.objc_getClass(c'WKProcessPool')), content_controller: u64(C.objc_getClass(c'WKUserContentController')),
			data_store: u64(C.objc_getClass(c'WKWebsiteDataStore')), webpage_preferences: u64(C.objc_getClass(c'WKWebpagePreferences')),
			string_class: u64(C.objc_getClass(c'NSString'))}
		for index, cls in [api.configuration, api.preferences, api.content_controller, api.process_pool, api.data_store, api.webpage_preferences]! {
			assert C.class_getInstanceSize(voidptr(cls)) == [usize(592), 152, 120, 1456, 600, 496]![index]
		}
		owned_pool := api.message(pool, c'new', 0, 0)
		webkit_cases(api)
		config := api.message(api.configuration, c'new', 0, 0)
		mutable := api.message(u64(C.objc_getClass(c'NSMutableString')), c'stringWithUTF8String:', u64(c'original'), 0)
		api.message(config, c'setApplicationNameForUserAgent:', mutable, 0)
		api.message(mutable, c'appendString:', api.message(api.string_class, c'stringWithUTF8String:', u64(c'-changed'), 0), 0)
		assert api.text(api.message(config, c'applicationNameForUserAgent', 0, 0)) == 'original'
		api.message(config, c'release', 0, 0)
		api.message(owned_pool, c'release', 0, 0)
		println('IOS-WEBKIT-NATIVE: measured layouts, defaults, scalar/FP setters, shared dependencies, copies, nil resets and data-store policies passed')
	}
}

fn test_webkit_runtime_configuration() {
	for _ in 0 .. 2 {
		objc_start()
		api := WebKitApi{send: u64(unsafe { voidptr(C.ios_objc_builtin) }),
			configuration: ios_runtime.names['WKWebViewConfiguration'], preferences: ios_runtime.names['WKPreferences'],
			process_pool: ios_runtime.names['WKProcessPool'], content_controller: ios_runtime.names['WKUserContentController'],
			data_store: ios_runtime.names['WKWebsiteDataStore'], webpage_preferences: ios_runtime.names['WKWebpagePreferences'],
			string_class: ios_runtime.names['NSString']}
		for cls in [api.configuration, api.preferences, api.process_pool, api.content_controller, api.data_store, api.webpage_preferences]! {
			info := ios_runtime.classes[cls] or { panic('missing fixture class') }
			name := info.name
			assert objc_class_size(cls) == webkit_size(name)
			assert runtime_symbol('/System/Library/Frameworks/WebKit.framework/WebKit', '_OBJC_CLASS_$_' + name) or { panic(err) } == cls
			assert runtime_symbol('/System/Library/Frameworks/WebKit.framework/WebKit', '_OBJC_METACLASS_$_' + name) or { panic(err) } == read64(cls)
		}
		assert objc_ivar_offset(objc_find_ivar(api.configuration, c'_pageConfiguration')) == 8
		assert objc_ivar_offset(objc_find_ivar(api.configuration, c'_limitsNavigationsToAppBoundDomains')) == 584
		assert ctext(u64(objc_method_types(objc_instance_method(api.configuration, u64(c'setLimitsNavigationsToAppBoundDomains:'))))) == 'v20@0:8B16'
		assert ctext(u64(objc_method_types(objc_instance_method(api.preferences, u64(c'setMinimumFontSize:'))))) == 'v24@0:8d16'
		pool := objc_pool_push()
		webkit_cases(api)
		objc_pool_pop(pool)
		assert ios_runtime.live == 1 // Runtime owns only the default store cache.
		for _ in 0 .. 100 {
			object := objc_new(api.configuration)
			agent := owned_string('mutable')
			api.message(object, c'setApplicationNameForUserAgent:', agent, 0)
			unsafe { obj_header(agent).text[0] = char(`z`) }
			assert api.text(api.message(object, c'applicationNameForUserAgent', 0, 0)) == 'mutable'
			objc_release(agent)
			api.message(object, c'setApplicationNameForUserAgent:', api.message(object, c'applicationNameForUserAgent', 0, 0), 0)
			copied := api.message(object, c'copy', 0, 0)
			objc_set_class(object, ios_runtime.names['NSObject'])
			objc_release(object)
			objc_release(copied)
			assert ios_runtime.live == 1
		}
		storage := u64(C.calloc(1, 592))
		assert objc_construct_instance(api.configuration, storage) == storage
		assert api.message(storage, c'init', 0, 0) == storage
		api.message(storage, c'setLimitsNavigationsToAppBoundDomains:', 1, 0)
		assert unsafe { *(&u8(storage + 584)) } == 1
		api.message(storage, c'preferences', 0, 0)
		assert objc_destruct_instance(storage) == storage
		C.free(unsafe { voidptr(storage) })
		assert ios_runtime.live == 1
		object := objc_new(api.configuration)
		for selector in [c'_apiObject', c'encodeWithCoder:', c'initWithCoder:', c'setURLSchemeHandler:forURLScheme:', c'setWebExtensionController:', c'allowsInlineMediaPlayback']! {
			assert !objc_responds(object, selector) && objc_instance_method(api.configuration, u64(selector)) == 0
		}
		assert !objc_responds(api.configuration, c'supportsSecureCoding')
		controller := objc_new(api.content_controller)
		assert !objc_responds(controller, c'copyWithZone:')
		assert !objc_responds(controller, c'copy') && objc_instance_method(api.content_controller, u64(c'copy')) == 0
		assert !objc_responds(controller, c'addUserScript:')
		objc_release(controller)
		objc_release(object)
		webkit_stop()
		assert ios_runtime.live == 0
		objc_stop()
	}
	println('IOS-WEBKIT: shared fixtures, imports and metadata, copied names, balanced repeated copy/isa change/caller-storage lifetimes and explicit unsupported browser APIs passed')
}

fn test_webkit_profile_rejections() {
	objc_start()
	api := WebKitApi{send: u64(unsafe { voidptr(C.ios_objc_builtin) }), configuration: ios_runtime.names['WKWebViewConfiguration']}
	object := objc_new(api.configuration)
	wrong := objc_new(ios_runtime.names['NSNumber'])
	for operation in 0 .. 4 {
		mut descriptors := [2]i32{}
		assert C.pipe(unsafe { &descriptors[0] }) == 0
		pid := C.ios_fork()
		assert pid >= 0
		if pid == 0 {
			C.close(descriptors[0])
			assert C.dup2(descriptors[1], 2) == 2
			C.close(descriptors[1])
			match operation {
				0 { api.message(object, c'setPreferences:', wrong, 0) }
				1 { api.message(object, c'setApplicationNameForUserAgent:', wrong, 0) }
				2 { api.message(object, c'_apiObject', 0, 0) }
				else { api.message(ios_runtime.names['WKWebsiteDataStore'], c'new', 0, 0) }
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
		assert output.contains(['WebKit configuration dependency has the wrong class', 'WebKit user-agent name must be a string',
			'unimplemented Objective-C method WKWebViewConfiguration _apiObject', 'use WebKit data store factories']![operation]), output
		assert !output.contains('AddressSanitizer') && !output.contains('runtime error:')
	}
	objc_release(wrong)
	objc_release(object)
	assert ios_runtime.live == 0
	objc_stop()
	println('IOS-WEBKIT-REJECT: wrong dependency/name classes, private engine access and unsupported data-store constructors fail explicitly')
}
