// SPDX-License-Identifier: GPL-2.0-or-later
module main

type AppAttestSend = fn (u64, u64, u64) u64

fn app_attest_msg(object u64, selector &char, argument u64) u64 {
	return unsafe { AppAttestSend(voidptr(C.ios_objc_msgsend))(object, u64(selector), argument) }
}

fn app_attest_first() u64 {
	return app_attest_msg(ios_runtime.names['DCAppAttestService'], c'sharedService', 0)
}

fn app_attest_reader(expected u64) {
	pool := objc_pool_push()
	for _ in 0 .. 128 {
		object := app_attest_first()
		assert object == expected
		assert app_attest_msg(object, c'isSupported', 0) == 0
		assert app_attest_msg(object, c'retain', 0) == object
		app_attest_msg(object, c'autorelease', 0)
	}
	objc_pool_pop(pool)
}

fn test_app_attest() {
	for _ in 0 .. 2 {
		objc_start()
		pool := objc_pool_push()
		cls := ios_runtime.names['DCAppAttestService']
		library := '/System/Library/Frameworks/DeviceCheck.framework/DeviceCheck'
		for prefix in ['_OBJC_CLASS_$_', '_OBJC_METACLASS_$_']! {
			symbol := prefix + 'DCAppAttestService'
			assert runtime_symbol(library, symbol)! == if prefix == '_OBJC_CLASS_$_' { cls } else { read64(cls) }
			for wrong in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libobjc.A.dylib']! {
				if _ := runtime_symbol(wrong, symbol) { assert false }
			}
		}
		if _ := app_attest_symbol('_OBJC_CLASS_$_DCAppAttestServiceUnknown') { assert false }
		// Opaque compatibility size, observed on Catalyst, not a device layout claim.
		assert objc_class_size(cls) == 16 && objc_class_parent(cls) == ios_runtime.names['NSObject']
		mut creators := []thread u64{}
		for _ in 0 .. 4 { creators << spawn app_attest_first() }
		mut object := u64(0)
		for worker in creators {
			value := worker.wait()
			assert value != 0
			if object == 0 { object = value } else { assert value == object }
		}
		unsafe { creators.free() }
		assert app_attest_first() == object && obj_header(object).refs == 1
		assert app_attest_msg(object, c'class', 0) == cls
		assert app_attest_msg(object, c'isKindOfClass:', ios_runtime.names['NSObject']) != 0
		assert app_attest_msg(object, c'isSupported', 0) == 0
		for meta in [false, true]! {
			for selector in ['sharedService', 'isSupported']! {
				expected := app_attest_types('DCAppAttestService', meta, selector)
				method := if meta { objc_class_method(cls, u64(selector.str)) } else { objc_instance_method(cls, u64(selector.str)) }
				receiver := if meta { cls } else { object }
				if types := expected {
					assert method != 0 && ctext(u64(objc_method_types(method))) == types
					assert objc_responds(receiver, selector.str)
					signature := app_attest_msg(receiver, c'methodSignatureForSelector:', u64(selector.str))
					assert signature != 0
					assert app_attest_msg(signature, c'numberOfArguments', 0) == 2
					assert ctext(app_attest_msg(signature, c'methodReturnType', 0)) == types[..1]
					imp := objc_method_imp(method)
					assert imp != 0
					result := unsafe { AppAttestSend(voidptr(imp))(receiver, u64(selector.str), 0) }
					assert result == if meta { object } else { u64(0) }
				} else {
					assert method == 0 && !objc_responds(receiver, selector.str)
				}
			}
		}
		for selector in [c'alloc', c'allocWithZone:', c'new', c'init', c'copy', c'copyWithZone:', c'mutableCopy', c'mutableCopyWithZone:', c'initWithCoder:', c'encodeWithCoder:', c'supportsSecureCoding', c'classForCoder', c'generateKeyWithCompletionHandler:', c'attestKey:clientDataHash:completionHandler:', c'generateAssertion:clientDataHash:completionHandler:']! {
			assert !objc_responds(object, selector) && !objc_responds(cls, selector)
			assert objc_instance_method(cls, u64(selector)) == 0 && objc_class_method(cls, u64(selector)) == 0
		}
		baseline := ios_runtime.live
		mut workers := []thread{}
		for _ in 0 .. 4 { workers << spawn app_attest_reader(object) }
		workers.wait()
		unsafe { workers.free() }
		assert ios_runtime.live == baseline && obj_header(object).refs == 1
		objc_pool_pop(pool)
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.block_refs.len == 0
	}
	println('IOS-APP-ATTEST: scoped imports, singleton race, unsupported availability, typed reflection, saved IMPs, four readers and two drained runtimes')
}

fn test_app_attest_rejections() {
	objc_start()
	cls := ios_runtime.names['DCAppAttestService']
	object := app_attest_first()
	for mode in ['alloc', 'allocWithZone:', 'new', 'init', 'copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding', 'classForCoder', 'allocate', 'directcopy', 'directzonecopy', 'caller', 'subclass', 'subclass-shared', 'isa-out', 'isa-in', 'destroy', 'release-borrowed', 'retired', 'generateKeyWithCompletionHandler:', 'attestKey:clientDataHash:completionHandler:', 'generateAssertion:clientDataHash:completionHandler:']! {
		mut fds := [2]i32{}
		assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.fork()
		assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			match mode {
				'allocate' { objc_allocate(cls) }
				'directcopy', 'directzonecopy' { objc_copy_value(object, mode == 'directzonecopy') }
				'caller' { mut storage := [2]u64{}; objc_construct_instance(cls, u64(unsafe { &storage[0] })) }
				'subclass', 'subclass-shared' {
					sub := objc_allocate_class(cls, c'VinixAppAttest', 0); objc_register_class(sub)
					if mode == 'subclass' { objc_allocate(sub) } else { app_attest_msg(sub, c'sharedService', 0) }
				}
				'isa-out' { objc_set_class(object, ios_runtime.names['NSObject']) }
				'isa-in' { objc_set_class(objc_allocate(ios_runtime.names['NSObject']), cls) }
				'destroy' { objc_destruct_instance(object) }
				'release-borrowed' { objc_release(object) }
				'retired' { app_attest_stop(); app_attest_msg(cls, c'sharedService', 0) }
				'alloc', 'allocWithZone:', 'new' { app_attest_msg(cls, mode.str, 0) }
				else { app_attest_msg(object, mode.str, 0) }
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
			'isa-out', 'isa-in' { 'changing App Attest storage isa is not implemented' }
			'destroy', 'release-borrowed' { 'destroying cached App Attest storage' }
			'subclass-shared' { 'custom App Attest subclasses are not implemented' }
			'retired' { 'App Attest cache is retired' }
			'generateKeyWithCompletionHandler:', 'attestKey:clientDataHash:completionHandler:', 'generateAssertion:clientDataHash:completionHandler:' { 'unimplemented Objective-C method' }
			else { 'DCAppAttestService requires sharedService' }
		}
		assert output.contains(reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), mode + ': ' + output
	}
	objc_stop()
	assert ios_runtime.live == 0
	println('IOS-APP-ATTEST-REJECT: 26 construction, copy, coding, caller storage, subclass, isa, destruction, retirement and attestation cases fail explicitly')
}
