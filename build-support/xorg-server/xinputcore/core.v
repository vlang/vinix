// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license in LICENSE.
// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module xinputcore

#include "xinput_abi.h"
struct C.FILE {}
@[c_extern] __global C.stderr &C.FILE
fn C.fprintf(&C.FILE, &char, ...voidptr) i32
fn C.read(i32, voidptr, usize) i64
fn C.close(i32) i32
fn C.vxi_open_display() voidptr
fn C.vxi_close_display(voidptr)
fn C.vxi_xtest_available(voidptr) i32
fn C.vxi_handlers()
fn C.vxi_open_device(&char) i32
fn C.vxi_raw_keyboard(i32) i32
fn C.vxi_restore_keyboard(i32)
fn C.vxi_delay()
fn C.vxi_error() &char
fn C.vxi_error_text(voidptr, i32, &char, i32)
fn C.vxi_key(voidptr, u64, i32)
fn C.vxi_button(voidptr, u32, i32)
fn C.vxi_pointer_child(voidptr) u64
fn C.vxi_focus(voidptr, u64)
fn C.vxi_dimensions(voidptr, &i32, &i32)
fn C.vxi_warp(voidptr, i32, i32)
fn C.vxi_flush(voidptr)
@[c: '__atomic_load_n'] fn C.vxi_load(&i32, i32) i32
@[c: '__atomic_store_n'] fn C.vxi_store(&i32, i32, i32)

__global (
 running i32 = 1
 keyboard_fd i32 = -1
 escape_bytes [16]u8
 escape_length usize
 escape_idle_polls u32
)
struct PointerPacket {
mut:
 x i32
 y i32
 max_x i32
 max_y i32
 buttons u32
 pressed u32
 released u32
 scroll i32
}

@[export: 'vxi_stop']
pub fn stop(signal_number i32) { unsafe { C.vxi_store(&running, 0, 0) } }
@[export: 'vxi_report_error']
pub fn report_error(display voidptr, code i32, request i32, minor i32) i32 {
 unsafe {
  mut message := [128]char{}
  C.vxi_error_text(display, code, &message[0], 128)
  C.fprintf(C.stderr, c'vinix-xinput: X11 error: %s (request %u.%u)\n', &message[0], u32(request), u32(minor))
  return 0
 }
}
fn tap_key(display voidptr, symbol u64, shift bool, control bool) {
 if control { C.vxi_key(display, 0xffe3, 1) }
 if shift { C.vxi_key(display, 0xffe1, 1) }
 C.vxi_key(display, symbol, 1)
 C.vxi_key(display, symbol, 0)
 if shift { C.vxi_key(display, 0xffe1, 0) }
 if control { C.vxi_key(display, 0xffe3, 0) }
}
pub fn type_ascii(display voidptr, byte u8) {
 unsafe {
  if byte == 0 { tap_key(display, 0, true, false); return }
  if byte >= 1 && byte <= 26 { tap_key(display, u64(`a` + byte - 1), false, true); return }
  match byte {
   10, 13 { tap_key(display, 0xff0d, false, false); return }
   9 { tap_key(display, 0xff09, false, false); return }
   8, 127 { tap_key(display, 0xff08, false, false); return }
   else {}
  }
  if byte >= `A` && byte <= `Z` { tap_key(display, u64(byte - `A` + `a`), true, false); return }
  shifted := &char(c'!@#$%^&*()_+{}|:"~<>?')
  bases := &char(c'1234567890-=[]\\;\'`,./')
  for i := usize(0); shifted[i] != 0; i++ {
   if shifted[i] == char(byte) { tap_key(display, u64(u8(bases[i])), true, false); return }
  }
  if byte >= 0x20 && byte <= 0x7e { tap_key(display, u64(byte), false, false) }
 }
}
fn clear_escape() { unsafe { escape_length = 0; escape_idle_polls = 0 } }
fn flush_escape_as_keys(display voidptr) {
 unsafe {
  tap_key(display, 0xff1b, false, false)
  for i := usize(1); i < escape_length; i++ { type_ascii(display, escape_bytes[i]) }
  clear_escape()
 }
}
fn finish_escape(display voidptr) i32 {
 unsafe {
  if escape_length < 2 { return 0 }
  if escape_bytes[1] != `[` && escape_bytes[1] != `O` { return -1 }
  if escape_length < 3 { return 0 }
  mut symbol := u64(0)
  if escape_bytes[1] == `O` {
   symbol = match escape_bytes[2] {
    `A` { u64(0xff52) } `B` { u64(0xff54) } `C` { u64(0xff53) } `D` { u64(0xff51) }
    `H` { u64(0xff50) } `F` { u64(0xff57) }
    `P` { u64(0xffbe) } `Q` { u64(0xffbf) } `R` { u64(0xffc0) } `S` { u64(0xffc1) }
    else { u64(0) }
   }
   if symbol == 0 { return -1 }
   tap_key(display, symbol, false, false); clear_escape(); return 1
  }
  symbol = match escape_bytes[2] {
   `A` { u64(0xff52) } `B` { u64(0xff54) } `C` { u64(0xff53) } `D` { u64(0xff51) }
   `H` { u64(0xff50) } `F` { u64(0xff57) } else { u64(0) }
  }
  if symbol != 0 { tap_key(display, symbol, false, false); clear_escape(); return 1 }
  if escape_bytes[2] < `0` || escape_bytes[2] > `9` { return -1 }
  if escape_bytes[escape_length - 1] != `~` { return if escape_length < 16 { 0 } else { -1 } }
  if escape_length == 4 {
   symbol = match escape_bytes[2] {
    `1`, `7` { u64(0xff50) } `2` { u64(0xff63) } `3` { u64(0xffff) }
    `4`, `8` { u64(0xff57) } `5` { u64(0xff55) } `6` { u64(0xff56) }
    else { u64(0) }
   }
  }
  if symbol == 0 { return -1 }
  tap_key(display, symbol, false, false); clear_escape(); return 1
 }
}
pub fn keyboard_byte(display voidptr, byte u8) {
 unsafe {
  if escape_length == 0 {
   if byte == 0x1b { escape_bytes[0] = byte; escape_length = 1; escape_idle_polls = 0 }
   else { type_ascii(display, byte) }
   return
  }
  if escape_length == 16 { flush_escape_as_keys(display); keyboard_byte(display, byte); return }
  escape_bytes[escape_length] = byte; escape_length++; escape_idle_polls = 0
  if finish_escape(display) < 0 { flush_escape_as_keys(display) }
 }
}
pub fn pump_keyboard(display voidptr) i32 {
 unsafe {
  mut bytes := [64]u8{}
  mut sent := i32(0)
  for {
   count := C.read(keyboard_fd, &bytes[0], 64)
   if count <= 0 { break }
   sent = 1
   for i := i64(0); i < count; i++ { keyboard_byte(display, bytes[i]) }
   if count < 64 { break }
  }
  if sent == 0 && escape_length != 0 {
   escape_idle_polls++
   if escape_idle_polls >= 2 { flush_escape_as_keys(display); sent = 1 }
  }
  return sent
 }
}
fn fake_button(display voidptr, button u32, pressed bool) {
 if button == 1 && pressed {
  child := C.vxi_pointer_child(display)
  if child != 0 { C.vxi_focus(display, child) }
 }
 C.vxi_button(display, button, i32(pressed))
}
pub fn pump_pointer(display voidptr, fd i32, sent_buttons &u32, last_x &i32, last_y &i32) i32 {
 unsafe {
  mut packet := PointerPacket{}
  if C.read(fd, &packet, sizeof(PointerPacket)) != i64(sizeof(PointerPacket)) || packet.max_x <= 0 || packet.max_y <= 0 { return 0 }
  mut width := i32(0); mut height := i32(0)
  C.vxi_dimensions(display, &width, &height)
  mut x := i32(i64(packet.x) * i64(width - 1) / i64(packet.max_x))
  mut y := i32(i64(packet.y) * i64(height - 1) / i64(packet.max_y))
  if x < 0 { x = 0 }; if y < 0 { y = 0 }
  if x >= width { x = width - 1 }; if y >= height { y = height - 1 }
  mut sent := i32(0)
  if x != *last_x || y != *last_y { C.vxi_warp(display, x, y); *last_x = x; *last_y = y; sent = 1 }
  buttons := [u32(1), u32(3), u32(2)]!
  for i := u32(0); i < 3; i++ {
   bit := u32(1) << i
   down := (packet.buttons & bit) != 0
   was_down := (*sent_buttons & bit) != 0
   press := (packet.pressed & bit) != 0
   release := (packet.released & bit) != 0
   if press && release {
    if down { if was_down { fake_button(display, buttons[i], false) }; fake_button(display, buttons[i], true) }
    else { if !was_down { fake_button(display, buttons[i], true) }; fake_button(display, buttons[i], false) }
    sent = 1
   } else if down != was_down { fake_button(display, buttons[i], down); sent = 1 }
   if down { *sent_buttons |= bit } else { *sent_buttons &= ~bit }
  }
  if packet.scroll != 0 {
   wheel := if packet.scroll > 0 { u32(4) } else { u32(5) }
   mut steps := if packet.scroll > 0 { packet.scroll } else { -packet.scroll }
   if steps > 32 { steps = 32 }
   for steps > 0 { fake_button(display, wheel, true); fake_button(display, wheel, false); steps-- }
   sent = 1
  }
  return sent
 }
}
@[export: 'vxi_main']
pub fn bridge_main() i32 {
 unsafe {
  C.vxi_handlers()
  mut display := voidptr(0)
  for attempts := i32(0); attempts < 200 && C.vxi_load(&running, 0) != 0; attempts++ {
   display = C.vxi_open_display()
   if display != nil { break }
   C.vxi_delay()
  }
  if display == nil { C.fprintf(C.stderr, c'vinix-xinput: cannot open X display\n'); return 1 }
  if C.vxi_xtest_available(display) == 0 { C.fprintf(C.stderr, c'vinix-xinput: XTEST extension is unavailable\n'); C.vxi_close_display(display); return 1 }
  pointer_fd := C.vxi_open_device(c'/dev/pointer')
  if pointer_fd < 0 { C.fprintf(C.stderr, c'vinix-xinput: /dev/pointer is unavailable: %s\n', C.vxi_error()) }
  keyboard_fd = C.vxi_open_device(c'/dev/console')
  available := C.vxi_raw_keyboard(keyboard_fd) != 0
  if !available { C.fprintf(C.stderr, c'vinix-xinput: console keyboard is unavailable\n') }
  C.fprintf(C.stderr, c'vinix-xinput: pointer and keyboard bridge ready\n')
  mut sent_buttons := u32(0); mut last_x := i32(-1); mut last_y := i32(-1)
  for C.vxi_load(&running, 0) != 0 {
   mut sent := if available { pump_keyboard(display) } else { i32(0) }
   if pointer_fd >= 0 { sent |= pump_pointer(display, pointer_fd, &sent_buttons, &last_x, &last_y) }
   if sent != 0 { C.vxi_flush(display) }
   C.vxi_delay()
  }
  C.vxi_restore_keyboard(keyboard_fd)
  if keyboard_fd >= 0 { C.close(keyboard_fd) }
  keyboard_fd = -1
  if pointer_fd >= 0 { C.close(pointer_fd) }
  C.vxi_close_display(display)
  C.fprintf(C.stderr, c'vinix-xinput: stopped\n')
  return 0
 }
}
