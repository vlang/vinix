// SPDX-License-Identifier: GPL-2.0-or-later
module main

type PlayerSend = fn (u64, u64, u64, u64) u64
type PlayerBool = fn (u64, u64) bool

fn player_msg(object u64, selector &char, argument u64) u64 {
	return unsafe { PlayerSend(voidptr(C.ios_objc_msgsend))(object, u64(selector), argument, 0) }
}

fn player_worker() {
	for _ in 0 .. 128 {
		pool := objc_pool_push()
		for name in ['GKBasePlayer', 'GKPlayer']! {
			object := player_msg(ios_runtime.names[name], c'new', 0)
			assert player_msg(object, c'playerID', 0) == 0
			if name == 'GKPlayer' {
				alias := player_msg(object, c'alias', 0)
				assert ctext(player_msg(alias, c'UTF8String', 0)) == 'Unknown'
				assert player_msg(object, c'init', 0) == object && player_msg(object, c'alias', 0) == alias
			}
			assert player_msg(object, c'copy', 0) == object
			objc_release(object); objc_release(object)
		}
		objc_pool_pop(pool)
	}
}

fn test_player() {
	for _ in 0 .. 2 {
		objc_start(); system_data_start()!
		pool := objc_pool_push()
		for name in ['GKBasePlayer', 'GKPlayer']! {
			cls := ios_runtime.names[name]; base := name == 'GKBasePlayer'
			for prefix in ['_OBJC_CLASS_$_', '_OBJC_METACLASS_$_']! {
				symbol := prefix + name
				assert runtime_symbol('/System/Library/Frameworks/GameKit.framework/GameKit', symbol)! == if prefix == '_OBJC_CLASS_$_' { cls } else { read64(cls) }
				for wrong in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/usr/lib/libobjc.A.dylib']! {
					if _ := runtime_symbol(wrong, symbol) { assert false }
				}
			}
			assert objc_class_size(cls) == if base { u64(8) } else { u64(32) }
			assert objc_class_parent(cls) == ios_runtime.names[if base { 'NSObject' } else { 'GKBasePlayer' }]
			assert gk_player_family(cls) && gk_player_family(read64(cls))
			for construction in [c'new', c'init']! {
				object := if construction == c'new' { player_msg(cls, c'new', 0) } else { player_msg(player_msg(cls, c'alloc', 0), c'init', 0) }
				mut weak := u64(0); objc_store_weak(&weak, object)
				mut alias_weak := u64(0)
				alias := if base { u64(0) } else { player_msg(object, c'alias', 0) }
				if !base { assert alias != 0; objc_store_weak(&alias_weak, alias) }
				for _ in 0 .. 2 {
					for selector in [c'playerID', c'displayName', c'alias', c'guestIdentifier', c'isFriend', c'isInvitable', c'scopedIDsArePersistent']! {
						if base && selector !in [c'playerID', c'displayName']! {
							assert !objc_responds(object, selector) && objc_instance_method(cls, u64(selector)) == 0
							continue
						}
						value := player_msg(object, selector, 0)
						assert value == if selector == c'alias' { alias } else { u64(0) }
						if selector == c'alias' { assert ctext(player_msg(value, c'UTF8String', 0)) == 'Unknown' }
						method := objc_instance_method(cls, u64(selector))
						assert method != 0 && objc_responds(object, selector)
						boolean := selector in [c'isFriend', c'isInvitable', c'scopedIDsArePersistent']!
						expected := if boolean { 'B16@0:8' } else { '@16@0:8' }
						assert ctext(u64(objc_method_types(method))) == expected
						assert objc_class_method(cls, u64(selector)) == 0 && !objc_responds(cls, selector)
						signature := player_msg(object, c'methodSignatureForSelector:', u64(selector))
						assert player_msg(signature, c'numberOfArguments', 0) == 2
						assert ctext(player_msg(signature, c'methodReturnType', 0)) == expected[..1]
						imp := objc_method_imp(method)
						if boolean { assert !unsafe { PlayerBool(voidptr(imp))(object, u64(selector)) } }
						else { assert unsafe { PlayerSend(voidptr(imp))(object, u64(selector), 0, 0) } == value }
					}
					init_imp := objc_method_imp(objc_instance_method(ios_runtime.names['NSObject'], u64(c'init')))
					assert unsafe { PlayerSend(voidptr(init_imp))(object, u64(c'init'), 0, 0) } == object
					if !base { assert player_msg(object, c'alias', 0) == alias }
				}
				for selector in [c'copy', c'copyWithZone:']! {
					method := objc_instance_method(cls, u64(selector))
					assert method != 0 && objc_responds(object, selector)
					assert ctext(u64(objc_method_types(method))) == if selector == c'copy' { '@16@0:8' } else { '@24@0:8^{_NSZone=}16' }
					assert unsafe { PlayerSend(voidptr(objc_method_imp(method)))(object, u64(selector), 0, 0) } == object
					assert C.ios_ref_change(unsafe { &obj_header(object).refs }, 0) == 2
					objc_release(object)
				}
				assert objc_copy_value(object, false) == object
				objc_release(object)
				for selector in [c'gamePlayerID', c'teamPlayerID', c'mutableCopy', c'mutableCopyWithZone:', c'initWithCoder:', c'encodeWithCoder:', c'supportsSecureCoding', c'classForCoder', c'valueForKey:', c'valueForKeyPath:', c'setValue:forKey:', c'addObserver:forKeyPath:options:context:', c'removeObserver:forKeyPath:', c'removeObserver:forKeyPath:context:', c'anonymousGuestPlayerWithIdentifier:', c'loadPlayersForIdentifiers:withCompletionHandler:', c'loadPhotoForSize:withCompletionHandler:', c'loadFriendPlayersWithCompletionHandler:', c'loadFriendsAuthorizationStatusWithCompletionHandler:', c'loadFriendsWithCompletionHandler:', c'loadFriends:withCompletionHandler:', c'loadChallengablePlayersWithCompletionHandler:', c'setAlias:', c'setUnknown:', c'initWithUnknown:']! {
					assert !objc_responds(object, selector) && objc_instance_method(cls, u64(selector)) == 0
					assert !objc_responds(cls, selector) && objc_class_method(cls, u64(selector)) == 0
				}
				// A copy must keep both player and its alias alive after the original release.
				assert player_msg(object, c'copy', 0) == object
				objc_release(object); assert weak == object && (base || alias_weak == alias)
				objc_release(object); assert weak == 0 && alias_weak == 0
				objc_destroy_weak(&weak); objc_destroy_weak(&alias_weak)
			}
		}
		if _ := game_center_symbol('_OBJC_CLASS_$_GKPlayerUnknown') { assert false }
		objc_pool_pop(pool); baseline := ios_runtime.live
		mut workers := []thread{}
		for _ in 0 .. 4 { workers << spawn player_worker() }
		workers.wait(); unsafe { workers.free() }
		assert ios_runtime.live == baseline
		objc_stop(); system_data_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.weak.len == 0
	}
	println('IOS-GKPLAYER: scoped imports, hierarchy, native local metadata and signatures, scalar ABI, saved IMPs, retained copies, alias ownership, four workers, two drained runtimes')
}

fn test_player_rejections() {
	objc_start(); system_data_start()!
	pool := objc_pool_push(); cls := ios_runtime.names['GKPlayer']
	object := player_msg(cls, c'new', 0); plain := objc_allocate(ios_runtime.names['NSObject'])
	modes := ['caller', 'install', 'subclass', 'metaclass', 'isa-in', 'isa-out', 'raw-getter', 'raw-copy', 'storage', 'forged-isa', 'getter-class', 'saved-wrong-receiver', 'base-alias', 'gamePlayerID', 'teamPlayerID', 'mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding', 'classForCoder', 'valueForKey:', 'valueForKeyPath:', 'setValue:forKey:', 'addObserver:forKeyPath:options:context:', 'removeObserver:forKeyPath:', 'removeObserver:forKeyPath:context:', 'anonymousGuestPlayerWithIdentifier:', 'loadPlayersForIdentifiers:withCompletionHandler:', 'loadPhotoForSize:withCompletionHandler:', 'loadFriendPlayersWithCompletionHandler:', 'loadFriendsAuthorizationStatusWithCompletionHandler:', 'loadFriendsWithCompletionHandler:', 'loadFriends:withCompletionHandler:', 'loadChallengablePlayersWithCompletionHandler:', 'setAlias:', 'setUnknown:', 'initWithUnknown:', 'class-load', 'class-guest']!
	for mode in modes {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			match mode {
				'caller' { mut storage := [4]u64{}; objc_construct_instance(cls, u64(unsafe { &storage[0] })) }
				'install' { mut storage := [4]u64{}; objc_install_storage(cls, u64(unsafe { &storage[0] }), true) }
				'subclass' { sub := objc_allocate_class(cls, c'VinixPlayer', 0); objc_register_class(sub); objc_allocate(sub) }
				'metaclass' { objc_allocate(read64(cls)) }
				'isa-in' { objc_set_class(plain, cls) }
				'isa-out' { objc_set_class(object, ios_runtime.names['NSObject']) }
				'raw-getter' { player_msg(objc_allocate(cls), c'playerID', 0) }
				'raw-copy' { objc_copy_value(objc_allocate(cls), false) }
				'storage' { obj_header(object).native_size = 16; player_msg(object, c'playerID', 0) }
				'forged-isa' { unsafe { *(&u64(plain)) = cls }; player_msg(plain, c'playerID', 0) }
				'getter-class' { player_msg(cls, c'playerID', 0) }
				'saved-wrong-receiver' { method := objc_instance_method(cls, u64(c'playerID')); unsafe { PlayerSend(voidptr(objc_method_imp(method)))(plain, u64(c'playerID'), 0, 0) } }
				'base-alias' { player_msg(player_msg(ios_runtime.names['GKBasePlayer'], c'new', 0), c'alias', 0) }
				'class-load' { player_msg(cls, c'loadPlayersForIdentifiers:withCompletionHandler:', 0) }
				'class-guest' { player_msg(cls, c'anonymousGuestPlayerWithIdentifier:', 0) }
				else { player_msg(object, mode.str, 0) }
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
			'getter-class', 'saved-wrong-receiver', 'base-alias' { 'unimplemented Objective-C method' }
			else { 'unsupported GKPlayer method:' }
		}
		assert output.contains(reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:') && !output.contains('> assert '), mode + ': ' + output
	}
	objc_release(object); objc_release(plain); objc_pool_pop(pool); objc_stop(); system_data_stop()
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	assert modes.len == 40
	println('IOS-GKPLAYER-REJECT: 40 allocation, storage, receiver, identity, mutation, coding, backend and observation cases fail explicitly')
}
