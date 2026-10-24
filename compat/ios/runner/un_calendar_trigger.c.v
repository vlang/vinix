// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Construction and inspection only. Scheduling and computing a next fire date
// require separate UserNotifications services. fields[0] owns the copied components.
fn un_trigger_metadata() {
	mut base := ios_runtime.classes[ios_runtime.names['UNNotificationTrigger']] or { panic('iOS: missing notification trigger') }
	base.ivars['_repeats'] = &ObjIvar{name: '_repeats'.clone(), types: 'B'.clone(), offset: 8, size: 1}
	mut calendar := ios_runtime.classes[ios_runtime.names['UNCalendarNotificationTrigger']] or { panic('iOS: missing calendar trigger') }
	calendar.ivars['_dateComponents'] = &ObjIvar{name: '_dateComponents'.clone(), types: '@"NSDateComponents"'.clone(), offset: 16, size: 8}
}

fn un_trigger_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'UNNotificationTrigger' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic notification trigger superclass chain')
}

fn un_trigger_require_class(cls u64) {
	if un_trigger_family(cls) && cls !in [ios_runtime.names['UNNotificationTrigger'], ios_runtime.names['UNCalendarNotificationTrigger']]! {
		panic('iOS: custom notification trigger construction is not implemented')
	}
}

// Caller holds the runtime lock. Changed isa never confers storage ownership.
fn un_trigger_storage(object u64, initialized bool) &ObjHeader {
	header := obj_header(object)
	if !header.un_trigger_owned || header.destroying || header.destroyed
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0
		|| header.cls != header.allocation_cls || read64(object) != header.allocation_cls
		|| header.allocation_cls !in [ios_runtime.names['UNNotificationTrigger'], ios_runtime.names['UNCalendarNotificationTrigger']]!
		|| header.native_size < if header.allocation_cls == ios_runtime.names['UNCalendarNotificationTrigger'] { u64(24) } else { u64(16) } {
		panic('iOS: notification trigger requires live owned built-in storage')
	}
	if initialized && !header.un_trigger_initialized { panic('iOS: notification trigger requires designated construction') }
	return header
}

fn un_trigger_dispose(object u64, mut header ObjHeader) {
	if !header.un_trigger_owned { return }
	unsafe { C.memset(voidptr(object + 8), 0, if header.allocation_cls == ios_runtime.names['UNCalendarNotificationTrigger'] { 16 } else { 8 }) }
	header.un_trigger_initialized = false
	// Generic field destruction releases the components after native destructors.
}

fn un_trigger_create(cls u64, components u64, repeats u64) u64 {
	un_trigger_require_class(cls)
	if cls != ios_runtime.names['UNCalendarNotificationTrigger'] { panic('iOS: calendar trigger factory requires its built-in class') }
	C.ios_objc_initialize_lock()
	state := ns_calendar_state(components, true)
	if !state.components { panic('iOS: calendar trigger requires NSDateComponents') }
	ns_calendar_pin(components)
	C.ios_objc_initialize_unlock()
	defer { ns_calendar_finish(components) }
	// Snapshot before the trigger constructor can mutate or release the input.
	copy := ns_calendar_copy(components)
	if copy == 0 { return 0 }
	object := objc_allocate(cls)
	if object == 0 { objc_release(copy); return 0 }
	C.ios_objc_initialize_lock()
	mut header := un_trigger_storage(object, false)
	if header.un_trigger_initialized || header.fields[0] != 0 {
		panic('iOS: calendar trigger constructor changed destination storage')
	}
	ns_calendar_state(copy, true)
	header.fields[0] = copy
	unsafe { *(&u8(object + 8)) = u8(repeats & 1); *(&u64(object + 16)) = copy }
	header.un_trigger_initialized = true
	C.ios_objc_initialize_unlock()
	return object
}

fn un_trigger_copy(object u64) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	un_trigger_storage(object, true)
	return objc_retain(object)
}

fn un_trigger_types(name string, meta bool, selector string) ?string {
	if name !in ['UNNotificationTrigger', 'UNCalendarNotificationTrigger']! { return none }
	if meta {
		if name == 'UNCalendarNotificationTrigger' && selector == 'triggerWithDateMatchingComponents:repeats:' { return '@28@0:8@16B24' }
		return none
	}
	return match selector {
		'init', 'copy' { '@16@0:8' }
		'copyWithZone:' { '@24@0:8^{_NSZone=}16' }
		'repeats' { 'B16@0:8' }
		'dateComponents' { if name != 'UNCalendarNotificationTrigger' { return none }; '@16@0:8' }
		else { return none }
	}
}

fn un_trigger_unsupported(selector string) bool {
	return selector in ['nextTriggerDate', 'mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:',
		'supportsSecureCoding', 'classForCoder', 'isEqual:', 'hash', 'description', 'debugDescription',
		'initWithRepeats:', 'initWithDateMatchingComponents:repeats:']!
}

fn un_trigger_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	mut cls := if meta { object } else { read64(object) }
	mut owned := un_trigger_family(cls)
	if !meta {
		C.ios_objc_initialize_lock()
		if header := ios_runtime.objects[object] {
			if header.un_trigger_owned { owned = true; cls = header.allocation_cls }
		}
		C.ios_objc_initialize_unlock()
	}
	if !owned { return false }
	if un_trigger_unsupported(selector) { panic('iOS: notification trigger option is not implemented') }
	info := ios_runtime.classes[cls] or { panic('iOS: missing notification trigger class') }
	name := info.name
	if un_trigger_types(name, meta, selector) == none { return false }
	if meta {
		frame.x[0] = objc_autorelease(un_trigger_create(object, frame.x[2], frame.x[3]))
	} else {
		match selector {
			'init' { panic('iOS: notification trigger requires designated construction') }
			'copy', 'copyWithZone:' {
				if selector == 'copyWithZone:' && frame.x[2] != 0 { panic('iOS: notification trigger copy zones are not implemented') }
				frame.x[0] = un_trigger_copy(object)
			}
			else {
				C.ios_objc_initialize_lock()
				header := un_trigger_storage(object, true)
				frame.x[0] = if selector == 'repeats' { u64(unsafe { *(&u8(object + 8)) }) } else { header.fields[0] }
				C.ios_objc_initialize_unlock()
			}
		}
	}
	return true
}
