// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os

fn test_native_audio_converter_and_teardown() {
	path := os.getenv('VINIX_IOS_AUDIO_FIXTURE')
	if path == '' { return }
	data := os.read_bytes(path)!
	defer { unsafe { data.free() } }
	image := macho.parse(data)!
	defer { module_image_free(image) }
	assert audit_imports(image, path)! == 0
	for _ in 0 .. 2 {
		assert execute(image, [path])! == 0
		assert ios_runtime.audio_converters.len == 0
		assert ios_runtime.live == 0
	}
}

fn audio_test_bad_callback(handle u64, packets &u32, data &AudioBuffers, descriptions voidptr, user voidptr) i32 {
	_ = data
	_ = descriptions
	_ = user
	assert audio_converter_reset(handle) == 0x6f703f3f
	assert audio_converter_dispose(handle) == 0x6f703f3f
	unsafe { *packets += 1 }
	return 0
}

fn test_audio_converter_rejects_short_buffers_and_reentrant_operations() {
	objc_start()
	defer { objc_stop() }
	format := AudioFormat{48000, 0x6c70636d, 12, 4, 1, 4, 2, 16, 0}
	mut handle := u64(0)
	assert audio_converter_new(&format, &format, &handle) == 0
	mut samples := [i16(1), 2, 3, 4]!
	mut buffers := AudioBuffers{count: 1}
	buffers.buffers[0] = AudioBuffer{2, 4, unsafe { &samples[0] }}
	mut count := u32(2)
	callback := u64(unsafe { voidptr(audio_test_bad_callback) })
	assert audio_converter_fill(handle, callback, unsafe { nil }, &count, &buffers, unsafe { nil }) == 0x6f74737a
	assert count == 0 && samples == [i16(1), 2, 3, 4]!
	buffers.buffers[0].bytes = 8
	count = 2
	assert audio_converter_fill(handle, callback, unsafe { nil }, &count, &buffers, unsafe { nil }) == 0x696e737a
	assert count == 0 && buffers.buffers[0].bytes == 0
	assert samples == [i16(1), 2, 3, 4]!
	assert audio_converter_dispose(handle) == 0
	assert audio_converter_dispose(handle) == -50
	assert ios_runtime.audio_converters.len == 0
	// Unreleased converters are runner-owned and freed at shutdown.
	assert audio_converter_new(&format, &format, &handle) == 0
}
