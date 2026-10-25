// SPDX-License-Identifier: GPL-2.0-or-later
module main

type AchievementDescriptionSend = fn (u64, u64, u64, u64) u64
type AchievementDescriptionPoints = fn (u64, u64) u16

fn achievement_description_msg(object u64, selector &char, argument u64) u64 {
	return unsafe { AchievementDescriptionSend(voidptr(C.ios_objc_msgsend))(object, u64(selector), argument, 0) }
}

fn achievement_description_worker() {
	for _ in 0 .. 128 {
		pool := objc_pool_push()
		object := achievement_description_msg(ios_runtime.names['GKAchievementDescription'], c'new', 0)
		assert achievement_description_msg(object, c'identifier', 0) == 0
		assert achievement_description_msg(object, c'maximumPoints', 0) == 0
		assert achievement_description_msg(object, c'init', 0) == object
		objc_release(object)
		objc_pool_pop(pool)
	}
}

fn test_achievement_description() {
	for _ in 0 .. 2 {
		objc_start(); system_data_start()!
		pool := objc_pool_push()
		cls := ios_runtime.names['GKAchievementDescription']
		for prefix in ['_OBJC_CLASS_$_', '_OBJC_METACLASS_$_']! {
			symbol := prefix + 'GKAchievementDescription'
			assert runtime_symbol('/System/Library/Frameworks/GameKit.framework/GameKit', symbol)! == if prefix == '_OBJC_CLASS_$_' { cls } else { read64(cls) }
			for wrong in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/usr/lib/libobjc.A.dylib']! {
				if _ := runtime_symbol(wrong, symbol) { assert false }
			}
		}
		if _ := game_center_symbol('_OBJC_CLASS_$_GKAchievementDescriptionUnknown') { assert false }
		assert objc_class_size(cls) == 24 && objc_class_parent(cls) == ios_runtime.names['NSObject']
		assert achievement_description_family(cls) && achievement_description_family(read64(cls))
		for construction in [c'new', c'init']! {
			object := if construction == c'new' { achievement_description_msg(cls, c'new', 0) }
				else { achievement_description_msg(achievement_description_msg(cls, c'alloc', 0), c'init', 0) }
			assert object != 0
			mut weak := u64(0); objc_store_weak(&weak, object)
			for _ in 0 .. 2 {
				for selector in [c'identifier', c'groupIdentifier', c'title', c'achievedDescription', c'unachievedDescription', c'maximumPoints', c'isHidden', c'isReplayable', c'image', c'rarityPercent', c'releaseState', c'activityIdentifier', c'activityProperties']! {
					assert achievement_description_msg(object, selector, 0) == 0
					method := objc_instance_method(cls, u64(selector))
					assert method != 0 && objc_responds(object, selector)
					expected := match ctext(u64(selector)) {
						'maximumPoints' { 'S16@0:8' }
						'isHidden', 'isReplayable' { 'B16@0:8' }
						'releaseState' { 'Q16@0:8' }
						else { '@16@0:8' }
					}
					assert ctext(u64(objc_method_types(method))) == expected
					assert objc_class_method(cls, u64(selector)) == 0 && !objc_responds(cls, selector)
					signature := achievement_description_msg(object, c'methodSignatureForSelector:', u64(selector))
					assert achievement_description_msg(signature, c'numberOfArguments', 0) == 2
					assert ctext(achievement_description_msg(signature, c'methodReturnType', 0)) == expected[..1]
					imp := objc_method_imp(method)
					assert unsafe { AchievementDescriptionSend(voidptr(imp))(object, u64(selector), 0, 0) } == 0
				}
				points := objc_method_imp(objc_instance_method(cls, u64(c'maximumPoints')))
				assert unsafe { AchievementDescriptionPoints(voidptr(points))(object, u64(c'maximumPoints')) } == 0
				// Inherited/saved NSObject init must initialize the actual family.
				init_imp := objc_method_imp(objc_instance_method(ios_runtime.names['NSObject'], u64(c'init')))
				assert unsafe { AchievementDescriptionSend(voidptr(init_imp))(object, u64(c'init'), 0, 0) } == object
			}
			for selector in [c'copy', c'copyWithZone:', c'mutableCopy', c'mutableCopyWithZone:', c'initWithCoder:', c'encodeWithCoder:', c'supportsSecureCoding', c'classForCoder', c'valueForKey:', c'valueForKeyPath:', c'setValue:forKey:', c'addObserver:forKeyPath:options:context:', c'removeObserver:forKeyPath:', c'removeObserver:forKeyPath:context:', c'loadAchievementDescriptionsWithCompletionHandler:', c'loadImageWithCompletionHandler:', c'incompleteAchievementImage', c'placeholderCompletedAchievementImage', c'setIdentifier:', c'setMaximumPoints:', c'setUnknown:']! {
				assert !objc_responds(object, selector) && objc_instance_method(cls, u64(selector)) == 0
				assert !objc_responds(cls, selector) && objc_class_method(cls, u64(selector)) == 0
			}
			objc_release(object)
			assert weak == 0; objc_destroy_weak(&weak)
		}
		objc_pool_pop(pool)
		baseline := ios_runtime.live
		mut workers := []thread{}
		for _ in 0 .. 4 { workers << spawn achievement_description_worker() }
		workers.wait(); unsafe { workers.free() }
		assert ios_runtime.live == baseline
		objc_stop(); system_data_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.weak.len == 0
	}
	println('IOS-GKACHIEVEMENTDESCRIPTION: scoped imports, native empty metadata and signatures, scalar ABI, saved IMPs, reinitialization, weak ownership, four workers, two drained runtimes')
}

fn test_achievement_description_rejections() {
	objc_start(); system_data_start()!
	pool := objc_pool_push(); cls := ios_runtime.names['GKAchievementDescription']
	object := achievement_description_msg(cls, c'new', 0); plain := objc_allocate(ios_runtime.names['NSObject'])
	for mode in ['caller', 'install', 'subclass', 'metaclass', 'directcopy', 'isa-in', 'isa-out', 'raw-getter', 'storage', 'forged-isa', 'getter-class', 'saved-wrong-receiver', 'copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding', 'classForCoder', 'valueForKey:', 'valueForKeyPath:', 'setValue:forKey:', 'addObserver:forKeyPath:options:context:', 'removeObserver:forKeyPath:', 'removeObserver:forKeyPath:context:', 'loadAchievementDescriptionsWithCompletionHandler:', 'loadImageWithCompletionHandler:', 'incompleteAchievementImage', 'placeholderCompletedAchievementImage', 'setIdentifier:', 'setMaximumPoints:', 'setUnknown:', 'initWithUnknown:', 'class-load', 'class-image']! {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			match mode {
				'caller' { mut storage := [3]u64{}; objc_construct_instance(cls, u64(unsafe { &storage[0] })) }
				'install' { mut storage := [3]u64{}; objc_install_storage(cls, u64(unsafe { &storage[0] }), true) }
				'subclass' { sub := objc_allocate_class(cls, c'VinixAchievementDescription', 0); objc_register_class(sub); objc_allocate(sub) }
				'metaclass' { objc_allocate(read64(cls)) }
				'directcopy' { objc_copy_value(object, false) }
				'isa-in' { objc_set_class(plain, cls) }
				'isa-out' { objc_set_class(object, ios_runtime.names['NSObject']) }
				'raw-getter' { achievement_description_msg(objc_allocate(cls), c'identifier', 0) }
				'storage' { obj_header(object).native_size = 16; achievement_description_msg(object, c'identifier', 0) }
				'forged-isa' { unsafe { *(&u64(plain)) = cls }; achievement_description_msg(plain, c'identifier', 0) }
				'getter-class' { achievement_description_msg(cls, c'identifier', 0) }
				'saved-wrong-receiver' { method := objc_instance_method(cls, u64(c'identifier')); unsafe { AchievementDescriptionSend(voidptr(objc_method_imp(method)))(plain, u64(c'identifier'), 0, 0) } }
				'class-load' { achievement_description_msg(cls, c'loadAchievementDescriptionsWithCompletionHandler:', 0) }
				'class-image' { achievement_description_msg(cls, c'incompleteAchievementImage', 0) }
				else { achievement_description_msg(object, mode.str, 0) }
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
			'caller', 'install', 'subclass', 'metaclass' { 'GKAchievementDescription requires built-in allocation' }
			'isa-in', 'isa-out' { 'changing GKAchievementDescription storage isa is not implemented' }
			'raw-getter' { 'GKAchievementDescription requires initialization' }
			'storage', 'forged-isa' { 'GKAchievementDescription requires live built-in storage' }
			'getter-class', 'saved-wrong-receiver' { 'unimplemented Objective-C method' }
			else { 'unsupported GKAchievementDescription method:' }
		}
		assert output.contains(reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:') && !output.contains('> assert '), mode + ': ' + output
	}
	objc_release(object); objc_release(plain); objc_pool_pop(pool); objc_stop(); system_data_stop()
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	println('IOS-GKACHIEVEMENTDESCRIPTION-REJECT: 36 allocation, storage, receiver, mutation, copy, coding, backend and observation cases fail explicitly')
}
