// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Bounded construction and inspection. Notification content and delivery need
// separate implementations. fields[0] owns the identifier; fields[1] the trigger.
fn un_request_metadata() {
	mut cls := ios_runtime.classes[ios_runtime.names['UNNotificationRequest']] or { panic('iOS: missing notification request') }
	for i, pair in [['_content', '@"UNNotificationContent"']!, ['_trigger', '@"UNNotificationTrigger"']!, ['_destinations', 'Q']!, ['_identifier', '@"NSString"']!]! {
		cls.ivars[pair[0]] = &ObjIvar{name: pair[0].clone(), types: pair[1].clone(), offset: i64(8 + i * 8), size: 8}
	}
}

fn un_request_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'UNNotificationRequest' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic notification request superclass chain')
}

fn un_request_require_class(cls u64) {
	if un_request_family(cls) && cls != ios_runtime.names['UNNotificationRequest'] {
		panic('iOS: custom notification request construction is not implemented')
	}
}

// Caller holds the runtime lock. An isa change never confers storage ownership.
fn un_request_storage(object u64, initialized bool) &ObjHeader {
	header := obj_header(object)
	if !header.un_request_owned || header.destroying || header.destroyed
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 || header.native_size < 40
		|| header.cls != header.allocation_cls || read64(object) != header.allocation_cls
		|| header.allocation_cls != ios_runtime.names['UNNotificationRequest'] {
		panic('iOS: notification request requires live owned built-in storage')
	}
	if initialized && !header.un_request_initialized { panic('iOS: notification request requires designated construction') }
	return header
}

fn un_request_text(object u64) string {
	if object == 0 { panic('iOS: notification request requires a non-nil identifier') }
	if header := ios_runtime.objects[object] {
		if header.destroying || header.cls != header.allocation_cls || read64(object) != header.allocation_cls
			|| header.allocation_cls !in [ios_runtime.names['NSString'], ios_runtime.names['NSMutableString']]!
			|| (header.mutable_string_owned && !header.mutable_string_initialized) {
			panic('iOS: notification request identifier requires a built-in initialized string')
		}
	}
	text := cf_string_compare_text(object) or { panic('iOS: notification request identifier requires a live UTF8 string') }
	if text.len > 65536 { panic('iOS: notification request identifier exceeds byte limit') }
	return text
}

fn un_request_create(cls u64, identifier u64, content u64, trigger u64) u64 {
	un_request_require_class(cls)
	if cls != ios_runtime.names['UNNotificationRequest'] { panic('iOS: notification request factory requires its built-in class') }
	if content != 0 { panic('iOS: notification request content is not implemented') }
	C.ios_objc_initialize_lock()
	text := un_request_text(identifier)
	if trigger != 0 {
		header := un_trigger_storage(trigger, true)
		if header.allocation_cls != ios_runtime.names['UNCalendarNotificationTrigger'] { panic('iOS: notification request requires a calendar trigger') }
	}
	// Snapshot bytes and hold the immutable trigger before application constructors.
	snapshot := text.clone()
	if trigger != 0 { objc_retain(trigger) }
	C.ios_objc_initialize_unlock()
	defer { unsafe { snapshot.free() } }
	copy := owned_string(snapshot)
	if copy == 0 { objc_release(trigger); return 0 }
	object := objc_allocate(cls)
	if object == 0 { objc_release(copy); objc_release(trigger); return 0 }
	C.ios_objc_initialize_lock()
	mut header := un_request_storage(object, false)
	if header.un_request_initialized || header.fields[0] != 0 || header.fields[1] != 0
		|| read64(object + 8) != 0 || read64(object + 16) != 0 || read64(object + 24) != 0 || read64(object + 32) != 0 {
		panic('iOS: notification request constructor changed destination storage')
	}
	un_request_text(copy)
	if trigger != 0 { un_trigger_storage(trigger, true) }
	header.fields[0] = copy
	header.fields[1] = trigger
	unsafe { *(&u64(object + 16)) = trigger; *(&u64(object + 24)) = 6; *(&u64(object + 32)) = copy }
	header.un_request_initialized = true
	C.ios_objc_initialize_unlock()
	return object
}

fn un_request_copy(object u64) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	un_request_storage(object, true)
	return objc_retain(object)
}

fn un_request_dispose(object u64, mut header ObjHeader) {
	if !header.un_request_owned { return }
	unsafe { C.memset(voidptr(object + 8), 0, 32) }
	header.un_request_initialized = false
	// Generic field destruction releases the identifier and trigger exactly once.
}

fn un_request_types(name string, meta bool, selector string) ?string {
	if name != 'UNNotificationRequest' { return none }
	if meta { return if selector == 'requestWithIdentifier:content:trigger:' { '@40@0:8@16@24@32' } else { none } }
	return match selector {
		'init', 'identifier', 'content', 'trigger', 'copy' { '@16@0:8' }
		'copyWithZone:' { '@24@0:8^{_NSZone=}16' }
		else { none }
	}
}

fn un_request_unsupported(selector string) bool {
	return selector in ['mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:',
		'supportsSecureCoding', 'classForCoder', 'isEqual:', 'hash', 'description', 'debugDescription',
		'destinations', 'setDestinations:', 'enterSecurityScope', 'leaveSecurityScope', 'removeSecurityScope', 'addSecurityScope:',
		'_notificationDestinationsForInterruptionLevel:inputDestinations:', '_initWithIdentifier:content:trigger:destinations:',
		'requestWithIdentifier:content:trigger:destinations:', 'requestWithIdentifier:pushPayload:bundleIdentifier:']!
}

fn un_request_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	mut cls := if meta { object } else { read64(object) }
	mut owned := un_request_family(cls)
	if !meta {
		C.ios_objc_initialize_lock()
		if header := ios_runtime.objects[object] {
			if header.un_request_owned { owned = true; cls = header.allocation_cls }
		}
		C.ios_objc_initialize_unlock()
	}
	if !owned { return false }
	if un_request_unsupported(selector) { panic('iOS: notification request option is not implemented') }
	info := ios_runtime.classes[cls] or { panic('iOS: missing notification request class') }
	if un_request_types(info.name, meta, selector) == none { return false }
	if meta {
		frame.x[0] = objc_autorelease(un_request_create(object, frame.x[2], frame.x[3], frame.x[4]))
	} else {
		match selector {
			'init' { panic('iOS: notification request requires designated construction') }
			'copy', 'copyWithZone:' {
				if selector == 'copyWithZone:' && frame.x[2] != 0 { panic('iOS: notification request copy zones are not implemented') }
				frame.x[0] = un_request_copy(object)
			}
			else {
				C.ios_objc_initialize_lock()
				header := un_request_storage(object, true)
				frame.x[0] = match selector { 'identifier' { header.fields[0] } 'trigger' { header.fields[1] } else { u64(0) } }
				C.ios_objc_initialize_unlock()
			}
		}
	}
	return true
}
