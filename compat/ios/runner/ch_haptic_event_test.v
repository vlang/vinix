// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math.bits

type HapticEventSend = fn (u64, u64, u64, u64) u64
type HapticEventInit = fn (u64, u64, u64, u64, f64) u64
type HapticEventInitDuration = fn (u64, u64, u64, u64, f64, f64) u64
type HapticEventGet = fn (u64, u64) f64
type HapticEventSet = fn (u64, u64, f64)
type HapticEventParameterInit = fn (u64, u64, u64, f32) u64

fn haptic_event_msg(object u64, selector &char, argument u64) u64 {
	return unsafe { HapticEventSend(voidptr(C.ios_objc_msgsend))(object, u64(selector), argument, 0) }
}

fn haptic_event_init(object u64, kind u64, parameters u64, time u64, duration u64) u64 {
	return unsafe { HapticEventInitDuration(voidptr(C.ios_objc_msgsend))(object,
		u64(c'initWithEventType:parameters:relativeTime:duration:'), kind, parameters,
		bits.f64_from_bits(time), bits.f64_from_bits(duration)) }
}

fn haptic_event_value(object u64, selector &char) u64 {
	return bits.f64_bits(unsafe { HapticEventGet(voidptr(C.ios_objc_msgsend))(object, u64(selector)) })
}

fn test_haptic_event_objects() {
	for _ in 0 .. 2 {
		objc_start()
		pool := objc_pool_push()
		cls := ios_runtime.names['CHHapticEvent']
		assert objc_class_parent(cls) == ios_runtime.names['NSObject']
		assert objc_class_size(cls) == 48
		assert !objc_class_meta(cls) && objc_class_meta(read64(cls))
		assert haptic_event_family(cls) && haptic_event_family(read64(cls))
		for prefix in ['_OBJC_CLASS_$_', '_OBJC_METACLASS_$_']! {
			symbol := prefix + 'CHHapticEvent'
			assert runtime_symbol('/System/Library/Frameworks/CoreHaptics.framework/CoreHaptics', symbol)! == if prefix == '_OBJC_CLASS_$_' { cls } else { read64(cls) }
			for wrong in ['/usr/lib/libobjc.A.dylib', '/System/Library/Frameworks/Foundation.framework/Foundation', '/System/Library/Frameworks/UIKit.framework/UIKit']! {
				if _ := runtime_symbol(wrong, symbol) { assert false, wrong }
			}
		}
		for i, name in ['_type', '_audioResID', '_eventParams', '_time', '_duration']! {
			ivar := objc_find_ivar(cls, name.str)
			assert ivar != 0 && objc_ivar_offset(ivar) == 8 + i * 8
			assert ctext(u64(objc_ivar_types(ivar))) == ['@"NSString"', 'Q', '@"NSArray"', 'd', 'd']![i]
		}
		selectors := ['initWithEventType:parameters:relativeTime:', 'initWithEventType:parameters:relativeTime:duration:',
			'initWithAudioResourceID:parameters:relativeTime:', 'initWithAudioResourceID:parameters:relativeTime:duration:',
			'type', 'eventParameters', 'audioResID', 'relativeTime', 'duration', 'setRelativeTime:', 'setDuration:']!
		for i, selector in selectors {
			method := objc_instance_method(cls, u64(selector.str))
			assert method != 0
			assert ctext(u64(objc_method_types(method))) == ['@40@0:8@16@24d32', '@48@0:8@16@24d32d40',
				'@40@0:8Q16@24d32', '@48@0:8Q16@24d32d40', '@16@0:8', '@16@0:8', 'Q16@0:8',
				'd16@0:8', 'd16@0:8', 'v24@0:8d16', 'v24@0:8d16']![i]
		}
		baseline := ios_runtime.live
		kind := haptic_event_msg(haptic_event_msg(ios_runtime.names['NSMutableString'], c'alloc', 0), c'initWithUTF8String:', u64(c'CustomEvent'))
		parameters := haptic_event_msg(ios_runtime.names['NSMutableArray'], c'new', 0)
		parameter_id := owned_string('HapticIntensity')
		parameter := unsafe { HapticEventParameterInit(voidptr(C.ios_objc_msgsend))(objc_allocate(ios_runtime.names['CHHapticEventParameter']), u64(c'initWithParameterID:value:'), parameter_id, f32(0.5)) }
		objc_release(parameter_id)
		haptic_event_msg(parameters, c'addObject:', parameter)
		object := haptic_event_init(objc_allocate(cls), kind, parameters, bits.f64_bits(-2.5), bits.f64_bits(-3.5))
		snapshot := haptic_event_msg(object, c'eventParameters', 0)
		assert snapshot != parameters && read64(snapshot) == ios_runtime.names['NSArray']
		assert haptic_event_msg(snapshot, c'objectAtIndex:', 0) == parameter
		assert haptic_event_msg(object, c'type', 0) == kind && obj_header(kind).refs == 2
		assert haptic_event_msg(object, c'audioResID', 0) == ~u64(0)
		assert read64(object + 8) == kind && read64(object + 24) == snapshot
		assert haptic_event_value(object, c'relativeTime') == bits.f64_bits(-2.5)
		assert haptic_event_value(object, c'duration') == bits.f64_bits(-3.5)
		suffix := owned_string('-changed')
		haptic_event_msg(kind, c'appendString:', suffix)
		objc_release(suffix)
		haptic_event_msg(parameters, c'removeAllObjects', 0)
		objc_release(kind); objc_release(parameters); objc_release(parameter)
		assert string_text(haptic_event_msg(object, c'type', 0)) == 'CustomEvent-changed'
		assert haptic_event_msg(snapshot, c'count', 0) == 1 && obj_header(parameter).refs == 1
		assert haptic_event_init(object, kind, snapshot, 0, 0) == object
		assert haptic_event_msg(object, c'eventParameters', 0) == snapshot
		assert obj_header(kind).refs == 1 && obj_header(snapshot).refs == 1
		replacement := owned_string('replacement')
		assert haptic_event_init(object, replacement, 0, 0, 0) == object
		assert kind !in ios_runtime.objects && snapshot !in ios_runtime.objects
		assert parameter !in ios_runtime.objects && parameter_id !in ios_runtime.objects
		objc_release(replacement)
		for raw in [u64(0), 0x8000000000000000, 0xbff0000000000000, 0x4000000000000000, 0x7ff0000000000000, 0xfff0000000000000, 0x7ff8000000001234]! {
			assert haptic_event_init(object, 0, 0, raw, raw) == object
			assert haptic_event_value(object, c'relativeTime') == raw && haptic_event_value(object, c'duration') == raw
			assert read64(object + 32) == raw && read64(object + 40) == raw
			for property in [c'setRelativeTime:', c'setDuration:']! {
				unsafe { HapticEventSet(voidptr(C.ios_objc_msgsend))(object, u64(property), bits.f64_from_bits(raw)) }
			}
			assert haptic_event_value(object, c'relativeTime') == raw && haptic_event_value(object, c'duration') == raw
		}
		assert replacement !in ios_runtime.objects
		assert haptic_event_msg(object, c'type', 0) == 0 && haptic_event_msg(object, c'eventParameters', 0) == 0
		for audio in [false, true]! {
			for duration in [false, true]! {
				selector := selectors[if audio { if duration { 3 } else { 2 } } else { if duration { 1 } else { 0 } }]
				argument := if audio { u64(0xfedcba9876543210) } else { 0 }
				fresh := if duration { unsafe { HapticEventInitDuration(voidptr(C.ios_objc_msgsend))(objc_allocate(cls), u64(selector.str), argument, 0, -1.25, 4.5) } } else { unsafe { HapticEventInit(voidptr(C.ios_objc_msgsend))(objc_allocate(cls), u64(selector.str), argument, 0, -1.25) } }
				assert haptic_event_value(fresh, c'relativeTime') == bits.f64_bits(-1.25)
				assert haptic_event_value(fresh, c'duration') == if duration { bits.f64_bits(4.5) } else { 0 }
				assert haptic_event_msg(fresh, c'audioResID', 0) == if audio { argument } else { ~u64(0) }
				assert if audio { string_text(haptic_event_msg(fresh, c'type', 0)) == 'AudioCustom' } else { haptic_event_msg(fresh, c'type', 0) == 0 }
				objc_release(fresh)
			}
		}
		for selector in selectors { assert objc_responds(object, selector.str) }
		for selector in ['init', 'new', 'copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding', 'classForCoder']! {
			assert objc_instance_method(cls, u64(selector.str)) == 0
			assert objc_class_method(cls, u64(selector.str)) == 0
			assert !objc_responds(object, selector.str) && !objc_responds(cls, selector.str)
		}
		objc_release(object)
		assert ios_runtime.live == baseline
		final_kind := owned_string('drained')
		objc_autorelease(haptic_event_init(objc_allocate(cls), final_kind, 0, 0, 0))
		objc_release(final_kind)
		objc_pool_pop(pool)
		assert final_kind !in ios_runtime.objects && ios_runtime.live == baseline
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-HAPTICEVENT: scoped imports, native metadata, four constructors, retained types, copied parameter snapshots, exact double bits and two drained runtimes')
}
fn test_haptic_event_rejections() {
	objc_start()
	cls := ios_runtime.names['CHHapticEvent']
	sub := objc_allocate_class(cls, c'BlockedHapticEvent', 0)
	objc_register_class(sub)
	for mode in ['subclass', 'metaclass', 'caller', 'install', 'init', 'new', 'copy', 'initWithCoder:', 'super-init', 'super-new', 'super-copy', 'isa-in', 'isa-out', 'invalid-storage']! {
		mut fds := [2]i32{}
		assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.fork()
		assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			match mode {
				'subclass' { objc_allocate(sub) }
				'metaclass' { objc_allocate(read64(cls)) }
				'caller' { mut storage := [6]u64{}; objc_construct_instance(cls, u64(unsafe { &storage[0] })) }
				'install' { mut storage := [6]u64{}; objc_install_storage(cls, u64(unsafe { &storage[0] }), true) }
				'isa-in' { objc_set_class(objc_allocate(ios_runtime.names['NSObject']), cls) }
				'isa-out' { objc_set_class(objc_allocate(cls), ios_runtime.names['NSObject']) }
				'invalid-storage' {
					object := objc_allocate(cls)
					obj_header(object).caller_storage = true
					haptic_event_msg(object, c'type', 0)
				}
				'super-init', 'super-new', 'super-copy' {
					selector := if mode == 'super-init' { c'init' } else if mode == 'super-copy' { c'copy' } else { c'new' }
					method := if mode == 'super-new' { objc_class_method(ios_runtime.names['NSObject'], u64(selector)) } else { objc_instance_method(ios_runtime.names['NSObject'], u64(selector)) }
					assert method != 0
					unsafe { HapticEventSend(voidptr(objc_method_imp(method)))(if mode == 'super-new' { cls } else { objc_allocate(cls) }, u64(selector), 0, 0) }
				}
				else { haptic_event_msg(if mode == 'new' { cls } else { objc_allocate(cls) }, mode.str, 0) }
			}
			C._exit(0)
		}
		C.close(fds[1])
		mut bytes := [16384]u8{}
		mut length := 0
		for {
			assert length < bytes.len
			count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length))
			if count == 0 { break }
			if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }
			assert count > 0
			length += int(count)
		}
		C.close(fds[0])
		mut status := i32(0)
		assert C.ios_waitpid(pid, &status, 0) == pid && status == 256, mode
		output := unsafe { tos(&bytes[0], length) }
		reason := if mode in ['subclass', 'metaclass']! { 'subclass or metaclass construction is not implemented' } else if mode in ['caller', 'install']! { 'caller storage is not implemented' } else if mode.starts_with('isa-') { 'changing CHHapticEvent storage isa is not implemented' } else if mode == 'invalid-storage' { 'requires live owned event storage' } else { 'unsupported CHHapticEvent method:' }
		assert output.contains(reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:') && !output.contains('> assert '), mode + ': ' + output
	}
	objc_stop()
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	println('IOS-HAPTICEVENT-REJECT: 14 subclass, metaclass, caller storage, unsupported method, saved NSObject IMP, isa and invalid storage cases fail explicitly')
}
