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

fn C.ps2_create(voidptr, voidptr) voidptr
fn C.vinix_ps2_load(voidptr, &char, &char, &char) int
fn C.vinix_ps2_frame(voidptr, u32) int
fn C.vinix_ps2_reset(voidptr) int
fn C.vinix_ps2_save(voidptr) int
fn C.vinix_ps2_error(voidptr) &char
fn C.vinix_ps2_destroy(voidptr)
fn C.ps2_surface_load(&u32) u32
fn C.ps2_surface_store(&u32, u32)
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
	core          voidptr = unsafe { nil }
	bios          string
	bios_override string
	saves         string
	game          string
	card_path     string
	surface_path  string
	surface       voidptr = unsafe { nil }
	buttons       u32
	pulse         u32
	pulse_frames  int
	paused        bool
	loaded        bool
	frames        u64
	audio_fd      int = -1
	muted         bool
	status        string = 'Open a PS2 ISO or ELF, or play the included homebrew.'
}

const surface_width = 640
const surface_height = 480
const surface_bytes = 48 + 2 * surface_width * surface_height * 4

fn ps2_audio(data &i16, frames usize) {
	if emulator.audio_fd >= 0 && !emulator.paused {
		C.write(emulator.audio_fd, data, frames * 4)
	}
}

fn ps2_video(data voidptr, width u32, height u32, pitch usize) {
	if data == unsafe { nil } || width == 0 || height == 0 || width > 2048 || height > 2048
		|| pitch < usize(width) * 4 || emulator.surface == unsafe { nil } { return }
	base := usize(emulator.surface)
	active := unsafe { &u32(base + 28) }
	reader := unsafe { &u32(base + 32) }
	next := C.ps2_surface_load(active) ^ 1
	if C.ps2_surface_load(reader) == next { return }
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
	C.ps2_surface_store(active, next)
}

fn surface_open() ! {
	emulator.surface_path = '/tmp/vinix-ps2-${C.getpid()}.surface'
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
	root := os.getenv('VINIX_PS2_DATA')
	path := if root.len > 0 { root } else {
		os.join_path(if home.len > 0 { home } else { '/root' }, '.local/share/vinix/ps2')
	}
	bios_directory := os.join_path(path, 'bios')
	emulator.bios = if emulator.bios_override.len > 0 {
		emulator.bios_override.clone()
	} else { os.join_path(bios_directory, 'ps2.bin') }
	emulator.saves = os.join_path(path, 'saves')
	os.mkdir_all(bios_directory)!
	os.mkdir_all(emulator.saves)!
	surface_open()!
	emulator.core = C.ps2_create(voidptr(ps2_video), voidptr(ps2_audio))
	if emulator.core == unsafe { nil } { return error('cannot initialize PS2 emulator') }
	if !emulator.muted {
		emulator.audio_fd = C.open(c'/dev/dsp', C.O_WRONLY | C.O_NONBLOCK)
		if emulator.audio_fd >= 0 {
			mut format := int(C.AFMT_S16_LE)
			mut channels := 2
			mut rate := 48000
			if C.ioctl(emulator.audio_fd, C.SNDCTL_DSP_SETFMT, &format) != 0
				|| C.ioctl(emulator.audio_fd, C.SNDCTL_DSP_CHANNELS, &channels) != 0
				|| C.ioctl(emulator.audio_fd, C.SNDCTL_DSP_SPEED, &rate) != 0 {
				C.close(emulator.audio_fd)
				emulator.audio_fd = -1
			}
		}
	}
}

fn core_error() string {
	message := C.vinix_ps2_error(emulator.core)
	return if message != unsafe { nil } { unsafe { cstring_to_vstring(message) } }
		else { 'PS2 emulation failed' }
}

fn card_save() {
	if emulator.loaded && C.vinix_ps2_save(emulator.core) == 0 {
		message := core_error()
		eprintln('PS2: ${message}')
		set_status(message)
		unsafe { message.free() }
	}
}

fn load_game(path string) ! {
	if !os.is_file(path) { return error('game file does not exist: ${path}') }
	card_save()
	game := os.real_path(path)
	name := os.file_name(path)
	defer { unsafe { name.free() } }
	card := os.join_path(emulator.saves, '${name}-${path_hash(game):08x}.ps2')
	if C.vinix_ps2_load(emulator.core, unsafe { &char(game.str) }, unsafe { &char(emulator.bios.str) },
		unsafe { &char(card.str) }) == 0 {
		unsafe { game.free(); card.free() }
		return error(core_error())
	}
	unsafe { emulator.game.free(); emulator.card_path.free() }
	emulator.game = game
	emulator.card_path = card
	emulator.loaded = true
	emulator.paused = false
	emulator.buttons = 0
	emulator.pulse = 0
	emulator.pulse_frames = 0
	emulator.frames = 0
	status := 'Playing ${name}'
	set_status(status)
	unsafe { status.free() }
	println('PS2: loaded ${emulator.game}')
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

fn emulator_reset() ! {
	if C.vinix_ps2_reset(emulator.core) == 0 {
		return error(core_error())
	}
}

fn emulator_tick() {
	if emulator.loaded && !emulator.paused {
		if C.vinix_ps2_frame(emulator.core, emulator.buttons | emulator.pulse) == 0 {
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
		if emulator.frames % 300 == 0 { card_save() }
	}
}

fn emulator_close() {
	card_save()
	if emulator.core != unsafe { nil } {
		C.vinix_ps2_destroy(emulator.core)
		emulator.core = unsafe { nil }
	}
	if emulator.audio_fd >= 0 { C.close(emulator.audio_fd) }
	if emulator.surface != unsafe { nil } { C.munmap(emulator.surface, surface_bytes) }
	if emulator.surface_path.len > 0 { C.unlink(unsafe { &char(emulator.surface_path.str) }) }
	println('PS2: clean shutdown')
}
