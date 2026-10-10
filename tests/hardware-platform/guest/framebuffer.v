// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Drawing on the machine's screen, for the scenarios that ask whether what
// was on it survives something.
//
// /dev/fb0 is the framebuffer the kernel was handed at boot. Mapping it is
// also what tells the kernel's console to stop drawing there, as it does for
// a desktop, so that what this program draws is not written over by the next
// kernel message. The pattern is one the host can work out for itself from a
// picture of the screen: in column x of row y, red is x, green is y and blue
// is their sum, each as a byte.
module main

#include <sys/mman.h>
#include <sys/ioctl.h>

fn C.mmap(address voidptr, length usize, protection i32, flags i32, fd i32, offset i64) voidptr
fn C.ioctl(fd i32, request u64, argument voidptr) i32

const fbioget_vscreeninfo = u64(0x4600)
const fbioget_fscreeninfo = u64(0x4602)

// How many columns and rows of the screen's corner carry the pattern; the
// host's ScreenCheck names the same number.
const screen_block = 256

struct Screen {
mut:
	pixels &u8 = unsafe { nil }
	width  int
	height int
	stride int
	bytes  int // per pixel
	red    int // bit offsets
	green  int
	blue   int
}

fn u32_at(buffer []u8, offset int) int {
	return int(u32(buffer[offset]) | (u32(buffer[offset + 1]) << 8) | (u32(buffer[offset + 2]) << 16) | (u32(buffer[
		offset + 3]) << 24))
}

// Maps the framebuffer. An error when the machine has none, or one in a
// layout this does not draw on.
fn open_screen() !Screen {
	fd := C.open(c'/dev/fb0', C.O_RDWR)
	if fd < 0 {
		return errno_error('/dev/fb0')
	}
	// struct fb_var_screeninfo and struct fb_fix_screeninfo, as Linux lays
	// them out; only a few fields are read.
	mut variable := []u8{len: 160}
	mut fixed := []u8{len: 80}
	if C.ioctl(fd, fbioget_vscreeninfo, variable.data) != 0 || C.ioctl(fd, fbioget_fscreeninfo, fixed.data) != 0 {
		return errno_error('/dev/fb0: reading the mode')
	}
	mut screen := Screen{
		width:  u32_at(variable, 0)
		height: u32_at(variable, 4)
		bytes:  u32_at(variable, 24) / 8
		red:    u32_at(variable, 32)
		green:  u32_at(variable, 44)
		blue:   u32_at(variable, 56)
		stride: u32_at(fixed, 48)
	}
	if screen.bytes != 4 || screen.width < screen_block || screen.height < screen_block || screen.stride < screen.width * 4 {
		return error('/dev/fb0 is ${screen.width} by ${screen.height} with ${screen.bytes} bytes a pixel and ${screen.stride} a row')
	}
	mapped := C.mmap(unsafe { nil }, usize(screen.stride * screen.height), C.PROT_READ | C.PROT_WRITE,
		C.MAP_SHARED, fd, 0)
	if i64(mapped) == -1 || mapped == unsafe { nil } {
		return errno_error('/dev/fb0: mapping it')
	}
	screen.pixels = unsafe { &u8(mapped) }
	return screen
}

fn (s &Screen) pixel(x int, y int) &u32 {
	return unsafe { &u32(s.pixels + y * s.stride + x * 4) }
}

// Draws the pattern in the top-left corner.
fn (mut s Screen) draw_pattern() {
	for y in 0 .. screen_block {
		for x in 0 .. screen_block {
			value := (u32(u8(x)) << u32(s.red)) | (u32(u8(y)) << u32(s.green)) | (u32(u8(x + y)) << u32(s.blue))
			unsafe {
				*s.pixel(x, y) = value
			}
		}
	}
}

// How many pixels of the corner are not the pattern, as the framebuffer
// reads back: what the kernel put there, which need not be what is shown.
fn (s &Screen) pattern_errors() int {
	mask := (u32(0xff) << u32(s.red)) | (u32(0xff) << u32(s.green)) | (u32(0xff) << u32(s.blue))
	mut wrong := 0
	for y in 0 .. screen_block {
		for x in 0 .. screen_block {
			value := (u32(u8(x)) << u32(s.red)) | (u32(u8(y)) << u32(s.green)) | (u32(u8(x + y)) << u32(s.blue))
			if unsafe { *s.pixel(x, y) } & mask != value {
				wrong++
			}
		}
	}
	return wrong
}
