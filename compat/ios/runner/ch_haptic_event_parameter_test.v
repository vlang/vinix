// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math.bits

type HapticParameterSend = fn (u64, u64, u64, u64) u64
type HapticParameterInit = fn (u64, u64, u64, f32) u64
type HapticParameterGet = fn (u64, u64) f32
type HapticParameterSet = fn (u64, u64, f32)

fn haptic_parameter_msg(object u64, selector &char, a u64) u64 {
	return unsafe { HapticParameterSend(voidptr(C.ios_objc_msgsend))(object, u64(selector), a, 0) }
}

fn haptic_parameter_init(object u64, identifier u64, raw u32) u64 {
	return unsafe { HapticParameterInit(voidptr(C.ios_objc_msgsend))(object, u64(c'initWithParameterID:value:'), identifier, bits.f32_from_bits(raw)) }
}

fn haptic_parameter_value(object u64) u32 {
	return bits.f32_bits(unsafe { HapticParameterGet(voidptr(C.ios_objc_msgsend))(object, u64(c'value')) })
}

fn test_haptic_parameter_objects() {
	for _ in 0 .. 2 {
		objc_start()
		pool := objc_pool_push()
		cls := ios_runtime.names['CHHapticEventParameter']
		assert objc_class_parent(cls) == ios_runtime.names['NSObject']
		assert objc_class_size(cls) == 24
		assert !objc_class_meta(cls) && objc_class_meta(read64(cls))
		assert haptic_parameter_family(cls) && haptic_parameter_family(read64(cls))
		for prefix in ['_OBJC_CLASS_$_', '_OBJC_METACLASS_$_']! {
			symbol := prefix + 'CHHapticEventParameter'
			assert runtime_symbol('/System/Library/Frameworks/CoreHaptics.framework/CoreHaptics', symbol)! == if prefix == '_OBJC_CLASS_$_' { cls } else { read64(cls) }
			for wrong in ['/usr/lib/libobjc.A.dylib', '/System/Library/Frameworks/Foundation.framework/Foundation', '/System/Library/Frameworks/UIKit.framework/UIKit']! {
				if _ := runtime_symbol(wrong, symbol) { assert false, wrong }
			}
		}
		for i, name in ['_value', '_param']! {
			ivar := objc_find_ivar(cls, name.str)
			assert ivar != 0
			assert objc_ivar_offset(ivar) == if i == 0 { 8 } else { 16 }
			assert ctext(u64(objc_ivar_types(ivar))) == if i == 0 { 'f' } else { '@"NSString"' }
		}
		for i, selector in ['initWithParameterID:value:', 'parameterID', 'value', 'setValue:']! {
			method := objc_instance_method(cls, u64(selector.str))
			assert method != 0
			assert ctext(u64(objc_method_types(method))) == ['@28@0:8@16f24', '@16@0:8', 'f16@0:8', 'v20@0:8f16']![i]
		}
		baseline := ios_runtime.live
		id := haptic_parameter_msg(haptic_parameter_msg(ios_runtime.names['NSMutableString'], c'alloc', 0), c'initWithUTF8String:', u64(c'CustomHapticParameter'))
		object := haptic_parameter_init(haptic_parameter_msg(cls, c'alloc', 0), id, 0x3e800000)
		assert object != 0 && objc_is_kind(object, ios_runtime.names['NSObject'])
		assert haptic_parameter_value(object) == 0x3e800000
		assert haptic_parameter_msg(object, c'parameterID', 0) == id
		assert obj_header(id).refs == 2
		suffix := owned_string('-changed')
		haptic_parameter_msg(id, c'appendString:', suffix)
		objc_release(suffix)
		objc_release(id)
		assert string_text(haptic_parameter_msg(object, c'parameterID', 0)) == 'CustomHapticParameter-changed'
		assert obj_header(id).refs == 1
		assert haptic_parameter_init(object, id, 0x80000000) == object
		assert obj_header(id).refs == 1 && haptic_parameter_value(object) == 0x80000000
		replacement := owned_string('replacement')
		assert haptic_parameter_init(object, replacement, 0) == object
		assert id !in ios_runtime.objects
		objc_release(replacement)
		assert haptic_parameter_init(object, 0, 0xbf000000) == object
		assert replacement !in ios_runtime.objects
		assert haptic_parameter_msg(object, c'parameterID', 0) == 0
		for raw in [u32(0), 0x80000000, 0xbf800000, 0x40000000, 0x7f800000, 0xff800000, 0x7fc01234]! {
			assert haptic_parameter_init(object, 0, raw) == object
			assert haptic_parameter_value(object) == raw
			unsafe { HapticParameterSet(voidptr(C.ios_objc_msgsend))(object, u64(c'setValue:'), bits.f32_from_bits(raw)) }
			assert haptic_parameter_value(object) == raw
		}
		for selector in ['initWithParameterID:value:', 'parameterID', 'value', 'setValue:']! {
			assert objc_responds(object, selector.str)
		}
		for selector in ['init', 'new', 'copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding', 'classForCoder']! {
			assert objc_instance_method(cls, u64(selector.str)) == 0
			assert objc_class_method(cls, u64(selector.str)) == 0
			assert !objc_responds(object, selector.str) && !objc_responds(cls, selector.str)
		}
		objc_release(object)
		assert ios_runtime.live == baseline
		// Draining an autoreleased parameter also releases its retained identifier.
		final_id := owned_string('drained')
		objc_autorelease(haptic_parameter_init(objc_allocate(cls), final_id, 0))
		objc_release(final_id)
		objc_pool_pop(pool)
		assert final_id !in ios_runtime.objects && ios_runtime.live == baseline
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-HAPTICEVENTPARAMETER: scoped imports, native metadata, retained identifiers, exact float bits and two drained runtimes')
}

fn test_haptic_parameter_rejections() {
	objc_start()
	cls := ios_runtime.names['CHHapticEventParameter']
	sub := objc_allocate_class(cls, c'BlockedHapticParameter', 0)
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
				'caller' { mut storage := [3]u64{}; objc_construct_instance(cls, u64(unsafe { &storage[0] })) }
				'install' { mut storage := [3]u64{}; objc_install_storage(cls, u64(unsafe { &storage[0] }), true) }
				'isa-in' { objc_set_class(objc_allocate(ios_runtime.names['NSObject']), cls) }
				'isa-out' { objc_set_class(objc_allocate(cls), ios_runtime.names['NSObject']) }
				'invalid-storage' {
					object := objc_allocate(cls)
					obj_header(object).caller_storage = true
					haptic_parameter_msg(object, c'parameterID', 0)
				}
				'super-init', 'super-new', 'super-copy' {
					selector := if mode == 'super-init' { c'init' } else if mode == 'super-copy' { c'copy' } else { c'new' }
					method := if mode == 'super-new' { objc_class_method(ios_runtime.names['NSObject'], u64(selector)) } else { objc_instance_method(ios_runtime.names['NSObject'], u64(selector)) }
					assert method != 0
					unsafe { HapticParameterSend(voidptr(objc_method_imp(method)))(if mode == 'super-new' { cls } else { objc_allocate(cls) }, u64(selector), 0, 0) }
				}
				else { haptic_parameter_msg(if mode == 'new' { cls } else { objc_allocate(cls) }, mode.str, 0) }
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
		reason := if mode in ['subclass', 'metaclass']! { 'subclass or metaclass construction is not implemented' } else if mode in ['caller', 'install']! { 'caller storage is not implemented' } else if mode.starts_with('isa-') { 'changing CHHapticEventParameter storage isa is not implemented' } else if mode == 'invalid-storage' { 'requires live owned parameter storage' } else { 'unsupported CHHapticEventParameter method:' }
		assert output.contains(reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:') && !output.contains('> assert '), mode + ': ' + output
	}
	objc_stop()
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	println('IOS-HAPTICEVENTPARAMETER-REJECT: 14 subclass, metaclass, caller storage, unsupported method, saved NSObject IMP, isa and invalid storage cases fail explicitly')
}
