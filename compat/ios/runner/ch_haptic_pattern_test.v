// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math.bits

type HapticPatternSend = fn (u64, u64, u64, u64, u64) u64
type HapticPatternEventInit = fn (u64, u64, u64, u64, f64, f64) u64
type HapticPatternGet = fn (u64, u64) f64
type HapticPatternFloat = fn (u64, u64) f32
type HapticPatternSet = fn (u64, u64, f64)

fn haptic_pattern_msg(object u64, selector &char, argument u64) u64 {
	return unsafe { HapticPatternSend(voidptr(C.ios_objc_msgsend))(object, u64(selector), argument, 0, 0) }
}

fn haptic_pattern_init(object u64, selector &char, events u64, parameters u64, error_slot &u64) u64 {
	return unsafe { HapticPatternSend(voidptr(C.ios_objc_msgsend))(object, u64(selector), events, parameters, u64(error_slot)) }
}

fn haptic_pattern_event(time f64, duration f64) u64 {
	kind := owned_string('HapticContinuous')
	defer { objc_release(kind) }
	return unsafe { HapticPatternEventInit(voidptr(C.ios_objc_msgsend))(objc_allocate(ios_runtime.names['CHHapticEvent']),
		u64(c'initWithEventType:parameters:relativeTime:duration:'), kind, 0, time, duration) }
}

fn haptic_pattern_duration(object u64) f64 {
	return unsafe { HapticPatternGet(voidptr(C.ios_objc_msgsend))(object, u64(c'duration')) }
}

fn test_haptic_pattern_objects() {
	for _ in 0 .. 2 {
		objc_start()
		baseline := ios_runtime.live
		pool := objc_pool_push()
		cls := ios_runtime.names['CHHapticPattern']
		assert objc_class_parent(cls) == ios_runtime.names['NSObject'] && objc_class_size(cls) == 72
		assert !objc_class_meta(cls) && objc_class_meta(read64(cls))
		assert haptic_pattern_family(cls) && haptic_pattern_family(read64(cls))
		for prefix in ['_OBJC_CLASS_$_', '_OBJC_METACLASS_$_']! {
			symbol := prefix + 'CHHapticPattern'
			assert runtime_symbol('/System/Library/Frameworks/CoreHaptics.framework/CoreHaptics', symbol)! == if prefix == '_OBJC_CLASS_$_' { cls } else { read64(cls) }
			for wrong in ['/usr/lib/libobjc.A.dylib', '/System/Library/Frameworks/Foundation.framework/Foundation', '/System/Library/Frameworks/UIKit.framework/UIKit']! {
				if _ := runtime_symbol(wrong, symbol) { assert false, wrong }
			}
		}
		for i, name in ['_ahapBaseURL', '_version', '_patternID', '_configurationDictionary', '_embeddedResourceInfo', '_events', '_parameters', '_parameterCurves']! {
			ivar := objc_find_ivar(cls, name.str)
			assert ivar != 0 && objc_ivar_offset(ivar) == 8 + i * 8
			assert ctext(u64(objc_ivar_types(ivar))) == ['@"NSURL"', '@"NSNumber"', '@"NSString"', '@"NSDictionary"', '@"NSMutableArray"', '@"NSMutableArray"', '@"NSMutableArray"', '@"NSMutableArray"']![i]
		}
		selectors := ['initWithEvents:parameters:error:', 'initWithEvents:parameterCurves:error:', 'events', 'parameters', 'parameterCurves', 'patternID', 'configurationDictionary', 'duration', 'version']!
		for i, selector in selectors {
			method := objc_instance_method(cls, u64(selector.str))
			assert method != 0
			assert ctext(u64(objc_method_types(method))) == ['@40@0:8@16@24^@32', '@40@0:8@16@24^@32', '@16@0:8', '@16@0:8', '@16@0:8', '@16@0:8', '@16@0:8', 'd16@0:8', 'f16@0:8']![i]
			assert objc_class_method(cls, u64(selector.str)) == 0
		}
		event := haptic_pattern_event(1.25, 3.5)
		events := haptic_pattern_msg(ios_runtime.names['NSMutableArray'], c'new', 0)
		empty := haptic_pattern_msg(ios_runtime.names['NSMutableArray'], c'new', 0)
		haptic_pattern_msg(events, c'addObject:', event)
		for selector in [c'initWithEvents:parameters:error:', c'initWithEvents:parameterCurves:error:']! {
			for nil_events in [false, true]! {
				for nil_list in [false, true]! {
					mut error_slot := u64(0x1234)
					object := haptic_pattern_init(objc_allocate(cls), selector, if nil_events { 0 } else { events }, if nil_list { 0 } else { empty }, &error_slot)
					assert object != 0 && error_slot == 0x1234
					assert haptic_pattern_duration(object) == if nil_events { 0.0 } else { 4.75 }
					assert read64(object + 48) != 0 && read64(read64(object + 48)) == ios_runtime.names['NSMutableArray']
					assert (read64(object + 56) != 0) == (selector == c'initWithEvents:parameters:error:')
					assert (read64(object + 64) != 0) == (selector == c'initWithEvents:parameterCurves:error:')
					for offset in [8, 16, 24, 32, 40]! { assert read64(object + u64(offset)) == 0 }
					for property in [c'events', c'parameters', c'parameterCurves']! {
						snapshot := haptic_pattern_msg(object, property, 0)
						assert snapshot != 0 && snapshot != events && snapshot != empty
						assert read64(snapshot) == ios_runtime.names['NSArray']
						assert cf_array_count(snapshot) == if !nil_events && property == c'events' { 1 } else { 0 }
						if !nil_events && property == c'events' { assert cf_array_value(snapshot, 0) == event }
					}
					assert haptic_pattern_msg(object, c'patternID', 0) == 0 && haptic_pattern_msg(object, c'configurationDictionary', 0) == 0
					assert unsafe { HapticPatternFloat(voidptr(C.ios_objc_msgsend))(object, u64(c'version')) } == 0
					for name in selectors { assert objc_responds(object, name.str) }
					objc_release(object)
				}
			}
		}
		mut error_slot := u64(0x1234)
		object := haptic_pattern_init(objc_allocate(cls), c'initWithEvents:parameters:error:', events, 0, &error_slot)
		snapshot := objc_retain(haptic_pattern_msg(object, c'events', 0))
		haptic_pattern_msg(events, c'removeAllObjects', 0)
		assert cf_array_count(snapshot) == 1 && haptic_pattern_duration(object) == 4.75
		unsafe { HapticPatternSet(voidptr(C.ios_objc_msgsend))(event, u64(c'setRelativeTime:'), 8.0) }
		assert haptic_pattern_duration(object) == 11.5
		unsafe { HapticPatternSet(voidptr(C.ios_objc_msgsend))(event, u64(c'setRelativeTime:'), 1.25) }
		// Reinitialize using the pattern's own backing array, then a getter snapshot.
		previous := read64(object + 48)
		assert haptic_pattern_init(object, c'initWithEvents:parameters:error:', previous, 0, &error_slot) == object
		assert previous !in ios_runtime.objects && cf_array_value(read64(object + 48), 0) == event
		parameters := read64(object + 56)
		assert haptic_pattern_init(object, c'initWithEvents:parameterCurves:error:', snapshot, empty, &error_slot) == object
		assert read64(object + 56) == parameters && read64(object + 64) != 0
		assert error_slot == 0x1234 && haptic_pattern_duration(object) == 4.75
		second := haptic_pattern_event(2.0, 0.5)
		haptic_pattern_msg(events, c'addObject:', second)
		haptic_pattern_msg(events, c'addObject:', event)
		assert haptic_pattern_init(object, c'initWithEvents:parameters:error:', events, empty, &error_slot) == object
		assert haptic_pattern_duration(object) == 4.75 && parameters !in ios_runtime.objects
		objc_release(object)
		assert cf_array_value(snapshot, 0) == event
		objc_release(snapshot)
		haptic_pattern_msg(events, c'removeAllObjects', 0)
		haptic_pattern_msg(events, c'addObject:', event)
		objc_release(second)
		for raw in [u64(0), 0x8000000000000000, 0xbff0000000000000, 0x4000000000000000, 0x7ff0000000000000, 0xfff0000000000000, 0x7ff8000000001234]! {
			unsafe {
				HapticPatternSet(voidptr(C.ios_objc_msgsend))(event, u64(c'setRelativeTime:'), bits.f64_from_bits(raw))
				HapticPatternSet(voidptr(C.ios_objc_msgsend))(event, u64(c'setDuration:'), 0.0)
			}
			pattern := haptic_pattern_init(objc_allocate(cls), c'initWithEvents:parameters:error:', events, 0, &error_slot)
			assert bits.f64_bits(haptic_pattern_duration(pattern)) == if bits.f64_from_bits(raw) > 0 { raw } else { u64(0) }
			objc_release(pattern)
		}
		for time in [-2.0, 2.0, 0.0]! {
			for length in [-4.0, 4.0, 0.0]! {
				unsafe {
					HapticPatternSet(voidptr(C.ios_objc_msgsend))(event, u64(c'setRelativeTime:'), time)
					HapticPatternSet(voidptr(C.ios_objc_msgsend))(event, u64(c'setDuration:'), length)
				}
				pattern := haptic_pattern_init(objc_allocate(cls), c'initWithEvents:parameters:error:', events, 0, &error_slot)
				assert haptic_pattern_duration(pattern) == if time + length > 0 { time + length } else { 0.0 }
				objc_release(pattern)
			}
		}
		for name in ['init', 'new', 'copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding', 'classForCoder', 'initWithDictionary:error:', 'initWithContentsOfURL:error:', 'exportDictionaryAndReturnError:', 'exportDictionaryWithConfigurationAndReturnError:', 'resolveExternalResources:error:', 'doInitWithDictionary:error:', 'eventListFromDictionary:error:', 'patternForKey:error:', 'eventListFromEvents:parameters:parameterCurves:engine:privileged:', 'priority', 'locality', 'audioPowerUsage', 'hapticPowerUsage', 'usageCategory']! {
			assert objc_instance_method(cls, u64(name.str)) == 0 && objc_class_method(cls, u64(name.str)) == 0
			assert !objc_responds(cls, name.str)
			probe := haptic_pattern_init(objc_allocate(cls), c'initWithEvents:parameters:error:', 0, 0, &error_slot)
			assert !objc_responds(probe, name.str)
			objc_release(probe)
		}
		objc_release(event); objc_release(events); objc_release(empty)
		objc_autorelease(haptic_pattern_init(objc_allocate(cls), c'initWithEvents:parameterCurves:error:', 0, 0, &error_slot))
		objc_pool_pop(pool)
		assert ios_runtime.live == baseline
		assert event !in ios_runtime.objects && second !in ios_runtime.objects
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-HAPTICPATTERN: scoped imports, native metadata, two constructors, copied arrays, retained events, dynamic duration and two drained runtimes')
}

fn test_haptic_pattern_rejections() {
	objc_start()
	cls := ios_runtime.names['CHHapticPattern']
	sub := objc_allocate_class(cls, c'BlockedHapticPattern', 0)
	objc_register_class(sub)
	for mode in ['subclass', 'metaclass', 'caller', 'install', 'init', 'new', 'copy', 'initWithCoder:', 'super-init', 'super-new', 'super-copy', 'isa-in', 'isa-out', 'invalid-storage', 'parameters', 'curves', 'wrong-array', 'wrong-event', 'initWithDictionary:error:', 'initWithContentsOfURL:error:', 'exportDictionaryAndReturnError:', 'direct-copy']! {
		mut fds := [2]i32{}
		assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.fork()
		assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			match mode {
				'subclass' { objc_allocate(sub) }
				'metaclass' { objc_allocate(read64(cls)) }
				'caller' { mut storage := [9]u64{}; objc_construct_instance(cls, u64(unsafe { &storage[0] })) }
				'install' { mut storage := [9]u64{}; objc_install_storage(cls, u64(unsafe { &storage[0] }), true) }
				'isa-in' { objc_set_class(objc_allocate(ios_runtime.names['NSObject']), cls) }
				'isa-out' { objc_set_class(objc_allocate(cls), ios_runtime.names['NSObject']) }
				'invalid-storage' {
					object := objc_allocate(cls)
					obj_header(object).caller_storage = true
					haptic_pattern_duration(object)
				}
				'parameters', 'curves', 'wrong-array', 'wrong-event' {
					array := haptic_pattern_msg(ios_runtime.names['NSMutableArray'], c'new', 0)
					item := objc_allocate(ios_runtime.names['NSObject'])
					haptic_pattern_msg(array, c'addObject:', item)
					mut error_slot := u64(0x1234)
					haptic_pattern_init(objc_allocate(cls), if mode == 'curves' { c'initWithEvents:parameterCurves:error:' } else { c'initWithEvents:parameters:error:' }, if mode == 'wrong-array' { item } else if mode == 'wrong-event' { array } else { 0 }, if mode in ['parameters', 'curves']! { array } else { 0 }, &error_slot)
				}
				'direct-copy' { objc_copy_value(objc_allocate(cls), false) }
				'super-init', 'super-new', 'super-copy' {
					selector := if mode == 'super-init' { c'init' } else if mode == 'super-copy' { c'copy' } else { c'new' }
					method := if mode == 'super-new' { objc_class_method(ios_runtime.names['NSObject'], u64(selector)) } else { objc_instance_method(ios_runtime.names['NSObject'], u64(selector)) }
					assert method != 0
					unsafe { HapticPatternSend(voidptr(objc_method_imp(method)))(if mode == 'super-new' { cls } else { objc_allocate(cls) }, u64(selector), 0, 0, 0) }
				}
				else { haptic_pattern_msg(if mode == 'new' { cls } else { objc_allocate(cls) }, mode.str, 0) }
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
		reason := if mode in ['subclass', 'metaclass']! { 'subclass or metaclass construction is not implemented' } else if mode in ['caller', 'install']! { 'caller storage is not implemented' } else if mode.starts_with('isa-') { 'changing CHHapticPattern storage isa is not implemented' } else if mode == 'invalid-storage' { 'requires live owned pattern storage' } else if mode in ['parameters', 'curves']! { 'nonempty parameters or curves are not implemented' } else if mode == 'wrong-array' { 'requires object arrays' } else if mode == 'wrong-event' { 'requires live owned event storage' } else { 'unsupported CHHapticPattern method:' }
		assert output.contains(reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:') && !output.contains('> assert '), mode + ': ' + output
	}
	objc_stop()
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	println('IOS-HAPTICPATTERN-REJECT: 22 subclass, metaclass, caller storage, unsupported method, saved NSObject IMP, isa, invalid storage, nonempty lists and invalid array cases fail explicitly')
}
