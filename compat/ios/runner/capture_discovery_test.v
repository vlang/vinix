// SPDX-License-Identifier: GPL-2.0-or-later
module main

type CaptureDiscoverySend = fn (u64, u64, u64, u64, u64) u64

fn capture_msg(object u64, selector &char, a u64, b u64, c u64) u64 {
	return unsafe { CaptureDiscoverySend(voidptr(C.ios_objc_msgsend))(object, u64(selector), a, b, c) }
}

fn capture_factory(types u64, media u64, position u64) u64 {
	return capture_msg(ios_runtime.names['AVCaptureDeviceDiscoverySession'], c'discoverySessionWithDeviceTypes:mediaType:position:', types, media, position)
}

fn capture_reader(types u64, media u64, empty u64) {
	pool := objc_pool_push()
	for i in 0 .. 128 {
		object := capture_factory(types, media, u64(i % 3))
		assert capture_msg(object, c'devices', 0, 0, 0) == empty
		assert capture_msg(object, c'supportedMultiCamDeviceSets', 0, 0, 0) == empty
	}
	objc_pool_pop(pool)
}

fn test_capture_discovery() {
	for _ in 0 .. 2 {
		objc_start()
		pool := objc_pool_push()
		cls := ios_runtime.names['AVCaptureDeviceDiscoverySession']
		library := '/System/Library/Frameworks/AVFoundation.framework/AVFoundation'
		for prefix in ['_OBJC_CLASS_$_', '_OBJC_METACLASS_$_']! {
			symbol := prefix + 'AVCaptureDeviceDiscoverySession'
			assert runtime_symbol(library, symbol)! == if prefix == '_OBJC_CLASS_$_' { cls } else { read64(cls) }
			for wrong in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libobjc.A.dylib']! {
				if _ := runtime_symbol(wrong, symbol) { assert false }
			}
		}
		if _ := capture_discovery_symbol('_OBJC_CLASS_$_AVCaptureDeviceDiscoverySessionUnknown') { assert false }
		assert objc_class_size(cls) == 48 && objc_class_parent(cls) == ios_runtime.names['NSObject']
		types := objc_allocate(ios_runtime.names['NSMutableArray'])
		device := owned_string('AVCaptureDeviceTypeBuiltInWideAngleCamera')
		media := owned_string('vide')
		capture_msg(types, c'addObject:', device, 0, 0)
		objc_release(device)
		object := capture_factory(types, media, 0)
		empty := capture_msg(object, c'devices', 0, 0, 0)
		assert empty != 0 && objc_is_kind(empty, ios_runtime.names['NSArray'])
		assert capture_msg(empty, c'count', 0, 0, 0) == 0
		assert capture_msg(object, c'supportedMultiCamDeviceSets', 0, 0, 0) == empty
		assert capture_msg(object, c'class', 0, 0, 0) == cls
		// Empty and unknown criteria are valid with no available hardware.
		plain := objc_allocate(ios_runtime.names['NSArray'])
		unknown := owned_string('VinixUnknownDeviceType')
		capture_msg(types, c'addObject:', unknown, 0, 0)
		objc_release(unknown)
		for position in 0 .. 3 {
			assert capture_msg(capture_factory(plain, 0, u64(position)), c'devices', 0, 0, 0) == empty
			assert capture_msg(capture_factory(types, media, u64(position)), c'devices', 0, 0, 0) == empty
		}
		objc_release(plain)
		for meta in [false, true]! {
			for selector in ['discoverySessionWithDeviceTypes:mediaType:position:', 'devices', 'supportedMultiCamDeviceSets']! {
				expected := capture_discovery_types('AVCaptureDeviceDiscoverySession', meta, selector)
				method := if meta { objc_class_method(cls, u64(selector.str)) } else { objc_instance_method(cls, u64(selector.str)) }
				receiver := if meta { cls } else { object }
				if encoding := expected {
					assert method != 0 && ctext(u64(objc_method_types(method))) == encoding
					assert objc_responds(receiver, selector.str)
					signature := capture_msg(receiver, c'methodSignatureForSelector:', u64(selector.str), 0, 0)
					assert capture_msg(signature, c'numberOfArguments', 0, 0, 0) == if meta { u64(5) } else { u64(2) }
					assert ctext(capture_msg(signature, c'methodReturnType', 0, 0, 0)) == '@'
					imp := objc_method_imp(method)
					assert imp != 0
					result := unsafe { CaptureDiscoverySend(voidptr(imp))(receiver, u64(selector.str), types, media, 2) }
					if meta { assert capture_msg(result, c'devices', 0, 0, 0) == empty } else { assert result == empty }
				} else {
					assert method == 0 && !objc_responds(receiver, selector.str)
				}
			}
		}
		for selector in [c'alloc', c'allocWithZone:', c'new', c'init', c'copy', c'copyWithZone:', c'mutableCopy', c'mutableCopyWithZone:', c'initWithCoder:', c'encodeWithCoder:', c'supportsSecureCoding', c'classForCoder', c'addObserver:forKeyPath:options:context:', c'removeObserver:forKeyPath:', c'removeObserver:forKeyPath:context:']! {
			assert !objc_responds(object, selector) && !objc_responds(cls, selector)
			assert objc_instance_method(cls, u64(selector)) == 0 && objc_class_method(cls, u64(selector)) == 0
		}
		baseline := ios_runtime.live
		mut workers := []thread{}
		for _ in 0 .. 4 { workers << spawn capture_reader(types, media, empty) }
		workers.wait()
		unsafe { workers.free() }
		assert ios_runtime.live == baseline
		nested := objc_pool_push()
		survivor := capture_factory(types, media, 1)
		objc_retain(survivor)
		objc_pool_pop(nested)
		objc_release(types)
		objc_release(media)
		assert capture_msg(survivor, c'devices', 0, 0, 0) == empty
		objc_release(survivor)
		assert capture_msg(empty, c'count', 0, 0, 0) == 0
		objc_pool_pop(pool)
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.block_refs.len == 0
	}
	println('IOS-CAPTURE-DISCOVERY: scoped imports, validated criteria, empty immutable results, typed reflection, saved IMPs, four workers and two drained runtimes')
}

fn test_capture_discovery_rejections() {
	objc_start()
	pool := objc_pool_push()
	cls := ios_runtime.names['AVCaptureDeviceDiscoverySession']
	types := objc_allocate(ios_runtime.names['NSMutableArray'])
	object := capture_factory(types, 0, 0)
	for mode in ['alloc', 'allocWithZone:', 'new', 'init', 'copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding', 'classForCoder', 'allocate', 'directcopy', 'directzonecopy', 'caller', 'subclass', 'subclass-factory', 'isa-out', 'isa-in', 'types-nil', 'types-object', 'types-item', 'media-object', 'position-three', 'position-negative', 'getter-class', 'factory-instance', 'immutable', 'storage', 'addObserver:forKeyPath:options:context:', 'removeObserver:forKeyPath:', 'removeObserver:forKeyPath:context:']! {
		mut fds := [2]i32{}
		assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.fork()
		assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			match mode {
				'allocate' { objc_allocate(cls) }
				'directcopy', 'directzonecopy' { objc_copy_value(object, mode == 'directzonecopy') }
				'caller' { mut storage := [6]u64{}; objc_construct_instance(cls, u64(unsafe { &storage[0] })) }
				'subclass', 'subclass-factory' {
					sub := objc_allocate_class(cls, c'VinixCaptureDiscovery', 0); objc_register_class(sub)
					if mode == 'subclass' { objc_allocate(sub) } else { capture_msg(sub, c'discoverySessionWithDeviceTypes:mediaType:position:', types, 0, 0) }
				}
				'isa-out' { objc_set_class(object, ios_runtime.names['NSObject']) }
				'isa-in' { objc_set_class(objc_allocate(ios_runtime.names['NSObject']), cls) }
				'types-nil' { capture_factory(0, 0, 0) }
				'types-object' { capture_factory(object, 0, 0) }
				'types-item' { capture_msg(types, c'addObject:', object, 0, 0); capture_factory(types, 0, 0) }
				'media-object' { capture_factory(types, object, 0) }
				'position-three' { capture_factory(types, 0, 3) }
				'position-negative' { capture_factory(types, 0, ~u64(0)) }
				'getter-class' { capture_msg(cls, c'devices', 0, 0, 0) }
				'factory-instance' { capture_msg(object, c'discoverySessionWithDeviceTypes:mediaType:position:', types, 0, 0) }
				'immutable' { capture_msg(capture_msg(object, c'devices', 0, 0, 0), c'addObject:', object, 0, 0) }
				'storage' { mut header := obj_header(object); header.native_size = 16; capture_msg(object, c'devices', 0, 0, 0) }
				'alloc', 'allocWithZone:', 'new' { capture_msg(cls, mode.str, 0, 0, 0) }
				else { capture_msg(object, mode.str, 0, 0, 0) }
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
		reason := match mode {
			'isa-out', 'isa-in' { 'changing capture discovery storage isa is not implemented' }
			'subclass-factory' { 'custom capture discovery subclasses are not implemented' }
			'types-nil', 'types-object' { 'requires an NSArray of NSString device types' }
			'types-item' { 'requires NSString device types' }
			'media-object' { 'requires NSString media type or nil' }
			'position-three', 'position-negative' { 'requires position 0, 1 or 2' }
			'getter-class', 'factory-instance' { 'unimplemented Objective-C method' }
			'immutable' { 'mutation of the immutable empty array' }
			'storage' { 'capture discovery requires live built-in storage' }
			else { 'AVCaptureDeviceDiscoverySession requires discovery factory' }
		}
		assert output.contains(reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), mode + ': ' + output
	}
	objc_release(types)
	objc_pool_pop(pool)
	objc_stop()
	assert ios_runtime.live == 0
	println('IOS-CAPTURE-DISCOVERY-REJECT: 33 construction, copy, coding, caller storage, subclass, isa, criteria, receiver, mutation, storage and observation cases fail explicitly')
}
