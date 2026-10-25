// SPDX-License-Identifier: GPL-2.0-or-later
module main

type TurnMatchSend = fn (u64, u64, u64, u64) u64

fn turn_match_msg(object u64, selector &char, argument u64) u64 {
	return unsafe { TurnMatchSend(voidptr(C.ios_objc_msgsend))(object, u64(selector), argument, 0) }
}

fn turn_match_worker() {
	for _ in 0 .. 128 {
		pool := objc_pool_push()
		object := turn_match_msg(ios_runtime.names['GKTurnBasedMatch'], c'new', 0)
		text := owned_string('worker')
		turn_match_msg(object, c'setMessage:', text); objc_release(text)
		assert turn_match_msg(object, c'message', 0) == text
		assert turn_match_msg(object, c'matchDataMaximumSize', 0) == 65536
		assert turn_match_msg(object, c'init', 0) == object
		assert turn_match_msg(object, c'message', 0) == 0
		objc_release(object); objc_pool_pop(pool)
	}
}

fn test_turn_match() {
	for _ in 0 .. 2 {
		objc_start(); system_data_start()!
		pool := objc_pool_push(); cls := ios_runtime.names['GKTurnBasedMatch']
		for prefix in ['_OBJC_CLASS_$_', '_OBJC_METACLASS_$_']! {
			symbol := prefix + 'GKTurnBasedMatch'
			assert runtime_symbol('/System/Library/Frameworks/GameKit.framework/GameKit', symbol)! == if prefix == '_OBJC_CLASS_$_' { cls } else { read64(cls) }
			for wrong in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/usr/lib/libobjc.A.dylib']! {
				if _ := runtime_symbol(wrong, symbol) { assert false }
			}
		}
		assert objc_class_size(cls) == 40 && objc_class_parent(cls) == ios_runtime.names['NSObject']
		assert turn_match_family(cls) && turn_match_family(read64(cls))
		for construction in [c'new', c'init']! {
			object := if construction == c'new' { turn_match_msg(cls, c'new', 0) } else { turn_match_msg(turn_match_msg(cls, c'alloc', 0), c'init', 0) }
			mut weak := u64(0); objc_store_weak(&weak, object)
			for selector in [c'init', c'matchID', c'creationDate', c'participants', c'status', c'currentParticipant', c'matchData', c'message', c'setMessage:', c'matchDataMaximumSize', c'exchanges', c'activeExchanges', c'completedExchanges', c'exchangeDataMaximumSize', c'exchangeMaxInitiatedExchangesPerPlayer']! {
				method := objc_instance_method(cls, u64(selector))
				assert method != 0 && objc_responds(object, selector)
				assert (objc_class_method(cls, u64(selector)) != 0) == (selector == c'init')
				assert objc_responds(cls, selector) == (selector == c'init')
				expected := match ctext(u64(selector)) {
					'status' { 'q16@0:8' }
					'matchDataMaximumSize', 'exchangeDataMaximumSize', 'exchangeMaxInitiatedExchangesPerPlayer' { 'Q16@0:8' }
					'setMessage:' { 'v24@0:8@16' }
					else { '@16@0:8' }
				}
				assert ctext(u64(objc_method_types(method))) == expected
				signature := turn_match_msg(object, c'methodSignatureForSelector:', u64(selector))
				argc := if selector == c'setMessage:' { u64(3) } else { u64(2) }
				assert turn_match_msg(signature, c'numberOfArguments', 0) == argc
				assert ctext(turn_match_msg(signature, c'methodReturnType', 0)) == expected[..1]
				assert ctext(turn_match_msg(signature, c'getArgumentTypeAtIndex:', 0)) == '@'
				assert ctext(turn_match_msg(signature, c'getArgumentTypeAtIndex:', 1)) == ':'
				if argc == 3 { assert ctext(turn_match_msg(signature, c'getArgumentTypeAtIndex:', 2)) == '@' }
				if selector !in [c'init', c'setMessage:']! {
					value := match ctext(u64(selector)) {
						'matchDataMaximumSize' { u64(65536) }
						'exchangeDataMaximumSize' { u64(1024) }
						'exchangeMaxInitiatedExchangesPerPlayer' { u64(30) }
						else { u64(0) }
					}
					assert turn_match_msg(object, selector, 0) == value
					assert unsafe { TurnMatchSend(voidptr(objc_method_imp(method)))(object, u64(selector), 0, 0) } == value
				}
			}
			getter := objc_method_imp(objc_instance_method(cls, u64(c'message')))
			setter := objc_method_imp(objc_instance_method(cls, u64(c'setMessage:')))
			init_imp := objc_method_imp(objc_instance_method(ios_runtime.names['NSObject'], u64(c'init')))
			inner := objc_pool_push()
			text := turn_match_msg(ios_runtime.names['NSMutableString'], c'new', 0)
			mut text_weak := u64(0); objc_store_weak(&text_weak, text)
			turn_match_msg(text, c'appendString:', objc_autorelease(owned_string('hello')))
			turn_match_msg(object, c'setMessage:', text)
			unsafe { TurnMatchSend(voidptr(setter))(object, u64(c'setMessage:'), text, 0) }
			assert unsafe { TurnMatchSend(voidptr(getter))(object, u64(c'message'), 0, 0) } == text
			turn_match_msg(text, c'appendString:', objc_autorelease(owned_string(' mutated')))
			assert string_text(turn_match_msg(object, c'message', 0)) == 'hello mutated'
			objc_release(text); assert text_weak == text
			assert unsafe { TurnMatchSend(voidptr(init_imp))(object, u64(c'init'), 0, 0) } == object
			assert turn_match_msg(object, c'message', 0) == 0 && text_weak == text
			// The autoreleased getter result pins the old message across reset.
			assert string_text(text) == 'hello mutated'
			objc_pool_pop(inner); assert text_weak == 0; objc_destroy_weak(&text_weak)
			first := owned_string('first'); second := owned_string('second')
			mut first_weak := u64(0); mut second_weak := u64(0)
			objc_store_weak(&first_weak, first); objc_store_weak(&second_weak, second)
			turn_match_msg(object, c'setMessage:', first); objc_release(first)
			turn_match_msg(object, c'setMessage:', second); objc_release(second)
			assert first_weak == 0 && second_weak == second
			turn_match_msg(object, c'setMessage:', 0); assert second_weak == 0
			objc_destroy_weak(&first_weak); objc_destroy_weak(&second_weak)
			last := owned_string('last'); mut last_weak := u64(0); objc_store_weak(&last_weak, last)
			turn_match_msg(object, c'setMessage:', last); objc_release(last)
			objc_release(object); assert weak == 0 && last_weak == 0
			objc_destroy_weak(&weak); objc_destroy_weak(&last_weak)
		}
		if _ := game_center_symbol('_OBJC_CLASS_$_GKTurnBasedMatchUnknown') { assert false }
		objc_pool_pop(pool); baseline := ios_runtime.live
		mut workers := []thread{}
		for _ in 0 .. 4 { workers << spawn turn_match_worker() }
		workers.wait(); unsafe { workers.free() }
		assert ios_runtime.live == baseline
		objc_stop(); system_data_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.weak.len == 0
	}
	println('IOS-GKTURNBASEDMATCH: scoped imports, native local metadata and signatures, saved IMPs, retained mutable message identity, reset initialization, weak lifetimes, four workers, two drained runtimes')
}

fn test_turn_match_rejections() {
	objc_start(); system_data_start()!
	pool := objc_pool_push(); cls := ios_runtime.names['GKTurnBasedMatch']
	object := turn_match_msg(cls, c'new', 0); plain := objc_allocate(ios_runtime.names['NSObject'])
	modes := ['caller', 'install', 'subclass', 'metaclass', 'isa-in', 'isa-out', 'raw-getter', 'raw-setter', 'storage', 'forged-isa', 'getter-class', 'setter-class', 'init-class', 'saved-wrong-receiver', 'directcopy', 'directcopy-zone', 'message-type', 'message-raw', 'message-caller', 'message-subclass', 'message-isa',
		'copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding', 'classForCoder', 'valueForKey:', 'valueForKeyPath:', 'setValue:forKey:', 'addObserver:forKeyPath:options:context:', 'removeObserver:forKeyPath:', 'removeObserver:forKeyPath:context:', 'setStatus:', 'setUnknown:', 'initWithUnknown:', 'setLocalizableMessageWithKey:arguments:',
		'findMatchForRequest:withCompletionHandler:', 'loadMatchesWithCompletionHandler:', 'loadMatchWithID:withCompletionHandler:', 'rematchWithCompletionHandler:', 'acceptInviteWithCompletionHandler:', 'declineInviteWithCompletionHandler:', 'removeWithCompletionHandler:', 'loadMatchDataWithCompletionHandler:', 'endTurnWithNextParticipants:turnTimeout:matchData:completionHandler:', 'participantQuitInTurnWithOutcome:nextParticipants:turnTimeout:matchData:completionHandler:', 'participantQuitOutOfTurnWithOutcome:withCompletionHandler:', 'endMatchInTurnWithMatchData:completionHandler:', 'endMatchInTurnWithMatchData:scores:achievements:completionHandler:', 'endMatchInTurnWithMatchData:leaderboardScores:achievements:completionHandler:', 'saveCurrentTurnWithMatchData:completionHandler:', 'saveMergedMatchData:withResolvedExchanges:completionHandler:', 'sendExchangeToParticipants:data:localizableMessageKey:arguments:timeout:completionHandler:', 'sendReminderToParticipants:localizableMessageKey:arguments:completionHandler:', 'endTurnWithNextParticipant:matchData:completionHandler:', 'participantQuitInTurnWithOutcome:nextParticipant:matchData:completionHandler:']!
	for mode in modes {
		if turn_match_unsupported(mode) {
			assert !objc_responds(object, mode.str) && objc_instance_method(cls, u64(mode.str)) == 0
			assert !objc_responds(cls, mode.str) && objc_class_method(cls, u64(mode.str)) == 0
		}
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			match mode {
				'caller' { mut storage := [5]u64{}; objc_construct_instance(cls, u64(unsafe { &storage[0] })) }
				'install' { mut storage := [5]u64{}; objc_install_storage(cls, u64(unsafe { &storage[0] }), true) }
				'subclass' { sub := objc_allocate_class(cls, c'VinixTurnMatch', 0); objc_register_class(sub); objc_allocate(sub) }
				'metaclass' { objc_allocate(read64(cls)) }
				'isa-in' { objc_set_class(plain, cls) }
				'isa-out' { objc_set_class(object, ios_runtime.names['NSObject']) }
				'raw-getter' { turn_match_msg(objc_allocate(cls), c'message', 0) }
				'raw-setter' { turn_match_msg(objc_allocate(cls), c'setMessage:', 0) }
				'storage' { obj_header(object).native_size = 8; turn_match_msg(object, c'message', 0) }
				'forged-isa' { unsafe { *(&u64(plain)) = cls }; turn_match_msg(plain, c'message', 0) }
				'getter-class' { turn_match_msg(cls, c'message', 0) }
				'setter-class' { turn_match_msg(cls, c'setMessage:', 0) }
				'init-class' { turn_match_msg(cls, c'init', 0) }
				'saved-wrong-receiver' { method := objc_instance_method(cls, u64(c'message')); unsafe { TurnMatchSend(voidptr(objc_method_imp(method)))(plain, u64(c'message'), 0, 0) } }
				'directcopy', 'directcopy-zone' { objc_copy_value(object, mode == 'directcopy-zone') }
				'message-type' { turn_match_msg(object, c'setMessage:', plain) }
				'message-raw' { turn_match_msg(object, c'setMessage:', objc_allocate(ios_runtime.names['NSMutableString'])) }
				'message-caller' { mut storage := [8]u64{}; text := objc_construct_instance(ios_runtime.names['NSString'], u64(unsafe { &storage[0] })); turn_match_msg(object, c'setMessage:', text) }
				'message-subclass' { sub := objc_allocate_class(ios_runtime.names['NSString'], c'VinixMatchString', 0); objc_register_class(sub); turn_match_msg(object, c'setMessage:', objc_allocate(sub)) }
				'message-isa' { text := owned_string('forged'); unsafe { *(&u64(text)) = ios_runtime.names['NSMutableString'] }; turn_match_msg(object, c'setMessage:', text) }
				else { turn_match_msg(object, mode.str, 0) }
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
			'caller', 'install', 'subclass', 'metaclass' { 'GKTurnBasedMatch requires built-in allocation' }
			'isa-in', 'isa-out' { 'changing GKTurnBasedMatch storage isa is not implemented' }
			'raw-getter', 'raw-setter' { 'GKTurnBasedMatch requires initialization' }
			'storage', 'forged-isa' { 'GKTurnBasedMatch requires live built-in storage' }
			'getter-class', 'setter-class', 'saved-wrong-receiver' { 'unimplemented Objective-C method' }
			'init-class' { 'GKTurnBasedMatch cannot initialize a class object' }
			'message-type', 'message-raw', 'message-caller', 'message-subclass', 'message-isa' { 'match message requires' }
			else { 'unsupported GKTurnBasedMatch method:' }
		}
		assert output.contains(reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:') && !output.contains('> assert '), mode + ': ' + output
	}
	objc_release(object); objc_release(plain); objc_pool_pop(pool); objc_stop(); system_data_stop()
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	assert modes.len == 59
	println('IOS-GKTURNBASEDMATCH-REJECT: 59 allocation, storage, receiver, message, copy, mutation, coding, backend and observation cases fail explicitly')
}
