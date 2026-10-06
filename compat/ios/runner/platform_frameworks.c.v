// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math.bits
import os

fn platform_framework_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	if defaults_dispatch(object, selector, mut frame) { return true }
	if notification_dispatch(object, selector, mut frame) { return true }
	if propertylist_dispatch(object, selector, mut frame) { return true }
	if scene_dispatch(object, selector, mut frame) { return true }
	cls := objc_class(object)
	info := ios_runtime.classes[cls] or { return false }
	if object in ios_runtime.classes {
		match info.name {
			'UIDevice' {
				if selector != 'currentDevice' { return false }
				if ios_runtime.device == 0 { ios_runtime.device = objc_allocate(cls) }
				frame.x[0] = ios_runtime.device
			}
			'NSBundle' {
				if selector != 'mainBundle' { return false }
				if ios_runtime.bundle_object == 0 { ios_runtime.bundle_object = objc_allocate(cls) }
				frame.x[0] = ios_runtime.bundle_object
			}
			'AVAudioSession' {
				if selector != 'sharedInstance' { return false }
				if ios_runtime.audio_session == 0 { ios_runtime.audio_session = objc_allocate(cls) }
				frame.x[0] = ios_runtime.audio_session
			}
			'NSLocale' {
				if selector != 'currentLocale' { return false }
				if ios_runtime.locale == 0 {
					ios_runtime.locale = objc_allocate(cls)
					mut language := os.getenv('LC_ALL')
					if language == '' { language = os.getenv('LC_MESSAGES') }
					if language == '' { language = os.getenv('LANG') }
					language = language.all_before('.').all_before('@')
					if language in ['', 'C', 'POSIX'] { language = 'en_US' }
					store_field(ios_runtime.locale, 0, make_string(unsafe { &char(language.str) }))
				}
				frame.x[0] = ios_runtime.locale
			}
			'NSFileHandle' {
				if selector != 'fileHandleForReadingFromURL:error:' { return false }
				path := string_text(obj_header(frame.x[2]).fields[0])
				native := C.fopen(unsafe { &char(path.str) }, c'rb')
				if native == unsafe { nil } { frame.x[0] = 0; return true }
				handle := objc_allocate(cls)
				mut header := obj_header(handle)
				header.file = native
				frame.x[0] = objc_autorelease(handle)
			}
			else { return false }
		}
		return true
	}
	mut header := obj_header(object)
	match info.name {
		'NSLocale' {
			if selector == 'objectForKey:' {
				if string_text(frame.x[2]) != 'kCFLocaleIdentifierKey' { panic('iOS: NSLocale key is not implemented') }
			} else if selector != 'localeIdentifier' { return false }
			frame.x[0] = header.fields[0]
		}
		'UIDevice' {
			match selector {
				'systemVersion' { frame.x[0] = make_string(c'17.0') }
				'systemName' { frame.x[0] = make_string(c'iOS') }
				'name' { frame.x[0] = make_string(c'Vinix ARM64') }
				'model', 'localizedModel' { frame.x[0] = make_string(c'iPad') }
				'userInterfaceIdiom', 'orientation' { frame.x[0] = 1 }
				'batteryState' { frame.x[0] = 0 }
				'batteryLevel' { frame.q[0] = u64(bits.f32_bits(-1)); frame.q[1] = 0 }
				'setBatteryMonitoringEnabled:' { header.valid = frame.x[2] != 0 }
				'isBatteryMonitoringEnabled' { frame.x[0] = u64(header.valid) }
				'beginGeneratingDeviceOrientationNotifications' { header.number++ }
				'endGeneratingDeviceOrientationNotifications' { if header.number > 0 { header.number-- } }
				'isGeneratingDeviceOrientationNotifications' { frame.x[0] = u64(header.number > 0) }
				else { return false }
			}
		}
		'NSBundle' {
			match selector {
				'resourcePath', 'bundlePath' { frame.x[0] = make_string(unsafe { &char(ios_runtime.bundle.str) }) }
				'executablePath' { frame.x[0] = make_string(unsafe { &char(image_runtime.path.str) }) }
				'executableURL', 'bundleURL' {
					url := objc_allocate(ios_runtime.names['NSURL'])
					store_field(url, 0, make_string(unsafe { &char(if selector == 'executableURL' { image_runtime.path.str } else { ios_runtime.bundle.str }) }))
					frame.x[0] = objc_autorelease(url)
				}
				else { return false }
			}
		}
		'NSFileHandle' {
			match selector {
				'seekToFileOffset:' { if header.file == unsafe { nil } || C.fseek(header.file, i64(frame.x[2]), 0) != 0 { panic('iOS: NSFileHandle seek failed') } }
				'readDataOfLength:' {
					if header.file == unsafe { nil } || frame.x[2] > 256 * 1024 * 1024 { panic('iOS: invalid NSFileHandle read') }
					data := objc_allocate(ios_runtime.names['NSData'])
					mut bytes := obj_header(data)
					bytes.data = []u8{len: int(frame.x[2])}
					length := C.fread(bytes.data.data, 1, usize(bytes.data.len), header.file)
					bytes.data.trim(int(length))
					if C.ferror(header.file) != 0 { panic('iOS: NSFileHandle read failed') }
					frame.x[0] = objc_autorelease(data)
				}
				'closeFile' { if header.file != unsafe { nil } { C.fclose(header.file); header.file = unsafe { nil } } }
				else { return false }
			}
		}
		'NSData' {
			match selector {
				'bytes' { frame.x[0] = data_pointer(object) }
				'length' { frame.x[0] = data_length(object) }
				else { return false }
			}
		}
		'NSURL' {
			match selector {
				'path', 'absoluteString' { frame.x[0] = header.fields[0] }
				else { return false }
			}
		}
		else { return false }
	}
	return true
}
