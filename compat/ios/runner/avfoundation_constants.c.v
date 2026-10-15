// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Installed AVFoundation exports NSString pointer cells. Media-type values
// are the measured four-character identifiers, rather than symbol spellings.
fn avfoundation_constant_symbol(symbol string) ?u64 {
	index := match symbol {
		'_AVCaptureDeviceTypeBuiltInTelephotoCamera' { 0 }
		'_AVCaptureDeviceTypeBuiltInUltraWideCamera' { 1 }
		'_AVCaptureDeviceTypeBuiltInWideAngleCamera' { 2 }
		'_AVCaptureDeviceTypeExternal' { 3 }
		'_AVCaptureDeviceTypeMicrophone' { 4 }
		'_AVCaptureSessionDidStartRunningNotification' { 5 }
		'_AVCaptureSessionDidStopRunningNotification' { 6 }
		'_AVCaptureSessionInterruptionEndedNotification' { 7 }
		'_AVCaptureSessionPresetHigh' { 8 }
		'_AVCaptureSessionRuntimeErrorNotification' { 9 }
		'_AVCaptureSessionWasInterruptedNotification' { 10 }
		'_AVMediaTypeAudio' { 11 }
		'_AVMediaTypeClosedCaption' { 12 }
		'_AVMediaTypeSubtitle' { 13 }
		'_AVMediaTypeText' { 14 }
		'_AVMediaTypeTimecode' { 15 }
		'_AVPlayerItemDidPlayToEndTimeNotification' { 16 }
		'_AVCaptureSessionPresetMedium' { 17 }
		'_AVLayerVideoGravityResizeAspectFill' { 18 }
		'_AVMediaTypeVideo' { 19 }
		else { return none }
	}
	if ios_runtime == unsafe { nil } { return none }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.avfoundation_constants_arena == 0 {
		if ios_runtime.swift_concurrency_retired { return none }
		page := usize(C.getpagesize())
		arena := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
		if arena == voidptr(-1) { panic('iOS: cannot allocate AVFoundation globals') }
		mut cursor := u64(800) // Twenty pointer cells followed by twenty 32-byte CFSTR records.
		for i, text in ['AVCaptureDeviceTypeBuiltInTelephotoCamera',
			'AVCaptureDeviceTypeBuiltInUltraWideCamera', 'AVCaptureDeviceTypeBuiltInWideAngleCamera',
			'AVCaptureDeviceTypeExternal', 'AVCaptureDeviceTypeMicrophone',
			'AVCaptureSessionDidStartRunningNotification', 'AVCaptureSessionDidStopRunningNotification',
			'AVCaptureSessionInterruptionEndedNotification', 'AVCaptureSessionPresetHigh',
			'AVCaptureSessionRuntimeErrorNotification', 'AVCaptureSessionWasInterruptedNotification',
			'soun', 'clcp', 'sbtl', 'text', 'tmcd', 'AVPlayerItemDidPlayToEndTimeNotification',
			'AVCaptureSessionPresetMedium', 'AVLayerVideoGravityResizeAspectFill', 'vide']! {
			object := u64(arena) + 160 + u64(i * 32)
			if cursor + u64(text.len) + 1 > u64(page) { panic('iOS: AVFoundation globals exceed their page') }
			unsafe {
				*(&u64(object)) = ios_runtime.names['NSString']
				*(&u64(object + 8)) = 0x7c8
				*(&u64(object + 16)) = u64(arena) + cursor
				*(&u64(object + 24)) = u64(text.len)
				C.memcpy(voidptr(u64(arena) + cursor), text.str, usize(text.len))
				*(&u64(u64(arena) + u64(i * 8))) = object
			}
			cursor += u64(text.len) + 1
			ios_runtime.constants[object] = true
		}
		if C.mprotect(arena, page, C.PROT_READ) != 0 { panic('iOS: cannot seal AVFoundation globals') }
		ios_runtime.avfoundation_constants_arena = u64(arena)
	}
	return ios_runtime.avfoundation_constants_arena + u64(index * 8)
}

// Notifications, pool destructors, dictionaries and Swift contexts must stop
// using these immortal strings before their registrations and page retire.
fn avfoundation_constants_stop() {
	arena := ios_runtime.avfoundation_constants_arena
	if arena == 0 { return }
	for i in 0 .. 20 { ios_runtime.constants.delete(read64(arena + u64(i * 8))) }
	if C.munmap(unsafe { voidptr(arena) }, usize(C.getpagesize())) != 0 { panic('iOS: cannot retire AVFoundation globals') }
	ios_runtime.avfoundation_constants_arena = 0
}
