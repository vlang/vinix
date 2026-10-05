// SPDX-License-Identifier: GPL-2.0-or-later
// Private Xvfb application/input/selection bridge; fixed storage and explicit
// libc/Xlib ownership preserve the original C process and allocation policy.
@[translated]
module winehost

#include "wine-host-v-abi.h"

fn is_null(p voidptr) bool { unsafe { return p == nil } }

@[typedef]
struct C.Display {}
@[typedef]
struct C.XErrorEvent {}
struct C.timespec { mut: tv_sec i64 tv_nsec i64 }
struct C.sockaddr_un { mut: sun_family u16 sun_path [108]char }
@[typedef]
struct C.XModifierKeymap { max_keypermod i32 modifiermap &u8 }
@[typedef]
struct C.XWindowAttributes { x i32 y i32 width i32 height i32 @class i32 map_state i32 override_redirect i32 }
@[typedef]
struct C.XClientData { mut: l [5]i64 }
@[typedef]
struct C.XClientMessageEvent { mut: @type i32 window u64 message_type u64 format i32 data C.XClientData }
@[typedef]
struct C.XSelectionEvent { mut: @type i32 display &C.Display requestor u64 selection u64 target u64 property u64 time u64 }
@[typedef]
struct C.XSelectionRequestEvent { owner u64 requestor u64 selection u64 target u64 property u64 time u64 }
@[typedef]
struct C.XEvent { mut: @type i32 xclient C.XClientMessageEvent xselection C.XSelectionEvent xselectionrequest C.XSelectionRequestEvent }
struct HostEvent { mut: magic u32 kind u32 x i32 y i32 length u32 }
struct HeldKey { mut: code u8 release_at_ms u64 }
struct UnicodeKey { mut: code u8 symbol u64 tap_number u64 tapped_at_ms u64 }
__global (
	hold_game_keys bool
	held_game_keys [16]HeldKey
	keyboard_scanned bool
	original_keysyms [256][2]u64
	unicode_keys [32]UnicodeKey
	unicode_key_count i32
	unicode_key_taps u64
	utf8_code_point u32
	utf8_length i32
	utf8_remaining i32
	clipboard_window u64
	clipboard_selection u64
	clipboard_utf8 u64
	clipboard_targets u64
	clipboard_text u64
	clipboard_data [65536]u8
	clipboard_length usize
)
@[c_extern]
__global C.stderr voidptr
fn C.vwh_running() i32
fn C.vwh_set_running(i32)
fn C.vwh_errno() i32
fn C.vwh_install_signals()
fn C.vwh_install_x_error()
fn C.vwh_damage_store(voidptr, u32)
fn C.snprintf(&char, usize, &char, ...) i32
fn C.fprintf(voidptr, &char, ...) i32
fn C.perror(&char)
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memmove(voidptr, voidptr, usize) voidptr
fn C.memset(voidptr, i32, usize) voidptr
fn C.strcmp(&char, &char) i32
fn C.strchr(&char, i32) &char
fn C.unlink(&char) i32
fn C.rmdir(&char) i32
fn C.mkdir(&char, u32) i32
fn C.access(&char, i32) i32
fn C.symlink(&char, &char) i32
fn C.readlink(&char, &char, usize) isize
fn C.fork() i32
fn C.execl(&char, &char, ...) i32
fn C._exit(i32)
fn C.setenv(&char, &char, i32) i32
fn C.unsetenv(&char) i32
fn C.setpgid(i32, i32) i32
fn C.waitpid(i32, &i32, i32) i32
fn C.kill(i32, i32) i32
fn C.nanosleep(voidptr, voidptr) i32
fn C.clock_gettime(i32, voidptr) i32
fn C.socket(i32, i32, i32) i32
fn C.connect(i32, voidptr, u32) i32
fn C.close(i32) i32
fn C.open(&char, i32, ...) i32
fn C.ftruncate(i32, i64) i32
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.munmap(voidptr, usize) i32
fn C.fcntl(i32, i32, ...) i32
fn C.read(i32, voidptr, usize) isize
fn C.XOpenDisplay(&char) &C.Display
fn C.XCloseDisplay(voidptr) i32
fn C.XKeysymToKeycode(voidptr, u64) u8
fn C.XTestFakeKeyEvent(voidptr, u32, i32, u64) i32
fn C.XTestFakeButtonEvent(voidptr, u32, i32, u64) i32
fn C.XWarpPointer(voidptr, u64, u64, i32, i32, u32, u32, i32, i32) i32
fn C.XFlush(voidptr) i32
fn C.XSync(voidptr, i32) i32
fn C.XDisplayKeycodes(voidptr, voidptr, voidptr) i32
fn C.XGetKeyboardMapping(voidptr, u8, i32, voidptr) voidptr
fn C.XGetModifierMapping(voidptr) &C.XModifierKeymap
fn C.XFreeModifiermap(voidptr) i32
fn C.XFree(voidptr) i32
fn C.XChangeKeyboardMapping(voidptr, i32, i32, voidptr, i32) i32
fn C.DefaultRootWindow(voidptr) u64
fn C.DefaultScreen(voidptr) i32
fn C.DisplayWidth(voidptr, i32) i32
fn C.DisplayHeight(voidptr, i32) i32
fn C.XQueryPointer(voidptr, u64, voidptr, voidptr, voidptr, voidptr, voidptr, voidptr, voidptr) i32
fn C.XSetInputFocus(voidptr, u64, i32, u64) i32
fn C.XQueryTree(voidptr, u64, voidptr, voidptr, voidptr, voidptr) i32
fn C.XGetWindowAttributes(voidptr, u64, voidptr) i32
fn C.XInternAtom(voidptr, &char, i32) u64
fn C.XGetWMProtocols(voidptr, u64, voidptr, voidptr) i32
fn C.XGetInputFocus(voidptr, voidptr, voidptr) i32
fn C.XSendEvent(voidptr, u64, i32, i64, voidptr) i32
fn C.XMoveResizeWindow(voidptr, u64, i32, i32, u32, u32) i32
fn C.XRaiseWindow(voidptr, u64) i32
fn C.XCreateSimpleWindow(voidptr, u64, i32, i32, u32, u32, u32, u64, u64) u64
fn C.XSetSelectionOwner(voidptr, u64, u64, u64) i32
fn C.XChangeProperty(voidptr, u64, u64, u64, i32, i32, voidptr, i32) i32
fn C.XDamageQueryExtension(voidptr, voidptr, voidptr) i32
fn C.XDamageQueryVersion(voidptr, voidptr, voidptr) i32
fn C.XDamageCreate(voidptr, u64, i32) u64
fn C.XDamageDestroy(voidptr, u64)
fn C.XDamageSubtract(voidptr, u64, u64, u64)
fn C.XTestQueryExtension(voidptr, voidptr, voidptr, voidptr, voidptr) i32
fn C.XSetWindowBackground(voidptr, u64, u64) i32
fn C.XClearWindow(voidptr, u64) i32
fn C.XPending(voidptr) i32
fn C.XNextEvent(voidptr, voidptr) i32

@[export: 'vinix_wine_host_stop']
pub fn stop_running(signal_number i32) { C.vwh_set_running(0) }
@[export: 'vinix_wine_host_x_error']
pub fn ignore_x_error(display &C.Display, event &C.XErrorEvent) i32 { return 0 }
fn sleep_10ms() { unsafe { delay := C.timespec{tv_sec: 0, tv_nsec: 10000000}; C.nanosleep(&delay, nil) } }
fn monotonic_millis() u64 {
	unsafe { mut now := C.timespec{}; if C.clock_gettime(C.CLOCK_MONOTONIC, &now) != 0 { return 0 }; return u64(now.tv_sec) * 1000 + u64(now.tv_nsec) / 1000000 }
}
fn display_number(name &char) i32 {
	unsafe {
		mut digit := name
		mut number := i32(0)
		for *digit == `:` { digit++ }
		if *digit == 0 { return -1 }
		for *digit != 0 {
			if *digit < `0` || *digit > `9` { return -1 }
			number = number * 10 + i32(*digit - `0`)
			if number > 65535 { return -1 }
			digit++
		}
		return number
	}
}
fn remove_display_files(number i32) {
	unsafe {
		if number < 0 { return }
		mut path := [64]char{}
		C.snprintf(&path[0], sizeof(path), c'/tmp/.X11-unix/X%d', number)
		C.unlink(&path[0])
		C.snprintf(&path[0], sizeof(path), c'/tmp/.X%d-lock', number)
		C.unlink(&path[0])
	}
}
fn remove_surface_files(directory &char) {
	unsafe {
		mut path := [4096]char{}
		names := [&char(c'Xvfb_screen0'), &char(c'Xvfb_screen1'), &char(c'damage')]!
		for index := 0; index < 3; index++ {
			if C.snprintf(&path[0], sizeof(path), c'%s/%s', directory, names[index]) < i32(sizeof(path)) { C.unlink(&path[0]) }
		}
	}
}
fn claim_display_number(number i32) bool {
	unsafe {
		mut path := [64]char{}
		mut address := C.sockaddr_un{}
		C.snprintf(&path[0], sizeof(path), c'/tmp/.X11-unix/X%d', number)
		address.sun_family = u16(C.AF_UNIX)
		C.snprintf(&address.sun_path[0], sizeof(address.sun_path), c'%s', &path[0])
		probe := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
		if probe >= 0 {
			connected := C.connect(probe, voidptr(&address), u32(sizeof(address))) == 0
			C.close(probe)
			if connected { return false }
		}
		remove_display_files(number)
		return true
	}
}
fn claim_display(requested &char, storage &char, size usize) &char {
	unsafe {
		base := display_number(requested)
		if base < 0 { return requested }
		for offset := i32(0); offset < 64; offset++ {
			number := base + offset
			if number > 65535 { break }
			if claim_display_number(number) { C.snprintf(storage, size, c':%d', number); return storage }
		}
		return nil
	}
}
fn spawn_xvfb(name &char, directory &char, geometry &char, game bool, obs bool, shm bool, glx bool) i32 {
	unsafe {
		pid := C.fork()
		if pid != 0 { return pid }
		C.setenv(c'LD_LIBRARY_PATH', c'/usr/lib/vinix-x11-software:/usr/lib:/usr/lib/xorg/modules', 1)
		C.setenv(c'LIBGL_ALWAYS_SOFTWARE', c'1', 1)
		C.setenv(c'LIBGL_DRIVERS_PATH', c'/usr/lib/dri:/usr/lib/xorg/modules/dri', 1)
		C.setenv(c'GALLIUM_DRIVER', c'softpipe', 1)
		xvfb := if (!game || glx) && C.access(c'/usr/bin/Xvfb-glx', C.X_OK) == 0 { &char(c'/usr/bin/Xvfb-glx') } else { &char(c'/usr/bin/Xvfb') }
		if obs {
			C.execl(xvfb, c'Xvfb', name, c'-screen', c'0', geometry, c'-screen', c'1', c'1280x900x24', c'-fbdir', directory, c'-nolisten', c'tcp', c'-noreset', c'-ac', c'+extension', c'GLX', c'+iglx', c'-extension', c'RANDR', voidptr(nil))
		} else if shm {
			C.execl(xvfb, c'Xvfb', name, c'-screen', c'0', geometry, c'-fbdir', directory, c'-nolisten', c'tcp', c'-noreset', c'-ac', voidptr(nil))
		} else if game {
			C.execl(xvfb, c'Xvfb', name, c'-screen', c'0', geometry, c'-fbdir', directory, c'-nolisten', c'tcp', c'-noreset', c'-ac', c'-extension', c'MIT-SHM', voidptr(nil))
		} else {
			C.execl(xvfb, c'Xvfb', name, c'-screen', c'0', geometry, c'-fbdir', directory, c'-nolisten', c'tcp', c'-noreset', c'-ac', c'-extension', c'MIT-SHM', c'+extension', c'GLX', c'+iglx', voidptr(nil))
		}
		C._exit(127)
		return 127
	}
}
fn publish_obs_screen(directory &char) i32 {
	unsafe { mut path := [4096]char{}; if C.snprintf(&path[0], sizeof(path), c'%s/Xvfb_screen1', directory) >= i32(sizeof(path)) { return -1 }; if C.access(&path[0], C.F_OK) != 0 { return -1 }; if C.access(c'/run/vinix-obs-screen', C.F_OK) != 0 { C.unlink(c'/run/vinix-obs-screen') }; if C.symlink(&path[0], c'/run/vinix-obs-screen') != 0 { return -1 }; return 0 }
}
fn unpublish_obs_screen(directory &char) {
	unsafe { mut expected := [4096]char{}; mut current := [4096]char{}; if C.snprintf(&expected[0], sizeof(expected), c'%s/Xvfb_screen1', directory) >= i32(sizeof(expected)) { return }; length := C.readlink(c'/run/vinix-obs-screen', &current[0], sizeof(current) - 1); if length < 0 { return }; current[length] = 0; if C.strcmp(&current[0], &expected[0]) == 0 { C.unlink(c'/run/vinix-obs-screen') } }
}
fn open_display(name &char, pid i32) &C.Display {
	unsafe { for attempt := 0; attempt < 300 && C.vwh_running() != 0; attempt++ { display := C.XOpenDisplay(name); if !is_null(display) { return display }; mut status := i32(0); if C.waitpid(pid, &status, C.WNOHANG) == pid { return nil }; sleep_10ms() }; return nil }
}
fn spawn_wine(name &char, command &char) i32 {
	unsafe { private_group := C.strcmp(command, c'/usr/bin/run-roblox-client') == 0; pid := C.fork(); if pid != 0 { if pid > 0 && private_group { C.setpgid(pid, pid) }; return pid }; if private_group && C.setpgid(0, 0) != 0 { C._exit(127) }; C.setenv(c'DISPLAY', name, 1); C.setenv(c'LIBGL_ALWAYS_SOFTWARE', c'1', 1); C.unsetenv(c'LIBGL_ALWAYS_INDIRECT'); C.setenv(c'GALLIUM_DRIVER', c'llvmpipe', 1); C.setenv(c'WINEDEBUG', c'-all', 0); C.execl(command, command, voidptr(nil)); C._exit(127); return 127 }
}
fn fake_key(display &C.Display, symbol u64, pressed i32) {
	code := C.XKeysymToKeycode(display, symbol)
	if code != 0 { C.XTestFakeKeyEvent(display, u32(code), pressed, 0) }
}
fn hold_game_key(display &C.Display, symbol u64) {
	unsafe {
		code := C.XKeysymToKeycode(display, symbol)
		deadline := monotonic_millis() + 500
		mut free_slot := -1
		if code == 0 { return }
		for i := 0; i < 16; i++ {
			if held_game_keys[i].code == code { held_game_keys[i].release_at_ms = deadline; return }
			if free_slot < 0 && held_game_keys[i].code == 0 { free_slot = i }
		}
		if free_slot < 0 { return }
		held_game_keys[free_slot].code = code
		held_game_keys[free_slot].release_at_ms = deadline
		C.XTestFakeKeyEvent(display, u32(code), 1, 0)
		C.XFlush(display)
	}
}
fn release_expired_game_keys(display &C.Display) {
	unsafe { now := monotonic_millis(); mut released := false; for i := 0; i < 16; i++ { if held_game_keys[i].code == 0 || now < held_game_keys[i].release_at_ms { continue }; C.XTestFakeKeyEvent(display, u32(held_game_keys[i].code), 0, 0); held_game_keys[i].code = 0; released = true }; if released { C.XFlush(display) } }
}
fn tap_key(display &C.Display, symbol u64, shift bool, control bool) {
	unsafe { if hold_game_keys && !shift && !control { hold_game_key(display, symbol); return }; if control { fake_key(display, u64(C.XK_Control_L), 1) }; if shift { fake_key(display, u64(C.XK_Shift_L), 1) }; fake_key(display, symbol, 1); fake_key(display, symbol, 0); if shift { fake_key(display, u64(C.XK_Shift_L), 0) }; if control { fake_key(display, u64(C.XK_Control_L), 0) } }
}
fn type_ascii(display &C.Display, byte u8) {
	unsafe {
		if byte == `\n` || byte == `\r` { tap_key(display, u64(C.XK_Return), false, false); return }
		if byte == `\t` { tap_key(display, u64(C.XK_Tab), false, false); return }
		if byte == `\b` || byte == 0x7f { tap_key(display, u64(C.XK_BackSpace), false, false); return }
		if byte >= 1 && byte <= 26 { tap_key(display, u64(`a` + byte - 1), false, true); return }
		if byte >= `A` && byte <= `Z` { tap_key(display, u64(byte - `A` + `a`), true, false); return }
		shifted := &char(c'!@#$%^&*()_+{}|:"~<>?')
		bases := &char(c'1234567890-=[]\\;\'`,./')
		position := C.strchr(shifted, i32(byte))
		if !is_null(position) { tap_key(display, u64(bases[usize(position) - usize(shifted)]), true, false); return }
		if byte >= 0x20 && byte <= 0x7e { tap_key(display, u64(byte), false, false) }
	}
}
fn keycode_is_modifier(modifiers &C.XModifierKeymap, code i32) bool {
	unsafe { if is_null(modifiers) { return false }; for i := i32(0); i < 8 * modifiers.max_keypermod; i++ { if modifiers.modifiermap[i] == code { return true } }; return false }
}
fn scan_keyboard_map(display &C.Display) {
	unsafe {
		if keyboard_scanned { return }
		keyboard_scanned = true
		mut min_code := i32(0)
		mut max_code := i32(0)
		mut per_code := i32(0)
		C.XDisplayKeycodes(display, voidptr(&min_code), voidptr(&max_code))
		if min_code < 0 || max_code > 255 || min_code > max_code { return }
		keymap := &u64(C.XGetKeyboardMapping(display, u8(min_code), max_code - min_code + 1, voidptr(&per_code)))
		if is_null(keymap) { return }
		if per_code <= 0 { C.XFree(keymap); return }
		modifiers := C.XGetModifierMapping(display)
		for code := min_code; code <= max_code; code++ {
			row := keymap + usize(code - min_code) * usize(per_code)
			mut bound := false
			for column := i32(0); column < per_code; column++ { if row[column] != 0 { bound = true } }
			original_keysyms[code][0] = row[0]
			original_keysyms[code][1] = if per_code > 1 { row[1] } else { u64(0) }
			if !bound && unicode_key_count < 32 && !keycode_is_modifier(modifiers, code) {
				unicode_keys[unicode_key_count].code = u8(code)
				unicode_keys[unicode_key_count].symbol = 0
				unicode_keys[unicode_key_count].tap_number = 0
				unicode_keys[unicode_key_count].tapped_at_ms = 0
				unicode_key_count++
			}
		}
		if !is_null(modifiers) { C.XFreeModifiermap(modifiers) }
		C.XFree(keymap)
	}
}
fn find_original_key(symbol u64, code &u8, shift &i32) bool {
	unsafe { for column := i32(0); column < 2; column++ { for index := 0; index < 256; index++ { if original_keysyms[index][column] == symbol { *code = u8(index); *shift = column; return true } } }; return false }
}
fn wait_until(display &C.Display, deadline u64) {
	unsafe { for monotonic_millis() < deadline { if hold_game_keys { release_expired_game_keys(display) }; sleep_10ms() } }
}
fn borrow_key(display &C.Display, symbol u64) &UnicodeKey {
	unsafe {
		mut oldest := &UnicodeKey(nil)
		for i := i32(0); i < unicode_key_count; i++ {
			key := &unicode_keys[i]
			if key.symbol == symbol { return key }
			if is_null(oldest) || key.tap_number < oldest.tap_number { oldest = key }
		}
		if is_null(oldest) { return nil }
		if oldest.symbol != 0 { wait_until(display, oldest.tapped_at_ms + 500) }
		columns := [symbol, symbol]!
		C.XChangeKeyboardMapping(display, i32(oldest.code), 2, voidptr(&columns[0]), 1)
		oldest.symbol = symbol
		return oldest
	}
}
fn tap_keycode(display &C.Display, code u8, shift i32) {
	if shift != 0 { fake_key(display, u64(C.XK_Shift_L), 1) }
	C.XTestFakeKeyEvent(display, u32(code), 1, 0)
	C.XTestFakeKeyEvent(display, u32(code), 0, 0)
	if shift != 0 { fake_key(display, u64(C.XK_Shift_L), 0) }
}
fn type_code_point(display &C.Display, point u32) {
	unsafe {
		if point < 0xa0 { return }
		symbol := if point <= 0xff { u64(point) } else { u64(u32(0x01000000) | point) }
		scan_keyboard_map(display)
		mut code := u8(0)
		mut shift := i32(0)
		if find_original_key(symbol, &code, &shift) { tap_keycode(display, code, shift); return }
		key := borrow_key(display, symbol)
		if is_null(key) { return }
		tap_keycode(display, key.code, 0)
		C.XSync(display, 0)
		unicode_key_taps++
		key.tap_number = unicode_key_taps
		key.tapped_at_ms = monotonic_millis()
	}
}
fn take_utf8_byte(display &C.Display, byte u8) bool {
	unsafe {
		if utf8_remaining == 0 {
			if byte >= 0xc2 && byte <= 0xdf { utf8_length = 2; utf8_code_point = u32(byte & 0x1f) }
			else if byte >= 0xe0 && byte <= 0xef { utf8_length = 3; utf8_code_point = u32(byte & 0x0f) }
			else if byte >= 0xf0 && byte <= 0xf4 { utf8_length = 4; utf8_code_point = u32(byte & 0x07) }
			else { return true }
			utf8_remaining = utf8_length - 1
			return true
		}
		if (byte & 0xc0) != 0x80 { utf8_remaining = 0; return false }
		utf8_code_point = (utf8_code_point << 6) | u32(byte & 0x3f)
		utf8_remaining--
		if utf8_remaining != 0 { return true }
		point := utf8_code_point
		if (utf8_length == 3 && point < 0x800) || (utf8_length == 4 && (point < 0x10000 || point > 0x10ffff)) || (point >= 0xd800 && point <= 0xdfff) { return true }
		type_code_point(display, point)
		return true
	}
}
fn send_keys(display &C.Display, keys &u8, length usize) {
	unsafe {
		mut index := usize(0)
		for index < length {
			if keys[index] >= 0x80 || utf8_remaining != 0 { if take_utf8_byte(display, keys[index]) { index++ }; continue }
			if keys[index] == 0x1b && index + 2 < length && keys[index + 1] == `[` {
				mut symbol := u64(0)
				match keys[index + 2] {
					`A` { symbol = u64(C.XK_Up) }
					`B` { symbol = u64(C.XK_Down) }
					`C` { symbol = u64(C.XK_Right) }
					`D` { symbol = u64(C.XK_Left) }
					`H` { symbol = u64(C.XK_Home) }
					`F` { symbol = u64(C.XK_End) }
					else {}
				}
				if symbol != 0 { tap_key(display, symbol, false, false); index += 3; continue }
				if keys[index + 2] == `3` && index + 3 < length && keys[index + 3] == `~` { tap_key(display, u64(C.XK_Delete), false, false); index += 4; continue }
			}
			if keys[index] == 0x1b { tap_key(display, u64(C.XK_Escape), false, false) }
			else { type_ascii(display, keys[index]) }
			index++
		}
	}
}
fn focus_pointer_window(display &C.Display) {
	unsafe {
		root := C.DefaultRootWindow(display)
		mut root_return := u64(0)
		mut child_return := u64(0)
		mut root_x := i32(0)
		mut root_y := i32(0)
		mut window_x := i32(0)
		mut window_y := i32(0)
		mut mask := u32(0)
		if C.XQueryPointer(display, root, voidptr(&root_return), voidptr(&child_return), voidptr(&root_x), voidptr(&root_y), voidptr(&window_x), voidptr(&window_y), voidptr(&mask)) != 0 && child_return != 0 { C.XSetInputFocus(display, child_return, C.RevertToPointerRoot, 0) }
	}
}
fn topmost_substantial_child(display &C.Display, parent u64) u64 {
	unsafe {
		mut root_return := u64(0)
		mut parent_return := u64(0)
		mut children := &u64(nil)
		mut count := u32(0)
		mut result := u64(0)
		if C.XQueryTree(display, parent, voidptr(&root_return), voidptr(&parent_return), voidptr(&children), voidptr(&count)) == 0 { return 0 }
		for index := count; index > 0; index-- {
			mut attributes := C.XWindowAttributes{}
			candidate := children[index - 1]
			if C.XGetWindowAttributes(display, candidate, &attributes) != 0 && attributes.map_state == C.IsViewable && attributes.@class == C.InputOutput && attributes.width >= 32 && attributes.height >= 32 && attributes.width <= C.DisplayWidth(display, C.DefaultScreen(display)) * 2 && attributes.height <= C.DisplayHeight(display, C.DefaultScreen(display)) * 2 { result = candidate; break }
		}
		if !is_null(children) { C.XFree(children) }
		return result
	}
}
fn topmost_input_window(display &C.Display, parent u64) u64 {
	candidate := topmost_substantial_child(display, parent)
	if candidate == 0 { return 0 }
	descendant := topmost_input_window(display, candidate)
	return if descendant == 0 { candidate } else { descendant }
}
fn topmost_toplevel(display &C.Display) u64 {
	unsafe {
		root := C.DefaultRootWindow(display)
		mut root_return := u64(0)
		mut parent_return := u64(0)
		mut children := &u64(nil)
		mut count := u32(0)
		mut result := u64(0)
		if C.XQueryTree(display, root, voidptr(&root_return), voidptr(&parent_return), voidptr(&children), voidptr(&count)) == 0 { return 0 }
		for index := count; index > 0; index-- {
			mut attributes := C.XWindowAttributes{}
			candidate := children[index - 1]
			if C.XGetWindowAttributes(display, candidate, &attributes) != 0 && attributes.map_state == C.IsViewable && attributes.@class == C.InputOutput && attributes.override_redirect == 0 && attributes.width >= 32 && attributes.height >= 32 { result = candidate; break }
		}
		if !is_null(children) { C.XFree(children) }
		return result
	}
}
fn takes_focus_itself(display &C.Display, window u64) bool {
	unsafe {
		take_focus := C.XInternAtom(display, c'WM_TAKE_FOCUS', 0)
		mut protocols := &u64(nil)
		mut count := i32(0)
		mut found := false
		if C.XGetWMProtocols(display, window, voidptr(&protocols), voidptr(&count)) == 0 { return false }
		for i := i32(0); i < count; i++ { if protocols[i] == take_focus { found = true } }
		C.XFree(protocols)
		return found
	}
}
fn focus_is_within(display &C.Display, top u64) bool {
	unsafe {
		mut focus := u64(0)
		mut revert := i32(0)
		C.XGetInputFocus(display, voidptr(&focus), voidptr(&revert))
		for focus != 0 && focus != u64(C.PointerRoot) {
			if focus == top { return true }
			mut root_return := u64(0)
			mut parent := u64(0)
			mut children := &u64(nil)
			mut count := u32(0)
			if C.XQueryTree(display, focus, voidptr(&root_return), voidptr(&parent), voidptr(&children), voidptr(&count)) == 0 { return false }
			if !is_null(children) { C.XFree(children) }
			if parent == root_return { return false }
			focus = parent
		}
		return false
	}
}
fn focus_toplevel(display &C.Display, top u64) {
	unsafe {
		mut event := C.XEvent{}
		C.XSetInputFocus(display, top, C.RevertToPointerRoot, 0)
		event.xclient.@type = C.ClientMessage
		event.xclient.window = top
		event.xclient.message_type = C.XInternAtom(display, c'WM_PROTOCOLS', 0)
		event.xclient.format = 32
		event.xclient.data.l[0] = i64(C.XInternAtom(display, c'WM_TAKE_FOCUS', 0))
		event.xclient.data.l[1] = 0
		C.XSendEvent(display, top, 0, 0, &event)
	}
}
fn focus_top_window(display &C.Display) {
	unsafe {
		root := C.DefaultRootWindow(display)
		if !hold_game_keys {
			top := topmost_toplevel(display)
			if top != 0 && takes_focus_itself(display, top) { if !focus_is_within(display, top) { focus_toplevel(display, top) }; return }
		}
		target := if hold_game_keys { topmost_substantial_child(display, root) } else { topmost_input_window(display, root) }
		if target != 0 { C.XSetInputFocus(display, target, C.RevertToPointerRoot, 0) }
	}
}
fn fill_top_window(display &C.Display) {
	unsafe {
		root := C.DefaultRootWindow(display)
		target := topmost_substantial_child(display, root)
		mut attributes := C.XWindowAttributes{}
		width := C.DisplayWidth(display, C.DefaultScreen(display))
		height := C.DisplayHeight(display, C.DefaultScreen(display))
		if target == 0 || C.XGetWindowAttributes(display, target, &attributes) == 0 { return }
		if attributes.x == 0 && attributes.y == 0 && attributes.width == width && attributes.height == height { return }
		C.XMoveResizeWindow(display, target, 0, 0, u32(width), u32(height))
		C.XRaiseWindow(display, target)
		C.XFlush(display)
	}
}
fn paste_clipboard(display &C.Display, text &u8, length usize) {
	unsafe {
		if clipboard_window == 0 {
			clipboard_window = C.XCreateSimpleWindow(display, C.DefaultRootWindow(display), 0, 0, 1, 1, 0, 0, 0)
			clipboard_selection = C.XInternAtom(display, c'CLIPBOARD', 0)
			clipboard_utf8 = C.XInternAtom(display, c'UTF8_STRING', 0)
			clipboard_targets = C.XInternAtom(display, c'TARGETS', 0)
			clipboard_text = C.XInternAtom(display, c'TEXT', 0)
		}
		C.memcpy(&clipboard_data[0], text, length)
		clipboard_length = length
		C.XSetSelectionOwner(display, clipboard_selection, clipboard_window, 0)
		control := C.XKeysymToKeycode(display, u64(C.XK_Control_L))
		v := C.XKeysymToKeycode(display, u64(C.XK_v))
		C.XTestFakeKeyEvent(display, u32(control), 1, 0)
		C.XTestFakeKeyEvent(display, u32(v), 1, 0)
		C.XTestFakeKeyEvent(display, u32(v), 0, 0)
		C.XTestFakeKeyEvent(display, u32(control), 0, 0)
	}
}
fn clipboard_selection_request(display &C.Display, request &C.XSelectionRequestEvent) {
	unsafe {
		mut reply := C.XEvent{}
		property := if request.property == 0 { request.target } else { request.property }
		reply.xselection.@type = C.SelectionNotify
		reply.xselection.display = display
		reply.xselection.requestor = request.requestor
		reply.xselection.selection = request.selection
		reply.xselection.target = request.target
		reply.xselection.time = request.time
		reply.xselection.property = 0
		if request.selection == clipboard_selection && request.owner == clipboard_window {
			if request.target == clipboard_targets {
				targets := [clipboard_targets, clipboard_utf8, clipboard_text, u64(C.XA_STRING)]!
				C.XChangeProperty(display, request.requestor, property, u64(C.XA_ATOM), 32, C.PropModeReplace, voidptr(&targets[0]), 4)
				reply.xselection.property = property
			} else if request.target == clipboard_utf8 || request.target == clipboard_text {
				C.XChangeProperty(display, request.requestor, property, clipboard_utf8, 8, C.PropModeReplace, voidptr(&clipboard_data[0]), i32(clipboard_length))
				reply.xselection.property = property
			} else if request.target == u64(C.XA_STRING) {
				mut latin1 := [65536]u8{}
				mut used := usize(0)
				for at := usize(0); at < clipboard_length; at++ {
					ch := clipboard_data[at]
					if ch < 0x80 { latin1[used] = ch; used++ }
					else if (ch == 0xc2 || ch == 0xc3) && at + 1 < clipboard_length { at++; latin1[used] = u8((ch & 3) << 6) | (clipboard_data[at] & 0x3f); used++ }
					else if (ch & 0xc0) != 0x80 { latin1[used] = `?`; used++ }
				}
				C.XChangeProperty(display, request.requestor, property, u64(C.XA_STRING), 8, C.PropModeReplace, voidptr(&latin1[0]), i32(used))
				reply.xselection.property = property
			}
		}
		C.XSendEvent(display, request.requestor, 0, 0, &reply)
		C.XFlush(display)
	}
}
fn process_event(display &C.Display, event &HostEvent, payload &u8) bool {
	unsafe {
		match event.kind {
			1 { C.XWarpPointer(display, 0, C.DefaultRootWindow(display), 0, 0, 0, 0, event.x, event.y) }
			2 { focus_pointer_window(display); C.XTestFakeButtonEvent(display, 1, 1, 0) }
			3 { C.XTestFakeButtonEvent(display, 1, 0, 0) }
			5 { C.XTestFakeButtonEvent(display, 2, 1, 0) }
			6 { C.XTestFakeButtonEvent(display, 2, 0, 0) }
			7 { C.XTestFakeButtonEvent(display, 3, 1, 0) }
			8 { C.XTestFakeButtonEvent(display, 3, 0, 0) }
			9, 10 { button := if event.kind == 9 { u32(4) } else { u32(5) }; C.XTestFakeButtonEvent(display, button, 1, 0); C.XTestFakeButtonEvent(display, button, 0, 0) }
			4 { focus_top_window(display); send_keys(display, payload, usize(event.length)) }
			11 { focus_top_window(display); paste_clipboard(display, payload, usize(event.length)) }
			else { return false }
		}
		C.XFlush(display)
		return true
	}
}
fn map_damage_counter(directory &char) voidptr {
	unsafe {
		mut path := [4096]char{}
		if C.snprintf(&path[0], sizeof(path), c'%s/damage', directory) >= i32(sizeof(path)) { return nil }
		fd := C.open(&path[0], C.O_RDWR | C.O_CREAT | C.O_TRUNC, u32(0o600))
		if fd < 0 { return nil }
		if C.ftruncate(fd, i64(sizeof(u32))) != 0 { C.close(fd); return nil }
		mapping := C.mmap(nil, sizeof(u32), C.PROT_READ | C.PROT_WRITE, C.MAP_SHARED, fd, 0)
		C.close(fd)
		if mapping == voidptr(usize(-1)) { return nil }
		return mapping
	}
}
fn watch_root_damage(display &C.Display, event_base &i32) u64 {
	unsafe { mut error_base := i32(0); mut major := i32(0); mut minor := i32(0); if C.XDamageQueryExtension(display, event_base, &error_base) == 0 { return 0 }; if C.XDamageQueryVersion(display, &major, &minor) == 0 { return 0 }; return C.XDamageCreate(display, C.DefaultRootWindow(display), C.XDamageReportNonEmpty) }
}
fn stop_child(pid i32) {
	unsafe {
		mut status := i32(0)
		if pid <= 0 || C.waitpid(pid, &status, C.WNOHANG) == pid { return }
		C.kill(pid, C.SIGTERM)
		for attempt := 0; attempt < 100; attempt++ { if C.waitpid(pid, &status, C.WNOHANG) == pid { return }; sleep_10ms() }
		C.kill(pid, C.SIGKILL)
		for C.waitpid(pid, &status, 0) < 0 && C.vwh_errno() == C.EINTR { continue }
	}
}
fn stop_application(initial_pid i32, group i32) {
	unsafe {
		mut pid := initial_pid
		if group <= 1 { stop_child(pid); return }
		C.kill(-group, C.SIGTERM)
		for attempt := 0; attempt < 100; attempt++ {
			mut status := i32(0)
			if pid > 0 && C.waitpid(pid, &status, C.WNOHANG) == pid { pid = -1 }
			if C.kill(-group, 0) != 0 && C.vwh_errno() == C.ESRCH { return }
			sleep_10ms()
		}
		C.kill(-group, C.SIGKILL)
		if pid > 0 { mut status := i32(0); for C.waitpid(pid, &status, 0) < 0 && C.vwh_errno() == C.EINTR { continue } }
	}
}
@[export: 'vinix_wine_host_main']
pub fn host_main(argc i32, argv &&char) i32 {
	unsafe {
		mut input := [65556]u8{}
		mut used := usize(0)
		mut chosen_display := [16]char{}
		mut wine_pid := i32(-1)
		mut application_group := i32(-1)
		mut status := i32(0)
		mut damage_event_base := i32(0)
		mut damage_counter := voidptr(nil)
		mut damage_sequence := u32(0)
		mut fill_surface := false
		mut game_input := false
		mut obs_capture := false
		mut fill_tick := u32(0)
		if argc != 5 && argc != 6 {
			C.fprintf(C.stderr, c'usage: %s DISPLAY FBDIR GEOMETRY COMMAND [--fill|--game-input|--obs]\n', argv[0])
			return 2
		}
		if argc == 6 {
			if C.strcmp(argv[5], c'--fill') == 0 { fill_surface = true }
			else if C.strcmp(argv[5], c'--game-input') == 0 { game_input = true }
			else if C.strcmp(argv[5], c'--obs') == 0 { obs_capture = true }
			else { C.fprintf(C.stderr, c'vinix-wine-host: unknown option: %s\n', argv[5]); return 2 }
		}
		mut display_name := argv[1]
		directory := argv[2]
		geometry := argv[3]
		command := argv[4]
		hold_game_keys = game_input && C.strcmp(command, c'/usr/bin/run-roblox-client') != 0
		C.vwh_install_signals()
		if C.mkdir(directory, u32(0o700)) != 0 && C.vwh_errno() != C.EEXIST { C.perror(c'vinix-wine-host: mkdir'); return 1 }
		display_name = claim_display(display_name, &chosen_display[0], sizeof(chosen_display))
		if is_null(display_name) { C.fprintf(C.stderr, c'vinix-wine-host: no free display near %s\n', argv[1]); C.rmdir(directory); return 1 }
		xvfb_pid := spawn_xvfb(display_name, directory, geometry, game_input, obs_capture,
			C.strcmp(command, c'/usr/bin/run-opengothic') == 0 || C.strcmp(command, c'/usr/bin/run-roblox-client') == 0,
			C.strcmp(command, c'/usr/bin/run-roblox-client') == 0)
		if xvfb_pid < 0 { C.perror(c'vinix-wine-host: fork Xvfb'); C.rmdir(directory); return 1 }
		display := open_display(display_name, xvfb_pid)
		if is_null(display) {
			C.fprintf(C.stderr, c'vinix-wine-host: Xvfb did not become ready\n')
			stop_child(xvfb_pid)
			remove_surface_files(directory)
			C.rmdir(directory)
			return 1
		}
		C.vwh_install_x_error()
		if obs_capture && publish_obs_screen(directory) != 0 {
			C.perror(c'vinix-wine-host: publish OBS capture screen')
			C.XCloseDisplay(display)
			stop_child(xvfb_pid)
			remove_surface_files(directory)
			C.rmdir(directory)
			return 1
		}
		mut xtest_event_base := i32(0)
		mut xtest_error_base := i32(0)
		mut xtest_major := i32(0)
		mut xtest_minor := i32(0)
		if C.XTestQueryExtension(display, &xtest_event_base, &xtest_error_base, &xtest_major, &xtest_minor) == 0 {
			C.fprintf(C.stderr, c'vinix-wine-host: XTEST extension is unavailable\n')
			C.XCloseDisplay(display)
			if obs_capture { unpublish_obs_screen(directory) }
			stop_child(xvfb_pid)
			remove_surface_files(directory)
			C.rmdir(directory)
			return 1
		}
		C.XSetWindowBackground(display, C.DefaultRootWindow(display), 0xf3f4f6)
		C.XClearWindow(display, C.DefaultRootWindow(display))
		C.XFlush(display)
		mut damage := watch_root_damage(display, &damage_event_base)
		if damage != 0 {
			damage_counter = map_damage_counter(directory)
			if is_null(damage_counter) { C.XDamageDestroy(display, damage); damage = 0 }
			else { damage_sequence++; C.vwh_damage_store(damage_counter, damage_sequence) }
		}
		wine_pid = spawn_wine(display_name, command)
		if wine_pid > 1 && C.strcmp(command, c'/usr/bin/run-roblox-client') == 0 { application_group = wine_pid }
		if wine_pid < 0 { C.perror(c'vinix-wine-host: fork Wine'); C.vwh_set_running(0) }
		stdin_flags := C.fcntl(0, C.F_GETFL)
		if stdin_flags >= 0 { C.fcntl(0, C.F_SETFL, stdin_flags | C.O_NONBLOCK) }
		for C.vwh_running() != 0 {
			count := C.read(0, &input[0] + used, sizeof(input) - used)
			if count > 0 { used += usize(count) }
			else if count == 0 { C.vwh_set_running(0) }
			else if C.vwh_errno() != C.EAGAIN && C.vwh_errno() != C.EWOULDBLOCK && C.vwh_errno() != C.EINTR { C.vwh_set_running(0) }
			for used >= sizeof(HostEvent) {
				mut event := HostEvent{}
				C.memcpy(&event, &input[0], sizeof(event))
				if event.magic != u32(0x56574831) || event.length > 65536 || (event.kind != 4 && event.kind != 11 && event.length != 0) { C.vwh_set_running(0); break }
				record_size := sizeof(event) + usize(event.length)
				if used < record_size { break }
				process_event(display, &event, &input[0] + sizeof(event))
				C.memmove(&input[0], &input[0] + record_size, used - record_size)
				used -= record_size
			}
			if used == sizeof(input) { C.vwh_set_running(0) }
			if fill_surface { if fill_tick % 10 == 0 { fill_top_window(display) }; fill_tick++ }
			mut drawn := false
			for C.XPending(display) > 0 {
				mut event := C.XEvent{}
				C.XNextEvent(display, &event)
				if event.@type == C.SelectionRequest { clipboard_selection_request(display, &event.xselectionrequest) }
				if damage != 0 && event.@type == damage_event_base + C.XDamageNotify { drawn = true }
			}
			if drawn { C.XDamageSubtract(display, damage, 0, 0); C.XFlush(display); damage_sequence++; C.vwh_damage_store(damage_counter, damage_sequence) }
			if wine_pid > 0 && C.waitpid(wine_pid, &status, C.WNOHANG) == wine_pid { wine_pid = -1; C.vwh_set_running(0) }
			if hold_game_keys { release_expired_game_keys(display) }
			sleep_10ms()
		}
		stop_application(wine_pid, application_group)
		if !is_null(damage_counter) { C.munmap(damage_counter, sizeof(u32)) }
		C.XCloseDisplay(display)
		if obs_capture { unpublish_obs_screen(directory) }
		stop_child(xvfb_pid)
		remove_display_files(display_number(display_name))
		remove_surface_files(directory)
		C.rmdir(directory)
		return 0
	}
}
