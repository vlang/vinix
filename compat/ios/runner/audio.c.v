// SPDX-License-Identifier: GPL-2.0-or-later
// Independent PCM implementation. Installed AudioToolbox is a behavioral
// reference; no Apple code or framework is linked into the Vinix runner.
module main

import math

struct AudioFormat {
	rate f64
	id u32
	flags u32
	packet_bytes u32
	packet_frames u32
	frame_bytes u32
	channels u32
	bits u32
	reserved u32
}

struct AudioBuffer {
mut:
	channels u32
	bytes u32
	data voidptr
}

// The public list is variable length; this private stack value has room for
// every channel we support, including its 8-byte-aligned first AudioBuffer.
struct AudioBuffers {
mut:
	count u32
	buffers [8]AudioBuffer
}

struct AudioConverter {
	input AudioFormat
	output AudioFormat
mut:
	eof bool
	busy bool
}

type AudioInputProc = fn (u64, &u32, &AudioBuffers, voidptr, voidptr) i32

fn audio_format_valid(format AudioFormat) bool {
	if !math.is_finite(format.rate) || format.rate < 1 || format.rate > 384000 || format.id != 0x6c70636d || format.channels == 0 || format.channels > 8 { return false }
	// Little-endian, packed, signed integer or IEEE float PCM. Endian swaps,
	// compressed codecs, resampling and channel remapping are not advertised.
	if format.flags & ~u32(0x2d) != 0 || format.flags & 8 == 0 { return false }
	if format.flags & 1 != 0 {
		if format.flags & 4 != 0 || format.bits !in [u32(32), 64] { return false }
	} else if format.flags & 4 == 0 || format.bits !in [u32(16), 32] { return false }
	stride := format.bits / 8 * if format.flags & 32 != 0 { u32(1) } else { format.channels }
	return format.frame_bytes == stride && format.packet_bytes == stride && format.packet_frames == 1
}

fn audio_formats_compatible(input AudioFormat, output AudioFormat) bool {
	return audio_format_valid(input) && audio_format_valid(output) && input.channels == output.channels && input.rate == output.rate
}

fn audio_buffer(list &AudioBuffers, index u32) &AudioBuffer {
	return unsafe { &AudioBuffer(u64(list) + 8 + u64(index) * 16) }
}

fn audio_buffers_valid(list &AudioBuffers, format AudioFormat, frames u32) bool {
	if list == unsafe { nil } { return false }
	planar := format.flags & 32 != 0
	if list.count != if planar { format.channels } else { u32(1) } { return false }
	needed := u64(frames) * format.frame_bytes
	for index in 0 .. list.count {
		buffer := audio_buffer(list, index)
		if buffer.channels != if planar { u32(1) } else { format.channels } || u64(buffer.bytes) < needed || (needed != 0 && buffer.data == unsafe { nil }) { return false }
	}
	return true
}

fn audio_sample_address(list &AudioBuffers, format AudioFormat, frame u32, channel u32) u64 {
	planar := format.flags & 32 != 0
	buffer := audio_buffer(list, if planar { channel } else { u32(0) })
	return u64(buffer.data) + u64(frame) * format.frame_bytes + if planar { u64(0) } else { u64(channel) * (format.bits / 8) }
}

fn audio_sample_read(list &AudioBuffers, format AudioFormat, frame u32, channel u32) f64 {
	address := audio_sample_address(list, format, frame, channel)
	unsafe {
		if format.flags & 1 != 0 { return if format.bits == 32 { f64(*(&f32(address))) } else { *(&f64(address)) } }
		return if format.bits == 16 { f64(*(&i16(address))) / 32768.0 } else { f64(*(&i32(address))) / 2147483648.0 }
	}
}

fn audio_sample_write(list &AudioBuffers, format AudioFormat, frame u32, channel u32, value f64) {
	address := audio_sample_address(list, format, frame, channel)
	unsafe {
		if format.flags & 1 != 0 {
			if format.bits == 32 { *(&f32(address)) = f32(value) } else { *(&f64(address)) = value }
		} else {
			sample := if math.is_nan(value) { f64(0) } else { math.max(-1.0, math.min(1.0, value)) }
			if format.bits == 16 { *(&i16(address)) = i16(math.max(-32768.0, math.min(32767.0, math.round(sample * 32768)))) }
			else { *(&i32(address)) = i32(math.max(-2147483648.0, math.min(2147483647.0, math.round(sample * 2147483648.0)))) }
		}
	}
}

fn audio_pcm_copy(input &AudioBuffers, input_format AudioFormat, output &AudioBuffers, output_format AudioFormat, start u32, frames u32) {
	for frame in 0 .. frames {
		for channel in 0 .. input_format.channels {
			audio_sample_write(output, output_format, start + frame, channel, audio_sample_read(input, input_format, frame, channel))
		}
	}
}

fn audio_converter_new(input &AudioFormat, output &AudioFormat, result &u64) i32 {
	if result == unsafe { nil } { return -50 }
	unsafe { *result = 0 }
	if input == unsafe { nil } || output == unsafe { nil } { return -50 }
	if !audio_formats_compatible(*input, *output) { return 0x666d743f } // 'fmt?'
	mut converter := unsafe { &AudioConverter(C.calloc(1, sizeof(AudioConverter))) }
	if converter == unsafe { nil } { return -108 }
	unsafe { *converter = AudioConverter{ input: *input, output: *output } }
	C.ios_objc_initialize_lock()
	ios_runtime.audio_converters[u64(converter)] = converter
	C.ios_objc_initialize_unlock()
	unsafe { *result = u64(converter) }
	return 0
}

fn audio_converter_lookup(handle u64) ?&AudioConverter {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	return ios_runtime.audio_converters[handle] or { return none }
}

fn audio_converter_dispose(handle u64) i32 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	converter := ios_runtime.audio_converters[handle] or { return -50 }
	if converter.busy { return 0x6f703f3f }
	ios_runtime.audio_converters.delete(handle)
	C.free(converter)
	return 0
}

fn audio_converter_reset(handle u64) i32 {
	mut converter := audio_converter_lookup(handle) or { return -50 }
	if converter.busy { return 0x6f703f3f }
	converter.eof = false
	return 0
}

fn audio_converter_fill(handle u64, callback u64, user voidptr, packets &u32, output &AudioBuffers, descriptions voidptr) i32 {
	_ = descriptions // Constant-size PCM packets do not need descriptions.
	mut converter := audio_converter_lookup(handle) or { return -50 }
	if callback == 0 || packets == unsafe { nil } || output == unsafe { nil } { return -50 }
	if converter.busy { return 0x6f703f3f }
	requested := unsafe { *packets }
	unsafe { *packets = 0 }
	if requested > 1048576 || !audio_buffers_valid(output, converter.output, requested) { return 0x6f74737a } // 'otsz'
	converter.busy = true
	defer { converter.busy = false }
	mut written := u32(0)
	mut status := i32(0)
	for written < requested && !converter.eof {
		mut input := AudioBuffers{}
		input.count = if converter.input.flags & 32 != 0 { converter.input.channels } else { u32(1) }
		for index in 0 .. input.count { input.buffers[index].channels = if input.count == 1 { converter.input.channels } else { u32(1) } }
		mut count := requested - written
		proc := unsafe { AudioInputProc(voidptr(callback)) }
		status = proc(handle, &count, &input, unsafe { nil }, user)
		if status != 0 { break }
		if count > requested - written || !audio_buffers_valid(&input, converter.input, count) { status = 0x696e737a; break } // 'insz'
		if count == 0 { converter.eof = true; break }
		audio_pcm_copy(&input, converter.input, output, converter.output, written, count)
		written += count
	}
	unsafe { *packets = written }
	for index in 0 .. output.count {
		mut buffer := audio_buffer(output, index)
		buffer.bytes = written * converter.output.frame_bytes
	}
	return status
}

fn audio_converter_complex(handle u64, frames u32, input &AudioBuffers, output &AudioBuffers) i32 {
	mut converter := audio_converter_lookup(handle) or { return -50 }
	if converter.busy { return 0x6f703f3f }
	if frames > 1048576 || !audio_buffers_valid(input, converter.input, frames) { return 0x696e737a }
	if !audio_buffers_valid(output, converter.output, frames) { return 0x6f74737a }
	audio_pcm_copy(input, converter.input, output, converter.output, 0, frames)
	for index in 0 .. output.count {
		mut buffer := audio_buffer(output, index)
		buffer.bytes = frames * converter.output.frame_bytes
	}
	return 0
}

fn audio_stop() {
	audio_graphs_stop()
	audio_units_stop()
	for _, converter in ios_runtime.audio_converters { C.free(converter) }
	unsafe { ios_runtime.audio_converters.free() }
}

fn audio_symbol(symbol string) ?u64 {
	if address := audio_graph_symbol(symbol) { return address }
	if address := audio_unit_symbol(symbol) { return address }
	address := match symbol {
		'_AudioConverterNew' { unsafe { voidptr(audio_converter_new) } }
		'_AudioConverterDispose' { unsafe { voidptr(audio_converter_dispose) } }
		'_AudioConverterReset' { unsafe { voidptr(audio_converter_reset) } }
		'_AudioConverterFillComplexBuffer' { unsafe { voidptr(audio_converter_fill) } }
		'_AudioConverterConvertComplexBuffer' { unsafe { voidptr(audio_converter_complex) } }
		else { return none }
	}
	return u64(address)
}
