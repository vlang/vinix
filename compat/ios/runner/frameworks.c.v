// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

// Framework class descriptors provide inheritance and native subclass layout.
// Their API methods are implemented individually; absent methods still fail.
fn framework_symbol(library string, symbol string) ?u64 {
	if !library.starts_with('/System/Library/Frameworks/') { return none }
	for prefix in ['_OBJC_CLASS_$_', '_OBJC_METACLASS_$_'] {
		if symbol.starts_with(prefix) {
			cls := ios_runtime.names[symbol[prefix.len..]] or { return none }
			return if prefix == '_OBJC_CLASS_$_' { cls } else { read64(cls) }
		}
	}
	if symbol == '___CFConstantStringClassReference' { return ios_runtime.names['NSString'] }
	if symbol == '_NSLog' { return u64(unsafe { voidptr(C.ios_nslog) }) }
	if symbol == '_NSClassFromString' { return u64(unsafe { voidptr(ns_class_from_string) }) }
	if symbol == '_NSSearchPathForDirectoriesInDomains' { return u64(unsafe { voidptr(ns_search_paths) }) }
	if symbol in ['___NSDictionary0__', '_kCFAllocatorDefault', '_kCFBooleanTrue'] {
		if symbol == '___NSDictionary0__' && ios_runtime.empty_dictionary != 0 { return ios_runtime.empty_dictionary }
		if address := ios_runtime.framework_data[symbol] { return address }
		object := if symbol == '___NSDictionary0__' { objc_allocate(ios_runtime.names['NSDictionary']) }
			else if symbol == '_kCFBooleanTrue' { objc_allocate(ios_runtime.names['NSNumber']) } else { u64(0) }
		if symbol == '_kCFBooleanTrue' { mut header := obj_header(object); header.number = 1 }
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

fn ns_class_from_string(name u64) u64 { return ios_runtime.names[string_text(name)] }

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
	if address := ios_runtime.framework_data[symbol] { return address }
	object := objc_retain(make_string(unsafe { &char(value.str) }))
	cell := C.calloc(1, 8)
	if cell == unsafe { nil } { panic('iOS: cannot allocate framework constant') }
	unsafe { *(&u64(cell)) = object }
	ios_runtime.framework_data[symbol] = u64(cell)
	ios_runtime.framework_objects << object
	return u64(cell)
}
