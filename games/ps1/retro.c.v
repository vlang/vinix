// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

#include "@VMODROOT/abi.h"
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/ioctl.h>
#include <sys/soundcard.h>
#include <errno.h>

struct C.retro_game_info {
	path &char
	data voidptr
	size usize
	meta &char
}

struct C.retro_variable {
	key &char
mut:
	value &char
}

fn C.retro_api_version() u32
fn C.retro_set_environment(fn (u32, voidptr) bool)
fn C.ps1_set_video(voidptr)
fn C.retro_set_audio_sample(fn (i16, i16))
fn C.ps1_set_audio_batch(voidptr)
fn C.retro_set_input_poll(fn ())
fn C.retro_set_input_state(fn (u32, u32, u32, u32) i16)
fn C.retro_set_controller_port_device(u32, u32)
fn C.retro_init()
fn C.retro_load_game(&C.retro_game_info) bool
fn C.retro_run()
fn C.retro_reset()
fn C.retro_unload_game()
fn C.retro_deinit()
fn C.retro_get_memory_data(u32) voidptr
fn C.retro_get_memory_size(u32) usize
fn C.ps1_set_log(voidptr)
fn C.ps1_surface_load(&u32) u32
fn C.ps1_surface_store(&u32, u32)
fn C.open(&char, int, ...int) int
fn C.close(int) int
fn C.read(int, voidptr, usize) isize
fn C.write(int, voidptr, usize) isize
fn C.ftruncate(i32, u64) i32
fn C.mmap(voidptr, usize, int, int, int, i64) voidptr
fn C.munmap(voidptr, usize) int
fn C.unlink(&char) int
fn C.getpid() int
fn C.ioctl(int, u64, voidptr) int
fn C.memcpy(voidptr, voidptr, usize) voidptr

__global emulator = Emulator{}

struct Emulator {
mut:
	options      map[string]string
	system       string
	saves        string
	game         string
	card_path    string
	surface_path string
	surface      voidptr = unsafe { nil }
	pixel_format u32
	buttons      u32
	pulse        u32
	pulse_frames int
	paused       bool
	loaded       bool
	initialized  bool
	frames       u64
	audio_fd     int = -1
	muted        bool
	status       string = 'Open a PS1 game, or play the included demo.'
}

const surface_width = 640
const surface_height = 480
const surface_bytes = 48 + 2 * surface_width * surface_height * 4

fn retro_environment(command u32, data voidptr) bool {
	if data == unsafe { nil } { return false }
	unsafe {
		match command {
			3 { *(&bool(data)) = true } // can duplicate frames
			6 { // Core message; text is the first field of retro_message.
				message := *(&&char(data))
				if message != nil { eprintln('PS1: ${cstring_to_vstring(message)}') }
			}
			9 { *(&&char(data)) = &char(emulator.system.str) }
			10 {
				format := *(&u32(data))
				if format > 2 { return false }
				emulator.pixel_format = format
			}
			15 {
				mut variable := &C.retro_variable(data)
				key := cstring_to_vstring(variable.key)
				value := emulator.options[key] or { return false }
				variable.value = &char(value.str)
			}
			16 {
				variables := &C.retro_variable(data)
				for index := 0; index < 1024 && variables[index].key != nil; index++ {
					key := cstring_to_vstring(variables[index].key)
					definition := cstring_to_vstring(variables[index].value)
					mut start := (definition.index(';') or { continue }) + 1
					for start < definition.len && definition[start] == ` ` { start++ }
					mut end := start
					for end < definition.len && definition[end] != `|` { end++ }
					value := definition[start..end]
					emulator.options[key] = value
				}
				// These are ordinary core options. The interpreter avoids executable
				// mappings and background compilation on the current Vinix runner.
				emulator.options['pcsx_rearmed_drc'] = 'disabled'
				emulator.options['pcsx_rearmed_gpu_thread_rendering'] = 'disabled'
			}
			17 { *(&bool(data)) = false }
			18, 11, 35 { return true } // descriptors, performance level, controller info
			27 { C.ps1_set_log(data) }
			31 { *(&&char(data)) = &char(emulator.saves.str) }
			37 { return true } // software geometry changes are scaled at presentation
			39 { *(&u32(data)) = 0 } // English
			52 { *(&u32(data)) = 0 } // original retro_variable option interface
			47 | 0x10000 { *(&u32(data)) = 3 } // video and audio enabled
			else { return false }
		}
	}
	return true
}

fn retro_input_poll() {}

fn retro_input(port u32, device u32, index u32, id u32) i16 {
	if port != 0 || device != 1 || index != 0 || id >= 16 { return 0 }
	return if (emulator.buttons | emulator.pulse) & (u32(1) << id) != 0 { i16(1) } else { i16(0) }
}

fn retro_audio_batch(data &i16, frames usize) usize {
	if emulator.audio_fd >= 0 && !emulator.paused {
		// Nonblocking audio keeps a busy device from parking the desktop IPC.
		C.write(emulator.audio_fd, data, frames * 4)
	}
	return frames
}

fn retro_audio(left i16, right i16) {
	samples := [left, right]!
	retro_audio_batch(unsafe { &samples[0] }, 1)
}

fn retro_video(data voidptr, width u32, height u32, pitch usize) {
	if data == unsafe { nil } || data == unsafe { voidptr(-1) } || width == 0 || height == 0
		|| width > 2048 || height > 1024 {
		return
	}
	bytes := if emulator.pixel_format == 1 { usize(4) } else { usize(2) }
	if pitch < usize(width) * bytes { return }
	base := usize(emulator.surface)
	active := unsafe { &u32(base + 28) }
	reader := unsafe { &u32(base + 32) }
	next := C.ps1_surface_load(active) ^ 1
	if C.ps1_surface_load(reader) == next { return }
	unsafe {
		destination := &u32(base + 48 + usize(next) * surface_width * surface_height * 4)
		for y in 0 .. surface_height {
			row := usize(data) + usize(u64(y) * height / surface_height) * pitch
			for x in 0 .. surface_width {
				column := usize(u64(x) * width / surface_width)
				mut color := u32(0)
				if emulator.pixel_format == 1 {
					color = *(&u32(row + column * 4)) & 0xffffff
				} else {
					pixel := u32(*(&u16(row + column * 2)))
					if emulator.pixel_format == 2 {
						color = ((pixel >> 11) * 255 / 31) << 16 | ((pixel >> 5 & 63) * 255 / 63) << 8 | (pixel & 31) * 255 / 31
					} else {
						color = ((pixel >> 10 & 31) * 255 / 31) << 16 | ((pixel >> 5 & 31) * 255 / 31) << 8 | (pixel & 31) * 255 / 31
					}
				}
				destination[y * surface_width + x] = 0xff000000 | color
			}
		}
	}
	C.ps1_surface_store(active, next)
}

fn surface_open() ! {
	emulator.surface_path = '/tmp/vinix-ps1-${C.getpid()}.surface'
	fd := C.open(unsafe { &char(emulator.surface_path.str) }, C.O_CREAT | C.O_EXCL | C.O_RDWR, 384)
	if fd < 0 { return error('cannot create shared framebuffer') }
	defer { C.close(fd) }
	if C.ftruncate(fd, surface_bytes) != 0 { return error('cannot size shared framebuffer') }
	emulator.surface = C.mmap(unsafe { nil }, surface_bytes, C.PROT_READ | C.PROT_WRITE, C.MAP_SHARED, fd, 0)
	if emulator.surface == unsafe { voidptr(-1) } {
		emulator.surface = unsafe { nil }
		return error('cannot map shared framebuffer')
	}
	unsafe {
		header := &u32(emulator.surface)
		for index, value in [u32(0x31534656), 1, 48, surface_width, surface_height, surface_width * 4,
			1, 0, ~u32(0), 0, surface_width * surface_height * 4, 0]! {
			header[index] = value
		}
	}
}

fn emulator_init() ! {
	home := os.getenv('VINIX_USER_HOME')
	root := os.getenv('VINIX_PS1_DATA')
	path := if root.len > 0 {
		root
	} else {
		os.join_path(if home.len > 0 { home } else { '/root' }, '.local/share/vinix/ps1')
	}
	emulator.system = os.join_path(path, 'bios')
	emulator.saves = os.join_path(path, 'saves')
	os.mkdir_all(emulator.system)!
	os.mkdir_all(emulator.saves)!
	surface_open()!
	if C.retro_api_version() != 1 { return error('unsupported libretro API') }
	C.retro_set_environment(retro_environment)
	C.ps1_set_video(voidptr(retro_video))
	C.retro_set_audio_sample(retro_audio)
	C.ps1_set_audio_batch(voidptr(retro_audio_batch))
	C.retro_set_input_poll(retro_input_poll)
	C.retro_set_input_state(retro_input)
	C.retro_init()
	emulator.initialized = true
	C.retro_set_controller_port_device(0, 1)
	if !emulator.muted {
		emulator.audio_fd = C.open(c'/dev/dsp', C.O_WRONLY | C.O_NONBLOCK)
		if emulator.audio_fd >= 0 {
			mut format := int(C.AFMT_S16_LE)
			mut channels := 2
			mut rate := 44100
			if C.ioctl(emulator.audio_fd, C.SNDCTL_DSP_SETFMT, &format) != 0
				|| C.ioctl(emulator.audio_fd, C.SNDCTL_DSP_CHANNELS, &channels) != 0
				|| C.ioctl(emulator.audio_fd, C.SNDCTL_DSP_SPEED, &rate) != 0 {
				C.close(emulator.audio_fd)
				emulator.audio_fd = -1
			}
		}
	}
}

fn card_save() {
	if !emulator.loaded { return }
	data := C.retro_get_memory_data(0)
	size := C.retro_get_memory_size(0)
	if data != unsafe { nil } && size > 0 && size <= 1024 * 1024 {
		temporary := emulator.card_path + '.tmp'
		defer { unsafe { temporary.free() } }
		os.write_file_array(temporary, unsafe { (&u8(data)).vbytes(int(size)) }) or {
			eprintln('PS1: memory card save failed: ${err}')
			return
		}
		os.rename(temporary, emulator.card_path) or { eprintln('PS1: memory card rename failed: ${err}') }
	}
}

fn load_game(path string) ! {
	if !os.is_file(path) { return error('game file does not exist: ${path}') }
	if emulator.loaded {
		card_save()
		C.retro_unload_game()
		emulator.loaded = false
	}
	unsafe {
		emulator.game.free()
		emulator.card_path.free()
	}
	emulator.game = os.real_path(path)
	info := C.retro_game_info{ path: unsafe { &char(emulator.game.str) }, data: unsafe { nil }, size: 0, meta: unsafe { nil } }
	if !C.retro_load_game(&info) { return error('PCSX-ReARMed could not load ${path}') }
	emulator.loaded = true
	emulator.paused = false
	emulator.buttons = 0
	emulator.pulse = 0
	emulator.frames = 0
	// A stable hash of the absolute path keeps games with the same basename
	// from sharing cards. Disc files remain beside their CUE/M3U manifests.
	emulator.card_path = os.join_path(emulator.saves, '${os.file_name(path)}-${path_hash(emulator.game):08x}.mcr')
	if os.is_file(emulator.card_path) {
		card := os.read_bytes(emulator.card_path)!
		defer { unsafe { card.free() } }
		if usize(card.len) == C.retro_get_memory_size(0) {
			C.memcpy(C.retro_get_memory_data(0), card.data, usize(card.len))
		}
	}
	set_status('Playing ${os.file_name(path)}')
	println('PS1: loaded ${emulator.game}')
}

fn path_hash(path string) u32 {
	mut hash := u32(2166136261)
	for character in path { hash = (hash ^ character) * 16777619 }
	return hash
}

fn set_status(value string) {
	unsafe { emulator.status.free() }
	emulator.status = value.clone()
}

fn emulator_tick() {
	if emulator.loaded && !emulator.paused {
		C.retro_run()
		emulator.frames++
		if emulator.pulse_frames > 0 {
			emulator.pulse_frames--
			if emulator.pulse_frames == 0 { emulator.pulse = 0 }
		}
		if emulator.frames % 300 == 0 { card_save() }
	}
}

fn emulator_close() {
	if emulator.loaded {
		card_save()
		C.retro_unload_game()
		emulator.loaded = false
	}
	if emulator.initialized {
		C.retro_deinit()
		emulator.initialized = false
	}
	if emulator.audio_fd >= 0 { C.close(emulator.audio_fd) }
	if emulator.surface != unsafe { nil } { C.munmap(emulator.surface, surface_bytes) }
	if emulator.surface_path.len > 0 { C.unlink(unsafe { &char(emulator.surface_path.str) }) }
	println('PS1: clean shutdown')
}
