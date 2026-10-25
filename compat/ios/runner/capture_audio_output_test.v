// SPDX-License-Identifier: GPL-2.0-or-later
module main

type CaptureAudioSend = fn (u64, u64, u64, u64) u64

fn audio_output_msg(object u64, selector &char, a u64, b u64) u64 {
	return unsafe { CaptureAudioSend(voidptr(C.ios_objc_msgsend))(object, u64(selector), a, b) }
}

fn audio_output_worker() {
	for _ in 0 .. 128 {
		pool := objc_pool_push()
		output := audio_output_msg(ios_runtime.names['AVCaptureAudioDataOutput'], c'new', 0, 0)
		delegate := objc_allocate(ios_runtime.names['NSObject'])
		queue := darwin_dispatch_queue_create(c'vinix.capture.audio', 0)
		audio_output_msg(output, c'setSampleBufferDelegate:queue:', delegate, queue)
		assert audio_output_msg(output, c'sampleBufferDelegate', 0, 0) == delegate
		assert audio_output_msg(output, c'sampleBufferCallbackQueue', 0, 0) == queue
		darwin_dispatch_release(queue)
		objc_release(delegate)
		objc_release(output)
		objc_pool_pop(pool)
		assert !dispatch_objc_is_queue(queue)
	}
}

fn test_capture_audio_output() {
	for _ in 0 .. 2 {
		objc_start()
		system_data_start()!
		pool := objc_pool_push()
		cls := ios_runtime.names['AVCaptureAudioDataOutput']
		base := ios_runtime.names['AVCaptureOutput']
		library := '/System/Library/Frameworks/AVFoundation.framework/AVFoundation'
		for name in ['AVCaptureOutput', 'AVCaptureAudioDataOutput']! {
			for prefix in ['_OBJC_CLASS_$_', '_OBJC_METACLASS_$_']! {
				symbol := prefix + name
				assert runtime_symbol(library, symbol)! == if prefix == '_OBJC_CLASS_$_' { ios_runtime.names[name] } else { read64(ios_runtime.names[name]) }
				for wrong in ['/System/Library/Frameworks/Foundation.framework/Foundation', '/usr/lib/libobjc.A.dylib']! {
					if _ := runtime_symbol(wrong, symbol) { assert false }
				}
			}
		}
		if _ := capture_audio_symbol('_OBJC_CLASS_$_AVCaptureAudioDataOutputUnknown') { assert false }
		assert objc_class_size(cls) == 24 && objc_class_size(base) == 16
		assert objc_class_parent(cls) == base && objc_class_parent(base) == ios_runtime.names['NSObject']
		output := audio_output_msg(audio_output_msg(cls, c'alloc', 0, 0), c'init', 0, 0)
		assert audio_output_msg(output, c'sampleBufferDelegate', 0, 0) == 0
		assert audio_output_msg(output, c'sampleBufferCallbackQueue', 0, 0) == 0
		empty := audio_output_msg(output, c'connections', 0, 0)
		assert empty != 0 && objc_is_kind(empty, ios_runtime.names['NSArray'])
		assert audio_output_msg(empty, c'count', 0, 0) == 0
		assert audio_output_msg(output, c'connectionWithMediaType:', 0, 0) == 0
		for file_type in ['com.apple.quicktime-movie', 'public.mpeg-4', 'public.3gpp', 'com.apple.m4v-video', 'com.apple.m4a-audio', 'com.apple.coreaudio-format', 'com.microsoft.waveform-audio', 'public.aiff-audio', 'public.aifc-audio', 'org.3gpp.adaptive-multi-rate-audio']! {
			text := owned_string(file_type)
			assert audio_output_msg(output, c'recommendedAudioSettingsForAssetWriterWithOutputFileType:', text, 0) == 0
			objc_release(text)
		}
		for selector in ['init', 'sampleBufferDelegate', 'sampleBufferCallbackQueue', 'connections', 'connectionWithMediaType:', 'setSampleBufferDelegate:queue:', 'recommendedAudioSettingsForAssetWriterWithOutputFileType:']! {
			method := objc_instance_method(cls, u64(selector.str))
			assert method != 0 && objc_responds(output, selector.str)
			assert ctext(u64(objc_method_types(method))) == capture_audio_types('AVCaptureAudioDataOutput', false, selector)?
			// NSObject supplies +init; output-specific selectors are instance-only.
			assert (objc_class_method(cls, u64(selector.str)) != 0) == (selector == 'init')
			assert objc_responds(cls, selector.str) == (selector == 'init')
			signature := audio_output_msg(output, c'methodSignatureForSelector:', u64(selector.str), 0)
			assert audio_output_msg(signature, c'numberOfArguments', 0, 0) == u64(2 + selector.count(':'))
			if selector in ['init', 'connections', 'connectionWithMediaType:', 'setSampleBufferDelegate:queue:']! {
				result := unsafe { CaptureAudioSend(voidptr(objc_method_imp(method)))(output, u64(selector.str), 0, 0) }
				assert result == if selector == 'init' { output } else if selector == 'connections' { empty } else { u64(0) }
			}
		}
		for selector in [c'copy', c'copyWithZone:', c'mutableCopy', c'mutableCopyWithZone:', c'initWithCoder:', c'encodeWithCoder:', c'supportsSecureCoding', c'classForCoder', c'setSampleBufferDelegate:', c'setSampleBufferCallbackQueue:', c'audioSettings', c'setAudioSettings:', c'spatialAudioChannelLayoutTag', c'addObserver:forKeyPath:options:context:']! {
			assert !objc_responds(output, selector) && objc_instance_method(cls, u64(selector)) == 0
		}
		delegate := objc_allocate(ios_runtime.names['NSObject'])
		first := darwin_dispatch_queue_create(c'vinix.capture.first', 0)
		second := darwin_dispatch_queue_create(c'vinix.capture.second', 0)
		audio_output_msg(output, c'setSampleBufferDelegate:queue:', delegate, first)
		assert obj_header(delegate).refs == 1
		darwin_dispatch_release(first)
		assert dispatch_objc_is_queue(first)
		nested := objc_pool_push()
		assert audio_output_msg(output, c'sampleBufferDelegate', 0, 0) == delegate
		assert audio_output_msg(output, c'sampleBufferCallbackQueue', 0, 0) == first
		objc_pool_pop(nested)
		audio_output_msg(output, c'setSampleBufferDelegate:queue:', delegate, second)
		assert !dispatch_objc_is_queue(first)
		darwin_dispatch_release(second)
		objc_release(delegate)
		assert audio_output_msg(output, c'sampleBufferDelegate', 0, 0) == 0
		// Weak zeroing does not clear the separately owned queue.
		assert obj_header(output).capture_audio_queue == second && dispatch_objc_is_queue(second)
		audio_output_msg(output, c'setSampleBufferDelegate:queue:', 0, second)
		assert !dispatch_objc_is_queue(second)
		assert audio_output_msg(output, c'sampleBufferCallbackQueue', 0, 0) == 0
		final_delegate := objc_allocate(ios_runtime.names['NSObject'])
		final_queue := darwin_dispatch_queue_create(c'vinix.capture.final', 0)
		audio_output_msg(output, c'setSampleBufferDelegate:queue:', final_delegate, final_queue)
		darwin_dispatch_release(final_queue)
		objc_release(output)
		assert !dispatch_objc_is_queue(final_queue) && obj_header(final_delegate).refs == 1
		objc_release(final_delegate)
		baseline := ios_runtime.live
		mut workers := []thread{}
		for _ in 0 .. 4 { workers << spawn audio_output_worker() }
		workers.wait()
		unsafe { workers.free() }
		assert ios_runtime.live == baseline
		objc_pool_pop(pool)
		objc_stop()
		system_data_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.block_refs.len == 0
	}
	println('IOS-CAPTURE-AUDIO-OUTPUT: scoped imports, native metadata, saved IMPs, empty results, weak delegate, retained and replaced queues, four workers, two drained runtimes')
}

fn test_capture_audio_output_rejections() {
	objc_start()
	system_data_start()!
	pool := objc_pool_push()
	cls := ios_runtime.names['AVCaptureAudioDataOutput']
	output := objc_allocate(cls)
	delegate := objc_allocate(ios_runtime.names['NSObject'])
	for mode in ['base', 'caller', 'subclass', 'directcopy', 'isa-in', 'isa-out', 'queue-nil', 'queue-object', 'delegate-invalid', 'file-nil', 'file-object', 'file-unknown', 'media-object', 'getter-class', 'storage', 'immutable', 'copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding', 'classForCoder', 'setSampleBufferDelegate:', 'setSampleBufferCallbackQueue:', 'audioSettings', 'setAudioSettings:', 'spatialAudioChannelLayoutTag', 'addObserver:forKeyPath:options:context:']! {
		mut fds := [2]i32{}
		assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.fork()
		assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			match mode {
				'base' { objc_allocate(ios_runtime.names['AVCaptureOutput']) }
				'caller' { mut storage := [3]u64{}; objc_construct_instance(cls, u64(unsafe { &storage[0] })) }
				'subclass' { sub := objc_allocate_class(cls, c'VinixCaptureAudio', 0); objc_register_class(sub); objc_allocate(sub) }
				'directcopy' { objc_copy_value(output, false) }
				'isa-in' { objc_set_class(delegate, cls) }
				'isa-out' { objc_set_class(output, ios_runtime.names['NSObject']) }
				'queue-nil' { audio_output_msg(output, c'setSampleBufferDelegate:queue:', delegate, 0) }
				'queue-object' { audio_output_msg(output, c'setSampleBufferDelegate:queue:', delegate, delegate) }
				'delegate-invalid' { audio_output_msg(output, c'setSampleBufferDelegate:queue:', 123, 0) }
				'file-nil', 'file-object', 'file-unknown' { audio_output_msg(output, c'recommendedAudioSettingsForAssetWriterWithOutputFileType:', if mode == 'file-nil' { u64(0) } else if mode == 'file-object' { delegate } else { owned_string('VinixUnknownFileType') }, 0) }
				'media-object' { audio_output_msg(output, c'connectionWithMediaType:', delegate, 0) }
				'getter-class' { audio_output_msg(cls, c'sampleBufferDelegate', 0, 0) }
				'storage' { mut header := obj_header(output); header.native_size = 16; audio_output_msg(output, c'connections', 0, 0) }
				'immutable' { audio_output_msg(audio_output_msg(output, c'connections', 0, 0), c'addObject:', delegate, 0) }
				else { audio_output_msg(output, mode.str, 0, 0) }
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
		output_text := unsafe { tos(&bytes[0], length) }
		reason := match mode {
			'base', 'caller', 'subclass' { 'capture audio output requires built-in allocation' }
			'directcopy' { 'unsupported capture audio output method: copy' }
			'isa-in', 'isa-out' { 'changing capture audio output storage isa is not implemented' }
			'queue-nil', 'queue-object' { 'delegate requires a dispatch queue' }
			'delegate-invalid' { 'requires an Objective-C delegate' }
			'file-nil', 'file-object' { 'requires NSString file type' }
			'file-unknown' { 'requires a supported file type' }
			'media-object' { 'requires NSString media type or nil' }
			'getter-class' { 'unimplemented Objective-C method' }
			'storage' { 'requires live built-in storage' }
			'immutable' { 'mutation of the immutable empty array' }
			else { 'unsupported capture audio output method' }
		}
		assert output_text.contains(reason) && !output_text.contains('AddressSanitizer') && !output_text.contains('runtime error:'), mode + ': ' + output_text
	}
	objc_release(output)
	objc_release(delegate)
	objc_pool_pop(pool)
	objc_stop()
	system_data_stop()
	assert ios_runtime.live == 0
	println('IOS-CAPTURE-AUDIO-OUTPUT-REJECT: 30 construction, copy, coding, isa, delegate, queue, criteria, receiver, storage, mutation and observation cases fail explicitly')
}
