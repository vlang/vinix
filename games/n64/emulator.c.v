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

fn C.n64_create(voidptr, voidptr) voidptr
fn C.vinix_n64_load(voidptr, &char, &char) int
fn C.vinix_n64_loaded(voidptr) int
fn C.vinix_n64_frame(voidptr, u32) int
fn C.vinix_n64_reset(voidptr) int
fn C.vinix_n64_save(voidptr) int
fn C.vinix_n64_error(voidptr) &char
fn C.vinix_n64_destroy(voidptr)
fn C.n64_surface_load(&u32) u32
fn C.n64_surface_store(&u32, u32)
fn C.open(&char, int, ...int) int
fn C.close(int) int
fn C.read(int, voidptr, usize) isize
fn C.write(int, voidptr, usize) isize
fn C.ftruncate(i32, u64) i32
fn C.mmap(voidptr, usize, int, int, int, i64) voidptr
fn C.munmap(voidptr, usize) int
fn C.unlink(&char) int
fn C.getpid() int
fn C.realpath(&char, voidptr) &char
fn C.ioctl(int, u64, voidptr) int
fn C.memcpy(voidptr, voidptr, usize) voidptr

__global emulator = Emulator{}

struct Emulator {
mut:
	core          voidptr = unsafe { nil }
	saves         string
	game          string
	save_path     string
	surface_path  string
	surface       voidptr = unsafe { nil }
	buttons       u32
	pulse         u32
	pulse_frames  int
	paused        bool
	loaded        bool
	frames        u64
	audio_fd      int = -1
	audio_rate    u32
	muted         bool
	status        string = 'Open an N64 cartridge, or play the included homebrew.'
}

const surface_width = 640
const surface_height = 480
const surface_bytes = 48 + 2 * surface_width * surface_height * 4

fn n64_audio(data &i16, frames usize, rate u32) {
	if data == unsafe { nil } || frames > 8192 { return }
	if emulator.audio_fd >= 0 && !emulator.paused {
		if rate < 8000 || rate > 96000 { return }
		if emulator.audio_rate != rate {
			mut requested := int(rate)
			if C.ioctl(emulator.audio_fd, C.SNDCTL_DSP_SPEED, &requested) != 0 { return }
			emulator.audio_rate = rate
		}
		C.write(emulator.audio_fd, data, frames * 4)
	}
}

fn n64_video(data voidptr, width u32, height u32, pitch usize) {
	if data == unsafe { nil } || width == 0 || height == 0 || width > 2048 || height > 2048
		|| pitch < usize(width) * 4 || emulator.surface == unsafe { nil } { return }
	base := usize(emulator.surface)
	active := unsafe { &u32(base + 28) }
	reader := unsafe { &u32(base + 32) }
	next := C.n64_surface_load(active) ^ 1
	if C.n64_surface_load(reader) == next { return }
	unsafe {
		destination := &u32(base + 48 + usize(next) * surface_width * surface_height * 4)
		for y in 0 .. surface_height {
			row := usize(data) + usize(u64(y) * height / surface_height) * pitch
			for x in 0 .. surface_width {
				column := usize(u64(x) * width / surface_width)
				destination[y * surface_width + x] = 0xff000000 | (*(&u32(row + column * 4)) & 0xffffff)
			}
		}
	}
	C.n64_surface_store(active, next)
}

fn surface_open() ! {
	emulator.surface_path = '/tmp/vinix-n64-${C.getpid()}.surface'
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
	root := os.getenv('VINIX_N64_DATA')
	path := if root.len > 0 { root } else {
		os.join_path(if home.len > 0 { home } else { '/root' }, '.local/share/vinix/n64')
	}
	emulator.saves = os.join_path(path, 'saves')
	os.mkdir_all(emulator.saves)!
	surface_open()!
	emulator.core = C.n64_create(voidptr(n64_video), voidptr(n64_audio))
	if emulator.core == unsafe { nil } { return error('cannot initialize N64 emulator') }
	if !emulator.muted {
		emulator.audio_fd = C.open(c'/dev/dsp', C.O_WRONLY | C.O_NONBLOCK)
		if emulator.audio_fd >= 0 {
			mut format := int(C.AFMT_S16_LE)
			mut channels := 2
			if C.ioctl(emulator.audio_fd, C.SNDCTL_DSP_SETFMT, &format) != 0
				|| C.ioctl(emulator.audio_fd, C.SNDCTL_DSP_CHANNELS, &channels) != 0 {
				C.close(emulator.audio_fd)
				emulator.audio_fd = -1
			}
		}
	}
}

fn core_error() string {
	message := C.vinix_n64_error(emulator.core)
	return if message != unsafe { nil } { unsafe { cstring_to_vstring(message) } }
		else { 'N64 emulation failed' }
}

fn game_save() {
	if emulator.loaded && C.vinix_n64_save(emulator.core) == 0 {
		message := core_error()
		eprintln(message)
		set_status(message)
		unsafe { message.free() }
	}
}

fn load_game(path string) bool {
	canonical := C.realpath(unsafe { &char(path.str) }, unsafe { nil })
	if canonical == unsafe { nil } {
		message := 'Cannot resolve cartridge path: ${path}'
		set_status(message)
		unsafe { message.free() }
		return false
	}
	game_save()
	game := unsafe { cstring_to_vstring(canonical) }
	unsafe { free(canonical) }
	name := os.file_name(path)
	defer { unsafe { name.free() } }
	hash := path_hash(game).hex_full()
	filename := '${name}-${hash}.sav'
	defer { unsafe { hash.free(); filename.free() } }
	save_path := '${emulator.saves}/${filename}'
	if C.vinix_n64_load(emulator.core, unsafe { &char(game.str) }, unsafe { &char(save_path.str) }) == 0 {
		unsafe { game.free(); save_path.free() }
		emulator.loaded = C.vinix_n64_loaded(emulator.core) != 0
		message := core_error()
		set_status(message)
		unsafe { message.free() }
		return false
	}
	unsafe { emulator.game.free(); emulator.save_path.free() }
	emulator.game = game
	emulator.save_path = save_path
	emulator.loaded = true
	emulator.paused = false
	emulator.buttons = 0
	emulator.pulse = 0
	emulator.pulse_frames = 0
	emulator.frames = 0
	status := 'Playing ${name} — arrows: D-pad, WASD: stick, Enter: Start'
	set_status(status)
	unsafe { status.free() }
	loaded_message := 'N64: loaded ${emulator.game}'
	println(loaded_message)
	unsafe { loaded_message.free() }
	return true
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

fn emulator_reset() bool {
	if C.vinix_n64_reset(emulator.core) == 0 {
		emulator.loaded = C.vinix_n64_loaded(emulator.core) != 0
		message := core_error()
		set_status(message)
		unsafe { message.free() }
		return false
	}
	return true
}

fn emulator_tick() {
	if emulator.loaded && !emulator.paused {
		if C.vinix_n64_frame(emulator.core, emulator.buttons | emulator.pulse) == 0 {
			message := core_error()
			set_status(message)
			unsafe { message.free() }
			emulator.paused = true
			return
		}
		emulator.frames++
		if emulator.pulse_frames > 0 {
			emulator.pulse_frames--
			if emulator.pulse_frames == 0 { emulator.pulse = 0 }
		}
		if emulator.frames % 300 == 0 { game_save() }
	}
}

fn emulator_close() {
	game_save()
	if emulator.core != unsafe { nil } {
		C.vinix_n64_destroy(emulator.core)
		emulator.core = unsafe { nil }
	}
	if emulator.audio_fd >= 0 { C.close(emulator.audio_fd) }
	if emulator.surface != unsafe { nil } { C.munmap(emulator.surface, surface_bytes) }
	if emulator.surface_path.len > 0 { C.unlink(unsafe { &char(emulator.surface_path.str) }) }
	println('N64: clean shutdown')
}
