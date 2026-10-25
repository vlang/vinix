// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math

type AchievementSend = fn (u64, u64, u64, u64) u64
type AchievementDoubleGet = fn (u64, u64) f64
type AchievementDoubleSet = fn (u64, u64, f64)

fn achievement_msg(object u64, selector &char, argument u64) u64 {
	return unsafe { AchievementSend(voidptr(C.ios_objc_msgsend))(object, u64(selector), argument, 0) }
}
fn achievement_percent(object u64) f64 {
	return unsafe { AchievementDoubleGet(voidptr(C.ios_objc_msgsend))(object, u64(c'percentComplete')) }
}
fn achievement_set_percent(object u64, value f64) {
	unsafe { AchievementDoubleSet(voidptr(C.ios_objc_msgsend))(object, u64(c'setPercentComplete:'), value) }
}
fn achievement_worker() {
	for i in 0 .. 128 {
		pool := objc_pool_push()
		object := achievement_msg(ios_runtime.names['GKAchievement'], c'new', 0)
		achievement_set_percent(object, f64(i))
		assert achievement_percent(object) == f64(i)
		assert achievement_msg(object, c'isCompleted', 0) == u64(i >= 100)
		objc_release(object)
		objc_pool_pop(pool)
	}
}

__global achievement_fixture_mode = ''
__global achievement_fixture_fired = false
__global achievement_fixture_receiver = u64(0)
__global achievement_fixture_input = u64(0)
__global achievement_fixture_weak = u64(0)

fn achievement_fixture_release() {
	C.ios_objc_initialize_lock(); C.ios_objc_initialize_unlock()
	objc_release(achievement_fixture_input)
}
fn achievement_fixture_constructor(object u64, selector u64) u64 {
	if achievement_fixture_mode == '' || achievement_fixture_fired { return object }
	achievement_fixture_fired = true
	match achievement_fixture_mode {
		'release-input' { worker := spawn achievement_fixture_release(); worker.wait() }
		'fail' { objc_store_weak(unsafe { &achievement_fixture_weak }, object); return 0 }
		'reenter' { achievement_msg(achievement_fixture_receiver, c'init', 0) }
		'getter-active' { achievement_msg(achievement_fixture_receiver, c'identifier', 0) }
		'destruct-active' { objc_destruct_instance(achievement_fixture_receiver) }
		'release-receiver' { objc_release(achievement_fixture_receiver) }
		else {}
	}
	return object
}
fn achievement_fixture_hook(cls u64) {
	assert objc_add_method(cls, u64(c'.cxx_construct'), u64(unsafe { voidptr(achievement_fixture_constructor) }), c'@16@0:8')
}

fn test_achievement() {
	for _ in 0 .. 2 {
		objc_start(); system_data_start()!
		pool := objc_pool_push()
		cls := ios_runtime.names['GKAchievement']
		for prefix in ['_OBJC_CLASS_$_', '_OBJC_METACLASS_$_']! {
			symbol := prefix + 'GKAchievement'
			assert runtime_symbol('/System/Library/Frameworks/GameKit.framework/GameKit', symbol)! == if prefix == '_OBJC_CLASS_$_' { cls } else { read64(cls) }
			for wrong in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/usr/lib/libobjc.A.dylib']! {
				if _ := runtime_symbol(wrong, symbol) { assert false }
			}
		}
		if _ := game_center_symbol('_OBJC_CLASS_$_GKAchievementUnknown') { assert false }
		assert objc_class_size(cls) == 40 && objc_class_parent(cls) == ios_runtime.names['NSObject']
		assert achievement_family(cls) && achievement_family(read64(cls))
		before := cf_absolute_time()
		object := achievement_msg(cls, c'new', 0)
		date := achievement_msg(object, c'lastReportedDate', 0)
		assert obj_header(date).real_number >= before && obj_header(date).real_number <= cf_absolute_time()
		assert string_text(achievement_msg(object, c'identifier', 0)) == '*uninitialized achievement identifier*'
		assert achievement_percent(object) == 0 && achievement_msg(object, c'isCompleted', 0) == 0
		assert achievement_msg(object, c'showsCompletionBanner', 0) == 1
		other := achievement_msg(achievement_msg(cls, c'alloc', 0), c'initWithIdentifier:', 0)
		assert achievement_msg(other, c'identifier', 0) == 0 && achievement_percent(other) == 0
		for value in [f64(-1), 0, 12.5, 99.9, 100, 101, math.inf(1), math.inf(-1), math.nan()]! {
			achievement_set_percent(object, value)
			actual := achievement_percent(object)
			assert if math.is_nan(value) { math.is_nan(actual) } else { actual == value }
			assert achievement_msg(object, c'isCompleted', 0) == u64(value >= 100)
			assert achievement_msg(object, c'lastReportedDate', 0) == date
			assert achievement_percent(other) == 0
		}
		for value in [u64(0), 1, 7, 255, 256, 257, 0xffffffffffffffff]! {
			achievement_msg(object, c'setShowsCompletionBanner:', value)
			assert achievement_msg(object, c'showsCompletionBanner', 0) == u64(u8(value) != 0)
		}
		for selector in [c'init', c'initWithIdentifier:', c'identifier', c'setIdentifier:', c'percentComplete', c'setPercentComplete:', c'isCompleted', c'lastReportedDate', c'showsCompletionBanner', c'setShowsCompletionBanner:']! {
			method := objc_instance_method(cls, u64(selector))
			assert method != 0 && objc_responds(object, selector)
			assert ctext(u64(objc_method_types(method))) == achievement_types('GKAchievement', false, ctext(u64(selector)))?
			// Root NSObject instance methods are also inherited by metaclasses.
			if selector != c'init' {
				assert objc_class_method(cls, u64(selector)) == 0 && !objc_responds(cls, selector)
			}
			signature := achievement_msg(object, c'methodSignatureForSelector:', u64(selector))
			assert achievement_msg(signature, c'numberOfArguments', 0) == u64(2 + ctext(u64(selector)).count(':'))
		}
		getter := objc_method_imp(objc_instance_method(cls, u64(c'percentComplete')))
		setter := objc_method_imp(objc_instance_method(cls, u64(c'setPercentComplete:')))
		unsafe { AchievementDoubleSet(voidptr(setter))(object, u64(c'setPercentComplete:'), 42.5) }
		assert unsafe { AchievementDoubleGet(voidptr(getter))(object, u64(c'percentComplete')) } == 42.5
		// Native retains the same mutable identifier, including across init.
		name := achievement_msg(ios_runtime.names['NSMutableString'], c'new', 0)
		achievement_msg(name, c'appendString:', objc_autorelease(owned_string('mutable')))
		achievement_msg(object, c'setIdentifier:', name)
		achievement_msg(object, c'setIdentifier:', name)
		assert achievement_msg(object, c'identifier', 0) == name
		achievement_msg(name, c'appendString:', objc_autorelease(owned_string('-changed')))
		assert string_text(achievement_msg(object, c'identifier', 0)) == 'mutable-changed'
		assert achievement_msg(other, c'initWithIdentifier:', name) == other
		assert achievement_msg(other, c'identifier', 0) == name
		objc_release(name)
		// Saved NSObject init dispatches according to the receiver's family.
		init_imp := objc_method_imp(objc_instance_method(ios_runtime.names['NSObject'], u64(c'init')))
		assert unsafe { AchievementSend(voidptr(init_imp))(object, u64(c'init'), 0, 0) } == object
		assert achievement_percent(object) == 0 && achievement_msg(object, c'showsCompletionBanner', 0) == 1
		assert string_text(achievement_msg(object, c'identifier', 0)) == '*uninitialized achievement identifier*'
		for selector in [c'copy', c'copyWithZone:', c'mutableCopy', c'mutableCopyWithZone:', c'initWithCoder:', c'encodeWithCoder:', c'supportsSecureCoding', c'classForCoder', c'valueForKey:', c'valueForKeyPath:', c'setValue:forKey:', c'addObserver:forKeyPath:options:context:', c'removeObserver:forKeyPath:', c'removeObserver:forKeyPath:context:', c'player', c'playerID', c'isHidden', c'loadAchievementsWithCompletionHandler:', c'resetAchievementsWithCompletionHandler:', c'reportAchievements:withCompletionHandler:', c'reportAchievementWithCompletionHandler:', c'setUnknown:']! {
			assert !objc_responds(object, selector) && objc_instance_method(cls, u64(selector)) == 0
		}
		objc_release(object); objc_release(other)
		objc_pool_pop(pool)
		baseline := ios_runtime.live
		mut workers := []thread{}
		for _ in 0 .. 4 { workers << spawn achievement_worker() }
		workers.wait(); unsafe { workers.free() }
		assert ios_runtime.live == baseline
		// Date constructor callbacks run outside the lock and input is pinned.
		achievement_fixture_hook(cf_date_id())
		input := owned_string('retained during constructor')
		achievement_fixture_input = input; achievement_fixture_mode = 'release-input'; achievement_fixture_fired = false
		pinned := achievement_msg(achievement_msg(cls, c'alloc', 0), c'initWithIdentifier:', input)
		achievement_fixture_mode = ''; achievement_fixture_input = 0
		assert achievement_fixture_fired && obj_header(pinned).fields[0] == input
		objc_release(pinned)
		// Both default-string and date allocation failure consume the receiver
		// and release temporaries, including previously initialized fields.
		achievement_fixture_hook(ios_runtime.names['NSString'])
		for initialized in [false, true]! {
			for constructor in [ios_runtime.names['NSString'], cf_date_id()]! {
				inner := objc_pool_push()
				receiver := if initialized { achievement_msg(cls, c'new', 0) } else { achievement_msg(cls, c'alloc', 0) }
				mut weak_receiver := u64(0); objc_store_weak(&weak_receiver, receiver)
				// Disable the other hook so failure occurs at the intended stage.
				other_class := if constructor == cf_date_id() { ios_runtime.names['NSString'] } else { cf_date_id() }
				method := objc_instance_method(other_class, u64(c'.cxx_construct'))
				original := objc_method_set_imp(method, u64(unsafe { voidptr(achievement_fixture_passthrough) }))
				achievement_fixture_mode = 'fail'; achievement_fixture_fired = false
				assert achievement_msg(receiver, c'init', 0) == 0
				achievement_fixture_mode = ''
				objc_method_set_imp(method, original)
				assert achievement_fixture_fired && weak_receiver == 0 && achievement_fixture_weak == 0
				objc_destroy_weak(&weak_receiver); objc_destroy_weak(unsafe { &achievement_fixture_weak })
				objc_pool_pop(inner)
				assert ios_runtime.live == baseline
			}
		}
		objc_stop(); system_data_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.weak.len == 0
	}
	println('IOS-GKACHIEVEMENT: scoped imports, native signatures and defaults, floating ABI, mutable identity, creation dates, saved IMPs, constructor rollback, four workers, two drained runtimes')
}
fn achievement_fixture_passthrough(object u64, selector u64) u64 { return object }

fn test_achievement_rejections() {
	objc_start(); system_data_start()!
	pool := objc_pool_push(); cls := ios_runtime.names['GKAchievement']
	object := achievement_msg(cls, c'new', 0); plain := objc_allocate(ios_runtime.names['NSObject'])
	for mode in ['caller', 'install', 'subclass', 'metaclass', 'directcopy', 'isa-in', 'isa-out', 'raw-getter', 'storage', 'forged-isa', 'getter-class', 'saved-wrong-receiver', 'identifier-type', 'identifier-raw', 'reenter', 'getter-active', 'destruct-active', 'release-receiver', 'copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding', 'classForCoder', 'valueForKey:', 'valueForKeyPath:', 'setValue:forKey:', 'addObserver:forKeyPath:options:context:', 'removeObserver:forKeyPath:', 'removeObserver:forKeyPath:context:', 'player', 'playerID', 'isHidden', 'loadAchievementsWithCompletionHandler:', 'resetAchievementsWithCompletionHandler:', 'reportAchievements:withCompletionHandler:', 'reportAchievementWithCompletionHandler:', 'setUnknown:', 'initWithUnknown:']! {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			match mode {
				'caller' { mut storage := [5]u64{}; objc_construct_instance(cls, u64(unsafe { &storage[0] })) }
				'install' { mut storage := [5]u64{}; objc_install_storage(cls, u64(unsafe { &storage[0] }), true) }
				'subclass' { sub := objc_allocate_class(cls, c'VinixAchievement', 0); objc_register_class(sub); objc_allocate(sub) }
				'metaclass' { objc_allocate(read64(cls)) }
				'directcopy' { objc_copy_value(object, false) }
				'isa-in' { objc_set_class(plain, cls) }
				'isa-out' { objc_set_class(object, ios_runtime.names['NSObject']) }
				'raw-getter' { achievement_msg(objc_allocate(cls), c'identifier', 0) }
				'storage' { obj_header(object).native_size = 16; achievement_msg(object, c'identifier', 0) }
				'forged-isa' { unsafe { *(&u64(plain)) = cls }; achievement_msg(plain, c'identifier', 0) }
				'getter-class' { achievement_msg(cls, c'identifier', 0) }
				'saved-wrong-receiver' { method := objc_instance_method(cls, u64(c'identifier')); unsafe { AchievementSend(voidptr(objc_method_imp(method)))(plain, u64(c'identifier'), 0, 0) } }
				'identifier-type' { achievement_msg(object, c'setIdentifier:', plain) }
				'identifier-raw' { achievement_msg(object, c'setIdentifier:', objc_allocate(ios_runtime.names['NSMutableString'])) }
				'reenter', 'getter-active', 'destruct-active', 'release-receiver' {
					achievement_fixture_receiver = object; achievement_fixture_mode = mode; achievement_fixture_fired = false
					achievement_fixture_hook(cf_date_id()); achievement_msg(object, c'init', 0)
				}
				else { achievement_msg(object, mode.str, 0) }
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
			'caller', 'install', 'subclass', 'metaclass' { 'GKAchievement requires built-in allocation' }
			'isa-in', 'isa-out' { 'changing GKAchievement storage isa is not implemented' }
			'raw-getter' { 'GKAchievement requires initialization' }
			'storage', 'forged-isa' { 'GKAchievement requires live built-in storage' }
			'getter-class', 'saved-wrong-receiver' { 'unimplemented Objective-C method' }
			'identifier-type', 'identifier-raw' { 'achievement identifier requires' }
			'reenter', 'getter-active' { 'GKAchievement initialization is active' }
			'destruct-active' { 'destroying an active GKAchievement' }
			'release-receiver' { 'consumed receiver ownership' }
			else { 'unsupported GKAchievement method:' }
		}
		assert output.contains(reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:') && !output.contains('> assert '), mode + ': ' + output
	}
	objc_release(object); objc_release(plain); objc_pool_pop(pool); objc_stop(); system_data_stop()
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	println('IOS-GKACHIEVEMENT-REJECT: 41 allocation, storage, receiver, identifier, constructor, copy, coding, backend and observation cases fail explicitly')
}
