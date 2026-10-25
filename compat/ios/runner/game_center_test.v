// SPDX-License-Identifier: GPL-2.0-or-later
module main

type GameCenterSend = fn (u64, u64, u64, u64) u64

fn game_center_msg(object u64, selector &char, a u64, b u64) u64 {
	return unsafe { GameCenterSend(voidptr(C.ios_objc_msgsend))(object, u64(selector), a, b) }
}

fn test_game_center_descriptors() {
	for _ in 0 .. 2 {
		objc_start()
		pool := objc_pool_push()
		nav := ios_runtime.names['UINavigationController']
		game := ios_runtime.names['GKGameCenterViewController']
		assert objc_class_parent(game) == nav
		assert objc_class_parent(nav) == ios_runtime.names['UIViewController']
		assert objc_class_parent(read64(game)) == read64(nav)
		assert objc_class_parent(read64(nav)) == read64(ios_runtime.names['UIViewController'])
		for name in ['UINavigationController', 'GKGameCenterViewController']! {
			cls := ios_runtime.names[name]
			assert ctext(u64(objc_class_name(cls))) == name
			assert !objc_class_meta(cls) && objc_class_meta(read64(cls))
			// These are shim descriptors, not a claim about Apple's private layout.
			assert objc_class_size(cls) == objc_class_size(ios_runtime.names['UIViewController'])
			framework := if cls == nav { 'UIKit' } else { 'GameKit' }
			for prefix in ['_OBJC_CLASS_$_', '_OBJC_METACLASS_$_']! {
				symbol := prefix + name
				assert runtime_symbol('/System/Library/Frameworks/' + framework + '.framework/' + framework, symbol)! == if prefix == '_OBJC_CLASS_$_' { cls } else { read64(cls) }
				for wrong in ['Foundation', 'UIKit', 'GameKit', 'GameController']! {
					if wrong == framework { continue }
					if _ := runtime_symbol('/System/Library/Frameworks/' + wrong + '.framework/' + wrong, symbol) { assert false, wrong + ': ' + symbol }
				}
				if _ := runtime_symbol('/usr/lib/libobjc.A.dylib', symbol) { assert false }
			}
			assert navigation_descriptor_family(cls) && navigation_descriptor_family(read64(cls))
			assert game_center_msg(cls, c'class', 0, 0) == cls
			assert objc_class_method(cls, u64(c'class')) != 0
			sub_name := 'Vinix' + name
			sub := objc_allocate_class(cls, sub_name.str, 0)
			objc_register_class(sub)
			assert objc_class_parent(sub) == cls && navigation_descriptor_family(sub)
			for target in [cls, sub]! {
				for selector in [c'alloc', c'allocWithZone:', c'new', c'init', c'initWithCoder:',
					c'initWithState:', c'initWithRootViewController:', c'initWithNibName:bundle:',
					c'copy', c'copyWithZone:', c'mutableCopy', c'mutableCopyWithZone:',
					c'encodeWithCoder:', c'supportsSecureCoding', c'classForCoder',
					c'gameCenterDelegate', c'setGameCenterDelegate:', c'viewState', c'setViewState:',
					c'viewControllers', c'pushViewController:animated:', c'popViewControllerAnimated:']! {
					assert objc_instance_method(target, u64(selector)) == 0, ctext(u64(selector))
					assert objc_class_method(target, u64(selector)) == 0, ctext(u64(selector))
					assert !objc_responds(target, selector), ctext(u64(selector))
				}
			}
		}
		if _ := runtime_symbol('/System/Library/Frameworks/GameKit.framework/GameKit', '_OBJC_CLASS_$_GKVoiceChat') { assert false }
		assert !navigation_descriptor_family(ios_runtime.names['UIViewController'])
		objc_pool_pop(pool)
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-GAMECENTER: scoped class/metaclass imports, SDK inheritance, subclass metadata, truthful reflection and two drained runtimes')
}

fn test_game_center_construction_rejected() {
	objc_start()
	for name in ['UINavigationController', 'GKGameCenterViewController']! {
		cls := ios_runtime.names[name]
		sub_name := 'Blocked' + name
		sub := objc_allocate_class(cls, sub_name.str, 0)
		objc_register_class(sub)
		for mode in ['alloc', 'allocWithZone:', 'new', 'init', 'initWithState:', 'copy',
			'allocate', 'caller', 'install', 'subclass', 'super-alloc', 'super-new', 'isa-in', 'isa-subclass', 'isa-out']! {
			mut fds := [2]i32{}
			assert C.pipe(unsafe { &fds[0] }) == 0
			pid := C.fork()
			assert pid >= 0
			if pid == 0 {
				C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
				match mode {
					'allocate' { objc_allocate(cls) }
					'caller' { mut storage := [1]u64{}; objc_construct_instance(cls, u64(unsafe { &storage[0] })) }
					'install' { mut storage := [1]u64{}; objc_install_storage(cls, u64(unsafe { &storage[0] }), true) }
					'subclass' { objc_allocate(sub) }
					'super-alloc', 'super-new' {
						selector := if mode == 'super-alloc' { c'alloc' } else { c'new' }
						method := objc_class_method(ios_runtime.names['NSObject'], u64(selector))
						assert method != 0
						unsafe { GameCenterSend(voidptr(objc_method_imp(method)))(cls, u64(selector), 0, 0) }
					}
					'isa-in', 'isa-subclass' { objc_set_class(objc_allocate(ios_runtime.names['NSObject']), if mode == 'isa-in' { cls } else { sub }) }
					'isa-out' {
						object := objc_allocate(ios_runtime.names['NSObject'])
						// Simulate a corrupt allocation header without constructing UI.
						obj_header(object).allocation_cls = cls
						objc_set_class(object, ios_runtime.names['NSObject'])
					}
					else { game_center_msg(cls, mode.str, 0, 0) }
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
			assert C.ios_waitpid(pid, &status, 0) == pid && status == 256, name + ': ' + mode
			output := unsafe { tos(&bytes[0], length) }
			reason := if mode.starts_with('isa-') { 'changing navigation controller storage isa is not implemented' } else { 'navigation and Game Center controller construction requires an implemented UI' }
			assert output.contains(reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:') && !output.contains('> assert '), name + ': ' + mode + ': ' + output
		}
	}
	objc_stop()
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	println('IOS-GAMECENTER-REJECT: 30 dispatch, direct/caller allocation, subclass, saved NSObject IMP and isa cases fail explicitly')
}
