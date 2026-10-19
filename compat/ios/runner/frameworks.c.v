// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

// Framework class descriptors provide inheritance and native subclass layout.
// Their API methods are implemented individually; absent methods still fail.
fn framework_symbol(library string, symbol string) ?u64 {
	if library == '/System/Library/Frameworks/StoreKit.framework/StoreKit' {
		if address := storekit_constant_symbol(symbol) { return address }
		if address := storefront_symbol(symbol) { return address }
		if address := refund_symbol(symbol) { return address }
	}
	if library == '/System/Library/Frameworks/VideoToolbox.framework/VideoToolbox' {
		if address := videotoolbox_symbol(symbol) { return address }
	}
	if library == '/System/Library/Frameworks/QuartzCore.framework/QuartzCore' {
		if address := quartzcore_time_symbol(symbol) { return address }
	}
	if library == '/System/Library/Frameworks/CoreHaptics.framework/CoreHaptics' {
		if address := corehaptics_constant_symbol(symbol) { return address }
	}
	if library == '/System/Library/Frameworks/Network.framework/Network' {
		if address := nw_symbol(symbol) { return address }
	}
	if library == '/System/Library/Frameworks/DeviceCheck.framework/DeviceCheck' {
		if address := devicecheck_symbol(symbol) { return address }
	}
	if library == '/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration' {
		if address := reachability_symbol(symbol) { return address }
	}
	if !library.starts_with('/System/Library/Frameworks/') { return none }
	if library == '/System/Library/Frameworks/Foundation.framework/Foundation' {
		if address := ns_url_error_symbol(symbol) { return address }
		if address := ns_url_session_constant_symbol(symbol) { return address }
		if address := ns_foundation_key_symbol(symbol) { return address }
	}
	// Foundation.framework reexports these Swift overlay entries. The main
	// executable uses this install name, while its bundled frameworks use the
	// dylib; installed native addresses are identical for these exports.
	if library == '/System/Library/Frameworks/Foundation.framework/Foundation'
		&& symbol in ['_$s10Foundation5NSLogyySS_s7CVarArg_pdtF',
			'_$sSD10FoundationE19_bridgeToObjectiveCSo12NSDictionaryCyF',
			'_$sSa10FoundationE36_unconditionallyBridgeFromObjectiveCySayxGSo7NSArrayCSgFZ',
			'_$sSy10FoundationE20replacingOccurrences2of4with7options5rangeSSqd___qd_0_So22NSStringCompareOptionsVSnySS5IndexVGSgtSyRd__SyRd_0_r0_lF',
			'_$s10Foundation3URLV19_bridgeToObjectiveCSo5NSURLCyF',
			'_$s10Foundation3URLV22appendingPathComponent_11isDirectoryACSS_SbtF',
			'_$s10Foundation3URLV25deletingLastPathComponentACyF',
			'_$s10Foundation3URLVMa', '_$s10Foundation3URLVMn',
			'_$s10Foundation4DataV11referencingACSo6NSDataCh_tcfC',
			'_$s10Foundation4DataV19_bridgeToObjectiveCSo6NSDataCyF',
			'_$s10Foundation4DataV19base64EncodedString7optionsSSSo27NSDataBase64EncodingOptionsV_tF',
			'_$s10Foundation4DataV36_unconditionallyBridgeFromObjectiveCyACSo6NSDataCSgFZ',
			'_$s10Foundation4DataV5write2to7optionsyAA3URLV_So20NSDataWritingOptionsVtKF',
			'_$s10Foundation4DateV11distantPastACvgZ',
			'_$s10Foundation4DateV17timeIntervalSinceySdACF',
			'_$s10Foundation4DateV2eeoiySbAC_ACtFZ',
			'_$s10Foundation4DateVACycfC',
			'_$s10Foundation4DateVMa', '_$s10Foundation4DateVMn',
			'_$s10Foundation4DateVSEAAMc', '_$s10Foundation4DateV6encode2toys7Encoder_p_tKF',
			'_$s10Foundation4DateVSeAAMc',
			'_$s10Foundation4DateV4fromACs7Decoder_p_tKcfC',
			'_$s10Foundation4DateVSQAAMc',
			'_$s10Foundation6LocaleV10identifierACSS_tcfC',
			'_$s10Foundation6LocaleV19_bridgeToObjectiveCSo8NSLocaleCyF',
			'_$s10Foundation6LocaleV10identifierSSvg',
			'_$s10Foundation6LocaleVMa', '_$s10Foundation6LocaleVMn',
			'_$sSS10FoundationE19_bridgeToObjectiveCSo8NSStringCyF',
			'_$sSS10FoundationE36_unconditionallyBridgeFromObjectiveCySSSo8NSStringCSgFZ',
			'_$sSSs7CVarArg10FoundationMc', '_$ss5ErrorP10FoundationE20localizedDescriptionSSvg',
			'_$s10Foundation10CocoaErrorV19fileWriteFileExistsAC4CodeVvgZ',
			'_$s10Foundation10CocoaErrorV4CodeVAA01_cD8ProtocolAAMc', '_$s10Foundation10CocoaErrorV4CodeVMa',
			'_$s10Foundation18_ErrorCodeProtocolPAAE2teoiySbx_s0B0_ptFZ',
			'_$s10Foundation22_convertErrorToNSErrorySo0E0Cs0C0_pF',
			'_$s10Foundation22_convertNSErrorToErrorys0E0_pSo0C0CSgF',
			'_$s10Foundation11JSONDecoderC6decode_4fromxxm_AA4DataVtKSeRzlFTj',
			'_$s10Foundation11JSONDecoderCACycfc', '_$s10Foundation11JSONDecoderCMa',
			'_$s10Foundation11JSONDecoderCMn',
			'_$s10Foundation11JSONEncoderCACycfc', '_$s10Foundation11JSONEncoderCMa',
			'_$s10Foundation11JSONEncoderCMn',
			'_$s10Foundation11JSONEncoderC20DateEncodingStrategyOMa',
			'_$s10Foundation11JSONEncoderC20DateEncodingStrategyOMn',
			'_$s10Foundation11JSONEncoderC20dateEncodingStrategyAC04DatedE0OvsTj',
			'_$s10Foundation11JSONEncoderC6encodeyAA4DataVxKSERzlFTj',
			'_$s10Foundation14LocalizedErrorPAAE16errorDescriptionSSSgvg',
			'_$s10Foundation14LocalizedErrorPAAE13failureReasonSSSgvg',
			'_$s10Foundation14LocalizedErrorPAAE18recoverySuggestionSSSgvg',
			'_$s10Foundation14LocalizedErrorPAAE10helpAnchorSSSgvg',
			'_$s10Foundation8CalendarV10IdentifierO7iso8601yA2EmFWC',
			'_$s10Foundation8CalendarV10IdentifierOMa', '_$s10Foundation8CalendarV10IdentifierOMn',
			'_$s10Foundation8CalendarV10identifierA2C10IdentifierOh_tcfC',
			'_$s10Foundation8CalendarV10identifierAC10IdentifierOvg',
			'_$s10Foundation8CalendarV10startOfDay3forAA4DateVAG_tF',
			'_$s10Foundation8CalendarV6localeAA6LocaleVSgvs', '_$s10Foundation8CalendarV6localeAA6LocaleVSgvg',
			'_$s10Foundation8CalendarV8timeZoneAA04TimeD0Vvs', '_$s10Foundation8CalendarV8timeZoneAA04TimeD0Vvg',
			'_$s10Foundation8TimeZoneV14secondsFromGMTACSgSi_tcfC', '_$s10Foundation8TimeZoneVMa',
			'_$s10Foundation8TimeZoneVMn', '_$s10Foundation8TimeZoneV10identifierSSvg',
			'_$s10Foundation8TimeZoneV19_bridgeToObjectiveCSo06NSTimeC0CyF',
			'_$s10Foundation8CalendarVMa', '_$s10Foundation8CalendarVMn',
			'_$s10Foundation11JSONEncoderC20DateEncodingStrategyO9formattedyAESo15NSDateFormatterCcAEmFWC'] {
		return swift_foundation_symbol(symbol) or { return none }
	}
	if library == '/System/Library/Frameworks/CoreVideo.framework/CoreVideo' {
		if address := corevideo_constant_symbol(symbol) { return address }
		if address := corevideo_symbol(symbol) { return address }
		if address := corevideo_metal_symbol(symbol) { return address }
	}
	if library == '/System/Library/Frameworks/CoreMedia.framework/CoreMedia' {
		if address := coremedia_hevc_symbol(symbol) { return address }
		if address := coremedia_h264_symbol(symbol) { return address }
		if address := coremedia_time_symbol(symbol) { return address }
		if address := coremedia_format_symbol(symbol) { return address }
		if address := coremedia_block_symbol(symbol) { return address }
		if address := coremedia_sample_symbol(symbol) { return address }
		if address := coremedia_constant_symbol(symbol) { return address }
	}
	if library == '/System/Library/Frameworks/IOSurface.framework/IOSurface' {
		if address := iosurface_symbol(symbol) { return address }
	}
	if library == '/System/Library/Frameworks/AVFoundation.framework/AVFoundation' {
		if address := avfoundation_constant_symbol(symbol) { return address }
	}
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
		if library == '/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox' {
			if address := audio_services_symbol(symbol) { return address }
		}
		if address := audio_symbol(symbol) { return address }
	}
	if library == '/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics' {
		if address := cg_font_symbol(symbol) { return address }
	}
	if library in ['/System/Library/Frameworks/UIKit.framework/UIKit', '/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics'] {
		if address := geometry_symbol(symbol) { return address }
		if address := provider_image_symbol(symbol) { return address }
		if address := color_symbol(symbol) { return address }
		if address := bitmap_symbol(symbol) { return address }
		if address := image_symbol(symbol) { return address }
	}
	if library == '/System/Library/Frameworks/UIKit.framework/UIKit' { if address := accessibility_symbol(symbol) { return address } }
	if library == '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation' && symbol == '_CFLocaleCopyCurrent' {
		return u64(unsafe { voidptr(cf_locale_copy_current) })
	}
	if library == '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation' && symbol == '_CFLocaleCopyPreferredLanguages' {
		return u64(unsafe { voidptr(cf_locale_copy_preferred_languages) })
	}
	if library == '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation' && symbol == '_CFLocaleGetValue' {
		return u64(unsafe { voidptr(cf_locale_get_value) })
	}
	if library == '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation' && symbol == '_CFPreferencesAppSynchronize' {
		return u64(unsafe { voidptr(cf_preferences_app_synchronize) })
	}
	if library == '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation' && symbol == '_CFPreferencesCopyAppValue' {
		return u64(unsafe { voidptr(cf_preferences_copy_app_value) })
	}
	if library == '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation' && symbol == '_CFPreferencesSetAppValue' {
		return u64(unsafe { voidptr(cf_preferences_set_app_value) })
	}
	if address := core_foundation_symbol(symbol) { return address }
	for prefix in ['_OBJC_CLASS_$_', '_OBJC_METACLASS_$_'] {
		if symbol.starts_with(prefix) {
			if _ := dispatch_objc_import_name(symbol) { return none }
			cls := ios_runtime.names[symbol[prefix.len..]] or { return none }
			return if prefix == '_OBJC_CLASS_$_' { cls } else { read64(cls) }
		}
	}
	if symbol == '___CFConstantStringClassReference' { return ios_runtime.names['NSString'] }
	if symbol == '_NSLog' { return u64(unsafe { voidptr(C.ios_nslog) }) }
	if library == '/System/Library/Frameworks/Foundation.framework/Foundation' && symbol == '_NSLogv' { return u64(unsafe { voidptr(ns_logv) }) }
	if symbol == '_NSGetSizeAndAlignment' { return u64(unsafe { voidptr(ns_get_size_alignment) }) }
	if library == '/System/Library/Frameworks/Foundation.framework/Foundation' && symbol == '_NSProtocolFromString' { return u64(unsafe { voidptr(ns_protocol_from_string) }) }
	if library == '/System/Library/Frameworks/Foundation.framework/Foundation' && symbol == '_NSStringFromProtocol' { return u64(unsafe { voidptr(ns_string_from_protocol) }) }
	if library == '/System/Library/Frameworks/Foundation.framework/Foundation' {
		if symbol == '_NSSetUncaughtExceptionHandler' { return u64(unsafe { voidptr(ns_set_uncaught_handler) }) }
		if symbol == '_NSGetUncaughtExceptionHandler' { return u64(unsafe { voidptr(ns_get_uncaught_handler) }) }
	}
	if symbol == '_NSClassFromString' { return u64(unsafe { voidptr(ns_class_from_string) }) }
	if symbol == '_NSSelectorFromString' { return u64(unsafe { voidptr(ns_selector_from_string) }) }
	if symbol == '_NSStringFromSelector' { return u64(unsafe { voidptr(ns_string_from_selector) }) }
	if symbol == '_NSSearchPathForDirectoriesInDomains' { return u64(unsafe { voidptr(ns_search_paths) }) }
	if library == '/System/Library/Frameworks/Foundation.framework/Foundation' && symbol == '_NSHomeDirectory' { return u64(unsafe { voidptr(ns_home_directory) }) }
	if library == '/System/Library/Frameworks/Foundation.framework/Foundation' && symbol == '_NSTemporaryDirectory' { return u64(unsafe { voidptr(ns_temp_directory) }) }
	if symbol in ['_kCFAllocatorSystemDefault', '_kCFAllocatorNull', '_kCFBooleanTrue', '_kCFBooleanFalse'] {
		framework_object(symbol)
		return ios_runtime.framework_data[symbol]
	}
	if symbol in ['___kCFBooleanTrue', '___kCFBooleanFalse'] {
		return framework_object(if symbol == '___kCFBooleanTrue' { '_kCFBooleanTrue' } else { '_kCFBooleanFalse' })
	}
	if address := framework_scalar(symbol) { return address }
	if symbol in ['___NSDictionary0__', '___NSDictionary0__struct'] { return framework_empty_dictionary() }
	if symbol == '_kCFAllocatorDefault' {
		if address := ios_runtime.framework_data[symbol] { return address }
		cell := C.calloc(1, 8)
		if cell == unsafe { nil } { panic('iOS: cannot allocate CF constant') }
		ios_runtime.framework_data[symbol] = u64(cell)
		return u64(cell)
	}
	return framework_constant(symbol)
}

fn framework_empty_dictionary() u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.empty_dictionary != 0 { return ios_runtime.empty_dictionary }
	// Apple's __NSDictionary0__struct export addresses the immutable object
	// directly. It is immortal to callers, but belongs to this runtime's cache.
	object := objc_allocate(ios_runtime.names['NSDictionary'])
	ios_runtime.constants[object] = true
	ios_runtime.framework_objects << object
	ios_runtime.empty_dictionary = object
	return object
}

fn framework_object(symbol string) u64 {
	if address := ios_runtime.framework_data[symbol] { return read64(address) }
	allocator := symbol in ['_kCFAllocatorSystemDefault', '_kCFAllocatorNull']!
	object := objc_allocate(ios_runtime.names[if allocator { 'NSObject' } else { 'NSNumber' }])
	if !allocator {
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
	ns_logv(format, stack)
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
		'_ASWebAuthenticationSessionErrorDomain' { 'com.apple.AuthenticationServices.WebAuthenticationSession' }
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
		'_NSHTTPCookieDomain' { 'Domain' }
		'_NSHTTPCookieVersion' { 'Version' }
		'_NSHTTPCookieSecure' { 'Secure' }
		'_NSHTTPCookieDiscard' { 'Discard' }
		'_NSHTTPCookieMaximumAge' { 'Max-Age' }
		'_NSHTTPCookieComment' { 'Comment' }
		'_NSHTTPCookieCommentURL' { 'CommentURL' }
		'_NSHTTPCookiePort' { 'Port' }
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
		'_AVAudioSessionCategoryPlayAndRecord' { 'AVAudioSessionCategoryPlayAndRecord' }
		'_AVAudioSessionCategoryRecord' { 'AVAudioSessionCategoryRecord' }
		'_AVAudioSessionInterruptionNotification' { 'AVAudioSessionInterruptionNotification' }
		'_AVAudioSessionInterruptionOptionKey' { 'AVAudioSessionInterruptionOptionKey' }
		'_AVAudioSessionInterruptionReasonKey' { 'AVAudioSessionInterruptionReasonKey' }
		'_AVAudioSessionInterruptionTypeKey' { 'AVAudioSessionInterruptionTypeKey' }
		'_AVAudioSessionMediaServicesWereResetNotification' { 'AVAudioSessionMediaServicesWereResetNotification' }
		'_AVAudioSessionModeDefault' { 'AVAudioSessionModeDefault' }
		'_AVAudioSessionModeVoiceChat' { 'AVAudioSessionModeVoiceChat' }
		'_AVAudioSessionPortBuiltInReceiver' { 'Receiver' }
		'_AVAudioSessionPortBuiltInSpeaker' { 'Speaker' }
		'_AVAudioSessionPortHeadphones' { 'Headphones' }
		'_AVAudioSessionRouteChangeNotification' { 'AVAudioSessionRouteChangeNotification' }
		'_AVAudioSessionRouteChangeReasonKey' { 'AVAudioSessionRouteChangeReasonKey' }
		'_AVAudioSessionSilenceSecondaryAudioHintNotification' { 'AVAudioSessionSilenceSecondaryAudioHintNotification' }
		'_AVAudioSessionSilenceSecondaryAudioHintTypeKey' { 'AVAudioSessionSilenceSecondaryAudioHintTypeKey' }
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
