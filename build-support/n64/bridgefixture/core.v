// SPDX-License-Identifier: MIT
// Native boundary regression linked against the real pinned upstream core.
@[translated; has_globals]
module bridgefixture

#include <bridge-test-abi.h>
@[typedef] struct C.n64_const_void {}
@[typedef] struct C.n64_const_sample {}
@[typedef] struct C.n64_const_char {}
struct C.retro_log_callback { mut: @log fn (i32, &char, ...) }
struct C.retro_variable { mut: key &char value &char }
struct C.retro_system_timing { mut: sample_rate f64 }
struct C.retro_system_av_info { mut: timing C.retro_system_timing }
@[c_extern] __global C.environ_cb fn (u32, voidptr) bool
@[c_extern] __global C.video_cb fn (&C.n64_const_void, u32, u32, usize)
@[c_extern] __global C.audio_batch_cb fn (&C.n64_const_sample, usize) usize
fn C.assert(bool)
fn C.strcmp(&char, &char) i32
fn C.puts(&char) i32
fn C.getenv(&char) &char
fn C.setenv(&char, &char, i32) i32
fn C.fflush(voidptr) i32
fn C.pause() i32
@[c_extern] __global C.stdout voidptr
fn C.vinix_n64_fixture_emit(i32, &char, ...)
fn C.vinix_n64_create(fn (&C.n64_const_void, u32, u32, usize), fn (&C.n64_const_sample, usize, u32)) voidptr
fn C.vinix_n64_error(voidptr) &C.n64_const_char
fn C.vinix_n64_loaded(voidptr) i32
fn C.vinix_n64_frame(voidptr, u32) i32
fn C.vinix_n64_reset(voidptr) i32
fn C.vinix_n64_save(voidptr) i32
fn C.vinix_n64_load(voidptr, &char, &char) i32
fn C.vinix_n64_destroy(voidptr)
__global video_count u32
__global video_pointer usize
__global audio_count usize
__global audio_pointer usize
__global audio_rate u32
__global strict_video bool = true
@[export: 'vinix_n64_fixture_log'] __global fixture_log C.retro_log_callback

fn video(pixels &C.n64_const_void, width u32, height u32, pitch usize) {
	if strict_video { C.assert(width == 2 && height == 1 && pitch == 8) }
	else { C.assert(width <= 640 && height <= 576 && pitch >= usize(width) * 4) }
	video_count++
	video_pointer = usize(pixels)
}
fn audio(samples &C.n64_const_sample, frames usize, rate u32) {
	unsafe { if strict_video { C.assert(frames == 1 && (&i16(samples))[0] == -123 && (&i16(samples))[1] == 456) } }
	audio_count += frames
	audio_pointer = usize(samples)
	audio_rate = rate
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		$if n64_bridge_guest ? {
			C.setenv(c'VINIX_N64_BRIDGE_ROM', c'/usr/share/games/n64/paddle.z64', 1)
			C.setenv(c'VINIX_N64_BRIDGE_SAVE', c'/tmp/bridge.sav', 1)
		}
		core := C.vinix_n64_create(video, audio)
		C.assert(core != nil && C.vinix_n64_create(video, audio) == nil)
		environment := C.environ_cb
		video_callback := C.video_cb
		audio_callback := C.audio_batch_cb
		wrong := voidptr(usize(1))
		C.assert(C.vinix_n64_loaded(wrong) == 0 && C.vinix_n64_frame(wrong, 0) == 0)
		C.assert(C.vinix_n64_save(wrong) == 0 && C.vinix_n64_reset(wrong) == 0)
		C.assert(C.vinix_n64_load(wrong, c'/missing', c'') == 0)
		C.assert(C.strcmp(&char(C.vinix_n64_error(wrong)), c'N64 emulator is unavailable') == 0)
		C.vinix_n64_destroy(wrong)
		C.assert(C.vinix_n64_save(core) == 1 && C.vinix_n64_loaded(core) == 0)
		C.assert(environment(C.RETRO_ENVIRONMENT_GET_LOG_INTERFACE, &fixture_log))
		C.vinix_n64_fixture_emit(C.RETRO_LOG_ERROR, c'%d %u %lld|%d %d %d %d %d %d %d|%.2f %.2f %.2f %.2f %.2f %.2f %.2f %.2f %.2f %.2f|%s',
			i32(-7), u32(4294967295), i64(-9223372036854775807), i32(4), i32(5), i32(6), i32(7), i32(8), i32(9), i32(10),
			f64(1.25), f64(2.25), f64(3.25), f64(4.25), f64(5.25), f64(6.25), f64(7.25), f64(8.25), f64(9.25), f64(10.25), c'ok')
		C.assert(C.strcmp(&char(C.vinix_n64_error(core)), c'-7 4294967295 -9223372036854775807|4 5 6 7 8 9 10|1.25 2.25 3.25 4.25 5.25 6.25 7.25 8.25 9.25 10.25|ok') == 0)
		C.vinix_n64_fixture_emit(C.RETRO_LOG_INFO, c'ignored %d', i32(42))
		C.assert(C.strcmp(&char(C.vinix_n64_error(core)), c'-7 4294967295 -9223372036854775807|4 5 6 7 8 9 10|1.25 2.25 3.25 4.25 5.25 6.25 7.25 8.25 9.25 10.25|ok') == 0)
		C.puts(c'N64 BRIDGE: native integer/FP/overflow variadic logging and severity PASS')
		mut pixels := [u32(0xff123456), 0xffabcdef]!
		video_callback(nil, 2, 1, 8)
		video_callback(&C.n64_const_void(usize(C.RETRO_HW_FRAME_BUFFER_VALID)), 2, 1, 8)
		C.assert(video_count == 0)
		video_callback(&C.n64_const_void(&pixels[0]), 2, 1, 8)
		C.assert(video_count == 1 && video_pointer == usize(&pixels[0]))
		mut samples := [i16(-123), 456]!
		C.assert(audio_callback(&C.n64_const_sample(&samples[0]), 1) == 1)
		C.assert(audio_count == 1 && audio_pointer == usize(&samples[0]) && audio_rate == 32040)
		mut av := C.retro_system_av_info{timing: C.retro_system_timing{sample_rate: 44100.6}}
		C.assert(environment(C.RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO, &av))
		audio_callback(&C.n64_const_sample(&samples[0]), 1)
		C.assert(audio_rate == 44101)
		av.timing.sample_rate = 999.9
		C.assert(environment(C.RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO, &av))
		audio_callback(&C.n64_const_sample(&samples[0]), 1)
		C.assert(audio_rate == 44101)
		C.puts(c'N64 BRIDGE: borrowed callback identity and native sample-rate rounding PASS')
		video_callback(&C.n64_const_void(&pixels[0]), 641, 1, 641 * 4)
		C.assert(C.strcmp(&char(C.vinix_n64_error(core)), c'Emulator produced an unsupported video frame') == 0)
		C.vinix_n64_fixture_emit(C.RETRO_LOG_ERROR, c'ignored after failure')
		C.assert(C.strcmp(&char(C.vinix_n64_error(core)), c'Emulator produced an unsupported video frame') == 0)
		C.vinix_n64_destroy(core)
		C.assert(C.vinix_n64_loaded(core) == 0 && C.strcmp(&char(C.vinix_n64_error(core)), c'N64 emulator is unavailable') == 0)
		fresh := C.vinix_n64_create(video, audio)
		C.assert(fresh != nil)
		C.vinix_n64_destroy(fresh)
		C.puts(c'N64 BRIDGE: invalid handles, singleton ownership and cleanup PASS')
		rom := C.getenv(c'VINIX_N64_BRIDGE_ROM')
		if rom != nil {
			strict_video = false
			owner := C.vinix_n64_create(video, audio)
			C.assert(owner != nil)
			save_path := C.getenv(c'VINIX_N64_BRIDGE_SAVE')
			C.assert(C.vinix_n64_load(owner, rom, save_path) == 1)
			before := video_count
			for i := u32(0); i < 32; i++ { C.assert(C.vinix_n64_frame(owner, if i < 16 { u32(0) } else { u32(1) << 3 }) == 1) }
			C.assert(video_count > before + 10)
			C.assert(C.vinix_n64_load(owner, c'/nonexistent', c'') == 0 && C.vinix_n64_loaded(owner) == 1)
			C.assert(C.vinix_n64_frame(owner, 0) == 1 && C.vinix_n64_save(owner) == 1)
			for i := u32(0); i < 3; i++ {
				C.assert(C.vinix_n64_reset(owner) == 1)
				C.assert(C.vinix_n64_frame(owner, 0) == 1)
				C.assert(C.vinix_n64_load(owner, rom, save_path) == 1)
				C.assert(C.vinix_n64_frame(owner, 0) == 1)
			}
			C.vinix_n64_destroy(owner)
			C.puts(c'N64 BRIDGE: real ROM replacement, frames, save, reset and cleanup PASS')
		}
		C.puts(c'N64 BRIDGE NATIVE: PASS')
		C.fflush(C.stdout)
		$if n64_bridge_guest ? { for { C.pause() } }
		return 0
	}
}
