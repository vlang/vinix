// SPDX-License-Identifier: GPL-2.0-or-later
module main

type ParticipantSend = fn (u64, u64, u64, u64) u64
type ParticipantOutcome = fn (u64, u64) u32
type ParticipantSetOutcome = fn (u64, u64, u32)
type ParticipantStatus = fn (u64, u64) i64

fn participant_msg(object u64, selector &char, argument u64) u64 {
	return unsafe { ParticipantSend(voidptr(C.ios_objc_msgsend))(object, u64(selector), argument, 0) }
}

fn participant_worker() {
	for _ in 0 .. 128 {
		pool := objc_pool_push()
		object := participant_msg(ios_runtime.names['GKTurnBasedParticipant'], c'new', 0)
		participant_msg(object, c'setMatchOutcome:', 0xff0001)
		copy := objc_copy_value(object, true)
		assert copy != object && participant_msg(copy, c'matchOutcome', 0) == 0xff0001
		assert participant_msg(object, c'init', 0) == object && participant_msg(object, c'matchOutcome', 0) == 0
		assert participant_msg(copy, c'matchOutcome', 0) == 0xff0001
		objc_release(object); objc_release(copy); objc_pool_pop(pool)
	}
}

fn test_turn_participant() {
	for _ in 0 .. 2 {
		objc_start(); system_data_start()!
		pool := objc_pool_push(); cls := ios_runtime.names['GKTurnBasedParticipant']
		for prefix in ['_OBJC_CLASS_$_', '_OBJC_METACLASS_$_']! {
			symbol := prefix + 'GKTurnBasedParticipant'
			assert runtime_symbol('/System/Library/Frameworks/GameKit.framework/GameKit', symbol)! == if prefix == '_OBJC_CLASS_$_' { cls } else { read64(cls) }
			for wrong in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/usr/lib/libobjc.A.dylib']! {
				if _ := runtime_symbol(wrong, symbol) { assert false }
			}
		}
		assert objc_class_size(cls) == 16 && objc_class_parent(cls) == ios_runtime.names['NSObject']
		assert turn_participant_family(cls) && turn_participant_family(read64(cls))
		for construction in [c'new', c'init']! {
			object := if construction == c'new' { participant_msg(cls, c'new', 0) } else { participant_msg(participant_msg(cls, c'alloc', 0), c'init', 0) }
			mut weak := u64(0); objc_store_weak(&weak, object)
			for selector in [c'init', c'player', c'playerID', c'lastTurnDate', c'timeoutDate', c'status', c'matchOutcome', c'setMatchOutcome:', c'copy', c'copyWithZone:']! {
				method := objc_instance_method(cls, u64(selector))
				assert method != 0 && objc_responds(object, selector)
				class_response := selector in [c'init', c'copy', c'copyWithZone:']!
				assert (objc_class_method(cls, u64(selector)) != 0) == class_response
				assert objc_responds(cls, selector) == class_response
				if selector in [c'copy', c'copyWithZone:']! { assert participant_msg(cls, selector, 0) == cls }
				expected := match ctext(u64(selector)) {
					'status' { 'q16@0:8' }
					'matchOutcome' { 'I16@0:8' }
					'setMatchOutcome:' { 'v20@0:8I16' }
					'copyWithZone:' { '@24@0:8^{_NSZone=}16' }
					else { '@16@0:8' }
				}
				assert ctext(u64(objc_method_types(method))) == expected
				signature := participant_msg(object, c'methodSignatureForSelector:', u64(selector))
				argc := if selector in [c'setMatchOutcome:', c'copyWithZone:']! { u64(3) } else { u64(2) }
				assert participant_msg(signature, c'numberOfArguments', 0) == argc
				assert ctext(participant_msg(signature, c'methodReturnType', 0)) == expected[..1]
				assert ctext(participant_msg(signature, c'getArgumentTypeAtIndex:', 0)) == '@'
				assert ctext(participant_msg(signature, c'getArgumentTypeAtIndex:', 1)) == ':'
				if argc == 3 { assert ctext(participant_msg(signature, c'getArgumentTypeAtIndex:', 2)) == if selector == c'setMatchOutcome:' { 'I' } else { '^{_NSZone=}' } }
				if selector in [c'player', c'playerID', c'lastTurnDate', c'timeoutDate', c'status', c'matchOutcome']! {
					assert participant_msg(object, selector, 0) == 0
					assert unsafe { ParticipantSend(voidptr(objc_method_imp(method)))(object, u64(selector), 0, 0) } == 0
				}
			}
			getter := objc_method_imp(objc_instance_method(cls, u64(c'matchOutcome')))
			setter := objc_method_imp(objc_instance_method(cls, u64(c'setMatchOutcome:')))
			status := objc_method_imp(objc_instance_method(cls, u64(c'status')))
			init_imp := objc_method_imp(objc_instance_method(ios_runtime.names['NSObject'], u64(c'init')))
			for value in [u64(0), 1, 9, 0xff0000, 0xff0001, 0xffffffffffffffff, 0x8000000000000000]! {
				participant_msg(object, c'setMatchOutcome:', value)
				assert participant_msg(object, c'matchOutcome', 0) == u64(u32(value))
				assert unsafe { ParticipantOutcome(voidptr(getter))(object, u64(c'matchOutcome')) } == u32(value)
				unsafe { ParticipantSetOutcome(voidptr(setter))(object, u64(c'setMatchOutcome:'), u32(value)) }
				assert participant_msg(object, c'matchOutcome', 0) == u64(u32(value))
				assert unsafe { ParticipantStatus(voidptr(status))(object, u64(c'status')) } == 0
				assert unsafe { ParticipantSend(voidptr(init_imp))(object, u64(c'init'), 0, 0) } == object
				assert participant_msg(object, c'matchOutcome', 0) == 0
			}
			for selector in [c'copy', c'copyWithZone:']! {
				participant_msg(object, c'setMatchOutcome:', 7)
				method := objc_instance_method(cls, u64(selector))
				copy := unsafe { ParticipantSend(voidptr(objc_method_imp(method)))(object, u64(selector), 0, 0) }
				assert copy != object && participant_msg(copy, c'matchOutcome', 0) == 7
				participant_msg(object, c'setMatchOutcome:', 8)
				assert participant_msg(copy, c'matchOutcome', 0) == 7
				participant_msg(copy, c'setMatchOutcome:', 9)
				assert participant_msg(object, c'matchOutcome', 0) == 8
				objc_release(copy)
			}
			for zone in [false, true]! {
				copy := objc_copy_value(object, zone)
				assert copy != object && participant_msg(copy, c'matchOutcome', 0) == 8
				objc_release(copy)
			}
			for selector in [c'mutableCopy', c'mutableCopyWithZone:', c'initWithCoder:', c'encodeWithCoder:', c'supportsSecureCoding', c'classForCoder', c'valueForKey:', c'valueForKeyPath:', c'setValue:forKey:', c'addObserver:forKeyPath:options:context:', c'removeObserver:forKeyPath:', c'removeObserver:forKeyPath:context:', c'setPlayer:', c'setStatus:', c'setUnknown:', c'initWithUnknown:']! {
				assert !objc_responds(object, selector) && objc_instance_method(cls, u64(selector)) == 0
				assert !objc_responds(cls, selector) && objc_class_method(cls, u64(selector)) == 0
			}
			copy := participant_msg(object, c'copy', 0)
			mut copy_weak := u64(0); objc_store_weak(&copy_weak, copy)
			objc_release(object); assert weak == 0 && copy_weak == copy
			assert participant_msg(copy, c'matchOutcome', 0) == 8
			objc_release(copy); assert copy_weak == 0
			objc_destroy_weak(&weak); objc_destroy_weak(&copy_weak)
		}
		if _ := game_center_symbol('_OBJC_CLASS_$_GKTurnBasedParticipantUnknown') { assert false }
		objc_pool_pop(pool); baseline := ios_runtime.live
		mut workers := []thread{}
		for _ in 0 .. 4 { workers << spawn participant_worker() }
		workers.wait(); unsafe { workers.free() }
		assert ios_runtime.live == baseline
		objc_stop(); system_data_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.weak.len == 0
	}
	println('IOS-GKTURNBASEDPARTICIPANT: scoped imports, native local metadata and signatures, 32-bit outcome ABI, saved IMPs, reset initialization, independent copies, weak lifetimes, four workers, two drained runtimes')
}

fn test_turn_participant_rejections() {
	objc_start(); system_data_start()!
	pool := objc_pool_push(); cls := ios_runtime.names['GKTurnBasedParticipant']
	object := participant_msg(cls, c'new', 0); plain := objc_allocate(ios_runtime.names['NSObject'])
	modes := ['caller', 'install', 'subclass', 'metaclass', 'isa-in', 'isa-out', 'raw-getter', 'raw-setter', 'raw-copy', 'storage', 'forged-isa', 'getter-class', 'setter-class', 'init-class', 'saved-wrong-receiver', 'mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding', 'classForCoder', 'valueForKey:', 'valueForKeyPath:', 'setValue:forKey:', 'addObserver:forKeyPath:options:context:', 'removeObserver:forKeyPath:', 'removeObserver:forKeyPath:context:', 'setPlayer:', 'setStatus:', 'setUnknown:', 'initWithUnknown:']!
	for mode in modes {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			match mode {
				'caller' { mut storage := [2]u64{}; objc_construct_instance(cls, u64(unsafe { &storage[0] })) }
				'install' { mut storage := [2]u64{}; objc_install_storage(cls, u64(unsafe { &storage[0] }), true) }
				'subclass' { sub := objc_allocate_class(cls, c'VinixParticipant', 0); objc_register_class(sub); objc_allocate(sub) }
				'metaclass' { objc_allocate(read64(cls)) }
				'isa-in' { objc_set_class(plain, cls) }
				'isa-out' { objc_set_class(object, ios_runtime.names['NSObject']) }
				'raw-getter' { participant_msg(objc_allocate(cls), c'player', 0) }
				'raw-setter' { participant_msg(objc_allocate(cls), c'setMatchOutcome:', 1) }
				'raw-copy' { objc_copy_value(objc_allocate(cls), false) }
				'storage' { obj_header(object).native_size = 8; participant_msg(object, c'player', 0) }
				'forged-isa' { unsafe { *(&u64(plain)) = cls }; participant_msg(plain, c'player', 0) }
				'getter-class' { participant_msg(cls, c'player', 0) }
				'setter-class' { participant_msg(cls, c'setMatchOutcome:', 1) }
				'init-class' { participant_msg(cls, c'init', 0) }
				'saved-wrong-receiver' { method := objc_instance_method(cls, u64(c'player')); unsafe { ParticipantSend(voidptr(objc_method_imp(method)))(plain, u64(c'player'), 0, 0) } }
				else { participant_msg(object, mode.str, 0) }
			}
			C._exit(0)
		}
		C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
		for {
			assert length < bytes.len
			count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length))
			if count == 0 { break }
			if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }
			assert count > 0; length += int(count)
		}
		C.close(fds[0]); mut status := i32(0)
		assert C.ios_waitpid(pid, &status, 0) == pid && status == 256, mode
		output := unsafe { tos(&bytes[0], length) }
		reason := match mode {
			'caller', 'install', 'subclass', 'metaclass' { 'GKTurnBasedParticipant requires built-in allocation' }
			'isa-in', 'isa-out' { 'changing GKTurnBasedParticipant storage isa is not implemented' }
			'raw-getter', 'raw-setter', 'raw-copy' { 'GKTurnBasedParticipant requires initialization' }
			'storage', 'forged-isa' { 'GKTurnBasedParticipant requires live built-in storage' }
			'getter-class', 'setter-class', 'saved-wrong-receiver' { 'unimplemented Objective-C method' }
			'init-class' { 'GKTurnBasedParticipant cannot initialize a class object' }
			else { 'unsupported GKTurnBasedParticipant method:' }
		}
		assert output.contains(reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:') && !output.contains('> assert '), mode + ': ' + output
	}
	objc_release(object); objc_release(plain); objc_pool_pop(pool); objc_stop(); system_data_stop()
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	assert modes.len == 31
	println('IOS-GKTURNBASEDPARTICIPANT-REJECT: 31 allocation, storage, receiver, mutation, coding and observation cases fail explicitly')
}
