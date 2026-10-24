// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Immutable ordinary default/named values. No playback, critical alerts,
// ringtones, coding or custom subclasses. fields[0] owns the filename snapshot.
fn un_sound_ivars() [15]string {
	return ['alertType', 'alertTopic', 'audioCategory', 'audioVolume', 'maximumDuration',
		'critical', 'shouldIgnoreAccessibilityDisabledVibrationSetting', 'shouldIgnoreRingerSwitch',
		'shouldRepeat', 'toneFileName', 'toneFileURL', 'toneIdentifier',
		'toneMediaLibraryItemIdentifier', 'vibrationIdentifier', 'vibrationPatternFileURL']!
}
fn un_sound_offsets() [15]u64 { return [u64(8), 16, 24, 32, 40, 48, 49, 50, 51, 56, 64, 72, 80, 88, 96]! }
fn un_sound_ivar_types() [15]string {
	return ['q', '@"NSString"', '@"NSString"', '@"NSNumber"', 'd', 'B', 'B', 'B', 'B',
		'@"NSString"', '@"NSURL"', '@"NSString"', 'Q', '@"NSString"', '@"NSURL"']!
}
fn un_sound_metadata() {
	mut cls := ios_runtime.classes[ios_runtime.names['UNNotificationSound']] or { panic('iOS: missing notification sound') }
	for i, property in un_sound_ivars() {
		name := '_' + property; types := un_sound_ivar_types()[i]
		cls.ivars[name] = &ObjIvar{name: name.clone(), types: types.clone(), offset: i64(un_sound_offsets()[i]), size: if types == 'B' { u64(1) } else { u64(8) }}
	}
}
fn un_sound_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'UNNotificationSound' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic notification sound superclass chain')
}
fn un_sound_require_class(cls u64) {
	if un_sound_family(cls) && cls != ios_runtime.names['UNNotificationSound'] { panic('iOS: custom notification sound construction is not implemented') }
}
// Caller holds the runtime lock. An isa change cannot confer storage ownership.
fn un_sound_storage(object u64, initialized bool) &ObjHeader {
	header := obj_header(object)
	if !header.un_sound_owned || header.destroying || header.destroyed
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 || header.native_size < 104
		|| header.cls != header.allocation_cls || read64(object) != header.allocation_cls
		|| header.allocation_cls != ios_runtime.names['UNNotificationSound'] {
		panic('iOS: notification sound requires live owned built-in storage')
	}
	if initialized && !header.un_sound_initialized { panic('iOS: notification sound requires designated construction') }
	for offset := u64(8); offset < 104; offset += 8 {
		expected := if header.un_sound_initialized && offset == 8 { u64(17) }
			else if offset == 56 { header.fields[0] } else { u64(0) }
		if read64(object + offset) != expected { panic('iOS: notification sound body was changed') }
	}
	if header.un_sound_initialized && header.fields[0] != 0 { un_request_text(header.fields[0]) }
	return header
}
fn un_sound_create(cls u64, filename u64) u64 {
	un_sound_require_class(cls)
	if cls != ios_runtime.names['UNNotificationSound'] { panic('iOS: notification sound factory requires its built-in class') }
	C.ios_objc_initialize_lock()
	snapshot := if filename == 0 { ''.clone() } else { un_request_text(filename).clone() }
	C.ios_objc_initialize_unlock()
	defer { unsafe { snapshot.free() } }
	// No borrowed input or runtime lock crosses an application constructor.
	name := if filename == 0 { u64(0) } else { owned_string(snapshot) }
	if filename != 0 && name == 0 { return 0 }
	object := objc_allocate(cls)
	if object == 0 { objc_release(name); return 0 }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut header := un_sound_storage(object, false)
	if header.un_sound_initialized || header.fields[0] != 0 { panic('iOS: notification sound constructor changed state') }
	if name != 0 { un_request_text(name) }
	header.fields[0] = name
	unsafe { *(&u64(object + 8)) = 17; *(&u64(object + 56)) = name }
	header.un_sound_initialized = true
	return object
}
fn un_sound_copy(object u64) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	un_sound_storage(object, true)
	return objc_retain(object)
}
fn un_sound_dispose(object u64, mut header ObjHeader) {
	if !header.un_sound_owned { return }
	unsafe { C.memset(voidptr(object + 8), 0, 96) }
	header.un_sound_initialized = false
	// Generic field destruction releases the filename exactly once.
}
fn un_sound_types(name string, meta bool, selector string) ?string {
	if name != 'UNNotificationSound' { return none }
	if meta { return match selector { 'defaultSound' { '@16@0:8' } 'soundNamed:' { '@24@0:8@16' } else { none } } }
	return match selector {
		'init', 'copy', 'alertTopic', 'audioCategory', 'audioVolume', 'toneFileName', 'toneFileURL',
		'toneIdentifier', 'vibrationIdentifier', 'vibrationPatternFileURL' { '@16@0:8' }
		'copyWithZone:' { '@24@0:8^{_NSZone=}16' }
		'alertType' { 'q16@0:8' }
		'maximumDuration' { 'd16@0:8' }
		'toneMediaLibraryItemIdentifier' { 'Q16@0:8' }
		'isCritical', 'shouldIgnoreAccessibilityDisabledVibrationSetting', 'shouldIgnoreRingerSwitch', 'shouldRepeat' { 'B16@0:8' }
		else { none }
	}
}
fn un_sound_unsupported(selector string) bool {
	return selector in ['mutableCopy', 'mutableCopyWithZone:', 'supportsSecureCoding', 'initWithCoder:',
		'encodeWithCoder:', 'classForCoder', 'isEqual:', 'hash', 'description', 'debugDescription',
		'defaultCriticalSound', 'defaultCriticalSoundWithAudioVolume:', 'criticalSoundNamed:',
		'criticalSoundNamed:withAudioVolume:', 'defaultRingtoneSound', 'ringtoneSoundNamed:',
		'defaultSystemSound', 'soundWithAlertType:', '_soundWithAlertType:audioVolume:critical:toneFileName:',
		'_initWithAlertType:alertTopic:audioCategory:audioVolume:critical:maximumDuration:shouldIgnoreAccessibilityDisabledVibrationSetting:shouldIgnoreRingerSwitch:shouldRepeat:toneFileName:toneFileURL:toneIdentifier:toneMediaLibraryItemIdentifier:vibrationIdentifier:vibrationPatternFileURL:']!
}
fn un_sound_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	mut cls := if meta { object } else { read64(object) }
	mut owned := un_sound_family(cls)
	if !meta {
		C.ios_objc_initialize_lock()
		if header := ios_runtime.objects[object] { if header.un_sound_owned { owned = true; cls = header.allocation_cls } }
		C.ios_objc_initialize_unlock()
	}
	if !owned { return false }
	if un_sound_unsupported(selector) { panic('iOS: notification sound option is not implemented') }
	info := ios_runtime.classes[cls] or { panic('iOS: missing notification sound class') }
	if un_sound_types(info.name, meta, selector) == none { return false }
	if meta { frame.x[0] = objc_autorelease(un_sound_create(object, if selector == 'soundNamed:' { frame.x[2] } else { u64(0) })) }
	else {
		match selector {
			'init' { panic('iOS: notification sound requires designated construction') }
			'copy', 'copyWithZone:' {
				if selector == 'copyWithZone:' && frame.x[2] != 0 { panic('iOS: notification sound copy zones are not implemented') }
				frame.x[0] = un_sound_copy(object)
			}
			else {
				C.ios_objc_initialize_lock()
				header := un_sound_storage(object, true)
				if selector == 'maximumDuration' { frame_float_return(mut frame, 0, 0) }
				else { frame.x[0] = match selector { 'alertType' { u64(17) } 'toneFileName' { header.fields[0] } else { u64(0) } } }
				C.ios_objc_initialize_unlock()
			}
		}
	}
	return true
}
