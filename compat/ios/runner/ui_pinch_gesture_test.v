// SPDX-License-Identifier: GPL-2.0-or-later
module main

type PinchGestureSend = fn (u64, u64, u64, u64) u64

fn pinch_gesture_msg(object u64, selector &char, a u64, b u64) u64 {
	return unsafe { PinchGestureSend(voidptr(C.ios_objc_msgsend))(object, u64(selector), a, b) }
}

fn test_pinch_gesture_descriptors() {
	for _ in 0 .. 2 {
		objc_start()
		pool := objc_pool_push()
		pinch := ios_runtime.names['UIPinchGestureRecognizer']
		base := ios_runtime.names['UIGestureRecognizer']
		assert objc_class_parent(pinch) == base
		assert objc_class_parent(read64(pinch)) == read64(base)
		assert !pan_descriptor_family(pinch)
		for name in ['UIPinchGestureRecognizer']! {
			cls := ios_runtime.names[name]
			assert ctext(u64(objc_class_name(cls))) == name
			assert !objc_class_meta(cls) && objc_class_meta(read64(cls))
			// These are shim descriptors, not a claim about Apple's private layout.
			assert objc_class_size(cls) == objc_class_size(ios_runtime.names['UIGestureRecognizer'])
			framework := 'UIKit'
			for prefix in ['_OBJC_CLASS_$_', '_OBJC_METACLASS_$_']! {
				symbol := prefix + name
				assert runtime_symbol('/System/Library/Frameworks/' + framework + '.framework/' + framework, symbol)! == if prefix == '_OBJC_CLASS_$_' { cls } else { read64(cls) }
				for wrong in ['Foundation', 'UIKit', 'GameKit', 'GameController']! {
					if wrong == framework { continue }
					if _ := runtime_symbol('/System/Library/Frameworks/' + wrong + '.framework/' + wrong, symbol) { assert false, wrong + ': ' + symbol }
				}
				if _ := runtime_symbol('/usr/lib/libobjc.A.dylib', symbol) { assert false }
			}
			assert pinch_descriptor_family(cls) && pinch_descriptor_family(read64(cls))
			assert pinch_gesture_msg(cls, c'class', 0, 0) == cls
			assert objc_class_method(cls, u64(c'class')) != 0
			sub_name := 'Vinix' + name
			sub := objc_allocate_class(cls, sub_name.str, 0)
			objc_register_class(sub)
			assert objc_class_parent(sub) == cls && pinch_descriptor_family(sub)
			for target in [cls, sub]! {
				for selector in [c'alloc', c'allocWithZone:', c'new', c'init', c'initWithCoder:',
					c'initWithTarget:action:', c'initWithFrame:',
					c'copy', c'copyWithZone:', c'mutableCopy', c'mutableCopyWithZone:',
					c'encodeWithCoder:', c'supportsSecureCoding', c'classForCoder',
					c'scale', c'setScale:', c'velocity', c'state', c'view', c'delegate', c'setDelegate:']! {
					assert objc_instance_method(target, u64(selector)) == 0, ctext(u64(selector))
					assert objc_class_method(target, u64(selector)) == 0, ctext(u64(selector))
					assert !objc_responds(target, selector), ctext(u64(selector))
				}
			}
		}
		assert !pinch_descriptor_family(ios_runtime.names['UIGestureRecognizer'])
		for name in ['UIGestureRecognizer', 'UISwipeGestureRecognizer']! {
			cls := ios_runtime.names[name]
			assert !pinch_descriptor_family(cls)
			object := objc_allocate(cls)
			assert pinch_gesture_msg(object, c'initWithTarget:action:', 0, 0) == object
			assert objc_is_kind(object, ios_runtime.names['UIGestureRecognizer'])
			objc_release(object)
		}
		objc_pool_pop(pool)
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-PINCHGESTURE: scoped class/metaclass imports, SDK pinch inheritance, subclass metadata, truthful reflection, existing swipe construction and two drained runtimes')
}

fn test_pinch_gesture_construction_rejected() {
	objc_start()
	for name in ['UIPinchGestureRecognizer']! {
		cls := ios_runtime.names[name]
		sub_name := 'Blocked' + name
		sub := objc_allocate_class(cls, sub_name.str, 0)
		objc_register_class(sub)
		for mode in ['alloc', 'allocWithZone:', 'new', 'init', 'initWithTarget:action:', 'super-init', 'copy',
			'allocate', 'caller', 'install', 'subclass', 'super-alloc', 'super-new', 'isa-in', 'isa-subclass', 'isa-out']! {
			mut fds := [2]i32{}
			assert C.pipe(unsafe { &fds[0] }) == 0
			pid := C.fork()
			assert pid >= 0
			if pid == 0 {
				C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
				match mode {
					'allocate' { objc_allocate(cls) }
					'caller' { mut storage := [1]u64{}; objc_construct_instance(cls, u64(unsafe { &storage[0] })) }
					'install' { mut storage := [1]u64{}; objc_install_storage(cls, u64(unsafe { &storage[0] }), true) }
					'subclass' { objc_allocate(sub) }
					'super-alloc', 'super-new', 'super-init' {
						selector := if mode == 'super-alloc' { c'alloc' } else if mode == 'super-init' { c'init' } else { c'new' }
						method := if mode == 'super-init' { objc_instance_method(ios_runtime.names['NSObject'], u64(selector)) } else { objc_class_method(ios_runtime.names['NSObject'], u64(selector)) }
						assert method != 0
						unsafe { PinchGestureSend(voidptr(objc_method_imp(method)))(cls, u64(selector), 0, 0) }
					}
					'isa-in', 'isa-subclass' { objc_set_class(objc_allocate(ios_runtime.names['NSObject']), if mode == 'isa-in' { cls } else { sub }) }
					'isa-out' {
						object := objc_allocate(ios_runtime.names['NSObject'])
						// Simulate a corrupt allocation header without constructing a pinch recognizer.
						obj_header(object).allocation_cls = cls
						objc_set_class(object, ios_runtime.names['NSObject'])
					}
					else { pinch_gesture_msg(cls, mode.str, 0, 0) }
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
			assert C.ios_waitpid(pid, &status, 0) == pid && status == 256, name + ': ' + mode
			output := unsafe { tos(&bytes[0], length) }
			reason := if mode.starts_with('isa-') { 'changing pinch gesture storage isa is not implemented' } else { 'pinch gesture construction requires an implemented continuous two-touch lifecycle' }
			assert output.contains(reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:') && !output.contains('> assert '), name + ': ' + mode + ': ' + output
		}
	}
	objc_stop()
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	println('IOS-PINCHGESTURE-REJECT: 16 dispatch, direct/caller allocation, subclass, saved NSObject allocation/init IMP and isa cases fail explicitly')
}
