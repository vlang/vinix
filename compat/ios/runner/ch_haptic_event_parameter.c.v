// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Native ARM64 layout and behavior measured by inspect-ch-haptic-event-parameter.v.
// Parameter objects store values only; this does not implement haptic playback.
fn haptic_parameter_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'CHHapticEventParameter' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic CHHapticEventParameter superclass chain')
}

fn haptic_parameter_require_class(cls u64) {
	if haptic_parameter_family(cls) && cls != ios_runtime.names['CHHapticEventParameter'] {
		panic('iOS: CHHapticEventParameter subclass or metaclass construction is not implemented')
	}
}

fn haptic_parameter_metadata() {
	mut info := ios_runtime.classes[ios_runtime.names['CHHapticEventParameter']] or { panic('iOS: missing CHHapticEventParameter') }
	info.ivars['_value'] = &ObjIvar{name: '_value'.clone(), types: 'f'.clone(), offset: 8, size: 4}
	info.ivars['_param'] = &ObjIvar{name: '_param'.clone(), types: '@"NSString"'.clone(), offset: 16, size: 8}
}

fn haptic_parameter_unsupported(selector string) bool {
	return selector in ['init', 'new', 'copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:',
		'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding', 'classForCoder']!
}

fn haptic_parameter_types(name string, meta bool, selector string) ?string {
	if name != 'CHHapticEventParameter' || meta { return none }
	return match selector {
		'initWithParameterID:value:' { '@28@0:8@16f24' }
		'parameterID' { '@16@0:8' }
		'value' { 'f16@0:8' }
		'setValue:' { 'v20@0:8f16' }
		else { none }
	}
}

fn haptic_parameter_require_storage(object u64) {
	header := obj_header(object)
	if header.destroying || header.destroyed || header.caller_storage
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 || header.native_size < 24
		|| header.cls != header.allocation_cls || read64(object) != header.allocation_cls
		|| header.allocation_cls != ios_runtime.names['CHHapticEventParameter'] {
		panic('iOS: CHHapticEventParameter requires live owned parameter storage')
	}
}

fn haptic_parameter_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	if !haptic_parameter_family(cls) { return false }
	if haptic_parameter_unsupported(selector) { panic('iOS: unsupported CHHapticEventParameter method: ' + selector) }
	if meta { return false }
	if selector !in ['initWithParameterID:value:', 'parameterID', 'value', 'setValue:']! { return false }
	haptic_parameter_require_storage(object)
	match selector {
		'initWithParameterID:value:' {
			// Retain before release also makes reinitialization with the same ID safe.
			identifier := objc_retain(frame.x[2])
			mut header := obj_header(object)
			previous := header.fields[0]
			header.fields[0] = identifier
			unsafe { *(&u64(object + 16)) = identifier }
			write32(object + 8, u32(frame.q[0]))
			objc_release(previous)
			frame.x[0] = object
		}
		'parameterID' { frame.x[0] = read64(object + 16) }
		'value' { frame.q[0] = u64(read32(object + 8)); frame.q[1] = 0 }
		'setValue:' { write32(object + 8, u32(frame.q[0])) }
		else {}
	}
	return true
}
