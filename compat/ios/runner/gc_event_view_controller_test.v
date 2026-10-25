// SPDX-License-Identifier: GPL-2.0-or-later
module main

type EventControllerSend = fn (u64, u64, u64, u64) u64

struct EventControllerSuper {
	object u64
	cls u64
}

fn event_controller_msg(object u64, selector &char, argument u64) u64 {
	return unsafe { EventControllerSend(voidptr(C.ios_objc_msgsend))(object, u64(selector), argument, 0) }
}

fn event_controller_init(object u64, selector &char) u64 {
	mut context := EventControllerSuper{object, read64(object)}
	return unsafe { EventControllerSend(voidptr(C.ios_objc_super))(u64(&context), u64(selector), 0, 0) }
}

fn event_controller_override(object u64, selector &char) u64 {
	return 1
}

fn test_event_controller_configuration() {
	for _ in 0 .. 2 {
		objc_start()
		pool := objc_pool_push()
		cls := ios_runtime.names['GCEventViewController']
		assert objc_class_parent(cls) == ios_runtime.names['UIViewController']
		assert objc_class_parent(read64(cls)) == read64(ios_runtime.names['UIViewController'])
		assert objc_class_size(cls) == 1112
		assert !objc_class_meta(cls) && objc_class_meta(read64(cls))
		for prefix in ['_OBJC_CLASS_$_', '_OBJC_METACLASS_$_']! {
			symbol := prefix + 'GCEventViewController'
			assert runtime_symbol('/System/Library/Frameworks/GameController.framework/GameController', symbol)! == if prefix == '_OBJC_CLASS_$_' { cls } else { read64(cls) }
			for wrong in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libobjc.A.dylib']! {
				if _ := runtime_symbol(wrong, symbol) { assert false, wrong }
			}
		}
		for i, selector in ['init', 'initWithNibName:bundle:', 'controllerUserInteractionEnabled', 'setControllerUserInteractionEnabled:']! {
			method := objc_instance_method(cls, u64(selector.str))
			assert method != 0
			assert ctext(u64(objc_method_types(method))) == ['@16@0:8', '@32@0:8@16@24', 'B16@0:8', 'v20@0:8B16']![i]
		}
		// Catalyst private ivars are not a public iOS layout contract.
		assert objc_find_ivar(cls, c'_controllerUserInteractionEnabled') == 0
		baseline := ios_runtime.live
		for mode in 0 .. 4 {
			object := if mode == 0 { event_controller_msg(cls, c'new', 0) } else { objc_allocate(cls) }
			if mode == 1 { assert event_controller_msg(object, c'init', 0) == object }
			if mode == 2 { assert event_controller_msg(object, c'initWithNibName:bundle:', 0) == object }
			if mode == 3 {
				saved := objc_method_imp(objc_instance_method(ios_runtime.names['NSObject'], u64(c'init')))
				assert unsafe { EventControllerSend(voidptr(saved))(object, u64(c'init'), 0, 0) } == object
			}
			assert event_controller_msg(object, c'controllerUserInteractionEnabled', 0) == 0
			for raw in [u64(1), 2, 0, 256, 0x8000000000000000, 257]! {
				event_controller_msg(object, c'setControllerUserInteractionEnabled:', raw)
				assert event_controller_msg(object, c'controllerUserInteractionEnabled', 0) == u64(u8(raw) != 0)
			}
			assert event_controller_msg(object, c'init', 0) == object
			assert event_controller_msg(object, c'initWithNibName:bundle:', 0) == object
			assert event_controller_msg(object, c'controllerUserInteractionEnabled', 0) == 1
			view := event_controller_msg(object, c'view', 0)
			assert view != 0 && event_controller_msg(object, c'view', 0) == view
			replacement := objc_new(ios_runtime.names['UIView'])
			event_controller_msg(object, c'setView:', replacement)
			assert event_controller_msg(object, c'view', 0) == replacement
			objc_release(replacement)
			assert replacement in ios_runtime.objects
			objc_release(object)
			assert view !in ios_runtime.objects && replacement !in ios_runtime.objects
			assert ios_runtime.live == baseline
		}
		sub := objc_allocate_class(cls, c'VinixEventController', 0)
		assert objc_add_ivar(sub, c'_tag', 8, 3, c'q')
		assert objc_add_method(sub, u64(c'init'), u64(unsafe { voidptr(event_controller_init) }), c'@16@0:8')
		assert objc_add_method(sub, u64(c'controllerUserInteractionEnabled'), u64(unsafe { voidptr(event_controller_override) }), c'B16@0:8')
		objc_register_class(sub)
		assert objc_ivar_offset(objc_find_ivar(sub, c'_tag')) == 1112 && objc_class_size(sub) == 1120
		instance := objc_new(sub)
		unsafe { *(&u64(instance + 1112)) = 0x123456789abcdef0 }
		assert event_controller_msg(instance, c'controllerUserInteractionEnabled', 0) == 1
		saved := objc_method_imp(objc_instance_method(cls, u64(c'controllerUserInteractionEnabled')))
		assert unsafe { EventControllerSend(voidptr(saved))(instance, u64(c'controllerUserInteractionEnabled'), 0, 0) } == 0
		event_controller_msg(instance, c'setControllerUserInteractionEnabled:', 1)
		assert event_controller_msg(instance, c'init', 0) == instance
		assert unsafe { EventControllerSend(voidptr(saved))(instance, u64(c'controllerUserInteractionEnabled'), 0, 0) } == 1
		assert read64(instance + 1112) == 0x123456789abcdef0
		for selector in ['copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding', 'classForCoder']! {
			assert objc_instance_method(sub, u64(selector.str)) == 0 && !objc_responds(instance, selector.str)
			assert objc_class_method(cls, u64(selector.str)) == 0 && !objc_responds(cls, selector.str)
		}
		objc_autorelease(instance)
		objc_pool_pop(pool)
		objc_dispose_class(sub)
		assert ios_runtime.live == baseline
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-GCEVENT: scoped imports, iOS hierarchy, BOOL state, subclass/saved IMP, UIKit view and two drained runtimes')
}

fn test_event_controller_rejections() {
	objc_start()
	cls := ios_runtime.names['GCEventViewController']
	for mode in ['caller', 'install', 'isa-in', 'isa-out', 'raw-getter', 'raw-setter', 'invalid-storage', 'forged-isa', 'nib', 'bundle', 'direct-copy', 'saved-copy', 'copy', 'mutableCopy', 'initWithCoder:', 'encodeWithCoder:']! {
		mut fds := [2]i32{}
		assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.fork()
		assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			match mode {
				'caller' { mut storage := [139]u64{}; objc_construct_instance(cls, u64(unsafe { &storage[0] })) }
				'install' { mut storage := [139]u64{}; objc_install_storage(cls, u64(unsafe { &storage[0] }), true) }
				'isa-in' { objc_set_class(objc_allocate(ios_runtime.names['NSObject']), cls) }
				'isa-out' { objc_set_class(objc_allocate(cls), ios_runtime.names['NSObject']) }
				'raw-getter' { event_controller_msg(objc_allocate(cls), c'controllerUserInteractionEnabled', 0) }
				'raw-setter' { event_controller_msg(objc_allocate(cls), c'setControllerUserInteractionEnabled:', 1) }
				'invalid-storage' {
					object := objc_new(cls); obj_header(object).caller_storage = true
					event_controller_msg(object, c'controllerUserInteractionEnabled', 0)
				}
				'forged-isa' {
					object := objc_allocate(ios_runtime.names['NSObject']); unsafe { *(&u64(object)) = cls }
					event_controller_msg(object, c'controllerUserInteractionEnabled', 0)
				}
				'nib', 'bundle' {
					object := objc_allocate(cls)
					nib := if mode == 'nib' { u64(1) } else { u64(0) }
					bundle := if mode == 'bundle' { u64(1) } else { u64(0) }
					unsafe { EventControllerSend(voidptr(C.ios_objc_msgsend))(object, u64(c'initWithNibName:bundle:'), nib, bundle) }
				}
				'direct-copy' { objc_copy_value(objc_new(cls), true) }
				'saved-copy' {
					saved := objc_method_imp(objc_instance_method(ios_runtime.names['NSObject'], u64(c'copy')))
					unsafe { EventControllerSend(voidptr(saved))(objc_new(cls), u64(c'copy'), 0, 0) }
				}
				else { event_controller_msg(objc_new(cls), mode.str, 0) }
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
		reason := if mode in ['caller', 'install']! { 'caller storage is not implemented' } else if mode.starts_with('isa-') { 'changing GCEventViewController storage isa is not implemented' } else if mode in ['raw-getter', 'raw-setter']! { 'requires initialization' } else if mode in ['invalid-storage', 'forged-isa']! { 'requires live owned controller storage' } else if mode in ['nib', 'bundle']! { 'nib resources are not implemented' } else { 'unsupported GCEventViewController method:' }
		assert output.contains(reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:') && !output.contains('> assert '), mode + ': ' + output
	}
	objc_stop()
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	println('IOS-GCEVENT-REJECT: 16 caller storage, isa, initialization, nib, copy and coding cases fail explicitly')
}
