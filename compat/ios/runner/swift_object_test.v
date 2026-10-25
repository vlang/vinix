// SPDX-License-Identifier: GPL-2.0-or-later
module main

type SwiftObjectSend = fn (u64, u64, u64, u64) u64

fn swift_object_msg(object u64, selector &char, a u64, b u64) u64 {
	return unsafe { SwiftObjectSend(voidptr(C.ios_objc_msgsend))(object, u64(selector), a, b) }
}

fn test_swift_object_descriptors() {
	for _ in 0 .. 2 {
		objc_start()
		pool := objc_pool_push()
		cls := ios_runtime.names['_TtCs12_SwiftObject']
		meta := read64(cls)
		assert cls != 0 && objc_class_parent(cls) == 0
		assert objc_class_parent(meta) == cls && read64(meta) == meta
		assert !objc_class_meta(cls) && objc_class_meta(meta)
		assert objc_class_size(cls) == 16 && ctext(u64(objc_class_name(cls))) == '_TtCs12_SwiftObject'
		ivar := objc_find_ivar(cls, c'isa')
		assert ivar != 0 && objc_ivar_offset(ivar) == 0
		assert ctext(u64(objc_ivar_name(ivar))) == 'isa' && ctext(u64(objc_ivar_types(ivar))) == '#'
		protocol := ios_runtime.protocol_names['NSObject']
		assert objc_class_conforms(cls, protocol)
		for prefix in ['_OBJC_CLASS_$_', '_OBJC_METACLASS_$_']! {
			symbol := prefix + '_TtCs12_SwiftObject'
			assert runtime_symbol('/usr/lib/swift/libswiftCore.dylib', symbol)! == if prefix == '_OBJC_CLASS_$_' { cls } else { meta }
			for wrong in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/System/Library/Frameworks/UIKit.framework/UIKit', '/System/Library/Frameworks/AVFoundation.framework/AVFoundation', '/usr/lib/libobjc.A.dylib']! {
				if _ := runtime_symbol(wrong, symbol) { assert false, wrong + ': ' + symbol }
			}
		}
		sub := objc_allocate_class(cls, c'VinixSwiftRoot', 0)
		objc_register_class(sub)
		assert objc_class_parent(sub) == cls && objc_class_parent(read64(sub)) == meta
		assert read64(read64(sub)) == meta && objc_class_size(sub) == 16
		assert objc_find_ivar(sub, c'isa') == ivar
		assert !swift_object_family(ios_runtime.names['NSObject'])
		selectors := [c'class', c'superclass', c'self', c'isKindOfClass:', c'respondsToSelector:', c'conformsToProtocol:']!
		encodings := ['#16@0:8', '#16@0:8', '@16@0:8', 'B24@0:8#16', 'B24@0:8:16', 'B24@0:8@16']!
		for target in [cls, sub]! {
			assert swift_object_family(target) && swift_object_family(read64(target))
			assert swift_object_msg(target, c'class', 0, 0) == target
			assert swift_object_msg(target, c'self', 0, 0) == target
			assert swift_object_msg(target, c'superclass', 0, 0) == objc_class_parent(target)
			assert swift_object_msg(target, c'isKindOfClass:', cls, 0) == 1
			assert swift_object_msg(target, c'isKindOfClass:', ios_runtime.names['NSObject'], 0) == 0
			assert swift_object_msg(target, c'conformsToProtocol:', protocol, 0) == 1
			for i, selector in selectors {
				for method in [objc_instance_method(target, u64(selector)), objc_class_method(target, u64(selector))]! {
					assert method != 0 && objc_method_name(method) != 0
					assert ctext(u64(objc_method_types(method))) == encodings[i]
				}
				assert objc_responds(target, selector)
				assert swift_object_msg(target, c'respondsToSelector:', u64(selector), 0) == 1
			}
			for selector in [c'alloc', c'allocWithZone:', c'new', c'init', c'copy', c'copyWithZone:', c'mutableCopy', c'retain', c'release', c'autorelease', c'forwardInvocation:', c'methodSignatureForSelector:', c'forwardingTargetForSelector:', c'description', c'notASwiftObjectMethod']! {
				assert objc_instance_method(target, u64(selector)) == 0
				assert objc_class_method(target, u64(selector)) == 0
				assert !objc_responds(target, selector)
				assert swift_object_msg(target, c'respondsToSelector:', u64(selector), 0) == 0
			}
		}
		objc_pool_pop(pool)
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-SWIFT-OBJECT: scoped imports, independent root, isa ivar, NSObject protocol, six typed methods, subclass metadata and two drained runtimes')
}

fn test_swift_object_construction_rejected() {
	objc_start()
	cls := ios_runtime.names['_TtCs12_SwiftObject']
	sub := objc_allocate_class(cls, c'BlockedSwiftRoot', 0)
	objc_register_class(sub)
	for target in [cls, sub]! {
		for mode in ['alloc', 'allocWithZone:', 'new', 'init', 'copy', 'retain', 'release', 'autorelease', 'forwardInvocation:', 'methodSignatureForSelector:', 'allocate', 'caller', 'install', 'metaclass', 'super-alloc', 'super-new', 'missing-imp', 'isa-in', 'isa-subclass', 'isa-out']! {
			mut fds := [2]i32{}
			assert C.pipe(unsafe { &fds[0] }) == 0
			pid := C.fork()
			assert pid >= 0
			if pid == 0 {
				C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
				match mode {
					'allocate' { objc_allocate(target) }
					'caller' { mut storage := [2]u64{}; objc_construct_instance(target, u64(unsafe { &storage[0] })) }
					'install' { mut storage := [2]u64{}; objc_install_storage(target, u64(unsafe { &storage[0] }), true) }
					'metaclass' { objc_allocate(read64(target)) }
					'super-alloc', 'super-new', 'missing-imp' {
						selector := if mode == 'super-alloc' { c'alloc' } else if mode == 'super-new' { c'new' } else { c'notASwiftObjectMethod' }
						imp := if mode == 'missing-imp' { objc_method_implementation(read64(target), u64(selector)) } else { objc_method_imp(objc_class_method(ios_runtime.names['NSObject'], u64(selector))) }
						assert imp != 0
						unsafe { SwiftObjectSend(voidptr(imp))(target, u64(selector), 0, 0) }
					}
					'isa-in', 'isa-subclass' { objc_set_class(objc_allocate(ios_runtime.names['NSObject']), if mode == 'isa-in' { target } else { sub }) }
					'isa-out' {
						object := objc_allocate(ios_runtime.names['NSObject'])
						// Simulate corrupt storage without constructing a Swift object.
						obj_header(object).allocation_cls = target
						objc_set_class(object, ios_runtime.names['NSObject'])
					}
					else { swift_object_msg(target, mode.str, 0, 0) }
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
			reason := if mode.starts_with('isa-') { 'changing SwiftObject storage isa is not implemented' } else { 'SwiftObject construction and Objective-C instance operations are not implemented' }
			assert output.contains(reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:') && !output.contains('> assert '), mode + ': ' + output
		}
	}
	objc_stop()
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	println('IOS-SWIFT-OBJECT-REJECT: 40 dispatch, forwarding, direct/caller allocation, metaclass, subclass, saved NSObject IMP and isa cases fail explicitly')
}
