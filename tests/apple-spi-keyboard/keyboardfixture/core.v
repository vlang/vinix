// SPDX-License-Identifier: GPL-2.0-or-later
// Independent original packet, input and PIO assertions; native V fixture.
@[translated]
@[has_globals]
module keyboardfixture

#include "keyboard-native-abi.h"

struct C.touchpad {
mut:
	message        [536]u8
	used           usize
	total          usize
	fragment_at    u64
	report_at      u64
	mode_at        u64
	reports        u64
	native_reports u64
	bad_packets    u64
	resets         u64
	mode_attempts  u32
	mode_errors    u32
	next_id        u8
	requested      i32
	mode_enabled   i32
	present        i32
	tracking       i32
	previous_x     i32
	previous_y     i32
	x              i32
	y              i32
	buttons        u32
	pressed        u32
	released       u32
}

struct C.key_bytes {
mut:
	// Long enough for the longest sequence a key can produce, which is the
	//     *report that Cmd has been let go rather than anything on a keycap.
	data [16]u8
	len  usize
}

struct C.decoder {
mut:
	keys       [6]u8
	modifiers  u8
	@fn        u8
	caps       u8
	repeat_key u8
	// Whether a chord was sent while Cmd was down. The desktop's window
	//     *switcher is drawn for as long as Cmd is held, so unlike every other
	//     *modifier this one's release has to be reported -- but only to someone
	//     *who asked, which is what pressing Cmd-Tab counts as.
	gui_chorded     u8
	alt_tab_chorded u8
	repeat_at       u64
	message         [20]u8
	message_used    usize
	fragment_at     u64
	reports         u64
}

struct C.io_ops {
mut:
	read32   fn (voidptr, u64) u32
	write32  fn (voidptr, u64, u32)
	now_us   fn (voidptr) u64
	delay_us fn (voidptr, u32)
}

struct C.spi_keyboard {
mut:
	io         C.io_ops
	cookie     voidptr
	spi        u64
	enable     u64
	ready      u64
	enable_low i32
	ready_low  i32
	active     i32
	errors     u32
	// What start_keyboard was given, so the transport can be brought back
	//     *without the device-tree work being done again.
	input_hz   u32
	maximum_hz u32
	// When to try that, or 0 for not scheduled.
	revive_at     u64
	next_poll     u64
	next_transfer u64
	decoder       C.decoder
	touchpad      C.touchpad
}

fn C.vinix_apple_spi_keyboard_poll(out &u8, capacity usize, application_cursor i32) i32
fn C.vinix_apple_spi_keyboard_reports() u64
fn C.vinix_apple_spi_keyboard_caps_lock() i32
fn C.vinix_apple_spi_touchpad_reports() u64
fn C.vinix_apple_spi_touchpad_read(out &i32) i32
fn C.vinix_spi_core_read_le16(p &u8) u16
fn C.vinix_spi_core_crc16(p &u8, n usize) u16
fn C.vinix_spi_core_has_key(keys &u8, key u8) i32
fn C.vinix_spi_core_cancel_repeat(d &C.decoder)
fn C.vinix_spi_core_reset_input(d &C.decoder)
fn C.vinix_spi_core_sequence(out &C.key_bytes, s &char)
fn C.vinix_spi_core_decimal(out &C.key_bytes, value u32)
fn C.vinix_spi_core_csi_u(out &C.key_bytes, codepoint u32, modifiers u32)
fn C.vinix_spi_core_modified_arrow(out &C.key_bytes, final i8, modifiers u32)
fn C.vinix_spi_core_encode_key(key u8, modifiers u8, caps i32, fn_ i32, application_cursor i32) C.key_bytes
fn C.vinix_spi_core_append_key(out &u8, capacity usize, used &usize, key C.key_bytes) i32
fn C.vinix_spi_core_accept_report(d &C.decoder, report &u8, now u64, app i32, out &u8, capacity usize) usize
fn C.vinix_spi_core_decode_packet(d &C.decoder, packet &u8, length usize, now u64, app i32, out &u8, capacity usize) usize
fn C.vinix_spi_core_repeat_key(d &C.decoder, now u64, app i32, out &u8, capacity usize) usize
fn C.vinix_spi_core_reg_read(k &C.spi_keyboard, offset u32) u32
fn C.vinix_spi_core_reg_write(k &C.spi_keyboard, offset u32, value u32)
fn C.vinix_spi_core_set_enable(k &C.spi_keyboard, enabled i32)
fn C.vinix_spi_core_start_keyboard(k &C.spi_keyboard, input_hz u32, maximum_hz u32) i32
fn C.vinix_spi_core_transfer_bytes(k &C.spi_keyboard, output &u8, input &u8, length usize) i32
fn C.vinix_spi_core_end_transfer(k &C.spi_keyboard, ok i32)
fn C.vinix_spi_core_read_packet(k &C.spi_keyboard, packet &u8) i32
fn C.vinix_spi_core_enable_touchpad(k &C.spi_keyboard, now u64)
fn C.vinix_spi_core_boot_packet(p &u8) i32
fn C.vinix_spi_core_packet_envelope_valid(p &u8) i32
fn C.vinix_spi_core_read_error(k &C.spi_keyboard) i32
fn C.vinix_spi_core_poll_keyboard(k &C.spi_keyboard, out &u8, capacity usize, application_cursor i32) i32
fn C.vinix_spi_core_kernel_read32(cookie voidptr, address u64) u32
fn C.vinix_spi_core_kernel_write32(cookie voidptr, address u64, value u32)
fn C.vinix_spi_core_kernel_now_us(cookie voidptr) u64
fn C.vinix_spi_core_kernel_delay_us(cookie voidptr, us u32)
fn C.vinix_spi_core_tp_le16(p &u8) u16
fn C.vinix_spi_core_tp_s16(p &u8) i32
fn C.vinix_spi_core_tp_s8(n u8) i32
fn C.vinix_spi_core_tp_put16(p &u8, n u16)
fn C.vinix_spi_core_tp_crc(p &u8, n usize) u16
fn C.vinix_spi_core_tp_buttons(t &C.touchpad, buttons u32)
fn C.vinix_spi_core_tp_discontinuity(t &C.touchpad)
fn C.vinix_spi_core_tp_bad(t &C.touchpad)
fn C.vinix_spi_core_tp_restart(t &C.touchpad, now u64)
fn C.vinix_spi_core_tp_init(t &C.touchpad, first_poll u64)
fn C.vinix_spi_core_tp_tick(t &C.touchpad, now u64)
fn C.vinix_spi_core_tp_mode_due(t &C.touchpad, now u64) i32
fn C.vinix_spi_core_tp_mode_packet(t &C.touchpad, p &u8, now u64)
fn C.vinix_spi_core_tp_clamp(value i32, maximum i32) i32
fn C.vinix_spi_core_tp_move(t &C.touchpad, dx i32, dy i32, gain i32)
fn C.vinix_spi_core_tp_report(t &C.touchpad, r &u8, n usize, now u64) i32
fn C.vinix_spi_core_tp_decode(t &C.touchpad, p &u8, size usize, now u64)
fn C.vinix_spi_core_tp_snapshot(t &C.touchpad, out &i32) i32

fn C.printf(&char, ...) i32
fn C.fflush(voidptr) i32
fn C.abort()
fn C.memset(voidptr, i32, usize) voidptr
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.vsf_keyboard_fake_read(voidptr, u64) u32
fn C.vsf_keyboard_fake_write(voidptr, u64, u32)
fn C.vsf_keyboard_fake_now(voidptr) u64
fn C.vsf_keyboard_fake_delay(voidptr, u32)
fn expect(ok bool, line i32, expression &char) {
 if !ok { unsafe { C.printf(c'SPI FIXTURE FAIL line %d: %s\n', line, expression); C.fflush(nil); C.abort() } }
}
__global tests u32

pub fn le16(p &u8, v u16) {
	unsafe {
	p[0] = u8(v)
	p[1] = u8((i32(v) >> 8))

	}
}

pub fn seal_packet(p &u8) {
	unsafe {
	le16(p + 254, C.vinix_spi_core_crc16(p, 254))

	}
}

pub fn message(m &u8, mods u8, fn_ u8, keys &u8) {
	unsafe {
	C.memset(voidptr(m), 0, 20)
	m[0] = 16
	m[1] = 1
	m[6] = 10
	m[8] = 1
	m[9] = mods
	m[17] = fn_
	C.memcpy(voidptr(m + 11), voidptr(keys), 6)
	le16(m + 18, C.vinix_spi_core_crc16(m, 18))

	}
}

pub fn fragment(p &u8, m &u8, offset u32, n u32) {
	unsafe {
	C.memset(voidptr(p), 0, 256)
	p[0] = 32
	p[1] = 1
	le16(p + 2, u16(offset))
	le16(p + 4, u16((20 - offset - n)))
	le16(p + 6, u16(n))
	C.memcpy(voidptr(p + 8), voidptr(m + offset), n)
	seal_packet(p)

	}
}

pub fn packet(p &u8, mods u8, fn_ u8, keys &u8) {
	unsafe {
	m := [20]u8{}
	message(&m[0], mods, fn_, keys)
	fragment(p,  &m[0] , 0, 20)

	}
}

pub fn feed(d &C.decoder, now u64, mods u8, fn_ u8, keys &u8, out &u8) usize {
	unsafe {
	p := [256]u8{}
	packet(&p[0], mods, fn_, keys)
	return usize(C.vinix_spi_core_decode_packet(d,  &p[0] , 256, now, 0, out, 128))

	}
}

pub fn single(d &C.decoder, now u64, mods u8, fn_ u8, key u8, out &u8) usize {
	unsafe {
	keys := [key, u8(0), u8(0), u8(0), u8(0), u8(0)]!

	return usize(feed(d, now, mods, fn_,  &keys[0] , out))

	}
}

pub fn expect_bytes(b C.key_bytes, bytes &u8, n usize) {
	unsafe {
	expect(!!(b.len == n), 49, c'b.len == n')
	expect(!!(C.memcmp(&b.data[0], voidptr(bytes), n) == 0), 49, c'memcmp(b.data, bytes, n) == 0')

	}
}

pub fn test_crc() {
	unsafe {
	expect(!!(C.vinix_spi_core_crc16(&u8(c'123456789'), 9) == 47933), 53, c'crc16((const uint8_t *)\"123456789\", 9) == 0xbb3d')
	expect(!!(C.vinix_spi_core_crc16(&u8(c''), 0) == 0), 54, c'crc16((const uint8_t *)\"\", 0) == 0')
	p := [256]u8{}
	keys := [u8(4), u8(0), u8(0), u8(0), u8(0), u8(0)]!

	packet(&p[0], 0, 0,  &keys[0] )
	expect(!!(C.vinix_spi_core_crc16( &p[0] , 256) == 0 && C.vinix_spi_core_crc16( &p[0]  + 8, 20) == 0), 56, c'crc16(p, 256) == 0 && crc16(p + 8, 20) == 0')
	expect(!!(C.vinix_spi_core_read_le16( &p[0]  + 6) == 20 && C.vinix_spi_core_read_le16( &p[0]  + 14) == 10), 57, c'read_le16(p + 6) == 20 && read_le16(p + 14) == 10')
	p[127] ^= 1
	expect(!!(C.vinix_spi_core_crc16( &p[0] , 256) != 0), 58, c'crc16(p, 256) != 0')

	}
}

pub fn test_press_release_duplicate() {
	unsafe {
	d := C.decoder{}

	out := [128]u8{}
	expect(!!(single(&d, 100, 0, 0, 4, &out[0]) == 1 && out[0] == `a`), 63, c"single(&d, 100, 0, 0, 4, out) == 1 && out[0] == 'a'")
	repeat := d.repeat_at
	expect(!!(single(&d, 200, 0, 0, 4, &out[0]) == 0 && d.repeat_at == repeat), 65, c'single(&d, 200, 0, 0, 4, out) == 0 && d.repeat_at == repeat')
	expect(!!(single(&d, 300, 0, 0, 0, &out[0]) == 0 && d.repeat_key == 0), 66, c'single(&d, 300, 0, 0, 0, out) == 0 && d.repeat_key == 0')
	expect(!!(single(&d, 400, 0, 0, 4, &out[0]) == 1 && out[0] == `a`), 67, c"single(&d, 400, 0, 0, 4, out) == 1 && out[0] == 'a'")

	}
}

pub fn test_six_keys_reordering() {
	unsafe {
	d := C.decoder{}

	out := [128]u8{}
	a := [u8(4), u8(5), u8(6), u8(7), u8(8), u8(9)]!

	b := [u8(9), u8(7), u8(8), u8(5), u8(4), u8(6)]!

	expect(!!(feed(&d, 1, 0, 0,  &a[0] , &out[0]) == 6 && !C.memcmp(voidptr( &out[0] ), voidptr(c'abcdef'), 6)), 73, c'feed(&d, 1, 0, 0, a, out) == 6 && !memcmp(out, \"abcdef\", 6)')
	expect(!!(feed(&d, 2, 0, 0,  &b[0] , &out[0]) == 0), 74, c'feed(&d, 2, 0, 0, b, out) == 0')
	C.memset(voidptr(&d), 0, sizeof(d))
	duplicates := [u8(4), u8(4), u8(4), u8(5), u8(5), u8(4)]!

	expect(!!(feed(&d, 3, 0, 0,  &duplicates[0] , &out[0]) == 2 && !C.memcmp(voidptr( &out[0] ), voidptr(c'ab'), 2)), 77, c'feed(&d, 3, 0, 0, duplicates, out) == 2 && !memcmp(out, \"ab\", 2)')

	}
}

pub fn test_modifiers_and_caps() {
	unsafe {
	d := C.decoder{}

	out := [128]u8{}
	expect(!!(single(&d, 1, 34, 0, 4, &out[0]) == 1 && out[0] == `A`), 82, c"single(&d, 1, 0x22, 0, 4, out) == 1 && out[0] == 'A'")
	expect(!!(single(&d, 2, 32, 0, 0, &out[0]) == 0), 83, c'single(&d, 2, 0x20, 0, 0, out) == 0')
	// release only left Shift

	expect(!!(single(&d, 3, 32, 0, 5, &out[0]) == 1 && out[0] == `B`), 84, c"single(&d, 3, 0x20, 0, 5, out) == 1 && out[0] == 'B'")
	single(&d, 4, 0, 0, 0, &out[0])
	expect(!!(single(&d, 5, 0, 0, 57, &out[0]) == 0 && d.caps), 86, c'single(&d, 5, 0, 0, 57, out) == 0 && d.caps')
	expect(!!(single(&d, 6, 0, 0, 57, &out[0]) == 0 && d.caps), 87, c'single(&d, 6, 0, 0, 57, out) == 0 && d.caps')
	single(&d, 7, 0, 0, 0, &out[0])
	expect(!!(single(&d, 8, 0, 0, 4, &out[0]) == 1 && out[0] == `A`), 89, c"single(&d, 8, 0, 0, 4, out) == 1 && out[0] == 'A'")
	single(&d, 9, 0, 0, 0, &out[0])
	expect(!!(single(&d, 10, 2, 0, 4, &out[0]) == 1 && out[0] == `a`), 91, c"single(&d, 10, 2, 0, 4, out) == 1 && out[0] == 'a'")
	single(&d, 11, 0, 0, 0, &out[0])
	expect(!!(single(&d, 12, 0, 0, 30, &out[0]) == 1 && out[0] == `1`), 93, c"single(&d, 12, 0, 0, 30, out) == 1 && out[0] == '1'")
	single(&d, 13, 0, 0, 0, &out[0])
	expect(!!(single(&d, 14, 0, 0, 57, &out[0]) == 0 && !d.caps), 95, c'single(&d, 14, 0, 0, 57, out) == 0 && !d.caps')

	}
}

pub fn test_ascii_controls() {
	unsafe {
	for key := u32(4); key <= 29; key++ {
		b := C.vinix_spi_core_encode_key(u8(key), 16, 0, 0, 0)
		expect(!!(b.len == 1 && b.data[0] == key - 3), 101, c'b.len == 1 && b.data[0] == key - 3')
	}
	b := C.vinix_spi_core_encode_key(6, 17, 0, 0, 0)
	expect(!!(b.len == 1 && b.data[0] == 3), 104, c'b.len == 1 && b.data[0] == 3')
	// both Ctrl keys

	b = C.vinix_spi_core_encode_key(4, 64, 0, 0, 0)
	expect_bytes(b, &u8(c'\033a'), 2)
	b = C.vinix_spi_core_encode_key(44, 1, 0, 0, 0)
	expect(!!(b.len == 1 && b.data[0] == 0), 106, c'b.len == 1 && b.data[0] == 0')
	b = C.vinix_spi_core_encode_key(31, 1, 0, 0, 0)
	expect(!!(b.len == 1 && b.data[0] == 0), 107, c'b.len == 1 && b.data[0] == 0')
	b = C.vinix_spi_core_encode_key(56, 3, 0, 0, 0)
	expect(!!(b.len == 1 && b.data[0] == 127), 108, c'b.len == 1 && b.data[0] == 127')
	b = C.vinix_spi_core_encode_key(40, 0, 0, 0, 0)
	expect(!!(b.len == 1 && b.data[0] == `\r`), 109, c"b.len == 1 && b.data[0] == '\\r'")
	b = C.vinix_spi_core_encode_key(42, 0, 0, 0, 0)
	expect(!!(b.len == 1 && b.data[0] == `\b`), 110, c"b.len == 1 && b.data[0] == '\\b'")
	b = C.vinix_spi_core_encode_key(43, 2, 0, 0, 0)
	expect_bytes(b, &u8(c'\033[Z'), 3)
	for i := u32(0); i < 10; i++ {
		b = C.vinix_spi_core_encode_key(u8((30 + i)), 2, 1, 0, 0)
		expect(!!(b.len == 1 && b.data[0] == u8(c'!@#$%^&*()'[i])), 114, c'b.len == 1 && b.data[0] == (uint8_t)\"!@#$%^&*()\"[i]')
	}
	// The ISO key is Â§ and Â±, after Option's escape; Cmd drops it.

	expect_bytes(C.vinix_spi_core_encode_key(100, 0, 0, 0, 0), &u8(c'\302\247'), 2)
	expect_bytes(C.vinix_spi_core_encode_key(100, 2, 1, 0, 0), &u8(c'\302\261'), 2)
	expect_bytes(C.vinix_spi_core_encode_key(100, 64, 0, 0, 0), &u8(c'\033\302\247'), 3)
	expect(!!(C.vinix_spi_core_encode_key(100, 8, 0, 0, 0).len == 0), 120, c'encode_key(100, 0x08, 0, 0, 0).len == 0')
	expect_bytes(C.vinix_spi_core_encode_key(49, 0, 0, 0, 0), &u8(c'\\'), 1)

	}
}

pub fn test_navigation_fn_and_function_keys() {
	unsafe {
	expect_bytes(C.vinix_spi_core_encode_key(82, 0, 0, 0, 0), &u8(c'\033[A'), 3)
	expect_bytes(C.vinix_spi_core_encode_key(82, 0, 0, 0, 1), &u8(c'\033OA'), 3)
	expect_bytes(C.vinix_spi_core_encode_key(80, 0, 0, 1, 0), &u8(c'\033[H'), 3)
	expect_bytes(C.vinix_spi_core_encode_key(79, 0, 0, 1, 1), &u8(c'\033OF'), 3)
	expect_bytes(C.vinix_spi_core_encode_key(81, 0, 0, 1, 0), &u8(c'\033[6~'), 4)
	expect_bytes(C.vinix_spi_core_encode_key(82, 0, 0, 1, 0), &u8(c'\033[5~'), 4)
	expect_bytes(C.vinix_spi_core_encode_key(42, 0, 0, 1, 0), &u8(c'\033[3~'), 4)
	expect_bytes(C.vinix_spi_core_encode_key(58, 0, 0, 0, 0), &u8(c'\033OP'), 3)
	expect_bytes(C.vinix_spi_core_encode_key(69, 0, 0, 0, 0), &u8(c'\033[24~'), 5)
	expect_bytes(C.vinix_spi_core_encode_key(69, 4, 0, 0, 0), &u8(c'\033\033[24~'), 6)
	expect(!!(C.vinix_spi_core_encode_key(255, 0, 0, 0, 0).len == 0), 135, c'encode_key(255, 0, 0, 0, 0).len == 0')

	}
}

// Cmd-Tab, and the release of Cmd that closes the window switcher. Neither is
// *a byte a terminal has ever produced, so the whole of what the desktop sees
// *is checked here rather than only that something came out.

pub fn test_command_tab() {
	unsafe {
	d := C.decoder{}

	out := [128]u8{}
	expect_bytes(C.vinix_spi_core_encode_key(43, 8, 0, 0, 0), &u8(c'\033[9;9u'), 6)
	expect_bytes(C.vinix_spi_core_encode_key(43, 128, 0, 0, 0), &u8(c'\033[9;9u'), 6)
	expect_bytes(C.vinix_spi_core_encode_key(43, 10, 0, 0, 0), &u8(c'\033[9;10u'), 7)
	// Without Cmd it is still a tab, and Shift-Tab still back-tab.

	expect_bytes(C.vinix_spi_core_encode_key(43, 0, 0, 0, 0), &u8(c'\t'), 1)
	expect_bytes(C.vinix_spi_core_encode_key(43, 2, 0, 0, 0), &u8(c'\033[Z'), 3)
	// Cmd down alone says nothing; each Tab is one chord; letting Cmd go ends
	//     *it once, and a Cmd that was never chorded with ends nothing.

	expect(!!(single(&d, 100, 8, 0, 0, &out[0]) == 0), 152, c'single(&d, 100, 0x08, 0, 0, out) == 0')
	expect(!!(single(&d, 200, 8, 0, 43, &out[0]) == 6 && !C.memcmp(voidptr( &out[0] ), voidptr(c'\033[9;9u'), 6)), 153, c'single(&d, 200, 0x08, 0, 43, out) == 6 && !memcmp(out, \"\\033[9;9u\", 6)')
	expect(!!(single(&d, 300, 8, 0, 0, &out[0]) == 0), 154, c'single(&d, 300, 0x08, 0, 0, out) == 0')
	expect(!!(single(&d, 400, 10, 0, 43, &out[0]) == 7 && !C.memcmp(voidptr( &out[0] ), voidptr(c'\033[9;10u'), 7)), 155, c'single(&d, 400, 0x0a, 0, 43, out) == 7 && !memcmp(out, \"\\033[9;10u\", 7)')
	expect(!!(single(&d, 500, 0, 0, 0, &out[0]) == 12 && !C.memcmp(voidptr( &out[0] ), voidptr(c'\033[57444;1:3u'), 12)), 157, c'single(&d, 500, 0, 0, 0, out) == 12 && !memcmp(out, \"\\033[57444;1:3u\", 12)')
	expect(!!(single(&d, 600, 0, 0, 0, &out[0]) == 0), 158, c'single(&d, 600, 0, 0, 0, out) == 0')
	expect(!!(single(&d, 700, 8, 0, 0, &out[0]) == 0), 159, c'single(&d, 700, 0x08, 0, 0, out) == 0')
	expect(!!(single(&d, 800, 0, 0, 0, &out[0]) == 0), 160, c'single(&d, 800, 0, 0, 0, out) == 0')
	// Held down, Cmd-Tab repeats like any other key: the switcher walks on.

	expect(!!(single(&d, 1000, 8, 0, 43, &out[0]) == 6), 163, c'single(&d, 1000, 0x08, 0, 43, out) == 6')
	expect(!!(C.vinix_spi_core_repeat_key(&d, 1000 + 500000, 0, &out[0], 128) == 6 && !C.memcmp(voidptr( &out[0] ), voidptr(c'\033[9;9u'), 6)), 165, c'repeat_key(&d, 1000 + REPEAT_DELAY, 0, out, 128) == 6 && !memcmp(out, \"\\033[9;9u\", 6)')

	}
}

pub fn test_command_chords() {
	unsafe {
	d := C.decoder{}

	out := [128]u8{}
	expect_bytes(C.vinix_spi_core_encode_key(20, 8, 0, 0, 0), &u8(c'\033[113;9u'), 8)
	// Cmd-Q

	expect_bytes(C.vinix_spi_core_encode_key(40, 8, 0, 0, 0), &u8(c'\033[13;9u'), 7)
	// Cmd-Return

	expect_bytes(C.vinix_spi_core_encode_key(20, 15, 0, 0, 0), &u8(c'\033[81;16u'), 8)
	// Shift-Ctrl-Alt-Cmd-Q

	expect_bytes(C.vinix_spi_core_encode_key(80, 8, 0, 0, 0), &u8(c'\033[1;9D'), 6)
	// Cmd-Left

	expect_bytes(C.vinix_spi_core_encode_key(82, 10, 0, 0, 0), &u8(c'\033[1;10A'), 7)
	// Shift-Cmd-Up

	expect_bytes(C.vinix_spi_core_encode_key(31, 10, 0, 0, 0), &u8(c'\033[64;10u'), 8)
	// Shift-Cmd-2

	expect(!!(single(&d, 100, 8, 0, 20, &out[0]) == 8 && !C.memcmp(voidptr( &out[0] ), voidptr(c'\033[113;9u'), 8)), 185, c'single(&d, 100, 0x08, 0, 20, out) == 8 && !memcmp(out, \"\\033[113;9u\", 8)')
	expect(!!(single(&d, 200, 0, 0, 0, &out[0]) == 12 && !C.memcmp(voidptr( &out[0] ), voidptr(c'\033[57444;1:3u'), 12)), 187, c'single(&d, 200, 0, 0, 0, out) == 12 && !memcmp(out, \"\\033[57444;1:3u\", 12)')

	}
}

pub fn test_alt_window_shortcuts() {
	unsafe {
	d := C.decoder{}

	out := [128]u8{}
	expect_bytes(C.vinix_spi_core_encode_key(43, 4, 0, 0, 0), &u8(c'\033[9;3u'), 6)
	expect_bytes(C.vinix_spi_core_encode_key(43, 64, 0, 0, 0), &u8(c'\033[9;3u'), 6)
	expect_bytes(C.vinix_spi_core_encode_key(43, 6, 0, 0, 0), &u8(c'\033[9;4u'), 6)
	expect_bytes(C.vinix_spi_core_encode_key(61, 4, 0, 0, 0), &u8(c'\033[1;3S'), 6)
	expect_bytes(C.vinix_spi_core_encode_key(61, 0, 0, 0, 0), &u8(c'\033OS'), 3)
	expect_bytes(C.vinix_spi_core_encode_key(43, 5, 0, 0, 0), &u8(c'\033\t'), 2)
	expect_bytes(C.vinix_spi_core_encode_key(4, 4, 0, 0, 0), &u8(c'\033a'), 2)
	// Both Alt keys may be held: only releasing the last ends switching.

	expect(!!(single(&d, 1, 68, 0, 43, &out[0]) == 6), 201, c'single(&d, 1, 0x44, 0, 43, out) == 6')
	expect(!!(d.alt_tab_chorded), 202, c'd.alt_tab_chorded')
	expect(!!(single(&d, 2, 64, 0, 0, &out[0]) == 0), 203, c'single(&d, 2, 0x40, 0, 0, out) == 0')
	expect(!!(single(&d, 3, 0, 0, 0, &out[0]) == 12 && !C.memcmp(voidptr( &out[0] ), voidptr(c'\033[57443;1:3u'), 12)), 205, c'single(&d, 3, 0, 0, 0, out) == 12 && !memcmp(out, \"\\033[57443;1:3u\", 12)')
	expect(!!(!d.alt_tab_chorded), 206, c'!d.alt_tab_chorded')
	expect(!!(single(&d, 4, 0, 0, 0, &out[0]) == 0), 207, c'single(&d, 4, 0, 0, 0, out) == 0')
	// Ordinary Meta input and Alt-F4 request no unsolicited release.

	expect(!!(single(&d, 5, 4, 0, 4, &out[0]) == 2), 209, c'single(&d, 5, 4, 0, 4, out) == 2')
	expect(!!(single(&d, 6, 0, 0, 0, &out[0]) == 0), 210, c'single(&d, 6, 0, 0, 0, out) == 0')
	expect(!!(single(&d, 7, 4, 0, 61, &out[0]) == 6), 211, c'single(&d, 7, 4, 0, 61, out) == 6')
	expect(!!(single(&d, 8, 0, 0, 0, &out[0]) == 0), 212, c'single(&d, 8, 0, 0, 0, out) == 0')
	expect(!!(single(&d, 9, 4, 0, 43, &out[0]) == 6), 213, c'single(&d, 9, 4, 0, 43, out) == 6')
	expect(!!(C.vinix_spi_core_repeat_key(&d, 9 + 500000, 0, &out[0], 128) == 6 && !C.memcmp(voidptr( &out[0] ), voidptr(c'\033[9;3u'), 6)), 215, c'repeat_key(&d, 9 + REPEAT_DELAY, 0, out, 128) == 6 && !memcmp(out, \"\\033[9;3u\", 6)')
	C.vinix_spi_core_reset_input(&d)
	expect(!!(!d.alt_tab_chorded), 217, c'!d.alt_tab_chorded')
	expect(!!(single(&d, 10 + 500000, 0, 0, 0, &out[0]) == 0), 218, c'single(&d, 10 + REPEAT_DELAY, 0, 0, 0, out) == 0')
	// Pressing Alt after Tab is held must also arm the repeated chord.

	expect(!!(single(&d, 20 + 500000, 0, 0, 43, &out[0]) == 1), 220, c'single(&d, 20 + REPEAT_DELAY, 0, 0, 43, out) == 1')
	expect(!!(single(&d, 21 + 500000, 4, 0, 43, &out[0]) == 0), 221, c'single(&d, 21 + REPEAT_DELAY, 4, 0, 43, out) == 0')
	expect(!!(C.vinix_spi_core_repeat_key(&d, 20 + 2 * 500000, 0, &out[0], 128) == 6), 222, c'repeat_key(&d, 20 + 2 * REPEAT_DELAY, 0, out, 128) == 6')
	expect(!!(d.alt_tab_chorded), 223, c'd.alt_tab_chorded')
	expect(!!(single(&d, 21 + 2 * 500000, 0, 0, 0, &out[0]) == 12), 224, c'single(&d, 21 + 2 * REPEAT_DELAY, 0, 0, 0, out) == 12')

	}
}

pub fn test_repeat() {
	unsafe {
	d := C.decoder{}

	out := [128]u8{}
	single(&d, 100, 0, 0, 4, &out[0])
	expect(!!(C.vinix_spi_core_repeat_key(&d, 100 + 500000 - 1, 0, &out[0], 128) == 0), 231, c'repeat_key(&d, 100 + REPEAT_DELAY - 1, 0, out, 128) == 0')
	expect(!!(C.vinix_spi_core_repeat_key(&d, 100 + 500000, 0, &out[0], 128) == 1 && out[0] == `a`), 232, c"repeat_key(&d, 100 + REPEAT_DELAY, 0, out, 128) == 1 && out[0] == 'a'")
	expect(!!(C.vinix_spi_core_repeat_key(&d, 100 + 500000 + 1, 0, &out[0], 128) == 0), 233, c'repeat_key(&d, 100 + REPEAT_DELAY + 1, 0, out, 128) == 0')
	single(&d, 101 + 500000, 2, 0, 4, &out[0])
	// held key, new modifier

	expect(!!(C.vinix_spi_core_repeat_key(&d, 100 + 500000 + 33333, 0, &out[0], 128) == 1 && out[0] == `A`), 235, c"repeat_key(&d, 100 + REPEAT_DELAY + REPEAT_PERIOD, 0, out, 128) == 1 && out[0] == 'A'")
	expect(!!(C.vinix_spi_core_repeat_key(&d, 9999999999, 0, &out[0], 128) == 1), 236, c'repeat_key(&d, 9999999999ULL, 0, out, 128) == 1')
	// one, not a burst

	single(&d, 10000000000, 0, 0, 0, &out[0])
	expect(!!(C.vinix_spi_core_repeat_key(&d, 10001000000, 0, &out[0], 128) == 0), 238, c'repeat_key(&d, 10001000000ULL, 0, out, 128) == 0')

	}
}

pub fn test_rollover() {
	unsafe {
	d := C.decoder{}

	out := [128]u8{}
	single(&d, 1, 0, 0, 4, &out[0])
	for error := u8(1); error <= 3; error++ {
		expect(!!(single(&d, 2, 0, 0, error, &out[0]) == 0), 245, c'single(&d, 2, 0, 0, error, out) == 0')
		expect(!!(C.vinix_spi_core_has_key( &d.keys[0] , 4)), 246, c'has_key(d.keys, 4)')
		expect(!!(C.vinix_spi_core_repeat_key(&d, 1000000, 0, &out[0], 128) == 0), 247, c'repeat_key(&d, 1000000, 0, out, 128) == 0')
	}
	expect(!!(single(&d, 1000001, 0, 0, 4, &out[0]) == 0), 249, c'single(&d, 1000001, 0, 0, 4, out) == 0')
	expect(!!(C.vinix_spi_core_repeat_key(&d, 1500001, 0, &out[0], 128) == 1), 250, c'repeat_key(&d, 1500001, 0, out, 128) == 1')
	expect(!!(single(&d, 1500002, 0, 0, 0, &out[0]) == 0 && d.repeat_key == 0), 251, c'single(&d, 1500002, 0, 0, 0, out) == 0 && d.repeat_key == 0')

	}
}

pub fn test_crc_and_identity_rejection() {
	unsafe {
	d := C.decoder{}

	p := [256]u8{}
	out := [128]u8{}
	keys := [u8(4), u8(0), u8(0), u8(0), u8(0), u8(0)]!

	packet(&p[0], 0, 0,  &keys[0] )
	p[11] ^= 1
	expect(!!(C.vinix_spi_core_decode_packet(&d,  &p[0] , 256, 1, 0, &out[0], 128) == 0 && d.reports == 0), 257, c'decode_packet(&d, p, 256, 1, 0, out, 128) == 0 && d.reports == 0')
	seal_packet(&p[0])
	// Good packet CRC, bad message CRC.

	expect(!!(C.vinix_spi_core_decode_packet(&d,  &p[0] , 256, 2, 0, &out[0], 128) == 0 && d.reports == 0), 259, c'decode_packet(&d, p, 256, 2, 0, out, 128) == 0 && d.reports == 0')
	for i := u32(0); i < 4; i++ {
		packet(&p[0], 0, 0,  &keys[0] )
		if i == 0 {
			p[0] = 64
		}
		if i == 1 {
			p[1] = 2
		}
		if i == 2 {
			p[8] = 81
		}
		if i == 3 {
			p[16] = 2
		}
		le16( &p[0]  + 26, C.vinix_spi_core_crc16( &p[0]  + 8, 18))
		seal_packet(&p[0])
		expect(!!(C.vinix_spi_core_decode_packet(&d,  &p[0] , 256, 3, 0, &out[0], 128) == 0 && d.reports == 0), 267, c'decode_packet(&d, p, 256, 3, 0, out, 128) == 0 && d.reports == 0')
	}
	single(&d, 100, 0, 0, 4, &out[0])
	packet(&p[0], 0, 0,  &keys[0] )
	p[254] ^= 1
	C.vinix_spi_core_decode_packet(&d,  &p[0] , 256, 101, 0, &out[0], 128)
	expect(!!(C.vinix_spi_core_repeat_key(&d, 1000000, 0, &out[0], 128) == 0), 272, c'repeat_key(&d, 1000000, 0, out, 128) == 0')
	expect(!!(C.vinix_spi_core_has_key( &d.keys[0] , 4)), 273, c'has_key(d.keys, 4)')
	// Do not manufacture a release.

	}
}

pub fn test_fragmentation() {
	unsafe {
	m := [20]u8{}
	p := [256]u8{}
	out := [128]u8{}
	keys := [u8(4), u8(0), u8(0), u8(0), u8(0), u8(0)]!

	message(&m[0], 0, 0,  &keys[0] )
	for split := u32(1); split < 20; split++ {
		d := C.decoder{}

		fragment(&p[0],  &m[0] , 0, split)
		expect(!!(C.vinix_spi_core_decode_packet(&d,  &p[0] , 256, 1, 0, &out[0], 128) == 0), 281, c'decode_packet(&d, p, 256, 1, 0, out, 128) == 0')
		fragment(&p[0],  &m[0] , split, 20 - split)
		expect(!!(C.vinix_spi_core_decode_packet(&d,  &p[0] , 256, 2, 0, &out[0], 128) == 1 && out[0] == `a`), 283, c"decode_packet(&d, p, 256, 2, 0, out, 128) == 1 && out[0] == 'a'")
		expect(!!(d.message_used == 0), 284, c'd.message_used == 0')
	}
	d := C.decoder{}

	fragment(&p[0],  &m[0] , 10, 10)
	expect(!!(C.vinix_spi_core_decode_packet(&d,  &p[0] , 256, 1, 0, &out[0], 128) == 0), 288, c'decode_packet(&d, p, 256, 1, 0, out, 128) == 0')
	fragment(&p[0],  &m[0] , 0, 10)
	C.vinix_spi_core_decode_packet(&d,  &p[0] , 256, 2, 0, &out[0], 128)
	fragment(&p[0],  &m[0] , 11, 9)
	expect(!!(C.vinix_spi_core_decode_packet(&d,  &p[0] , 256, 3, 0, &out[0], 128) == 0 && d.message_used == 0), 291, c'decode_packet(&d, p, 256, 3, 0, out, 128) == 0 && d.message_used == 0')
	fragment(&p[0],  &m[0] , 0, 10)
	C.vinix_spi_core_decode_packet(&d,  &p[0] , 256, 4, 0, &out[0], 128)
	fragment(&p[0],  &m[0] , 10, 10)
	expect(!!(C.vinix_spi_core_decode_packet(&d,  &p[0] , 256, 4 + 100000, 0, &out[0], 128) == 0), 294, c'decode_packet(&d, p, 256, 4 + FRAGMENT_US, 0, out, 128) == 0')
	fragment(&p[0],  &m[0] , 0, 20)
	expect(!!(C.vinix_spi_core_decode_packet(&d,  &p[0] , 256, 5 + 100000, 0, &out[0], 128) == 1), 296, c'decode_packet(&d, p, 256, 5 + FRAGMENT_US, 0, out, 128) == 1')

	}
}

pub fn test_lengths_and_output_bounds() {
	unsafe {
	p := [256]u8{}
	keys := [u8(69), u8(68), u8(67), u8(66), u8(65), u8(64)]!

	guarded := [32]u8{}

	for length := usize(0); length <= 256; length++ {
		d := C.decoder{}

		packet(&p[0], 4, 0,  &keys[0] )
		if length != 256 {
			expect(!!(C.vinix_spi_core_decode_packet(&d,  &p[0] , length, 1, 0, &guarded[0], 32) == 0), 303, c'decode_packet(&d, p, length, 1, 0, guarded, 32) == 0')
		}
	}
	for cap := usize(0); cap <= 16; cap++ {
		d := C.decoder{}

		packet(&p[0], 4, 0,  &keys[0] )
		C.memset(voidptr( &guarded[0] ), 165, 32)
		n := C.vinix_spi_core_decode_packet(&d,  &p[0] , 256, 1, 0,  &guarded[0]  + 4, cap)
		expect(!!(n <= cap && n % 6 == 0), 308, c'n <= cap && n % 6 == 0')
		for i := usize(0); i < 4; i++ {
			expect(!!(guarded[i] == 165), 309, c'guarded[i] == 0xa5')
		}
		for i := usize(4 + cap); i < 32; i++ {
			expect(!!(guarded[i] == 165), 310, c'guarded[i] == 0xa5')
		}
	}
	bad := [u16(0), u16(21), u16(246), u16(247), u16(255), u16(256), u16(65535)]!

	for i := usize(0); i < 7; i++ {
		d := C.decoder{}

		packet(&p[0], 0, 0,  &keys[0] )
		le16( &p[0]  + 6, bad[i])
		seal_packet(&p[0])
		expect(!!(C.vinix_spi_core_decode_packet(&d,  &p[0] , 256, 1, 0, &guarded[0], 32) == 0), 315, c'decode_packet(&d, p, 256, 1, 0, guarded, 32) == 0')
	}

	}
}

struct Fake {
mut:
	now           u64
	asserted_at   u64
	deasserted_at u64
	first_tx      u64
	last_clock    u64
	regs          [92]u32
	enable        u32
	ready         u32
	incoming      [256]u8
	rx_fifo       [16]u8
	tx_level      u32
	rx_head       u32
	rx_level      u32
	cursor        u32
	reads         u32
	writes        u32
	assertions    u32
	releases      u32
	enables       u32
	enable_values [8]u32
	run           i32
	stall         i32
	invalid_fifo  i32
}

@[export: 'vsf_keyboard_fake_read']
pub fn fake_read(cookie voidptr, address u64) u32 {
	unsafe {
	f := &Fake(cookie)
	f.reads++
	f.now++
	if address == 2097152 {
		return f.enable
	}
	if address == 3145728 {
		return f.ready
	}
	expect(!!(address >= 1048576 && address < 1048576 + sizeof([92]u32)), 336, c'address >= FAKE_SPI && address < FAKE_SPI + sizeof(f->regs)')
	off := u32((address - 1048576))
	expect(!!((off & 3) == 0), 337, c'(off & 3) == 0')
	if off == 268 {
		if f.invalid_fifo {
			return 17 << 24
		}
		if f.run && !f.stall && f.tx_level && f.rx_level < 16 && f.cursor < 256 {
			f.tx_level--
			f.rx_fifo[(f.rx_head + f.rx_level++) % 16] = f.incoming[f.cursor++]
			f.last_clock = f.now
		}
		return (f.rx_level << 24) | (f.tx_level << 8)
	}
	if off == 32 {
		expect(!!(f.rx_level > 0), 348, c'f->rx_level > 0')
		f.rx_level--
		v := f.rx_fifo[f.rx_head]
		f.rx_head = (f.rx_head + 1) % 16
		return u32(v)
	}
	return f.regs[off / 4]

	}
}

@[export: 'vsf_keyboard_fake_write']
pub fn fake_write(cookie voidptr, address u64, value u32) {
	unsafe {
	f := &Fake(cookie)
	f.writes++
	f.now++
	if address == 2097152 {
		f.enable = value
		if f.enables < 8 {
			f.enable_values[f.enables++] = value
		}
		return
	}
	expect(!!(address >= 1048576 && address < 1048576 + sizeof([92]u32)), 361, c'address >= FAKE_SPI && address < FAKE_SPI + sizeof(f->regs)')
	off := u32((address - 1048576))
	expect(!!((off & 3) == 0), 362, c'(off & 3) == 0')
	if off == 0 {
		f.run = !!(value & 1)
		if value & 12 {
			f.cursor = 0
			f.rx_head = f.cursor
			f.rx_level = f.rx_head
			f.tx_level = f.rx_level
		}
	}
	if off == 12 && value == 0 {
		if f.assertions {
			expect(!!(f.now - f.deasserted_at >= 250), 368, c'f->now - f->deasserted_at >= 250')
		}
		f.asserted_at = f.now
		f.first_tx = 0
		f.assertions++
	}
	if off == 12 && value == 2 && f.regs[off / 4] == 0 {
		expect(!!(f.now - f.asserted_at >= 200), 372, c'f->now - f->asserted_at >= 200')
		if f.last_clock >= f.asserted_at {
			expect(!!(f.now - f.last_clock >= 100), 373, c'f->now - f->last_clock >= 100')
		}
		f.deasserted_at = f.now
		f.releases++
	}
	if off == 16 {
		expect(!!(value == 0 && f.tx_level < 16), 377, c'value == 0 && f->tx_level < 16')
		expect(!!(f.now - f.asserted_at >= 100), 378, c'f->now - f->asserted_at >= 100')
		if !f.first_tx {
			f.first_tx = f.now
		}
		f.tx_level++
	}
	f.regs[off / 4] = value

	}
}

@[export: 'vsf_keyboard_fake_now']
pub fn fake_now(cookie voidptr) u64 {
	unsafe {
	return u64((&Fake(cookie)).now++)

	}
}

@[export: 'vsf_keyboard_fake_delay']
pub fn fake_delay(cookie voidptr, us u32) {
	unsafe {
	(&Fake(cookie)).now += us

	}
}

pub fn setup(f &Fake, active_low i32) C.spi_keyboard {
	unsafe {
	C.memset(voidptr(f), 0, sizeof(Fake))
	f.regs[12 / 4] = 2
	f.enable = 42240
	k := C.spi_keyboard{}

	k.io = C.io_ops{
		read32:   C.vsf_keyboard_fake_read
		write32:  C.vsf_keyboard_fake_write
		now_us:   C.vsf_keyboard_fake_now
		delay_us: C.vsf_keyboard_fake_delay
	}

	k.cookie = f
	k.spi = 1048576
	k.enable = 2097152
	k.enable_low = active_low
	return k

	}
}

pub fn test_spi_setup_and_reset() {
	unsafe {
	for low := i32(0); low <= 1; low++ {
		f := Fake{}
		k := setup(&f, low)
		expect(!!(C.vinix_spi_core_start_keyboard(&k, 120000000, 8000000)), 398, c'start_keyboard(&k, 120000000, 8000000)')
		expect(!!(k.active && f.enables == 3 && f.now >= 10000), 399, c'k.active && f.enables == 3 && f.now >= 10000')
		expect(!!(f.regs[48 / 4] == 15 && f.regs[4 / 4] == 32), 400, c'f.regs[SPI_CLKDIV / 4] == 15 && f.regs[SPI_CFG / 4] == 32')
		expect(!!(f.regs[312 / 4] == 0 && f.regs[304 / 4] == 0), 401, c'f.regs[SPI_IE_FIFO / 4] == 0 && f.regs[SPI_IE_XFER / 4] == 0')
		expect(!!((f.enable_values[0] & 1) == u32((1 ^ low))), 402, c'(f.enable_values[0] & 1) == (uint32_t)(1 ^ low)')
		expect(!!((f.enable_values[1] & 1) == u32(low)), 403, c'(f.enable_values[1] & 1) == (uint32_t)low')
		expect(!!((f.enable_values[2] & 1) == u32((1 ^ low))), 404, c'(f.enable_values[2] & 1) == (uint32_t)(1 ^ low)')
		expect(!!((f.enable & 110) == 2 && (f.enable & 65280) == 42240), 405, c'(f.enable & 0x6e) == 2 && (f.enable & 0xff00) == 0xa500')
	}
	f := Fake{}
	k := setup(&f, 0)
	expect(!!(!C.vinix_spi_core_start_keyboard(&k, 0, 8000000) && f.writes == 0), 408, c'!start_keyboard(&k, 0, 8000000) && f.writes == 0')
	expect(!!(!C.vinix_spi_core_start_keyboard(&k, 120000000, 0) && f.writes == 0), 409, c'!start_keyboard(&k, 120000000, 0) && f.writes == 0')
	expect(!!(!C.vinix_spi_core_start_keyboard(&k, 120000000, 8000001) && f.writes == 0), 410, c'!start_keyboard(&k, 120000000, 8000001) && f.writes == 0')
	expect(!!(!C.vinix_spi_core_start_keyboard(&k, 120000000, 1) && f.writes == 0), 411, c'!start_keyboard(&k, 120000000, 1) && f.writes == 0')

	}
}

pub fn test_spi_end_to_end() {
	unsafe {
	f := Fake{}
	k := setup(&f, 0)
	out := [128]u8{}
	keys := [u8(4), u8(0), u8(0), u8(0), u8(0), u8(0)]!

	expect(!!(C.vinix_spi_core_start_keyboard(&k, 120000000, 8000000)), 416, c'start_keyboard(&k, 120000000, 8000000)')
	packet(&f.incoming[0], 2, 0,  &keys[0] )
	writes := f.writes
	expect(!!(C.vinix_spi_core_poll_keyboard(&k, &out[0], 128, 0) == 0 && f.writes == writes), 418, c'poll_keyboard(&k, out, 128, 0) == 0 && f.writes == writes')
	// boot delay

	f.now = k.next_poll
	expect(!!(C.vinix_spi_core_poll_keyboard(&k, &out[0], 128, 0) == 1 && out[0] == `A`), 420, c"poll_keyboard(&k, out, 128, 0) == 1 && out[0] == 'A'")
	expect(!!(f.assertions == 1 && f.releases == 1 && !f.run && f.cursor == 256), 421, c'f.assertions == 1 && f.releases == 1 && !f.run && f.cursor == 256')
	expect(!!(f.regs[76 / 4] == 256 && f.regs[52 / 4] == 256), 422, c'f.regs[SPI_TXCNT / 4] == 256 && f.regs[SPI_RXCNT / 4] == 256')
	expect(!!(k.decoder.reports == 1 && f.regs[12 / 4] == 2), 423, c'k.decoder.reports == 1 && f.regs[SPI_PIN / 4] == SPI_CS_HIGH')
	writes = f.writes
	expect(!!(C.vinix_spi_core_poll_keyboard(&k, &out[0], 128, 0) == 0 && f.writes == writes), 425, c'poll_keyboard(&k, out, 128, 0) == 0 && f.writes == writes')
	f.now = k.next_poll
	expect(!!(C.vinix_spi_core_poll_keyboard(&k, &out[0], 128, 0) == 0 && k.decoder.reports == 2), 427, c'poll_keyboard(&k, out, 128, 0) == 0 && k.decoder.reports == 2')
	// held

	C.memset(voidptr( &keys[0] ), 0, 6)
	packet(&f.incoming[0], 0, 0,  &keys[0] )
	f.now = k.next_poll
	expect(!!(C.vinix_spi_core_poll_keyboard(&k, &out[0], 128, 0) == 0 && k.decoder.repeat_key == 0), 429, c'poll_keyboard(&k, out, 128, 0) == 0 && k.decoder.repeat_key == 0')

	}
}

pub fn test_spi_timeout_backoff_disable() {
	unsafe {
	f := Fake{}
	k := setup(&f, 0)
	out := [128]u8{}
	C.vinix_spi_core_start_keyboard(&k, 120000000, 8000000)
	f.stall = 1
	for i := u32(1); i <= 3; i++ {
		f.now = k.next_poll
		start := f.now
		expect(!!(C.vinix_spi_core_poll_keyboard(&k, &out[0], 128, 0) == (if i == 3 {
			-2
		} else {
			-1
		})), 438, c'poll_keyboard(&k, out, 128, 0) == (i == 3 ? -2 : -1)')
		expect(!!(f.now - start >= 5000 && f.now - start < 5000 + 1000), 439, c'f.now - start >= TRANSFER_US && f.now - start < TRANSFER_US + 1000')
		expect(!!(f.regs[12 / 4] == 2 && !f.run && k.errors == i), 440, c'f.regs[SPI_PIN / 4] == SPI_CS_HIGH && !f.run && k.errors == i')
		expect(!!(f.assertions == f.releases && k.decoder.repeat_at == 0), 441, c'f.assertions == f.releases && k.decoder.repeat_at == 0')
		writes := f.writes
		expect(!!(C.vinix_spi_core_poll_keyboard(&k, &out[0], 128, 0) == 0 && f.writes == writes), 443, c'poll_keyboard(&k, out, 128, 0) == 0 && f.writes == writes')
	}
	expect(!!(!k.active), 445, c'!k.active')
	// Down, and staying down while the cool-off runs.

	reads := f.reads
	expect(!!(C.vinix_spi_core_poll_keyboard(&k, &out[0], 128, 0) == 0 && f.reads == reads), 448, c'poll_keyboard(&k, out, 128, 0) == 0 && f.reads == reads')
	// Past it, brought back rather than left dead for the rest of the boot.
	//     *Nothing used to clear `active`, so three bad reads cost the machine its
	//     *keyboard and its touchpad together while the desktop carried on drawing
	//     *-- input simply stopped and never returned.

	f.stall = 0
	f.now += 2000000 + 1
	expect(!!(C.vinix_spi_core_poll_keyboard(&k, &out[0], 128, 0) == -3), 455, c'poll_keyboard(&k, out, 128, 0) == -3')
	expect(!!(k.active && k.errors == 0 && k.revive_at == 0), 456, c'k.active && k.errors == 0 && k.revive_at == 0')
	// And it works afterwards, rather than merely claiming to be up.

	keys := [u8(4), u8(0), u8(0), u8(0), u8(0), u8(0)]!

	packet(&f.incoming[0], 0, 0,  &keys[0] )
	f.now = k.next_poll
	expect(!!(C.vinix_spi_core_poll_keyboard(&k, &out[0], 128, 0) == 1 && out[0] == `a`), 461, c"poll_keyboard(&k, out, 128, 0) == 1 && out[0] == 'a'")

	}
}

pub fn test_spi_invalid_fifo_and_recovery() {
	unsafe {
	f := Fake{}
	k := setup(&f, 0)
	out := [128]u8{}
	keys := [u8(4), u8(0), u8(0), u8(0), u8(0), u8(0)]!

	C.vinix_spi_core_start_keyboard(&k, 120000000, 8000000)
	f.invalid_fifo = 1
	f.now = k.next_poll
	expect(!!(C.vinix_spi_core_poll_keyboard(&k, &out[0], 128, 0) == -1 && !f.run), 467, c'poll_keyboard(&k, out, 128, 0) == -1 && !f.run')
	f.invalid_fifo = 0
	packet(&f.incoming[0], 0, 0,  &keys[0] )
	f.now = k.next_poll
	expect(!!(C.vinix_spi_core_poll_keyboard(&k, &out[0], 128, 0) == 1 && out[0] == `a` && k.errors == 0), 469, c"poll_keyboard(&k, out, 128, 0) == 1 && out[0] == 'a' && k.errors == 0")

	}
}

pub fn test_ready_gpio_gates_reads_and_repeat() {
	unsafe {
	f := Fake{}
	k := setup(&f, 0)
	out := [128]u8{}
	keys := [u8(4), u8(0), u8(0), u8(0), u8(0), u8(0)]!

	k.ready = 3145728
	k.ready_low = 1
	C.vinix_spi_core_start_keyboard(&k, 120000000, 8000000)
	f.ready = 0
	packet(&f.incoming[0], 0, 0,  &keys[0] )
	f.now = k.next_poll
	expect(!!(C.vinix_spi_core_poll_keyboard(&k, &out[0], 128, 0) == 1), 477, c'poll_keyboard(&k, out, 128, 0) == 1')
	f.ready = 1
	f.now = k.next_poll
	assertions := f.assertions
	expect(!!(C.vinix_spi_core_poll_keyboard(&k, &out[0], 128, 0) == 0 && f.assertions == assertions), 479, c'poll_keyboard(&k, out, 128, 0) == 0 && f.assertions == assertions')
	f.now = k.decoder.repeat_at
	expect(!!(C.vinix_spi_core_poll_keyboard(&k, &out[0], 128, 0) == 1 && out[0] == `a` && f.assertions == assertions), 482, c"poll_keyboard(&k, out, 128, 0) == 1 && out[0] == 'a' && f.assertions == assertions")
	// Even after a minute idle, an inactive ready line must not cause an
	//     *unsolicited transfer.

	f.now += 60000000
	expect(!!(C.vinix_spi_core_poll_keyboard(&k, &out[0], 128, 0) == 1 && out[0] == `a` && f.assertions == assertions), 488, c"poll_keyboard(&k, out, 128, 0) == 1 && out[0] == 'a' && f.assertions == assertions")

	}
}

pub fn test_ready_gpio_invalid_packet_recovery() {
	unsafe {
	f := Fake{}
	k := setup(&f, 0)
	out := [128]u8{}
	k.ready = 3145728
	C.vinix_spi_core_start_keyboard(&k, 120000000, 8000000)
	f.ready = 1
	// FIFO progress and the byte count both succeed, but an all-zero response
	//     *is not an Apple packet and must participate in bounded recovery.

	for i := u32(1); i <= 3; i++ {
		C.memset(f.incoming, 0, sizeof([256]u8))
		f.now = k.next_poll
		expect(!!(C.vinix_spi_core_poll_keyboard(&k, &out[0], 128, 0) == (if i == 3 {
			-2
		} else {
			-1
		})), 501, c'poll_keyboard(&k, out, 128, 0) == (i == 3 ? -2 : -1)')
		expect(!!(k.errors == i && f.cursor == 256), 502, c'k.errors == i && f.cursor == 256')
	}
	expect(!!(!k.active), 504, c'!k.active')
	f.now += 2000000 + 1
	expect(!!(C.vinix_spi_core_poll_keyboard(&k, &out[0], 128, 0) == -3 && k.active && k.errors == 0), 507, c'poll_keyboard(&k, out, 128, 0) == -3 && k.active && k.errors == 0')
	keys := [u8(4), u8(0), u8(0), u8(0), u8(0), u8(0)]!

	packet(&f.incoming[0], 0, 0,  &keys[0] )
	f.now = k.next_poll
	expect(!!(C.vinix_spi_core_poll_keyboard(&k, &out[0], 128, 0) == 1 && out[0] == `a`), 510, c"poll_keyboard(&k, out, 128, 0) == 1 && out[0] == 'a'")

	}
}

__global random_state = u32(1975686705)

pub fn random32() u32 {
	unsafe {
	random_state ^= random_state << 13
	random_state ^= random_state >> 17
	random_state ^= random_state << 5
	return random_state

	}
}

pub fn test_seeded_mutation_fuzz() {
	unsafe {
	d := C.decoder{}

	p := [320]u8{}
	out := [128]u8{}
	keys := [6]u8{}

	for i := u32(0); i < 100000; i++ {
		for j := u32(0); j < 6; j++ {
			keys[j] = u8(random32())
		}
		packet(&p[0], u8(random32()), u8(random32()),  &keys[0] )
		mutations := random32() % 8
		for mutations-- {
			p[random32() % 256] ^= u8(random32())
		}
		if i & 1 {
			seal_packet(&p[0])
		}
		length := if i % 4 { 256 } else { random32() % sizeof([320]u8) }
		capacity := random32() % sizeof([128]u8)
		n := C.vinix_spi_core_decode_packet(&d,  &p[0] , length, u64(i) * 4000, i & 1, &out[0], capacity)
		expect(!!(n <= capacity && d.message_used <= 20), 530, c'n <= capacity && d.message_used <= MESSAGE_SIZE')
		n = C.vinix_spi_core_repeat_key(&d, u64(i) * 4000, i & 1, &out[0], capacity)
		expect(!!(n <= capacity), 532, c'n <= capacity')
	}

	}
}

pub fn run(test fn (), name &char) {
	unsafe {
	test()
	tests++
	C.printf(c'ok %u - %s\n', tests, name)

	}
}

@[export: 'vinix_spi_keyboard_fixture']
pub fn suite() i32 {
	unsafe {
	run(test_crc, c'CRC-16 known answer and framing')
	run(test_press_release_duplicate, c'press, release, duplicate reports')
	run(test_six_keys_reordering, c'six keys, slot reorder, duplicate usages')
	run(test_modifiers_and_caps, c'independent modifiers and Caps Lock')
	run(test_ascii_controls, c'ASCII, control bytes, Option, NUL')
	run(test_navigation_fn_and_function_keys, c'navigation, DECCKM, Fn, function keys')
	run(test_command_tab, c'Cmd-Tab chords and the release that ends them')
	run(test_command_chords, c'CSI-u preserves general Cmd chords')
	run(test_alt_window_shortcuts, c'Alt window chords, last-Alt release and ordinary Meta input')
	run(test_repeat, c'repeat timing, modifiers, no catch-up burst')
	run(test_rollover, c'rollover errors and recovery')
	run(test_crc_and_identity_rejection, c'packet/message CRC and identity rejection')
	run(test_fragmentation, c'all fragment splits, order and expiry')
	run(test_lengths_and_output_bounds, c'length and output capacity bounds')
	run(test_spi_setup_and_reset, c'SPI setup, divider and reset polarity')
	run(test_spi_end_to_end, c'mock-MMIO SPI to console bytes')
	run(test_spi_timeout_backoff_disable, c'bounded timeout, CS cleanup, backoff, disable')
	run(test_spi_invalid_fifo_and_recovery, c'invalid FIFO count and recovery')
	run(test_ready_gpio_gates_reads_and_repeat, c'ready GPIO gates idle reads and repeat')
	run(test_ready_gpio_invalid_packet_recovery, c'invalid ready packet resets and recovers')
	run(test_seeded_mutation_fuzz, c'100000 deterministic mutated packets')
	C.printf(c'PASS: %u test groups\n', tests)
	return 0

	}
}
