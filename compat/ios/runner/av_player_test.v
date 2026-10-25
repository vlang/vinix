// SPDX-License-Identifier: GPL-2.0-or-later
module main

type AvPlayerSend = fn (u64, u64, u64, u64) u64

fn av_player_msg(object u64, selector &char, a u64, b u64) u64 {
	return unsafe { AvPlayerSend(voidptr(C.ios_objc_msgsend))(object, u64(selector), a, b) }
}

fn test_av_player_descriptors() {
	names := ['AVAsset', 'AVURLAsset', 'AVPlayer', 'AVPlayerItem', 'AVPlayerItemOutput',
		'AVPlayerItemLegibleOutput', 'AVPlayerItemVideoOutput']!
	parents := ['NSObject', 'AVAsset', 'NSObject', 'NSObject', 'NSObject',
		'AVPlayerItemOutput', 'AVPlayerItemOutput']!
	for _ in 0 .. 2 {
		objc_start()
		pool := objc_pool_push()
		for i, name in names {
			cls := ios_runtime.names[name]
			parent := ios_runtime.names[parents[i]]
			assert objc_class_parent(cls) == parent
			assert objc_class_parent(read64(cls)) == read64(parent)
			assert ctext(u64(objc_class_name(cls))) == name
			assert !objc_class_meta(cls) && objc_class_meta(read64(cls))
			// Descriptor storage only, not Apple's private instance layout.
			assert objc_class_size(cls) == 8
			for prefix in ['_OBJC_CLASS_$_', '_OBJC_METACLASS_$_']! {
				symbol := prefix + name
				assert runtime_symbol('/System/Library/Frameworks/AVFoundation.framework/AVFoundation', symbol)! == if prefix == '_OBJC_CLASS_$_' { cls } else { read64(cls) }
				for wrong in ['Foundation', 'UIKit', 'GameKit', 'GameController']! {
					if _ := runtime_symbol('/System/Library/Frameworks/' + wrong + '.framework/' + wrong, symbol) { assert false, wrong + ': ' + symbol }
				}
				if _ := runtime_symbol('/usr/lib/libobjc.A.dylib', symbol) { assert false }
			}
			assert av_player_family(cls) && av_player_family(read64(cls))
			assert av_player_msg(cls, c'class', 0, 0) == cls
			assert av_player_msg(cls, c'superclass', 0, 0) == parent
			assert objc_class_method(cls, u64(c'class')) != 0
			assert objc_class_method(cls, u64(c'superclass')) != 0
			sub_name := 'Vinix' + name
			sub := objc_allocate_class(cls, sub_name.str, 0)
			objc_register_class(sub)
			assert objc_class_parent(sub) == cls && av_player_family(sub)
			assert av_player_family(read64(sub))
			assert av_player_msg(sub, c'superclass', 0, 0) == cls
			for target in [cls, sub]! {
				for selector in [c'alloc', c'allocWithZone:', c'new', c'init', c'copy', c'copyWithZone:',
					c'mutableCopy', c'mutableCopyWithZone:', c'initWithCoder:', c'encodeWithCoder:',
					c'classForCoder', c'supportsSecureCoding', c'initWithURL:options:', c'URLAssetWithURL:options:',
					c'assetWithURL:', c'playerWithURL:', c'playerItemWithAsset:', c'initWithAsset:',
					c'initWithPixelBufferAttributes:', c'initWithMediaSubtypesForNativeRepresentation:',
					c'play', c'pause', c'rate', c'setRate:', c'currentItem', c'currentTime', c'duration',
					c'status', c'error', c'addOutput:', c'setDelegate:queue:', c'copyPixelBufferForItemTime:itemTimeForDisplay:']! {
					assert objc_instance_method(target, u64(selector)) == 0, ctext(u64(selector))
					assert objc_class_method(target, u64(selector)) == 0, ctext(u64(selector))
					assert !objc_responds(target, selector), ctext(u64(selector))
				}
			}
		}
		if _ := runtime_symbol('/System/Library/Frameworks/AVFoundation.framework/AVFoundation', '_OBJC_CLASS_$_AVQueuePlayer') { assert false }
		assert !av_player_family(ios_runtime.names['NSObject'])
		assert !av_player_family(ios_runtime.names['AVAudioSession'])
		objc_pool_pop(pool)
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-AVPLAYER: seven scoped class/metaclass imports, native inheritance, subclass metadata, truthful reflection and two drained runtimes')
}

fn test_av_player_construction_rejected() {
	objc_start()
	for name in ['AVAsset', 'AVURLAsset', 'AVPlayer', 'AVPlayerItem', 'AVPlayerItemOutput',
		'AVPlayerItemLegibleOutput', 'AVPlayerItemVideoOutput']! {
		cls := ios_runtime.names[name]
		sub_name := 'Blocked' + name
		sub := objc_allocate_class(cls, sub_name.str, 0)
		objc_register_class(sub)
		for mode in ['alloc', 'allocWithZone:', 'new', 'init', 'initWithURL:options:', 'initWithAsset:', 'copy',
			'allocate', 'caller', 'install', 'subclass', 'super-alloc', 'super-new', 'isa-in', 'isa-subclass', 'isa-out',
			'playerWithURL:', 'playerItemWithAsset:', 'URLAssetWithURL:options:', 'play']! {
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
						unsafe { AvPlayerSend(voidptr(objc_method_imp(method)))(cls, u64(selector), 0, 0) }
					}
					'isa-in', 'isa-subclass' { objc_set_class(objc_allocate(ios_runtime.names['NSObject']), if mode == 'isa-in' { cls } else { sub }) }
					'isa-out' {
						object := objc_allocate(ios_runtime.names['NSObject'])
						// Simulate corrupt storage without constructing a player.
						obj_header(object).allocation_cls = cls
						objc_set_class(object, ios_runtime.names['NSObject'])
					}
					else { av_player_msg(cls, mode.str, 0, 0) }
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
			reason := if mode.starts_with('isa-') { 'changing AVFoundation playback storage isa is not implemented' } else { 'AVFoundation player, asset and output construction or playback is not implemented' }
			assert output.contains(reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:') && !output.contains('> assert '), name + ': ' + mode + ': ' + output
		}
	}
	objc_stop()
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	println('IOS-AVPLAYER-REJECT: 140 dispatch, factories, direct/caller allocation, subclass, saved NSObject IMP and isa cases fail explicitly')
}
