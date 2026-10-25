// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct LeaderboardRange { location u64; length u64 }
type LeaderboardSend = fn (u64, u64, u64, u64) u64
type LeaderboardRangeSend = fn (u64, u64) LeaderboardRange
type LeaderboardDoubleSend = fn (u64, u64) f64

fn leaderboard_msg(object u64, selector &char, argument u64) u64 {
	return unsafe { LeaderboardSend(voidptr(C.ios_objc_msgsend))(object, u64(selector), argument, 0) }
}

fn leaderboard_range(object u64) LeaderboardRange {
	return unsafe { LeaderboardRangeSend(voidptr(C.ios_objc_msgsend))(object, u64(c'range')) }
}

fn leaderboard_set_range(object u64, value LeaderboardRange) {
	unsafe { LeaderboardSend(voidptr(C.ios_objc_msgsend))(object, u64(c'setRange:'), value.location, value.length) }
}

fn leaderboard_worker() {
	for _ in 0 .. 128 {
		pool := objc_pool_push()
		object := leaderboard_msg(ios_runtime.names['GKLeaderboard'], c'new', 0)
		text := owned_string('worker')
		leaderboard_msg(object, c'setCategory:', text); objc_release(text)
		assert leaderboard_msg(object, c'identifier', 0) == text
		leaderboard_msg(object, c'setTimeScope:', ~u64(0))
		leaderboard_msg(object, c'setPlayerScope:', 3)
		leaderboard_set_range(object, LeaderboardRange{5, 100})
		assert leaderboard_range(object) == LeaderboardRange{5, 100}
		assert leaderboard_msg(object, c'init', 0) == object
		assert leaderboard_msg(object, c'identifier', 0) == 0
		assert leaderboard_msg(object, c'timeScope', 0) == 2
		assert leaderboard_msg(object, c'playerScope', 0) == 0
		assert leaderboard_range(object) == LeaderboardRange{1, 25}
		objc_release(object); objc_pool_pop(pool)
	}
}

fn test_leaderboard() {
	for _ in 0 .. 2 {
		objc_start(); system_data_start()!
		pool := objc_pool_push(); cls := ios_runtime.names['GKLeaderboard']
		for prefix in ['_OBJC_CLASS_$_', '_OBJC_METACLASS_$_']! {
			symbol := prefix + 'GKLeaderboard'
			assert runtime_symbol('/System/Library/Frameworks/GameKit.framework/GameKit', symbol)! == if prefix == '_OBJC_CLASS_$_' { cls } else { read64(cls) }
			for wrong in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/usr/lib/libobjc.A.dylib']! {
				if _ := runtime_symbol(wrong, symbol) { assert false }
			}
		}
		assert objc_class_size(cls) == 88 && objc_class_parent(cls) == ios_runtime.names['NSObject']
		assert leaderboard_family(cls) && leaderboard_family(read64(cls))
		for construction in [c'new', c'init']! {
			object := if construction == c'new' { leaderboard_msg(cls, c'new', 0) } else { leaderboard_msg(leaderboard_msg(cls, c'alloc', 0), c'init', 0) }
			mut weak := u64(0); objc_store_weak(&weak, object)
			for selector in [c'init', c'title', c'groupIdentifier', c'baseLeaderboardID', c'type', c'startDate', c'nextStartDate', c'duration', c'category', c'setCategory:', c'timeScope', c'setTimeScope:', c'playerScope', c'setPlayerScope:', c'identifier', c'setIdentifier:', c'range', c'setRange:', c'scores', c'maxRange', c'localPlayerScore', c'isLoading']! {
				method := objc_instance_method(cls, u64(selector))
				assert method != 0 && objc_responds(object, selector)
				assert (objc_class_method(cls, u64(selector)) != 0) == (selector == c'init')
				assert objc_responds(cls, selector) == (selector == c'init')
				expected := match ctext(u64(selector)) {
					'type', 'timeScope', 'playerScope' { 'q16@0:8' }
					'maxRange' { 'Q16@0:8' }
					'duration' { 'd16@0:8' }
					'isLoading' { 'B16@0:8' }
					'setCategory:', 'setIdentifier:' { 'v24@0:8@16' }
					'setTimeScope:', 'setPlayerScope:' { 'v24@0:8q16' }
					'range' { '{_NSRange=QQ}16@0:8' }
					'setRange:' { 'v32@0:8{_NSRange=QQ}16' }
					else { '@16@0:8' }
				}
				assert ctext(u64(objc_method_types(method))) == expected
				setter := ctext(u64(selector)).starts_with('set')
				// NSMethodSignature currently rejects aggregate values. Range
				// encodings and the two-register ABI are checked independently.
				if selector !in [c'range', c'setRange:']! {
					signature := leaderboard_msg(object, c'methodSignatureForSelector:', u64(selector))
					argc := if setter { u64(3) } else { u64(2) }
					assert leaderboard_msg(signature, c'numberOfArguments', 0) == argc
					assert ctext(leaderboard_msg(signature, c'methodReturnType', 0)) == expected[..1]
					assert ctext(leaderboard_msg(signature, c'getArgumentTypeAtIndex:', 0)) == '@'
					assert ctext(leaderboard_msg(signature, c'getArgumentTypeAtIndex:', 1)) == ':'
					if setter {
						argtype := if selector in [c'setCategory:', c'setIdentifier:']! { '@' } else { 'q' }
						assert ctext(leaderboard_msg(signature, c'getArgumentTypeAtIndex:', 2)) == argtype
					}
				}
				if selector == c'range' {
					assert leaderboard_range(object) == LeaderboardRange{1, 25}
					assert unsafe { LeaderboardRangeSend(voidptr(objc_method_imp(method)))(object, u64(selector)) } == LeaderboardRange{1, 25}
				} else if selector == c'duration' {
					assert unsafe { LeaderboardDoubleSend(voidptr(C.ios_objc_msgsend))(object, u64(selector)) } == 0.0
					assert unsafe { LeaderboardDoubleSend(voidptr(objc_method_imp(method)))(object, u64(selector)) } == 0.0
				} else if !setter && selector != c'init' {
					value := if selector == c'timeScope' { u64(2) } else { u64(0) }
					assert leaderboard_msg(object, selector, 0) == value
					assert unsafe { LeaderboardSend(voidptr(objc_method_imp(method)))(object, u64(selector), 0, 0) } == value
				}
			}
			for value in [u64(0), 1, 2, 3, ~u64(0)]! {
				for pair in [[c'setTimeScope:', c'timeScope']!, [c'setPlayerScope:', c'playerScope']!]! {
					method := objc_instance_method(cls, u64(pair[0]))
					unsafe { LeaderboardSend(voidptr(objc_method_imp(method)))(object, u64(pair[0]), value, 0) }
					assert leaderboard_msg(object, pair[1], 0) == value
				}
			}
			for value in [LeaderboardRange{1, 0}, LeaderboardRange{~u64(0), 100}, LeaderboardRange{5, 25}]! {
				setter := objc_method_imp(objc_instance_method(cls, u64(c'setRange:')))
				unsafe { LeaderboardSend(voidptr(setter))(object, u64(c'setRange:'), value.location, value.length) }
				assert leaderboard_range(object) == value
			}
			getter := objc_method_imp(objc_instance_method(cls, u64(c'identifier')))
			setter := objc_method_imp(objc_instance_method(cls, u64(c'setIdentifier:')))
			init_imp := objc_method_imp(objc_instance_method(ios_runtime.names['NSObject'], u64(c'init')))
			inner := objc_pool_push()
			text := leaderboard_msg(ios_runtime.names['NSMutableString'], c'new', 0)
			mut text_weak := u64(0); objc_store_weak(&text_weak, text)
			leaderboard_msg(text, c'appendString:', objc_autorelease(owned_string('hello')))
			leaderboard_msg(object, c'setIdentifier:', text)
			unsafe { LeaderboardSend(voidptr(setter))(object, u64(c'setIdentifier:'), text, 0) }
			assert unsafe { LeaderboardSend(voidptr(getter))(object, u64(c'identifier'), 0, 0) } == text
			assert leaderboard_msg(object, c'category', 0) == text
			assert leaderboard_msg(object, c'baseLeaderboardID', 0) == 0
			leaderboard_msg(text, c'appendString:', objc_autorelease(owned_string(' mutated')))
			assert string_text(leaderboard_msg(object, c'identifier', 0)) == 'hello mutated'
			objc_release(text); assert text_weak == text
			assert unsafe { LeaderboardSend(voidptr(init_imp))(object, u64(c'init'), 0, 0) } == object
			assert leaderboard_msg(object, c'identifier', 0) == 0 && leaderboard_msg(object, c'category', 0) == 0
			assert leaderboard_msg(object, c'timeScope', 0) == 2 && leaderboard_msg(object, c'playerScope', 0) == 0
			assert leaderboard_range(object) == LeaderboardRange{1, 25}
			// Getter results keep the old retained string alive across reset.
			assert text_weak == text && string_text(text) == 'hello mutated'
			objc_pool_pop(inner); assert text_weak == 0; objc_destroy_weak(&text_weak)
			first := owned_string('first'); second := owned_string('second')
			mut first_weak := u64(0); mut second_weak := u64(0)
			objc_store_weak(&first_weak, first); objc_store_weak(&second_weak, second)
			leaderboard_msg(object, c'setIdentifier:', first); objc_release(first)
			leaderboard_msg(object, c'setCategory:', second); objc_release(second)
			assert first_weak == 0 && second_weak == second
			inner2 := objc_pool_push()
			assert leaderboard_msg(object, c'identifier', 0) == second && leaderboard_msg(object, c'category', 0) == second
			objc_pool_pop(inner2)
			leaderboard_msg(object, c'setCategory:', 0); assert second_weak == 0
			objc_destroy_weak(&first_weak); objc_destroy_weak(&second_weak)
			last := owned_string('last'); mut last_weak := u64(0); objc_store_weak(&last_weak, last)
			leaderboard_msg(object, c'setIdentifier:', last); objc_release(last)
			objc_release(object); assert weak == 0 && last_weak == 0
			objc_destroy_weak(&weak); objc_destroy_weak(&last_weak)
		}
		if _ := game_center_symbol('_OBJC_CLASS_$_GKLeaderboardUnknown') { assert false }
		objc_pool_pop(pool); baseline := ios_runtime.live
		mut workers := []thread{}
		for _ in 0 .. 4 { workers << spawn leaderboard_worker() }
		workers.wait(); unsafe { workers.free() }
		assert ios_runtime.live == baseline
		objc_stop(); system_data_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.weak.len == 0
	}
	println('IOS-GKLEADERBOARD: scoped imports, native local metadata and scalar signatures, saved IMPs, retained mutable identifier and category identity, scopes, range and double ABI, reset initialization, weak lifetimes, four workers, two drained runtimes')
}

fn test_leaderboard_rejections() {
	objc_start(); system_data_start()!
	pool := objc_pool_push(); cls := ios_runtime.names['GKLeaderboard']
	object := leaderboard_msg(cls, c'new', 0); plain := objc_allocate(ios_runtime.names['NSObject'])
	modes := ['caller', 'install', 'subclass', 'metaclass', 'isa-in', 'isa-out', 'raw-getter', 'raw-setter', 'storage', 'forged-isa', 'getter-class', 'setter-class', 'init-class', 'saved-wrong-receiver', 'directcopy', 'directcopy-zone', 'identifier-type', 'identifier-raw', 'identifier-caller', 'identifier-subclass', 'identifier-isa',
		'copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding', 'classForCoder', 'valueForKey:', 'valueForKeyPath:', 'setValue:forKey:', 'addObserver:forKeyPath:options:context:', 'removeObserver:forKeyPath:', 'removeObserver:forKeyPath:context:', 'setType:', 'setUnknown:', 'initWithUnknown:', 'range-location', 'range-length', 'range-max', 'range-signature', 'set-range-signature',
		'loadLeaderboardsWithIDs:completionHandler:', 'loadPreviousOccurrenceWithCompletionHandler:', 'submitScore:context:player:leaderboardIDs:completionHandler:', 'submitScore:context:player:completionHandler:', 'loadEntriesForPlayerScope:timeScope:range:completionHandler:', 'loadEntriesForPlayers:timeScope:completionHandler:', 'loadCategoriesWithCompletionHandler:', 'loadScoresWithCompletionHandler:', 'loadLeaderboardsWithCompletionHandler:', 'loadImageWithCompletionHandler:']!
	for mode in modes {
		if leaderboard_unsupported(mode) {
			assert !objc_responds(object, mode.str) && objc_instance_method(cls, u64(mode.str)) == 0
			assert !objc_responds(cls, mode.str) && objc_class_method(cls, u64(mode.str)) == 0
		}
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			match mode {
				'caller' { mut storage := [11]u64{}; objc_construct_instance(cls, u64(unsafe { &storage[0] })) }
				'install' { mut storage := [11]u64{}; objc_install_storage(cls, u64(unsafe { &storage[0] }), true) }
				'subclass' { sub := objc_allocate_class(cls, c'VinixLeaderboard', 0); objc_register_class(sub); objc_allocate(sub) }
				'metaclass' { objc_allocate(read64(cls)) }
				'isa-in' { objc_set_class(plain, cls) }
				'isa-out' { objc_set_class(object, ios_runtime.names['NSObject']) }
				'raw-getter' { leaderboard_msg(objc_allocate(cls), c'identifier', 0) }
				'raw-setter' { leaderboard_msg(objc_allocate(cls), c'setIdentifier:', 0) }
				'storage' { obj_header(object).native_size = 8; leaderboard_msg(object, c'identifier', 0) }
				'forged-isa' { unsafe { *(&u64(plain)) = cls }; leaderboard_msg(plain, c'identifier', 0) }
				'getter-class' { leaderboard_msg(cls, c'identifier', 0) }
				'setter-class' { leaderboard_msg(cls, c'setIdentifier:', 0) }
				'init-class' { leaderboard_msg(cls, c'init', 0) }
				'saved-wrong-receiver' { method := objc_instance_method(cls, u64(c'identifier')); unsafe { LeaderboardSend(voidptr(objc_method_imp(method)))(plain, u64(c'identifier'), 0, 0) } }
				'range-location' { leaderboard_set_range(object, LeaderboardRange{0, 0}) }
				'range-length' { leaderboard_set_range(object, LeaderboardRange{1, 101}) }
				'range-max' { leaderboard_set_range(object, LeaderboardRange{~u64(0), ~u64(0)}) }
				'range-signature', 'set-range-signature' { leaderboard_msg(object, c'methodSignatureForSelector:', if mode == 'range-signature' { u64(c'range') } else { u64(c'setRange:') }) }
				'directcopy', 'directcopy-zone' { objc_copy_value(object, mode == 'directcopy-zone') }
				'identifier-type' { leaderboard_msg(object, c'setIdentifier:', plain) }
				'identifier-raw' { leaderboard_msg(object, c'setIdentifier:', objc_allocate(ios_runtime.names['NSMutableString'])) }
				'identifier-caller' { mut storage := [8]u64{}; text := objc_construct_instance(ios_runtime.names['NSString'], u64(unsafe { &storage[0] })); leaderboard_msg(object, c'setIdentifier:', text) }
				'identifier-subclass' { sub := objc_allocate_class(ios_runtime.names['NSString'], c'VinixMatchString', 0); objc_register_class(sub); leaderboard_msg(object, c'setIdentifier:', objc_allocate(sub)) }
				'identifier-isa' { text := owned_string('forged'); unsafe { *(&u64(text)) = ios_runtime.names['NSMutableString'] }; leaderboard_msg(object, c'setIdentifier:', text) }
				else { leaderboard_msg(object, mode.str, 0) }
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
			'caller', 'install', 'subclass', 'metaclass' { 'GKLeaderboard requires built-in allocation' }
			'isa-in', 'isa-out' { 'changing GKLeaderboard storage isa is not implemented' }
			'raw-getter', 'raw-setter' { 'GKLeaderboard requires initialization' }
			'storage', 'forged-isa' { 'GKLeaderboard requires live built-in storage' }
			'getter-class', 'setter-class', 'saved-wrong-receiver' { 'unimplemented Objective-C method' }
			'range-location', 'range-length', 'range-max' { 'GKLeaderboard range requires location >= 1 and length <= 100' }
			'range-signature', 'set-range-signature' { 'NSMethodSignature aggregate or unknown value type is not implemented' }
			'init-class' { 'GKLeaderboard cannot initialize a class object' }
			'identifier-type', 'identifier-raw', 'identifier-caller', 'identifier-subclass', 'identifier-isa' { 'leaderboard identifier requires' }
			else { 'unsupported GKLeaderboard method:' }
		}
		assert output.contains(reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:') && !output.contains('> assert '), mode + ': ' + output
	}
	objc_release(object); objc_release(plain); objc_pool_pop(pool); objc_stop(); system_data_stop()
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	assert modes.len == 53
	println('IOS-GKLEADERBOARD-REJECT: 53 allocation, storage, receiver, identifier, range, aggregate signatures, copy, mutation, coding, backend and observation cases fail explicitly')
}
