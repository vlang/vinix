// SPDX-License-Identifier: GPL-2.0-or-later
// Pull-based GenericOutput and MultiChannelMixer units. Hardware I/O and
// voice processing components are absent until there is a working backend.
module main

import math

struct AudioDescription {
	kind u32
	subtype u32
	manufacturer u32
	flags u32
	mask u32
}

struct AudioCallback {
	proc u64
	user voidptr
}

struct AudioConnection {
	unit u64
	output u32
	input u32
}

struct AudioBus {
mut:
	format AudioFormat
	callback AudioCallback
	source u64
	gain f32 = 1
	enabled bool = true
	storage voidptr
}

struct AudioUnit {
mut:
	component u64
	graph u64
	inputs [16]AudioBus
	input_count u32
	output AudioFormat
	output_gain f32 = 1
	maximum u32 = 4096
	allocate_output bool = true
	storage voidptr
	initialized bool
	running bool
	rendering bool
}

type AudioRenderProc = fn (voidptr, &u32, voidptr, u32, u32, &AudioBuffers) i32

fn audio_description(component u64) ?AudioDescription {
	return match component {
		1 { AudioDescription{0x61756f75, 0x67656e72, 0x6170706c, 0, 0} } // 'auou'/'genr'/'appl'
		2 { AudioDescription{0x61756d78, 0x6d636d78, 0x6170706c, 0, 0} } // 'aumx'/'mcmx'/'appl'
		else { return none }
	}
}

fn audio_component_find(previous u64, requested &AudioDescription) u64 {
	if requested == unsafe { nil } || previous > 2 { return 0 }
	for component in previous + 1 .. u64(3) {
		description := audio_description(component) or { continue }
		if (requested.kind == 0 || requested.kind == description.kind) && (requested.subtype == 0 || requested.subtype == description.subtype) && (requested.manufacturer == 0 || requested.manufacturer == description.manufacturer) && (description.flags & requested.mask == requested.flags & requested.mask) { return component }
	}
	return 0
}

fn audio_component_description(component u64, result &AudioDescription) i32 {
	if result == unsafe { nil } { return -50 }
	description := audio_description(component) or { return -50 }
	unsafe { *result = description }
	return 0
}

fn audio_unit_new(component u64, result &u64) i32 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if result == unsafe { nil } { return -50 }
	unsafe { *result = 0 }
	if _ := audio_description(component) {} else { return -3000 }
	if ios_runtime.audio_units.len >= 256 { return -108 }
	mut unit := unsafe { &AudioUnit(C.calloc(1, sizeof(AudioUnit))) }
	if unit == unsafe { nil } { return -108 }
	format := AudioFormat{44100, 0x6c70636d, 41, 4, 1, 4, 2, 32, 0}
	unsafe { *unit = AudioUnit{ component: component, input_count: if component == 1 { u32(1) } else { u32(8) }, output: format } }
	for index in 0 .. 16 { unit.inputs[index] = AudioBus{format: format, gain: if component == 2 { f32(0) } else { f32(1) }} }
	if component == 2 { unit.output_gain = 0 }
	ios_runtime.audio_units[u64(unit)] = unit
	unsafe { *result = u64(unit) }
	return 0
}

fn audio_unit_buffers(storage voidptr, format AudioFormat, maximum u32, frames u32) AudioBuffers {
	mut list := AudioBuffers{ count: if format.flags & 32 != 0 { format.channels } else { u32(1) } }
	for index in 0 .. list.count {
		list.buffers[index] = AudioBuffer{ if list.count == 1 { format.channels } else { u32(1) }, frames * format.frame_bytes, unsafe { voidptr(u64(storage) + u64(index) * maximum * format.frame_bytes) } }
	}
	return list
}

fn audio_unit_free_buffers(mut unit AudioUnit) {
	for index in 0 .. 16 {
		C.free(unit.inputs[index].storage)
		unit.inputs[index].storage = unsafe { nil }
	}
	C.free(unit.storage)
	unit.storage = unsafe { nil }
	unit.initialized = false
	unit.running = false
}

fn audio_unit_dispose(handle u64) i32 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut unit := ios_runtime.audio_units[handle] or { return -50 }
	if unit.rendering || unit.graph != 0 { return -10863 }
	for _, other in ios_runtime.audio_units {
		for index in 0 .. other.input_count { if other.inputs[index].source == handle { return -10863 } }
	}
	audio_unit_free_buffers(mut unit)
	ios_runtime.audio_units.delete(handle)
	C.free(unit)
	return 0
}

fn audio_unit_initialize(handle u64) i32 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut unit := ios_runtime.audio_units[handle] or { return -50 }
	if unit.rendering { return -10863 }
	if unit.initialized { return 0 }
	// Channel-layout remapping/spatialization is outside this mixer subset.
	// Only same-rate mono mixing is currently advertised.
	if unit.component == 2 && unit.output.channels != 1 { return -10868 }
	for index in 0 .. unit.input_count {
		format := unit.inputs[index].format
		if !audio_formats_compatible(format, unit.output) { return -10868 }
		if source := ios_runtime.audio_units[unit.inputs[index].source] {
			if source.output != format { return -10868 }
		} else if unit.inputs[index].source != 0 { return -10876 }
	}
	for index in 0 .. unit.input_count {
		format := unit.inputs[index].format
		planes := if format.flags & 32 != 0 { format.channels } else { u32(1) }
		unit.inputs[index].storage = C.calloc(usize(unit.maximum), usize(format.frame_bytes * planes))
		if unit.inputs[index].storage == unsafe { nil } { audio_unit_free_buffers(mut unit); return -108 }
	}
	planes := if unit.output.flags & 32 != 0 { unit.output.channels } else { u32(1) }
	unit.storage = C.calloc(usize(unit.maximum), usize(unit.output.frame_bytes * planes))
	if unit.storage == unsafe { nil } { audio_unit_free_buffers(mut unit); return -108 }
	unit.initialized = true
	return 0
}

fn audio_unit_uninitialize(handle u64) i32 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut unit := ios_runtime.audio_units[handle] or { return -50 }
	if unit.rendering { return -10863 }
	audio_unit_free_buffers(mut unit)
	if graph := ios_runtime.audio_graphs[unit.graph] {
		mut owner := unsafe { &AudioGraph(graph) }
		owner.initialized = false
		owner.running = false
	}
	return 0
}

fn audio_output_start(handle u64) i32 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut unit := ios_runtime.audio_units[handle] or { return -50 }
	if unit.component != 1 { return -50 }
	if !unit.initialized { return -10867 }
	unit.running = true
	// GenericOutput is rendered by the caller, not by a hardware worker.
	return 0
}

fn audio_output_stop(handle u64) i32 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut unit := ios_runtime.audio_units[handle] or { return -50 }
	if unit.component != 1 { return -50 }
	unit.running = false
	return 0
}

fn audio_unit_set_property(handle u64, property u32, scope u32, element u32, data voidptr, size u32) i32 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut unit := ios_runtime.audio_units[handle] or { return -50 }
	if unit.rendering { return -10863 }
	if data == unsafe { nil } { return -50 }
	match property {
		8 { // StreamFormat
			if scope !in [u32(1), 2] { return -10866 }
			if element >= if scope == 1 { unit.input_count } else { u32(1) } { return -10877 }
			if size != sizeof(AudioFormat) { return -10851 }
			if unit.initialized { return -10849 }
			format := unsafe { *(&AudioFormat(data)) }
			if !audio_format_valid(format) { return -10868 }
			if scope == 1 { unit.inputs[element].format = format } else { unit.output = format }
		}
		11 { // ElementCount
			if scope != 1 { return -10865 }
			if element != 0 { return -10877 }
			if size != 4 { return -10851 }
			if unit.initialized { return -10849 }
			count := unsafe { *(&u32(data)) }
			if unit.component != 2 || count == 0 || count > 16 { return -10851 }
			unit.input_count = count
		}
		14, 51 { // MaximumFramesPerSlice / ShouldAllocateBuffer
			if (property == 14 && scope != 0) || (property == 51 && scope != 2) { return -10866 }
			if element != 0 { return -10877 }
			if size != 4 { return -10851 }
			if unit.initialized { return -10849 }
			value := unsafe { *(&u32(data)) }
			if property == 14 {
				if value == 0 || value > 16384 { return -10851 }
				unit.maximum = value
			} else { unit.allocate_output = value != 0 }
		}
		23 { // SetRenderCallback
			if scope != 1 { return -10866 }
			if element >= unit.input_count { return -10877 }
			if size != sizeof(AudioCallback) { return -10851 }
			unit.inputs[element].callback = unsafe { *(&AudioCallback(data)) }
			unit.inputs[element].source = 0
		}
		1 { // MakeConnection
			if scope != 1 { return -10866 }
			if size != sizeof(AudioConnection) { return -10851 }
			if unit.initialized { return -10849 }
			connection := unsafe { *(&AudioConnection(data)) }
			if connection.input >= unit.input_count || connection.output != 0 { return -10877 }
			if connection.unit != 0 {
				if _ := ios_runtime.audio_units[connection.unit] {} else { return -10876 }
				if audio_unit_reaches(connection.unit, handle) { return -10861 }
			}
			unit.inputs[connection.input].source = connection.unit
			unit.inputs[connection.input].callback = AudioCallback{}
		}
		else { return -10879 }
	}
	return 0
}

fn audio_unit_reaches(source u64, target u64) bool {
	mut visited := [256]u64{}
	visited[0] = source
	mut head := 0
	mut tail := 1
	for head < tail {
		address := visited[head]
		head++
		if address == target { return true }
		unit := ios_runtime.audio_units[address] or { continue }
		for index in 0 .. unit.input_count {
			next := unit.inputs[index].source
			if next == 0 { continue }
			mut seen := false
			for previous in 0 .. tail { if visited[previous] == next { seen = true; break } }
			if !seen {
				if tail == 256 { return true }
				visited[tail] = next
				tail++
			}
		}
	}
	return false
}

fn audio_unit_property_size(property u32) ?u32 {
	return match property { 8 { u32(sizeof(AudioFormat)) } 11, 14, 51 { u32(4) } else { return none } }
}

fn audio_unit_get_property(handle u64, property u32, scope u32, element u32, data voidptr, size &u32) i32 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	unit := ios_runtime.audio_units[handle] or { return -50 }
	needed := audio_unit_property_size(property) or { return -10879 }
	if data == unsafe { nil } || size == unsafe { nil } { return -50 }
	if unsafe { *size } < needed { return -10851 }
	if property in [u32(8), 11] {
		if scope !in [u32(1), 2] { return -10866 }
		if element >= if scope == 1 && property == 8 { unit.input_count } else { u32(1) } { return -10877 }
	} else {
		if (property == 14 && scope != 0) || (property == 51 && scope != 2) { return -10866 }
		if element != 0 { return -10877 }
	}
	unsafe {
		if property == 8 { *(&AudioFormat(data)) = if scope == 1 { unit.inputs[element].format } else { unit.output } }
		else { *(&u32(data)) = match property { 11 { if scope == 1 { unit.input_count } else { u32(1) } } 14 { unit.maximum } else { u32(unit.allocate_output) } } }
		*size = needed
	}
	return 0
}

fn audio_unit_set_parameter(handle u64, parameter u32, scope u32, element u32, value f32, offset u32) i32 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut unit := ios_runtime.audio_units[handle] or { return -50 }
	if unit.component != 2 || parameter !in [u32(0), 1] { return -10878 }
	if scope != 1 && !(scope == 2 && parameter == 0) { return -10866 }
	if element >= if scope == 1 { unit.input_count } else { u32(1) } { return -10877 }
	if !math.is_finite(value) { return -66743 }
	// Sample-offset automation needs a scheduled render event implementation.
	if offset != 0 { return -10878 }
	if parameter == 0 {
		if value < 0 || value > 1 { return -66743 }
		if scope == 1 { unit.inputs[element].gain = value } else { unit.output_gain = value }
	} else { unit.inputs[element].enabled = value != 0 }
	return 0
}

fn audio_unit_get_parameter(handle u64, parameter u32, scope u32, element u32, value &f32) i32 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	unit := ios_runtime.audio_units[handle] or { return -50 }
	if value == unsafe { nil } { return -50 }
	if unit.component != 2 || parameter !in [u32(0), 1] { return -10878 }
	if scope != 1 && !(scope == 2 && parameter == 0) { return -10866 }
	if element >= if scope == 1 { unit.input_count } else { u32(1) } { return -10877 }
	unsafe { *value = if scope == 2 { unit.output_gain } else if parameter == 0 { unit.inputs[element].gain } else { f32(unit.inputs[element].enabled) } }
	return 0
}

fn audio_unit_render(handle u64, flags &u32, timestamp voidptr, bus u32, frames u32, output &AudioBuffers) i32 {
	C.ios_objc_initialize_lock()
	mut locked := true
	defer { if locked { C.ios_objc_initialize_unlock() } }
	mut unit := ios_runtime.audio_units[handle] or { return -50 }
	if !unit.initialized { return -10867 }
	if unit.rendering { return -10863 }
	if bus != 0 { return -10877 }
	if frames > unit.maximum { return -10874 }
	if output == unsafe { nil } || flags == unsafe { nil } || timestamp == unsafe { nil } { return -50 }
	if output.count != if unit.output.flags & 32 != 0 { unit.output.channels } else { u32(1) } { return -50 }
	mut own := audio_unit_buffers(unit.storage, unit.output, unit.maximum, frames)
	for index in 0 .. output.count {
		mut buffer := audio_buffer(output, index)
		if buffer.data == unsafe { nil } && unit.allocate_output { unsafe { *buffer = own.buffers[index] } }
	}
	if !audio_buffers_valid(output, unit.output, frames) { return -50 }
	unit.rendering = true
	// Pin storage with rendering and snapshot parameters. Never hold the
	// registry lock across an app callback (it may join another app thread).
	inputs := unit.inputs
	output_gain := unit.output_gain
	C.ios_objc_initialize_unlock()
	locked = false
	defer { C.ios_objc_initialize_lock(); unit.rendering = false; C.ios_objc_initialize_unlock() }
	for index in 0 .. output.count { C.memset(audio_buffer(output, index).data, 0, usize(frames * unit.output.frame_bytes)) }
	mut lists := [16]AudioBuffers{}
	mut active := [16]bool{}
	for index in 0 .. unit.input_count {
		input := inputs[index]
		if input.source == 0 && input.callback.proc == 0 { continue }
		lists[index] = audio_unit_buffers(input.storage, input.format, unit.maximum, frames)
		mut input_flags := unsafe { *flags } & ~u32(16)
		mut status := i32(0)
		if input.source != 0 { status = audio_unit_render(input.source, &input_flags, timestamp, 0, frames, unsafe { &lists[index] }) }
		else {
			proc := unsafe { AudioRenderProc(voidptr(input.callback.proc)) }
			status = proc(input.callback.user, &input_flags, timestamp, index, frames, unsafe { &lists[index] })
		}
		// The reference mixer treats failed inputs as silence; GenericOutput
		// propagates its input error. Muted mixer buses still pull callbacks.
		if status != 0 { if unit.component == 2 { continue }; return status }
		if input_flags & 16 != 0 || !input.enabled || input.gain == 0 { continue }
		if !audio_buffers_valid(unsafe { &lists[index] }, input.format, frames) { return -50 }
		active[index] = true
	}
	mut silent := true
	for frame in 0 .. frames {
		for channel in 0 .. unit.output.channels {
			mut value := f64(0)
			for index in 0 .. unit.input_count {
				if active[index] { value += audio_sample_read(unsafe { &lists[index] }, inputs[index].format, frame, channel) * inputs[index].gain }
			}
			value *= output_gain
			if value != 0 { silent = false }
			audio_sample_write(output, unit.output, frame, channel, value)
		}
	}
	for index in 0 .. output.count { mut buffer := audio_buffer(output, index); buffer.bytes = frames * unit.output.frame_bytes }
	unsafe { *flags = (*flags & ~u32(16)) | if silent { u32(16) } else { u32(0) } }
	return 0
}

fn audio_units_stop() {
	for _, unit in ios_runtime.audio_units { mut owned := unsafe { &AudioUnit(unit) }; audio_unit_free_buffers(mut owned); C.free(owned) }
	unsafe { ios_runtime.audio_units.free() }
}

fn audio_unit_symbol(symbol string) ?u64 {
	address := match symbol {
		'_AudioComponentFindNext' { unsafe { voidptr(audio_component_find) } }
		'_AudioComponentGetDescription' { unsafe { voidptr(audio_component_description) } }
		'_AudioComponentInstanceNew' { unsafe { voidptr(audio_unit_new) } }
		'_AudioComponentInstanceDispose' { unsafe { voidptr(audio_unit_dispose) } }
		'_AudioUnitInitialize' { unsafe { voidptr(audio_unit_initialize) } }
		'_AudioUnitUninitialize' { unsafe { voidptr(audio_unit_uninitialize) } }
		'_AudioUnitSetProperty' { unsafe { voidptr(audio_unit_set_property) } }
		'_AudioUnitGetProperty' { unsafe { voidptr(audio_unit_get_property) } }
		'_AudioUnitSetParameter' { unsafe { voidptr(audio_unit_set_parameter) } }
		'_AudioUnitGetParameter' { unsafe { voidptr(audio_unit_get_parameter) } }
		'_AudioOutputUnitStart' { unsafe { voidptr(audio_output_start) } }
		'_AudioOutputUnitStop' { unsafe { voidptr(audio_output_stop) } }
		'_AudioUnitRender' { unsafe { voidptr(audio_unit_render) } }
		else { return none }
	}
	return u64(address)
}
