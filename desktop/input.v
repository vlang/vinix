// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// Input sources: /dev/pointer for the mouse and the controlling terminal for
// the keyboard. Reads never block. Between active frames the compositor waits
// for either descriptor to become ready, with a timeout for its housekeeping.
module main

// PointerPacket mirrors the struct the Vinix pointer driver writes. `x`/`y`
// are raw device coordinates spanning 0..max_x/0..max_y; the desktop scales
// them to the screen, so the driver need not know the resolution.
struct PointerPacket {
mut:
	// This is a kernel ABI, so keep its scalar widths explicit. The desktop's
	// v3 compiler represents `int` as 64 bits while the kernel compiler uses a
	// 32-bit C int; spelling these as i32 keeps both sides at the same 32-byte
	// packet prefix; newer kernels append horizontal scrolling.
	x        i32
	y        i32
	max_x    i32
	max_y    i32
	buttons  u32
	pressed  u32
	released u32
	scroll   i32
	scroll_x i32
}

// Button bits, in the order the kernel pointer ABI reports them.
const button_left = u32(1)
const button_right = u32(2)
const button_middle = u32(4)
const button_back = u32(0x48) // BTN_SIDE (HID button 4) or BTN_BACK

struct PointerDevice {
mut:
	fd int = -1
}

fn open_pointer(path string) PointerDevice {
	return PointerDevice{
		fd: desktop_open_ro_nonblock(path)
	}
}

fn (p &PointerDevice) available() bool {
	return p.fd >= 0
}

// poll answers with the driver's current view. A read that comes up short is
// reported as "nothing new" rather than as a zeroed position, which would
// otherwise yank the cursor to the top left corner.
fn (mut p PointerDevice) poll() ?PointerPacket {
	if p.fd < 0 {
		return none
	}
	mut packet := PointerPacket{}
	n := desktop_read(p.fd, &packet, u64(sizeof(PointerPacket)))
	// Older kernels (and PS/2) return the original 32-byte prefix. The zeroed
	// trailing axis keeps those devices working during an app/kernel upgrade.
	if n != 32 && n != i64(sizeof(PointerPacket)) {
		return none
	}
	return packet
}

fn (mut p PointerDevice) close() {
	if p.fd >= 0 {
		desktop_close(p.fd)
		p.fd = -1
	}
}

// Keyboard puts the terminal in raw mode for as long as the desktop owns the
// screen. Without it the console would echo keystrokes straight onto the
// framebuffer the compositor is drawing into.
struct Keyboard {
mut:
	fd    int
	saved TerminalState
	key_events bool
	packet [32]u8
	packet_used int
	packet_ms i64
	held [256]bool
	owners [256]int
	aliases [256]int
	caps bool
	num bool
}

fn open_keyboard() Keyboard {
	mut kbd := Keyboard{
		fd: 0
	}
	kbd.saved = desktop_terminal_raw(kbd.fd)
	kbd.key_events = desktop_ioctl(kbd.fd, u64(0x564b0001), voidptr(1)) == 0
	kbd.caps = desktop_keyboard_caps_lock(kbd.fd)
	mut leds := u8(0)
	if desktop_ioctl(kbd.fd, keyboard_kdgetled, unsafe { &leds }) == 0 { kbd.num = leds & 2 != 0 }
	return kbd
}

// poll returns every byte waiting on the terminal, or an empty string.
fn (mut kbd Keyboard) poll() string {
	mut buf := [64]u8{}
	n := desktop_read(kbd.fd, &buf[0], 64)
	if n <= 0 {
		return ''
	}
	return unsafe { tos(&buf[0], int(n)).clone() }
}

fn (mut kbd Keyboard) close() {
	if kbd.key_events { desktop_ioctl(kbd.fd, u64(0x564b0001), unsafe { nil }) }
	desktop_terminal_restore(kbd.fd, mut kbd.saved)
}
