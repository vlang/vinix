// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Native ARM64 layout and value semantics measured by inspect-ch-haptic-event.v.
// Events describe haptics/audio only; this does not implement playback.
fn haptic_event_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'CHHapticEvent' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic CHHapticEvent superclass chain')
}

fn haptic_event_require_class(cls u64) {
	if haptic_event_family(cls) && cls != ios_runtime.names['CHHapticEvent'] {
		panic('iOS: CHHapticEvent subclass or metaclass construction is not implemented')
	}
}

fn haptic_event_metadata() {
	mut info := ios_runtime.classes[ios_runtime.names['CHHapticEvent']] or { panic('iOS: missing CHHapticEvent') }
	for i, name in ['_type', '_audioResID', '_eventParams', '_time', '_duration']! {
		info.ivars[name] = &ObjIvar{name: name.clone(), types: ['@"NSString"', 'Q', '@"NSArray"', 'd', 'd']![i].clone(), offset: i64(8 + i * 8), size: 8}
	}
}

fn haptic_event_unsupported(selector string) bool {
	return selector in ['init', 'new', 'copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:',
		'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding', 'classForCoder']!
}

fn haptic_event_types(name string, meta bool, selector string) ?string {
	if name != 'CHHapticEvent' || meta { return none }
	return match selector {
		'initWithEventType:parameters:relativeTime:' { '@40@0:8@16@24d32' }
		'initWithEventType:parameters:relativeTime:duration:' { '@48@0:8@16@24d32d40' }
		'initWithAudioResourceID:parameters:relativeTime:' { '@40@0:8Q16@24d32' }
		'initWithAudioResourceID:parameters:relativeTime:duration:' { '@48@0:8Q16@24d32d40' }
		'type', 'eventParameters' { '@16@0:8' }
		'audioResID' { 'Q16@0:8' }
		'relativeTime', 'duration' { 'd16@0:8' }
		'setRelativeTime:', 'setDuration:' { 'v24@0:8d16' }
		else { none }
	}
}

fn haptic_event_require_storage(object u64) {
	header := obj_header(object)
	if header.destroying || header.destroyed || header.caller_storage
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 || header.native_size < 48
		|| header.cls != header.allocation_cls || read64(object) != header.allocation_cls
		|| header.allocation_cls != ios_runtime.names['CHHapticEvent'] {
		panic('iOS: CHHapticEvent requires live owned event storage')
	}
}

fn haptic_event_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	if !haptic_event_family(cls) { return false }
	if haptic_event_unsupported(selector) { panic('iOS: unsupported CHHapticEvent method: ' + selector) }
	if meta { return false }
	if _ := haptic_event_types('CHHapticEvent', false, selector) {} else { return false }
	haptic_event_require_storage(object)
	if selector.starts_with('initWith') {
		audio := selector.starts_with('initWithAudioResourceID:')
		// Acquire both new references before retiring either old reference: an
		// event can be reinitialized using its own type and parameter snapshot.
		kind := if audio { owned_string('AudioCustom') } else { objc_retain(frame.x[2]) }
		parameters := if frame.x[3] == 0 { u64(0) } else { objc_copy_value(frame.x[3], false) }
		mut header := obj_header(object)
		previous_kind := header.fields[0]
		previous_parameters := header.fields[1]
		header.fields[0] = kind
		header.fields[1] = parameters
		unsafe {
			*(&u64(object + 8)) = kind
			*(&u64(object + 16)) = if audio { frame.x[2] } else { ~u64(0) }
			*(&u64(object + 24)) = parameters
			*(&u64(object + 32)) = frame.q[0]
			*(&u64(object + 40)) = if selector.ends_with('duration:') { frame.q[2] } else { u64(0) }
		}
		objc_release(previous_kind)
		objc_release(previous_parameters)
		frame.x[0] = object
	} else {
		match selector {
			'type' { frame.x[0] = read64(object + 8) }
			'audioResID' { frame.x[0] = read64(object + 16) }
			'eventParameters' { frame.x[0] = read64(object + 24) }
			'relativeTime', 'duration' { frame.q[0] = read64(object + if selector == 'relativeTime' { u64(32) } else { u64(40) }); frame.q[1] = 0 }
			'setRelativeTime:', 'setDuration:' { unsafe { *(&u64(object + if selector == 'setRelativeTime:' { u64(32) } else { u64(40) })) = frame.q[0] } }
			else {}
		}
	}
	return true
}
