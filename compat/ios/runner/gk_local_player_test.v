// SPDX-License-Identifier: GPL-2.0-or-later
module main

type LocalPlayerSend = fn (u64, u64, u64, u64) u64
type LocalPlayerBool = fn (u64, u64) bool

fn local_player_msg(object u64, selector &char, argument u64) u64 {
	return unsafe { LocalPlayerSend(voidptr(C.ios_objc_msgsend))(object, u64(selector), argument, 0) }
}

fn local_player_worker() u64 {
	mut cached := u64(0)
	for _ in 0 .. 128 {
		pool := objc_pool_push()
		cls := ios_runtime.names['GKLocalPlayer']
		local := local_player_msg(cls, c'localPlayer', 0)
		assert local != 0 && local == local_player_msg(cls, c'local', 0)
		assert cached == 0 || cached == local
		cached = local
		assert local_player_msg(local, c'isAuthenticated', 0) == 0
		assert local_player_msg(local, c'copy', 0) == local
		objc_release(local)
		object := local_player_msg(cls, c'new', 0)
		assert object != local
		alias := local_player_msg(object, c'alias', 0)
		assert ctext(local_player_msg(alias, c'UTF8String', 0)) == 'Unknown'
		assert local_player_msg(object, c'init', 0) == object
		assert local_player_msg(object, c'alias', 0) == alias
		objc_release(object)
		objc_pool_pop(pool)
	}
	return cached
}

fn test_local_player() {
	for _ in 0 .. 2 {
		objc_start(); system_data_start()!
		cls := ios_runtime.names['GKLocalPlayer']
		assert objc_class_size(cls) == 120 && objc_class_parent(cls) == ios_runtime.names['GKPlayer']
		assert gk_player_family(cls) && gk_player_family(read64(cls))
		for prefix in ['_OBJC_CLASS_$_', '_OBJC_METACLASS_$_']! {
			symbol := prefix + 'GKLocalPlayer'
			assert runtime_symbol('/System/Library/Frameworks/GameKit.framework/GameKit', symbol)! == if prefix == '_OBJC_CLASS_$_' { cls } else { read64(cls) }
			for wrong in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/usr/lib/libobjc.A.dylib']! {
				if _ := runtime_symbol(wrong, symbol) { assert false }
			}
		}
		baseline := ios_runtime.live
		mut workers := []thread u64{}
		for _ in 0 .. 4 { workers << spawn local_player_worker() }
		values := workers.wait()
		cached := values[0]
		assert values.all(it == cached) && ios_runtime.live == baseline + 2
		unsafe { workers.free(); values.free() }
		assert C.ios_ref_change(unsafe { &obj_header(cached).refs }, 0) == 1
		mut cached_weak := u64(0); objc_store_weak(&cached_weak, cached)
		mut cached_alias_weak := u64(0)
		objc_store_weak(&cached_alias_weak, local_player_msg(cached, c'alias', 0))
		pool := objc_pool_push()
		for selector in [c'localPlayer', c'local']! {
			method := objc_class_method(cls, u64(selector))
			assert method != 0 && objc_responds(cls, selector)
			assert ctext(u64(objc_method_types(method))) == '@16@0:8'
			assert unsafe { LocalPlayerSend(voidptr(objc_method_imp(method)))(cls, u64(selector), 0, 0) } == cached
			assert objc_instance_method(cls, u64(selector)) == 0 && !objc_responds(cached, selector)
		}
		for construction in [c'new', c'init', c'localPlayer', c'local']! {
			owned := construction in [c'new', c'init']!
			object := if construction == c'init' { local_player_msg(local_player_msg(cls, c'alloc', 0), c'init', 0) } else { local_player_msg(cls, construction, 0) }
			assert (object != cached) == owned
			mut weak := u64(0); objc_store_weak(&weak, object)
			alias := local_player_msg(object, c'alias', 0)
			mut alias_weak := u64(0); objc_store_weak(&alias_weak, alias)
			for selector in [c'playerID', c'displayName', c'alias', c'guestIdentifier', c'isFriend', c'isInvitable', c'scopedIDsArePersistent', c'isAuthenticated', c'isUnderage', c'isMultiplayerGamingRestricted', c'isPersonalizedCommunicationRestricted', c'authenticateHandler']! {
				boolean := selector in [c'isFriend', c'isInvitable', c'scopedIDsArePersistent', c'isAuthenticated', c'isUnderage', c'isMultiplayerGamingRestricted', c'isPersonalizedCommunicationRestricted']!
				block := selector == c'authenticateHandler'
				expected := if boolean { 'B16@0:8' } else if block { '@?16@0:8' } else { '@16@0:8' }
				value := if selector == c'alias' { alias } else if selector in [c'isMultiplayerGamingRestricted', c'isPersonalizedCommunicationRestricted']! { u64(1) } else { u64(0) }
				assert local_player_msg(object, selector, 0) == value
				if selector == c'alias' { assert ctext(local_player_msg(value, c'UTF8String', 0)) == 'Unknown' }
				method := objc_instance_method(cls, u64(selector))
				assert method != 0 && objc_responds(object, selector)
				assert ctext(u64(objc_method_types(method))) == expected
				assert objc_class_method(cls, u64(selector)) == 0 && !objc_responds(cls, selector)
				signature := local_player_msg(object, c'methodSignatureForSelector:', u64(selector))
				assert local_player_msg(signature, c'numberOfArguments', 0) == 2
				assert ctext(local_player_msg(signature, c'methodReturnType', 0)) == if block { '@?' } else { expected[..1] }
				assert local_player_msg(signature, c'methodReturnLength', 0) == if boolean { u64(1) } else { u64(8) }
				imp := objc_method_imp(method)
				if boolean { assert unsafe { LocalPlayerBool(voidptr(imp))(object, u64(selector)) } == (value != 0) }
				else { assert unsafe { LocalPlayerSend(voidptr(imp))(object, u64(selector), 0, 0) } == value }
			}
			init_imp := objc_method_imp(objc_instance_method(ios_runtime.names['NSObject'], u64(c'init')))
			assert unsafe { LocalPlayerSend(voidptr(init_imp))(object, u64(c'init'), 0, 0) } == object
			assert local_player_msg(object, c'alias', 0) == alias
			for selector in [c'copy', c'copyWithZone:']! {
				method := objc_instance_method(cls, u64(selector))
				assert ctext(u64(objc_method_types(method))) == if selector == c'copy' { '@16@0:8' } else { '@24@0:8^{_NSZone=}16' }
				assert unsafe { LocalPlayerSend(voidptr(objc_method_imp(method)))(object, u64(selector), 0, 0) } == object
				assert C.ios_ref_change(unsafe { &obj_header(object).refs }, 0) == 2
				objc_release(object)
			}
			assert objc_copy_value(object, false) == object
			objc_release(object)
			for selector in [c'friends', c'loadFriendsWithCompletionHandler:', c'loadDefaultLeaderboardIdentifierWithCompletionHandler:', c'loadRecentPlayersWithCompletionHandler:', c'setAuthenticateHandler:', c'authenticateWithCompletionHandler:', c'generateIdentityVerificationSignatureWithCompletionHandler:', c'fetchItemsForIdentityVerificationSignature:', c'registerListener:', c'unregisterListener:', c'unregisterAllListeners', c'saveGameData:withName:completionHandler:', c'fetchSavedGamesWithCompletionHandler:', c'deleteSavedGamesWithName:completionHandler:', c'resolveConflictingSavedGames:withData:completionHandler:', c'presentFriendRequestCreatorFromViewController:completionHandler:', c'isPresentingFriendRequestViewController', c'gamePlayerID', c'teamPlayerID', c'setAlias:', c'initWithCoder:', c'encodeWithCoder:', c'mutableCopy']! {
				assert !objc_responds(object, selector) && objc_instance_method(cls, u64(selector)) == 0
				assert !objc_responds(cls, selector) && objc_class_method(cls, u64(selector)) == 0
			}
			if owned {
				assert local_player_msg(object, c'copy', 0) == object
				objc_release(object); assert weak == object && alias_weak == alias
				objc_release(object); assert weak == 0 && alias_weak == 0
			}
			objc_destroy_weak(&weak); objc_destroy_weak(&alias_weak)
		}
		objc_pool_pop(pool)
		assert ios_runtime.live == baseline + 2 && cached_weak == cached && cached_alias_weak != 0
		objc_stop(); system_data_stop()
		assert cached_weak == 0 && cached_alias_weak == 0
		objc_destroy_weak(&cached_weak); objc_destroy_weak(&cached_alias_weak)
		assert ios_runtime.gk_local_player == 0 && ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.weak.len == 0
	}
	println('IOS-GKLOCALPLAYER: scoped imports, native unauthenticated defaults and signatures, scalar and block ABI, saved IMPs, retained copies, alias ownership, concurrent singleton, four workers, two drained runtimes')
}

fn test_local_player_rejections() {
	objc_start(); system_data_start()!
	pool := objc_pool_push(); cls := ios_runtime.names['GKLocalPlayer']
	object := local_player_msg(cls, c'new', 0); plain := objc_allocate(ios_runtime.names['NSObject'])
	modes := ['caller', 'install', 'subclass', 'metaclass', 'isa-in', 'isa-out', 'raw-getter', 'raw-copy', 'storage', 'forged-isa', 'getter-class', 'saved-wrong-receiver', 'saved-class-wrong-receiver', 'local-instance', 'player-authenticated', 'friends', 'loadFriendsWithCompletionHandler:', 'loadDefaultLeaderboardIdentifierWithCompletionHandler:', 'loadRecentPlayersWithCompletionHandler:', 'setAuthenticateHandler:', 'authenticateWithCompletionHandler:', 'generateIdentityVerificationSignatureWithCompletionHandler:', 'fetchItemsForIdentityVerificationSignature:', 'registerListener:', 'unregisterListener:', 'unregisterAllListeners', 'saveGameData:withName:completionHandler:', 'fetchSavedGamesWithCompletionHandler:', 'deleteSavedGamesWithName:completionHandler:', 'resolveConflictingSavedGames:withData:completionHandler:', 'presentFriendRequestCreatorFromViewController:completionHandler:', 'isPresentingFriendRequestViewController', 'gamePlayerID', 'teamPlayerID', 'setAlias:', 'initWithCoder:', 'encodeWithCoder:', 'mutableCopy']!
	for mode in modes {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			match mode {
				'caller' { mut storage := [15]u64{}; objc_construct_instance(cls, u64(unsafe { &storage[0] })) }
				'install' { mut storage := [15]u64{}; objc_install_storage(cls, u64(unsafe { &storage[0] }), true) }
				'subclass' { sub := objc_allocate_class(cls, c'VinixLocalPlayer', 0); objc_register_class(sub); objc_allocate(sub) }
				'metaclass' { objc_allocate(read64(cls)) }
				'isa-in' { objc_set_class(plain, cls) }
				'isa-out' { objc_set_class(object, ios_runtime.names['NSObject']) }
				'raw-getter' { local_player_msg(objc_allocate(cls), c'isAuthenticated', 0) }
				'raw-copy' { objc_copy_value(objc_allocate(cls), false) }
				'storage' { obj_header(object).native_size = 32; local_player_msg(object, c'isAuthenticated', 0) }
				'forged-isa' { unsafe { *(&u64(plain)) = cls }; local_player_msg(plain, c'isAuthenticated', 0) }
				'getter-class' { local_player_msg(cls, c'isAuthenticated', 0) }
				'saved-wrong-receiver' { method := objc_instance_method(cls, u64(c'isAuthenticated')); unsafe { LocalPlayerSend(voidptr(objc_method_imp(method)))(plain, u64(c'isAuthenticated'), 0, 0) } }
				'saved-class-wrong-receiver' { method := objc_class_method(cls, u64(c'localPlayer')); unsafe { LocalPlayerSend(voidptr(objc_method_imp(method)))(ios_runtime.names['GKPlayer'], u64(c'localPlayer'), 0, 0) } }
				'local-instance' { local_player_msg(object, c'localPlayer', 0) }
				'player-authenticated' { local_player_msg(local_player_msg(ios_runtime.names['GKPlayer'], c'new', 0), c'isAuthenticated', 0) }
				else { local_player_msg(object, mode.str, 0) }
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
			'caller', 'install', 'subclass', 'metaclass' { 'GKPlayer requires built-in allocation' }
			'isa-in', 'isa-out' { 'changing GKPlayer storage isa is not implemented' }
			'raw-getter', 'raw-copy' { 'GKPlayer requires initialization' }
			'storage', 'forged-isa' { 'GKPlayer requires live built-in storage' }
			'getter-class', 'saved-wrong-receiver', 'saved-class-wrong-receiver', 'local-instance', 'player-authenticated' { 'unimplemented Objective-C method' }
			'gamePlayerID', 'teamPlayerID', 'setAlias:', 'initWithCoder:', 'encodeWithCoder:', 'mutableCopy', 'setAuthenticateHandler:' { 'unsupported GKPlayer method:' }
			else { 'unsupported GKLocalPlayer method:' }
		}
		assert output.contains(reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:') && !output.contains('> assert '), mode + ': ' + output
	}
	objc_release(object); objc_release(plain); objc_pool_pop(pool); objc_stop(); system_data_stop()
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	assert modes.len == 38
	println('IOS-GKLOCALPLAYER-REJECT: 38 allocation, storage, receiver, authentication, friends, listener, saved game, identity, mutation and coding cases fail explicitly')
}
