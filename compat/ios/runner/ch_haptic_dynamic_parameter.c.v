// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Native ARM64 layout and behavior measured by inspect-ch-haptic-dynamic-parameter.v.
// Dynamic parameters store values only; this does not implement haptic playback.
fn haptic_dynamic_parameter_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'CHHapticDynamicParameter' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic CHHapticDynamicParameter superclass chain')
}

fn haptic_dynamic_parameter_require_class(cls u64) {
	if haptic_dynamic_parameter_family(cls) && cls != ios_runtime.names['CHHapticDynamicParameter'] {
		panic('iOS: CHHapticDynamicParameter subclass or metaclass construction is not implemented')
	}
}

fn haptic_dynamic_parameter_metadata() {
	mut info := ios_runtime.classes[ios_runtime.names['CHHapticDynamicParameter']] or { panic('iOS: missing CHHapticDynamicParameter') }
	info.ivars['_param'] = &ObjIvar{name: '_param'.clone(), types: '@"NSString"'.clone(), offset: 8, size: 8}
	info.ivars['_value'] = &ObjIvar{name: '_value'.clone(), types: 'f'.clone(), offset: 16, size: 4}
	info.ivars['_time'] = &ObjIvar{name: '_time'.clone(), types: 'd'.clone(), offset: 24, size: 8}
}

fn haptic_dynamic_parameter_unsupported(selector string) bool {
	return selector in ['init', 'new', 'copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:',
		'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding', 'classForCoder']!
}

fn haptic_dynamic_parameter_types(name string, meta bool, selector string) ?string {
	if name != 'CHHapticDynamicParameter' || meta { return none }
	return match selector {
		'initWithParameterID:value:relativeTime:' { '@36@0:8@16f24d28' }
		'parameterID' { '@16@0:8' }
		'value' { 'f16@0:8' }
		'setValue:' { 'v20@0:8f16' }
		'relativeTime' { 'd16@0:8' }
		'setRelativeTime:' { 'v24@0:8d16' }
		else { none }
	}
}

fn haptic_dynamic_parameter_require_storage(object u64) {
	header := obj_header(object)
	if header.destroying || header.destroyed || header.caller_storage
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 || header.native_size < 32
		|| header.cls != header.allocation_cls || read64(object) != header.allocation_cls
		|| header.allocation_cls != ios_runtime.names['CHHapticDynamicParameter'] {
		panic('iOS: CHHapticDynamicParameter requires live owned parameter storage')
	}
}

fn haptic_dynamic_parameter_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	if !haptic_dynamic_parameter_family(cls) { return false }
	if haptic_dynamic_parameter_unsupported(selector) { panic('iOS: unsupported CHHapticDynamicParameter method: ' + selector) }
	if meta { return false }
	if selector !in ['initWithParameterID:value:relativeTime:', 'parameterID', 'value', 'setValue:', 'relativeTime', 'setRelativeTime:']! { return false }
	haptic_dynamic_parameter_require_storage(object)
	match selector {
		'initWithParameterID:value:relativeTime:' {
			// Retain before release also makes reinitialization with the same ID safe.
			identifier := objc_retain(frame.x[2])
			mut header := obj_header(object)
			previous := header.fields[0]
			header.fields[0] = identifier
			unsafe { *(&u64(object + 8)) = identifier }
			write32(object + 16, u32(frame.q[0]))
			// Each vector register occupies two q entries: time is in v1, not v0.
			unsafe { *(&u64(object + 24)) = frame.q[2] }
			objc_release(previous)
			frame.x[0] = object
		}
		'parameterID' { frame.x[0] = read64(object + 8) }
		'value' { frame.q[0] = u64(read32(object + 16)); frame.q[1] = 0 }
		'setValue:' { write32(object + 16, u32(frame.q[0])) }
		'relativeTime' { frame.q[0] = read64(object + 24); frame.q[1] = 0 }
		'setRelativeTime:' { unsafe { *(&u64(object + 24)) = frame.q[0] } }
		else {}
	}
	return true
}
