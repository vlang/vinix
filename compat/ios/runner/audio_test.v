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
	graph_path := os.join_path(os.dir(path), 'audio-graph')
	graph_data := os.read_bytes(graph_path)!
	defer { unsafe { graph_data.free() } }
	graph_image := macho.parse(graph_data)!
	defer { module_image_free(graph_image) }
	for _ in 0 .. 2 {
		assert execute(graph_image, [graph_path])! == 0
		assert ios_runtime.audio_units.len == 0 && ios_runtime.audio_graphs.len == 0
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

fn audio_test_render_lifetime(user voidptr, flags &u32, timestamp voidptr, bus u32, frames u32, data &AudioBuffers) i32 {
	_ = timestamp
	_ = bus
	_ = frames
	_ = data
	handle := u64(user)
	assert audio_unit_uninitialize(handle) == -10863
	assert audio_unit_dispose(handle) == -10863
	unit := ios_runtime.audio_units[handle] or { panic('lost live unit') }
	assert audio_graph_dispose(unit.graph) == -10863
	assert audio_graph_uninitialize(unit.graph) == -10863
	unsafe { *flags |= 16 }
	return 0
}

fn test_audio_render_bounds_cycles_and_callback_lifetimes() {
	objc_start()
	defer { objc_stop() }
	mut graph := u64(0)
	assert audio_graph_new(&graph) == 0
	description := audio_description(1) or { panic('missing component') }
	mut node := i32(0)
	assert audio_graph_add(graph, &description, &node) == 0
	assert audio_graph_connect(graph, node, 0, node, 0) == -10861
	assert audio_graph_open(graph) == 0
	mut unit := u64(0)
	assert audio_graph_info(graph, node, unsafe { nil }, &unit) == 0
	format := AudioFormat{48000, 0x6c70636d, 41, 4, 1, 4, 1, 32, 0}
	assert audio_unit_set_property(unit, 8, 1, 0, unsafe { &format }, sizeof(AudioFormat)) == 0
	assert audio_unit_set_property(unit, 8, 2, 0, unsafe { &format }, sizeof(AudioFormat)) == 0
	callback := AudioCallback{ u64(unsafe { voidptr(audio_test_render_lifetime) }), unsafe { voidptr(unit) } }
	assert audio_graph_callback(graph, node, 0, &callback) == 0
	assert audio_graph_initialize(graph) == 0
	mut value := f32(42)
	mut buffers := AudioBuffers{count: 1}
	buffers.buffers[0] = AudioBuffer{1, 4, unsafe { &value }}
	mut timestamp := [8]u64{}
	mut flags := u32(0)
	assert audio_unit_render(unit, &flags, unsafe { &timestamp[0] }, 0, 4097, &buffers) == -10874
	assert value == 42 && buffers.buffers[0].bytes == 4
	assert audio_unit_render(unit, &flags, unsafe { &timestamp[0] }, 0, 2, &buffers) == -50
	assert value == 42 && buffers.buffers[0].bytes == 4
	assert audio_unit_render(unit, &flags, unsafe { &timestamp[0] }, 0, 1, &buffers) == 0
	assert value == 0 && flags & 16 != 0
	assert audio_graph_dispose(graph) == 0
	assert audio_unit_dispose(unit) == -50
	assert ios_runtime.audio_units.len == 0 && ios_runtime.audio_graphs.len == 0
}
