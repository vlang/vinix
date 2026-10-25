// SPDX-License-Identifier: GPL-2.0-or-later
module main

type MatchRequestSend = fn (u64, u64, u64, u64) u64

fn match_request_msg(object u64, selector &char, argument u64) u64 {
	return unsafe { MatchRequestSend(voidptr(C.ios_objc_msgsend))(object, u64(selector), argument, 0) }
}

fn match_request_defaults(object u64) {
	for i, selector in [c'minPlayers', c'maxPlayers', c'playerGroup', c'playerAttributes', c'defaultNumberOfPlayers', c'restrictToAutomatch']! {
		assert match_request_msg(object, selector, 0) == [u64(2), 2, 1, 0xffffffff, 0, 0]![i]
	}
}

fn match_request_worker() {
	for i in 0 .. 128 {
		pool := objc_pool_push()
		object := match_request_msg(ios_runtime.names['GKMatchRequest'], c'new', 0)
		match_request_defaults(object)
		match_request_msg(object, c'setPlayerGroup:', u64(i))
		assert match_request_msg(object, c'playerGroup', 0) == u64(i)
		objc_release(object)
		objc_pool_pop(pool)
	}
}

fn test_match_request() {
	for _ in 0 .. 2 {
		objc_start()
		system_data_start()!
		pool := objc_pool_push()
		cls := ios_runtime.names['GKMatchRequest']
		for prefix in ['_OBJC_CLASS_$_', '_OBJC_METACLASS_$_']! {
			symbol := prefix + 'GKMatchRequest'
			assert runtime_symbol('/System/Library/Frameworks/GameKit.framework/GameKit', symbol)! == if prefix == '_OBJC_CLASS_$_' { cls } else { read64(cls) }
			for wrong in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/usr/lib/libobjc.A.dylib']! {
				if _ := runtime_symbol(wrong, symbol) { assert false }
			}
		}
		if _ := game_center_symbol('_OBJC_CLASS_$_GKMatchRequestUnknown') { assert false }
		assert objc_class_size(cls) == 40 && objc_class_parent(cls) == ios_runtime.names['NSObject']
		assert match_request_family(cls) && match_request_family(read64(cls))
		object := match_request_msg(match_request_msg(cls, c'alloc', 0), c'init', 0)
		other := match_request_msg(cls, c'new', 0)
		match_request_defaults(object)
		match_request_defaults(other)
		getters := [c'minPlayers', c'maxPlayers', c'playerGroup', c'playerAttributes', c'defaultNumberOfPlayers', c'restrictToAutomatch']!
		setters := [c'setMinPlayers:', c'setMaxPlayers:', c'setPlayerGroup:', c'setPlayerAttributes:', c'setDefaultNumberOfPlayers:', c'setRestrictToAutomatch:']!
		for i, getter in getters {
			for value in [u64(0), 1, 7, 255, 256, 0x100000001, 0xffffffffffffffff]! {
				match_request_msg(object, setters[i], value)
				assert match_request_msg(object, getter, 0) == if i == 2 { value } else if i == 3 { u64(u32(value)) } else { u64(u8(value)) }
				match_request_defaults(other)
			}
			// Shim methods represent native forwarding signatures; they do not
			// reproduce the native class's dynamic method-list membership.
			for selector in [getter, setters[i]]! {
				text := ctext(u64(selector))
				method := objc_instance_method(cls, u64(selector))
				assert method != 0 && objc_responds(object, selector)
				assert ctext(u64(objc_method_types(method))) == match_request_types('GKMatchRequest', false, text)?
				assert objc_class_method(cls, u64(selector)) == 0 && !objc_responds(cls, selector)
				signature := match_request_msg(object, c'methodSignatureForSelector:', u64(selector))
				assert match_request_msg(signature, c'numberOfArguments', 0) == u64(2 + text.count(':'))
				type_code := ['C', 'C', 'Q', 'I', 'C', 'B']![i]
				assert ctext(match_request_msg(signature, c'methodReturnType', 0)) == if selector == getter { type_code } else { 'v' }
				if selector != getter { assert ctext(match_request_msg(signature, c'getArgumentTypeAtIndex:', 2)) == type_code }
			}
			setter := objc_instance_method(cls, u64(setters[i]))
			getter_method := objc_instance_method(cls, u64(getter))
			unsafe { MatchRequestSend(voidptr(objc_method_imp(setter)))(object, u64(setters[i]), 7, 0) }
			assert unsafe { MatchRequestSend(voidptr(objc_method_imp(getter_method)))(object, u64(getter), 0, 0) } == 7
		}
		match_request_msg(object, c'setMinPlayers:', 2)
		match_request_msg(object, c'setMaxPlayers:', 8)
		match_request_msg(object, c'setDefaultNumberOfPlayers:', 0)
		match_request_msg(object, c'setPlayerAttributes:', 0)
		assert match_request_msg(object, c'minPlayers', 0) == 2 && match_request_msg(object, c'maxPlayers', 0) == 8
		assert match_request_msg(object, c'defaultNumberOfPlayers', 0) == 0 && match_request_msg(object, c'playerAttributes', 0) == 0
		// A saved NSObject initializer must use the actual receiver's family.
		init_method := objc_instance_method(ios_runtime.names['NSObject'], u64(c'init'))
		assert unsafe { MatchRequestSend(voidptr(objc_method_imp(init_method)))(object, u64(c'init'), 0, 0) } == object
		match_request_defaults(object)
		for selector in [c'recipients', c'playersToInvite', c'inviteMessage', c'queueName', c'properties', c'recipientProperties', c'recipientResponseHandler', c'inviteeResponseHandler', c'copy', c'copyWithZone:', c'mutableCopy', c'mutableCopyWithZone:', c'initWithCoder:', c'encodeWithCoder:', c'supportsSecureCoding', c'classForCoder', c'valueForKey:', c'valueForKeyPath:', c'setValue:forKey:', c'addObserver:forKeyPath:options:context:', c'removeObserver:forKeyPath:', c'removeObserver:forKeyPath:context:', c'maxPlayersAllowedForMatchOfType:', c'setUnknown:']! {
			assert !objc_responds(object, selector) && objc_instance_method(cls, u64(selector)) == 0
		}
		objc_release(object)
		objc_release(other)
		baseline := ios_runtime.live
		mut workers := []thread{}
		for _ in 0 .. 4 { workers << spawn match_request_worker() }
		workers.wait()
		unsafe { workers.free() }
		assert ios_runtime.live == baseline
		objc_pool_pop(pool)
		objc_stop()
		system_data_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.block_refs.len == 0
	}
	println('IOS-GKMATCHREQUEST: scoped imports, native signatures and defaults, truncation, independent properties, saved IMPs, four workers, two drained runtimes')
}

fn test_match_request_rejections() {
	objc_start()
	system_data_start()!
	pool := objc_pool_push()
	cls := ios_runtime.names['GKMatchRequest']
	object := match_request_msg(cls, c'new', 0)
	plain := objc_allocate(ios_runtime.names['NSObject'])
	for mode in ['caller', 'install', 'subclass', 'metaclass', 'directcopy', 'isa-in', 'isa-out', 'raw-getter', 'storage', 'forged-isa', 'getter-class', 'saved-wrong-receiver', 'recipients', 'playersToInvite', 'inviteMessage', 'recipientResponseHandler', 'inviteeResponseHandler', 'queueName', 'properties', 'recipientProperties', 'setRecipients:', 'setPlayersToInvite:', 'setInviteMessage:', 'setRecipientResponseHandler:', 'setInviteeResponseHandler:', 'setQueueName:', 'setProperties:', 'setRecipientProperties:', 'copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding', 'classForCoder', 'valueForKey:', 'valueForKeyPath:', 'setValue:forKey:', 'addObserver:forKeyPath:options:context:', 'removeObserver:forKeyPath:', 'removeObserver:forKeyPath:context:', 'maxPlayersAllowedForMatchOfType:', 'setUnknown:', 'initWithUnknown:']! {
		mut fds := [2]i32{}
		assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.fork()
		assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			match mode {
				'caller' { mut storage := [5]u64{}; objc_construct_instance(cls, u64(unsafe { &storage[0] })) }
				'install' { mut storage := [5]u64{}; objc_install_storage(cls, u64(unsafe { &storage[0] }), true) }
				'subclass' { sub := objc_allocate_class(cls, c'VinixMatchRequest', 0); objc_register_class(sub); objc_allocate(sub) }
				'metaclass' { objc_allocate(read64(cls)) }
				'directcopy' { objc_copy_value(object, false) }
				'isa-in' { objc_set_class(plain, cls) }
				'isa-out' { objc_set_class(object, ios_runtime.names['NSObject']) }
				'raw-getter' { match_request_msg(objc_allocate(cls), c'minPlayers', 0) }
				'storage' { obj_header(object).native_size = 16; match_request_msg(object, c'minPlayers', 0) }
				'forged-isa' { unsafe { *(&u64(plain)) = cls }; match_request_msg(plain, c'minPlayers', 0) }
				'getter-class' { match_request_msg(cls, c'minPlayers', 0) }
				'saved-wrong-receiver' { method := objc_instance_method(cls, u64(c'minPlayers')); unsafe { MatchRequestSend(voidptr(objc_method_imp(method)))(plain, u64(c'minPlayers'), 0, 0) } }
				else { match_request_msg(object, mode.str, 0) }
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
			'caller', 'install', 'subclass', 'metaclass' { 'GKMatchRequest requires built-in allocation' }
			'isa-in', 'isa-out' { 'changing GKMatchRequest storage isa is not implemented' }
			'raw-getter' { 'GKMatchRequest requires initialization' }
			'storage', 'forged-isa' { 'GKMatchRequest requires live built-in storage' }
			'getter-class', 'saved-wrong-receiver' { 'unimplemented Objective-C method' }
			else { 'unsupported GKMatchRequest method:' }
		}
		assert output.contains(reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:') && !output.contains('> assert '), mode + ': ' + output
	}
	objc_release(object)
	objc_release(plain)
	objc_pool_pop(pool)
	objc_stop()
	system_data_stop()
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	println('IOS-GKMATCHREQUEST-REJECT: 45 construction, initialization, storage, receiver, copy, coding, matchmaking and observation cases fail explicitly')
}
