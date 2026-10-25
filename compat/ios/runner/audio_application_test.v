// SPDX-License-Identifier: GPL-2.0-or-later
module main

type AudioApplicationSend = fn (u64, u64, u64) u64

fn audio_application_msg(object u64, selector &char, argument u64) u64 {
	return unsafe { AudioApplicationSend(voidptr(C.ios_objc_msgsend))(object, u64(selector), argument) }
}

struct AudioApplicationBlockState {
mut:
	calls int
	granted bool
	object u64
}
struct AudioApplicationBlockDescriptor { reserved u64 size u64 }
struct AudioApplicationBlockLiteral { isa u64 flags u32 reserved u32 invoke u64 descriptor u64 capture u64 }

fn audio_application_reader(expected u64) {
	pool := objc_pool_push()
	for _ in 0 .. 128 {
		object := audio_application_msg(ios_runtime.names['AVAudioApplication'], c'sharedInstance', 0)
		assert object == expected
		assert audio_application_msg(object, c'recordPermission', 0) == audio_application_denied
		assert audio_application_msg(object, c'isInputMuted', 0) == 0
		assert audio_application_msg(object, c'retain', 0) == object
		audio_application_msg(object, c'release', 0)
	}
	objc_pool_pop(pool)
}

fn audio_application_permission_complete(block u64, granted bool) {
	mut state := unsafe { &AudioApplicationBlockState(read64(block + 32)) }
	state.calls++
	state.granted = granted
	// A separate thread detects a lock accidentally held around client code.
	worker := spawn audio_application_reader(state.object)
	worker.wait()
}

fn test_audio_application() {
	for _ in 0 .. 2 {
		objc_start()
		pool := objc_pool_push()
		cls := ios_runtime.names['AVAudioApplication']
		library := '/System/Library/Frameworks/AVFAudio.framework/AVFAudio'
		for prefix in ['_OBJC_CLASS_$_', '_OBJC_METACLASS_$_']! {
			symbol := prefix + 'AVAudioApplication'
			assert runtime_symbol(library, symbol)! == if prefix == '_OBJC_CLASS_$_' { cls } else { read64(cls) }
			for wrong in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libobjc.A.dylib']! {
				if _ := runtime_symbol(wrong, symbol) { assert false }
			}
		}
		if _ := audio_application_symbol('_OBJC_CLASS_$_AVAudioApplicationUnknown') { assert false }
		assert objc_class_size(cls) == 24 && objc_class_parent(cls) == ios_runtime.names['NSObject']
		object := audio_application_msg(cls, c'sharedInstance', 0)
		assert object != 0 && audio_application_msg(cls, c'sharedInstance', 0) == object
		assert obj_header(object).refs == 1
		assert audio_application_msg(object, c'class', 0) == cls
		assert audio_application_msg(object, c'isKindOfClass:', ios_runtime.names['NSObject']) != 0
		for meta in [false, true]! {
			for selector in ['sharedInstance', 'recordPermission', 'isInputMuted', 'requestRecordPermissionWithCompletionHandler:']! {
				expected := audio_application_types('AVAudioApplication', meta, selector)
				method := if meta { objc_class_method(cls, u64(selector.str)) } else { objc_instance_method(cls, u64(selector.str)) }
				receiver := if meta { cls } else { object }
				if types := expected {
					assert method != 0 && ctext(u64(objc_method_types(method))) == types
					assert objc_responds(receiver, selector.str)
					signature := audio_application_msg(receiver, c'methodSignatureForSelector:', u64(selector.str))
					assert signature != 0
					completion := selector == 'requestRecordPermissionWithCompletionHandler:'
					assert audio_application_msg(signature, c'numberOfArguments', 0) == if completion { u64(3) } else { u64(2) }
					assert ctext(audio_application_msg(signature, c'methodReturnType', 0)) == types[..1]
					if completion { assert ctext(audio_application_msg(signature, c'getArgumentTypeAtIndex:', 2)) == '@?' }
				} else {
					assert method == 0 && !objc_responds(receiver, selector.str)
				}
			}
		}
		for selector in [c'alloc', c'new', c'init', c'copy', c'mutableCopy', c'initWithCoder:', c'encodeWithCoder:', c'supportsSecureCoding', c'classForCoder', c'microphoneInjectionPermission', c'requestMicrophoneInjectionPermissionWithCompletionHandler:', c'setInputMuted:error:', c'setInputMuted:context:error:', c'setInputMuteStateChangeHandler:error:']! {
			assert !objc_responds(object, selector) && !objc_responds(cls, selector)
			assert objc_instance_method(cls, u64(selector)) == 0 && objc_class_method(cls, u64(selector)) == 0
		}
		baseline := ios_runtime.live
		mut workers := []thread{}
		for _ in 0 .. 4 { workers << spawn audio_application_reader(object) }
		workers.wait()
		unsafe { workers.free() }
		descriptor := AudioApplicationBlockDescriptor{0, sizeof(AudioApplicationBlockLiteral)}
		mut state := AudioApplicationBlockState{granted: true, object: object}
		literal := AudioApplicationBlockLiteral{block_isa(0), 0, 0, u64(unsafe { voidptr(audio_application_permission_complete) }), u64(unsafe { &descriptor }), u64(unsafe { &state })}
		for receiver in [cls, object]! {
			before := state.calls
			assert audio_application_msg(receiver, c'requestRecordPermissionWithCompletionHandler:', u64(unsafe { &literal })) == 0
			assert state.calls == before + 1 && !state.granted
		}
		assert ios_runtime.live == baseline && ios_runtime.block_refs.len == 0
		objc_pool_pop(pool)
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.block_refs.len == 0
	}
	println('IOS-AUDIO-APPLICATION: scoped imports, 24-byte singleton, typed reflection, denied record permission, synchronous false completions, callback reentry, four readers and two drained runtimes')
}

fn test_audio_application_rejections() {
	objc_start()
	cls := ios_runtime.names['AVAudioApplication']
	object := audio_application_msg(cls, c'sharedInstance', 0)
	for mode in ['alloc', 'new', 'init', 'copy', 'mutableCopy', 'encodeWithCoder:', 'allocate', 'caller', 'subclass', 'subclass-shared', 'isa-out', 'isa-in', 'destroy', 'release-borrowed', 'retired', 'nil-class-block', 'nil-instance-block', 'microphoneInjectionPermission', 'setInputMuted:error:']! {
		mut fds := [2]i32{}
		assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.fork()
		assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			match mode {
				'allocate' { objc_allocate(cls) }
				'caller' { mut storage := [3]u64{}; objc_construct_instance(cls, u64(unsafe { &storage[0] })) }
				'subclass', 'subclass-shared' {
					sub := objc_allocate_class(cls, c'VinixAudioApplication', 0); objc_register_class(sub)
					if mode == 'subclass' { objc_allocate(sub) } else { audio_application_msg(sub, c'sharedInstance', 0) }
				}
				'isa-out' { objc_set_class(object, ios_runtime.names['NSObject']) }
				'isa-in' { objc_set_class(objc_allocate(ios_runtime.names['NSObject']), cls) }
				'destroy' { objc_destruct_instance(object) }
				'release-borrowed' { objc_release(object) }
				'retired' { audio_application_stop(); audio_application_msg(cls, c'sharedInstance', 0) }
				'nil-class-block' { audio_application_msg(cls, c'requestRecordPermissionWithCompletionHandler:', 0) }
				'nil-instance-block' { audio_application_msg(object, c'requestRecordPermissionWithCompletionHandler:', 0) }
				'alloc', 'new' { audio_application_msg(cls, mode.str, 0) }
				else { audio_application_msg(object, mode.str, 0) }
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
			'isa-out', 'isa-in' { 'changing audio application storage isa is not implemented' }
			'destroy', 'release-borrowed' { 'destroying cached audio application storage' }
			'subclass-shared' { 'custom audio application subclasses are not implemented' }
			'retired' { 'audio application cache is retired' }
			'nil-class-block', 'nil-instance-block' { 'audio record permission requires a completion block' }
			'microphoneInjectionPermission', 'setInputMuted:error:' { 'unimplemented Objective-C method' }
			else { 'AVAudioApplication requires sharedInstance' }
		}
		assert output.contains(reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), mode + ': ' + output
	}
	objc_stop()
	assert ios_runtime.live == 0
	println('IOS-AUDIO-APPLICATION-REJECT: 19 construction, caller storage, subclass, isa, destruction, retirement, nil completion and unsupported input cases fail explicitly')
}
