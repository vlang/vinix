// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math.bits

// Native layout and array/duration semantics measured by inspect-ch-haptic-pattern.v.
// This descriptor supports event arrays with empty parameter/curve lists, not playback.
fn haptic_pattern_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'CHHapticPattern' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic CHHapticPattern superclass chain')
}

fn haptic_pattern_require_class(cls u64) {
	if haptic_pattern_family(cls) && cls != ios_runtime.names['CHHapticPattern'] {
		panic('iOS: CHHapticPattern subclass or metaclass construction is not implemented')
	}
}

fn haptic_pattern_metadata() {
	mut info := ios_runtime.classes[ios_runtime.names['CHHapticPattern']] or { panic('iOS: missing CHHapticPattern') }
	for i, name in ['_ahapBaseURL', '_version', '_patternID', '_configurationDictionary', '_embeddedResourceInfo', '_events', '_parameters', '_parameterCurves']! {
		info.ivars[name] = &ObjIvar{name: name.clone(), types: ['@"NSURL"', '@"NSNumber"', '@"NSString"', '@"NSDictionary"', '@"NSMutableArray"', '@"NSMutableArray"', '@"NSMutableArray"', '@"NSMutableArray"']![i].clone(), offset: i64(8 + i * 8), size: 8}
	}
}

fn haptic_pattern_unsupported(selector string) bool {
	return selector in ['init', 'new', 'copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:',
		'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding', 'classForCoder',
		'initWithDictionary:error:', 'initWithContentsOfURL:error:', 'exportDictionaryAndReturnError:',
		'exportDictionaryWithConfigurationAndReturnError:', 'resolveExternalResources:error:',
		'doInitWithDictionary:error:', 'eventListFromDictionary:error:', 'patternForKey:error:',
		'eventListFromEvents:parameters:parameterCurves:engine:privileged:', 'priority', 'locality',
		'audioPowerUsage', 'hapticPowerUsage', 'usageCategory']!
}

fn haptic_pattern_types(name string, meta bool, selector string) ?string {
	if name != 'CHHapticPattern' || meta { return none }
	return match selector {
		'initWithEvents:parameters:error:', 'initWithEvents:parameterCurves:error:' { '@40@0:8@16@24^@32' }
		'events', 'parameters', 'parameterCurves', 'patternID', 'configurationDictionary' { '@16@0:8' }
		'duration' { 'd16@0:8' }
		'version' { 'f16@0:8' }
		else { none }
	}
}

fn haptic_pattern_require_storage(object u64) {
	header := obj_header(object)
	if header.destroying || header.destroyed || header.caller_storage
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 || header.native_size < 72
		|| header.cls != header.allocation_cls || read64(object) != header.allocation_cls
		|| header.allocation_cls != ios_runtime.names['CHHapticPattern'] {
		panic('iOS: CHHapticPattern requires live owned pattern storage')
	}
}

fn haptic_pattern_array(array u64) {
	if array != 0 && (!objc_is_kind(array, ios_runtime.names['NSArray']) || obj_header(array).cf_raw_values) {
		panic('iOS: CHHapticPattern requires object arrays')
	}
}

fn haptic_pattern_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	cls := if meta { object } else { read64(object) }
	if !haptic_pattern_family(cls) { return false }
	if haptic_pattern_unsupported(selector) { panic('iOS: unsupported CHHapticPattern method: ' + selector) }
	if meta { return false }
	if _ := haptic_pattern_types('CHHapticPattern', false, selector) {} else { return false }
	haptic_pattern_require_storage(object)
	if selector.starts_with('initWithEvents:') {
		events := frame.x[2]
		parameters := frame.x[3]
		haptic_pattern_array(events)
		haptic_pattern_array(parameters)
		if parameters != 0 && cf_array_count(parameters) != 0 {
			panic('iOS: CHHapticPattern nonempty parameters or curves are not implemented')
		}
		// Acquire the new shallow copies before releasing previous backing arrays.
		copied := objc_allocate(ios_runtime.names['NSMutableArray'])
		mut copied_header := obj_header(copied)
		if events != 0 {
			for i in 0 .. cf_array_count(events) {
				event := cf_array_value(events, i)
				haptic_event_require_storage(event)
				array_append(mut copied_header, event)
			}
		}
		active := if selector == 'initWithEvents:parameters:error:' { 1 } else { 2 }
		list := objc_allocate(ios_runtime.names['NSMutableArray'])
		mut header := obj_header(object)
		previous_events := header.fields[0]
		previous_list := header.fields[active]
		header.fields[0] = copied
		header.fields[active] = list
		unsafe {
			*(&u64(object + 48)) = copied
			*(&u64(object + u64(48 + active * 8))) = list
		}
		objc_release(previous_events)
		objc_release(previous_list)
		// Native success leaves the caller's NSError slot untouched.
		frame.x[0] = object
	} else {
		match selector {
			'events', 'parameters', 'parameterCurves' {
				offset := if selector == 'events' { u64(48) } else if selector == 'parameters' { u64(56) } else { u64(64) }
				array := read64(object + offset)
				frame.x[0] = objc_autorelease(if array == 0 { objc_allocate(ios_runtime.names['NSArray']) } else { objc_copy_value(array, false) })
			}
			'patternID', 'configurationDictionary' { frame.x[0] = 0 }
			'version' { frame.q[0] = 0; frame.q[1] = 0 }
			'duration' {
				mut duration := f64(0)
				array := read64(object + 48)
				if array != 0 {
					for i in 0 .. cf_array_count(array) {
						event := cf_array_value(array, i)
						haptic_event_require_storage(event)
						end := bits.f64_from_bits(read64(event + 32)) + bits.f64_from_bits(read64(event + 40))
						if end > duration { duration = end }
					}
				}
				frame.q[0] = bits.f64_bits(duration); frame.q[1] = 0
			}
			else {}
		}
	}
	return true
}
