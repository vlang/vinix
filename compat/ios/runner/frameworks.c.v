// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

// Framework class descriptors provide inheritance and native subclass layout.
// Their API methods are implemented individually; absent methods still fail.
fn framework_symbol(library string, symbol string) ?u64 {
	if !library.starts_with('/System/Library/Frameworks/') { return none }
	if library == '/System/Library/Frameworks/CFNetwork.framework/CFNetwork' {
		if address := cfnetwork_symbol(symbol) { return address }
	}
	if library == '/System/Library/Frameworks/Security.framework/Security' {
		if address := security_symbol(symbol) { return address }
	}
	if library == '/System/Library/Frameworks/GameController.framework/GameController' {
		if address := game_key_symbol(symbol) { return address }
	}
	if library in ['/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox', '/System/Library/Frameworks/AudioUnit.framework/AudioUnit'] {
		if address := audio_symbol(symbol) { return address }
	}
	if library in ['/System/Library/Frameworks/UIKit.framework/UIKit', '/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics'] {
		if address := geometry_symbol(symbol) { return address }
		if address := provider_image_symbol(symbol) { return address }
		if address := color_symbol(symbol) { return address }
		if address := bitmap_symbol(symbol) { return address }
		if address := image_symbol(symbol) { return address }
	}
	if library == '/System/Library/Frameworks/UIKit.framework/UIKit' { if address := accessibility_symbol(symbol) { return address } }
	if address := core_foundation_symbol(symbol) { return address }
	for prefix in ['_OBJC_CLASS_$_', '_OBJC_METACLASS_$_'] {
		if symbol.starts_with(prefix) {
			cls := ios_runtime.names[symbol[prefix.len..]] or { return none }
			return if prefix == '_OBJC_CLASS_$_' { cls } else { read64(cls) }
		}
	}
	if symbol == '___CFConstantStringClassReference' { return ios_runtime.names['NSString'] }
	if symbol == '_NSLog' { return u64(unsafe { voidptr(C.ios_nslog) }) }
	if symbol == '_NSClassFromString' { return u64(unsafe { voidptr(ns_class_from_string) }) }
	if symbol == '_NSSelectorFromString' { return u64(unsafe { voidptr(ns_selector_from_string) }) }
	if symbol == '_NSStringFromSelector' { return u64(unsafe { voidptr(ns_string_from_selector) }) }
	if symbol == '_NSSearchPathForDirectoriesInDomains' { return u64(unsafe { voidptr(ns_search_paths) }) }
	if symbol in ['_kCFAllocatorSystemDefault', '_kCFBooleanTrue', '_kCFBooleanFalse'] {
		framework_object(symbol)
		return ios_runtime.framework_data[symbol]
	}
	if symbol in ['___kCFBooleanTrue', '___kCFBooleanFalse'] {
		return framework_object(if symbol == '___kCFBooleanTrue' { '_kCFBooleanTrue' } else { '_kCFBooleanFalse' })
	}
	if address := framework_scalar(symbol) { return address }
	if symbol in ['___NSDictionary0__', '_kCFAllocatorDefault'] {
		if symbol == '___NSDictionary0__' && ios_runtime.empty_dictionary != 0 { return ios_runtime.empty_dictionary }
		if address := ios_runtime.framework_data[symbol] { return address }
		object := if symbol == '___NSDictionary0__' { objc_allocate(ios_runtime.names['NSDictionary']) } else { u64(0) }
		if object != 0 { ios_runtime.framework_objects << object }
		if symbol == '___NSDictionary0__' { ios_runtime.empty_dictionary = object; return object }
		cell := C.calloc(1, 8)
		if cell == unsafe { nil } { panic('iOS: cannot allocate CF constant') }
		unsafe { *(&u64(cell)) = object }
		ios_runtime.framework_data[symbol] = u64(cell)
		return u64(cell)
	}
	return framework_constant(symbol)
}

fn framework_object(symbol string) u64 {
	if address := ios_runtime.framework_data[symbol] { return read64(address) }
	object := objc_allocate(ios_runtime.names[if symbol == '_kCFAllocatorSystemDefault' { 'NSObject' } else { 'NSNumber' }])
	if symbol != '_kCFAllocatorSystemDefault' {
		mut header := obj_header(object)
		header.cf_boolean = true
		header.number = i64(symbol == '_kCFBooleanTrue')
	}
	cell := C.calloc(1, 8)
	if cell == unsafe { nil } { panic('iOS: cannot allocate CF object constant') }
	unsafe { *(&u64(cell)) = object }
	ios_runtime.framework_objects << object
	ios_runtime.framework_data[symbol] = u64(cell)
	return object
}

fn framework_scalar(symbol string) ?u64 {
	value := match symbol {
		'_UIAccessibilityTraitNone', '_UIBackgroundTaskInvalid', '_kCFAbsoluteTimeIntervalSince1970', '_UIWindowLevelNormal' { u64(0) }
		'_UIWindowLevelStatusBar' { u64(1000) }
		'_UIWindowLevelAlert' { u64(2000) }
		'_UIAccessibilityTraitButton' { u64(1) }
		'_UIAccessibilityTraitLink' { u64(2) }
		'_UIAccessibilityTraitImage' { u64(4) }
		'_UIAccessibilityTraitNotEnabled' { u64(256) }
		'_UIAccessibilityTraitAdjustable' { u64(4096) }
		'_UIAccessibilityAnnouncementNotification' { u64(1008) }
		'_UIAccessibilityLayoutChangedNotification' { u64(1001) }
		else { return none }
	}
	if address := ios_runtime.framework_data[symbol] { return address }
	cell := C.calloc(1, 8)
	if cell == unsafe { nil } { panic('iOS: cannot allocate framework scalar') }
	unsafe {
		if symbol == '_kCFAbsoluteTimeIntervalSince1970' { *(&f64(cell)) = 978307200.0 }
		else if symbol.starts_with('_UIWindowLevel') { *(&f64(cell)) = f64(value) }
		else { *(&u64(cell)) = value }
	}
	ios_runtime.framework_data[symbol] = u64(cell)
	return u64(cell)
}

fn ns_class_from_string(name u64) u64 { return ios_runtime.names[string_text(name)] }

fn ns_selector_from_string(name u64) u64 {
	if name == 0 { return 0 }
	text := string_text(name)
	return objc_selector(unsafe { &char(text.str) })
}

fn ns_string_from_selector(selector &char) u64 {
	if selector == unsafe { nil } { return 0 }
	return make_string(selector)
}

fn ns_search_paths(directory u64, domain u64, expand bool) u64 {
	_ = expand
	if directory != 9 || domain != 1 { panic('iOS: unsupported Foundation search path/domain') }
	path := os.getenv('VINIX_IOS_DOCUMENTS')
	documents := if path != '' { path } else { os.join_path(os.dir(ios_runtime.bundle), 'Documents') }
	os.mkdir_all(documents) or { panic('iOS: cannot create Documents directory: ${err}') }
	array := objc_allocate(ios_runtime.names['NSArray'])
	mut header := obj_header(array)
	array_append(mut header, make_string(unsafe { &char(documents.str) }))
	return objc_autorelease(array)
}

fn C.ios_nslog()

@[export: 'ios_nslog_stack']
fn ns_log(format u64, stack u64) {
	pool := objc_pool_push()
	defer { objc_pool_pop(pool) }
	message := ns_format(format, stack)
	C.puts(unsafe { &char(string_text(message).str) })
}

fn framework_constant(symbol string) ?u64 {
	value := match symbol {
		'_UIApplicationWillResignActiveNotification' { 'UIApplicationWillResignActiveNotification' }
		'_UISceneDidActivateNotification' { 'UISceneDidActivateNotification' }
		'_UISceneWillDeactivateNotification' { 'UISceneWillDeactivateNotification' }
		'_UIWindowSceneSessionRoleApplication' { 'UIWindowSceneSessionRoleApplication' }
		'_NSCocoaErrorDomain' { 'NSCocoaErrorDomain' }
		'_NSMachErrorDomain' { 'NSMachErrorDomain' }
		'_NSPOSIXErrorDomain' { 'NSPOSIXErrorDomain' }
		'_NSLocalizedDescriptionKey' { 'NSLocalizedDescription' }
		'_NSLocalizedFailureReasonErrorKey' { 'NSLocalizedFailureReason' }
		'_NSLocalizedRecoverySuggestionErrorKey' { 'NSLocalizedRecoverySuggestion' }
		'_NSFileModificationDate' { 'NSFileModificationDate' }
		'_NSFilePosixPermissions' { 'NSFilePosixPermissions' }
		'_NSFileSize' { 'NSFileSize' }
		'_NSFileSystemFreeSize' { 'NSFileSystemFreeSize' }
		'_NSFileSystemSize' { 'NSFileSystemSize' }
		'_NSKeyValueChangeNewKey' { 'new' }
		'_NSKeyValueChangeOldKey' { 'old' }
		'_NSKeyedArchiveRootObjectKey' { 'root' }
		'_NSProcessInfoPowerStateDidChangeNotification' { 'NSProcessInfoPowerStateDidChangeNotification' }
		'_NSProcessInfoThermalStateDidChangeNotification' { 'NSProcessInfoThermalStateDidChangeNotification' }
		'_NSHTTPCookieExpires' { 'Expires' }
		'_NSHTTPCookieName' { 'Name' }
		'_NSHTTPCookieOriginURL' { 'OriginURL' }
		'_NSHTTPCookiePath' { 'Path' }
		'_NSHTTPCookieValue' { 'Value' }
		'_NSURLAuthenticationMethodServerTrust' { 'NSURLAuthenticationMethodServerTrust' }
		'_NSURLErrorFailingURLPeerTrustErrorKey' { 'NSURLErrorFailingURLPeerTrustErrorKey' }
		'_NSURLErrorFailingURLStringErrorKey' { 'NSErrorFailingURLStringKey' }
		'_NSDocumentTypeDocumentAttribute' { 'DocumentType' }
		'_NSForegroundColorAttributeName' { 'NSColor' }
		'_NSPlainTextDocumentType' { 'NSPlainText' }
		'_UIAccessibilityVoiceOverStatusDidChangeNotification' { 'UIAccessibilityVoiceOverTouchStatusChanged' }
		'_UIActivityTypeAssignToContact' { 'com.apple.UIKit.activity.AssignToContact' }
		'_UIActivityTypePostToFlickr' { 'com.apple.UIKit.activity.PostToFlickr' }
		'_UIActivityTypePostToVimeo' { 'com.apple.UIKit.activity.PostToVimeo' }
		'_UIActivityTypePrint' { 'com.apple.UIKit.activity.Print' }
		'_UIActivityTypeSaveToCameraRoll' { 'com.apple.UIKit.activity.SaveToCameraRoll' }
		'_UIApplicationDidBecomeActiveNotification' { 'UIApplicationDidBecomeActiveNotification' }
		'_UIApplicationDidEnterBackgroundNotification' { 'UIApplicationDidEnterBackgroundNotification' }
		'_UIApplicationOpenNotificationSettingsURLString' { 'app-settings:notifications' }
		'_UIApplicationOpenSettingsURLString' { 'app-settings:' }
		'_UIApplicationOpenURLOptionsSourceApplicationKey' { 'UIApplicationOpenURLOptionsSourceApplicationKey' }
		'_UIApplicationWillEnterForegroundNotification' { 'UIApplicationWillEnterForegroundNotification' }
		'_UIDeviceBatteryStateDidChangeNotification' { 'UIDeviceBatteryStateDidChangeNotification' }
		'_UIFontTextStyleBody' { 'UICTFontTextStyleBody' }
		'_UIKeyboardDidShowNotification' { 'UIKeyboardDidShowNotification' }
		'_UIKeyboardFrameEndUserInfoKey' { 'UIKeyboardFrameEndUserInfoKey' }
		'_UIKeyboardWillHideNotification' { 'UIKeyboardWillHideNotification' }
		'_UIKeyboardWillShowNotification' { 'UIKeyboardWillShowNotification' }
		'_kCFBundleVersionKey' { 'CFBundleVersion' }
		'_kCFLocaleCountryCode' { 'kCFLocaleCountryCodeKey' }
		'_kCFLocaleLanguageCode' { 'kCFLocaleLanguageCodeKey' }
		'_kCFPreferencesCurrentApplication' { 'kCFPreferencesCurrentApplication' }
		'_kCFRunLoopCommonModes' { 'kCFRunLoopCommonModes' }
		'_kUTTypeFolder' { 'public.folder' }
		'_kUTTypeItem' { 'public.item' }
		'_kCTFontAttributeName' { 'NSFont' }
		'_kCTFontNameAttribute' { 'NSFontNameAttribute' }
		'_kCTForegroundColorFromContextAttributeName' { 'CTForegroundColorFromContext' }
		'_kCVPixelBufferPixelFormatTypeKey' { 'PixelFormatType' }
		'_NSDefaultRunLoopMode' { 'kCFRunLoopDefaultMode' }
		'_NSLocaleIdentifier' { 'kCFLocaleIdentifierKey' }
		'_GCControllerDidConnectNotification' { 'GCControllerDidConnectNotification' }
		'_GCControllerDidDisconnectNotification' { 'GCControllerDidDisconnectNotification' }
		'_GCControllerDidBecomeCurrentNotification' { 'GCControllerDidBecomeCurrentNotification' }
		'_GCKeyboardDidConnectNotification' { 'GCKeyboardDidConnectNotification' }
		'_GCKeyboardDidDisconnectNotification' { 'GCKeyboardDidDisconnectNotification' }
		'_GCMouseDidConnectNotification' { 'GCMouseDidConnectNotification' }
		'_GCMouseDidDisconnectNotification' { 'GCMouseDidDisconnectNotification' }
		'_GCHapticsLocalityDefault' { 'Default' }
		'_GCHapticsLocalityHandles' { 'Handles' }
		'_GCHapticsLocalityLeftHandle' { 'Left Handle' }
		'_GCHapticsLocalityRightHandle' { 'Right Handle' }
		'_AVAudioSessionCategoryAmbient' { 'AVAudioSessionCategoryAmbient' }
		'_AVAudioSessionCategoryAudioProcessing' { 'AVAudioSessionCategoryAudioProcessing' }
		'_AVAudioSessionCategoryPlayback' { 'AVAudioSessionCategoryPlayback' }
		'_AVAudioSessionCategorySoloAmbient' { 'AVAudioSessionCategorySoloAmbient' }
		'_AVAudioSessionInterruptionNotification' { 'AVAudioSessionInterruptionNotification' }
		'_AVAudioSessionInterruptionTypeKey' { 'AVAudioSessionInterruptionTypeKey' }
		'_AVAudioSessionMediaServicesWereResetNotification' { 'AVAudioSessionMediaServicesWereResetNotification' }
		'_AVCaptureSessionPresetMedium' { 'AVCaptureSessionPresetMedium' }
		'_AVLayerVideoGravityResizeAspectFill' { 'AVLayerVideoGravityResizeAspectFill' }
		'_AVMediaTypeVideo' { 'vide' }
		'_UIApplicationLaunchOptionsURLKey' { 'UIApplicationLaunchOptionsURLKey' }
		'_UIApplicationWillTerminateNotification' { 'UIApplicationWillTerminateNotification' }
		'_UIDeviceBatteryLevelDidChangeNotification' { 'UIDeviceBatteryLevelDidChangeNotification' }
		'_UIDeviceOrientationDidChangeNotification' { 'UIDeviceOrientationDidChangeNotification' }
		'_UIImagePickerControllerOriginalImage' { 'UIImagePickerControllerOriginalImage' }
		else { '' }
	}
	if value == '' { return none }
	return framework_string_constant(symbol, value)
}

fn framework_string_constant(symbol string, value string) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if address := ios_runtime.framework_data[symbol] { return address }
	object := owned_string(value)
	cell := C.calloc(1, 8)
	if cell == unsafe { nil } { panic('iOS: cannot allocate framework constant') }
	unsafe { *(&u64(cell)) = object }
	ios_runtime.framework_data[symbol] = u64(cell)
	ios_runtime.framework_objects << object
	return u64(cell)
}
