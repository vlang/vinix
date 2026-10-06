// SPDX-License-Identifier: GPL-2.0-or-later
// Independent original packet, input and PIO assertions; native V fixture.
@[translated]
@[has_globals]
module touchpadfixture

#include "touchpad-native-abi.h"

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
fn C.vsf_touchpad_mock_read(voidptr, u64) u32
fn C.vsf_touchpad_mock_write(voidptr, u64, u32)
fn C.vsf_touchpad_mock_now(voidptr) u64
fn C.vsf_touchpad_mock_delay(voidptr, u32)
fn expect(ok bool, line i32, expression &char) {
 if !ok { unsafe { C.printf(c'SPI FIXTURE FAIL line %d: %s\n', line, expression); C.fflush(nil); C.abort() } }
}
const mode_prefix = [u8(64), u8(2), u8(0), u8(0), u8(0), u8(0), u8(12), u8(0), u8(82), u8(2),
		u8(0), u8(0), u8(2), u8(0), u8(2), u8(0), u8(2), u8(1), u8(123), u8(17)]!

__global groups u32

pub fn seal(p &u8) {
	unsafe {
	C.vinix_spi_core_tp_put16(p + 254, C.vinix_spi_core_tp_crc(p, 254))

	}
}

pub fn seal_message(m &u8, n usize) {
	unsafe {
	C.vinix_spi_core_tp_put16(m + n - 2, C.vinix_spi_core_tp_crc(m, n - 2))

	}
}

pub fn make_message(m &u8, slots u32, fingers u32, buttons u32) usize {
	unsafe {
	n := 10 + 46 + slots * 30
	expect(!!(n <= (10 + 46 + 30 * 16)), 18, c'n <= TP_MESSAGE_MAX')
	C.memset(voidptr(m), 0, n)
	m[0] = 16
	m[1] = 2
	C.vinix_spi_core_tp_put16(m + 6, u16((n - 10)))
	m[8] = 2
	m[8 + 30] = u8(fingers)
	m[8 + 31] = u8(buttons)
	seal_message(m, n)
	return usize(n)

	}
}

pub fn set_finger(m &u8, i u32, x i32, y i32, major i32) {
	unsafe {
	f := m + 8 + 46 + (i * 30)
	C.vinix_spi_core_tp_put16(f + 4, u16(x))
	C.vinix_spi_core_tp_put16(f + 6, u16(y))
	C.vinix_spi_core_tp_put16(f + 18, u16(major))
	seal_message(m, usize(C.vinix_spi_core_tp_le16(m + 6)) + 10)

	}
}

pub fn make_fragment(p &u8, m &u8, total usize, offset usize, n usize) {
	unsafe {
	expect(!!(offset + n <= total && n <= 246), 36, c'offset + n <= total && n <= 246')
	C.memset(voidptr(p), 0, 256)
	p[0] = 32
	p[1] = 2
	C.vinix_spi_core_tp_put16(p + 2, u16(offset))
	C.vinix_spi_core_tp_put16(p + 4, u16((total - offset - n)))
	C.vinix_spi_core_tp_put16(p + 6, u16(n))
	C.memcpy(voidptr(p + 8), voidptr(m + offset), n)
	seal(p)

	}
}

pub fn feed_message(t &C.touchpad, m &u8, n usize, now u64) {
	unsafe {
	p := [256]u8{}
	for offset := usize(0); offset < n; {
		count := if n - offset > 246 { 246 } else { n - offset }
		make_fragment(&p[0], m, n, offset, count)
		C.vinix_spi_core_tp_decode(t,  &p[0] , 256, now++)
		offset += count
	}

	}
}

pub fn finger(t &C.touchpad, x i32, y i32, button u32, now u64) {
	unsafe {
	m := [536]u8{}
	n := make_message(&m[0], 1, 1, button)
	set_finger(&m[0], 0, x, y, 30)
	feed_message(t,  &m[0] , n, now)

	}
}

pub fn lift(t &C.touchpad, now u64) {
	unsafe {
	m := [536]u8{}
	n := make_message(&m[0], 0, 0, 0)
	feed_message(t,  &m[0] , n, now)

	}
}

pub fn keyboard_packet(p &u8, key u8) {
	unsafe {
	m := [u8(16), u8(1), u8(0), u8(0), u8(0), u8(0), u8(10), u8(0), u8(1), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0)]!

	m[11] = key
	seal_message(&m[0], 20)
	make_fragment(p,  &m[0] , 20, 0, 20)
	p[1] = 1
	seal(p)

	}
}

pub fn test_mode_wire_packet() {
	unsafe {


	t := C.touchpad{}
	C.vinix_spi_core_tp_init(&t, 100)
	p := [256]u8{}
	expect(!!(C.vinix_spi_core_tp_crc(&u8(c'123456789'), 9) == 47933), 73, c'tp_crc((const uint8_t *)\"123456789\", 9) == 0xbb3d')
	C.vinix_spi_core_tp_mode_packet(&t, &p[0], 1000)
	expect(!!(!C.memcmp(voidptr( &p[0] ), voidptr( &mode_prefix[0] ), sizeof([20]u8)) && p[254] == 35 && p[255] == 171), 75, c'!memcmp(p, prefix, sizeof(prefix)) && p[254] == 0x23 && p[255] == 0xab')
	for i := usize(sizeof([20]u8)); i < 254; i++ {
		expect(!!(p[i] == 0), 76, c'p[i] == 0')
	}
	expect(!!(C.vinix_spi_core_tp_crc( &p[0] , 256) == 0 && C.vinix_spi_core_tp_crc( &p[0]  + 8, 12) == 0), 77, c'tp_crc(p, 256) == 0 && tp_crc(p + 8, 12) == 0')
	expect(!!(t.mode_attempts == 1 && t.next_id == 1 && !t.mode_enabled), 78, c't.mode_attempts == 1 && t.next_id == 1 && !t.mode_enabled')
	t.next_id = 255
	C.vinix_spi_core_tp_mode_packet(&t, &p[0], 2000)
	expect(!!(p[11] == 255 && t.next_id == 0 && C.vinix_spi_core_tp_crc( &p[0] , 256) == 0), 80, c'p[11] == 255 && t.next_id == 0 && tp_crc(p, 256) == 0')

	}
}

pub fn test_relative_native_motion() {
	unsafe {
	t := C.touchpad{}
	C.vinix_spi_core_tp_init(&t, 0)
	x := t.x
	y := t.y

	finger(&t, -300, 1000, 0, 100)
	expect(!!(t.x == x && t.y == y && t.tracking && t.mode_enabled), 87, c't.x == x && t.y == y && t.tracking && t.mode_enabled')
	finger(&t, -290, 1020, 0, 200)
	expect(!!(t.x == x + 80 && t.y == y - 160), 89, c't.x == x + 80 && t.y == y - 160')
	m := [536]u8{}
	n := make_message(&m[0], 1, 1, 0)
	set_finger(&m[0], 0, -290, 1020, 30)
	m[8 + 2] = 127
	m[8 + 3] = 128
	seal_message(&m[0], n)
	feed_message(&t,  &m[0] , n, 300)
	expect(!!(t.x == x + 80 && t.y == y - 160), 94, c't.x == x + 80 && t.y == y - 160')
	// no duplicate prefix movement

	}
}

pub fn test_lifts_stale_and_jumps() {
	unsafe {
	t := C.touchpad{}
	C.vinix_spi_core_tp_init(&t, 0)
	finger(&t, 100, 100, 0, 1)
	x := t.x
	y := t.y

	lift(&t, 2)
	finger(&t, -5000, 6000, 0, 3)
	expect(!!(t.x == x && t.y == y), 101, c't.x == x && t.y == y')
	finger(&t, -4990, 6000, 0, 4)
	expect(!!(t.x == x + 80), 102, c't.x == x + 80')
	finger(&t, 6000, 100, 0, 5)
	expect(!!(t.x == x + 80), 103, c't.x == x + 80')
	finger(&t, 6001, 100, 0, 6)
	expect(!!(t.x == x + 88), 104, c't.x == x + 88')
	finger(&t, 6020, 100, 0, 6 + 100000)
	expect(!!(t.x == x + 88), 105, c't.x == x + 88')
	finger(&t, 6021, 100, 0, 7 + 100000)
	expect(!!(t.x == x + 96), 106, c't.x == x + 96')

	}
}

pub fn test_contacts_and_padding() {
	unsafe {
	t := C.touchpad{}
	C.vinix_spi_core_tp_init(&t, 0)
	finger(&t, 0, 0, 0, 1)
	x := t.x
	m := [536]u8{}
	n := make_message(&m[0], 2, 2, 0)
	set_finger(&m[0], 0, 100, 0, 20)
	set_finger(&m[0], 1, 800, 0, 20)
	feed_message(&t,  &m[0] , n, 2)
	expect(!!(!t.tracking && t.x == x), 114, c'!t.tracking && t.x == x')
	finger(&t, 800, 0, 0, 3)
	expect(!!(t.x == x), 115, c't.x == x')
	finger(&t, 801, 0, 0, 4)
	expect(!!(t.x == x + 8), 116, c't.x == x + 8')
	// A zero-area record is not an active finger; advertised slots can be padded.

	n = make_message(&m[0], 3, 2, 0)
	set_finger(&m[0], 0, 2000, 0, 0)
	set_finger(&m[0], 1, 802, 0, 20)
	feed_message(&t,  &m[0] , n, 5)
	expect(!!(t.x == x + 16 && t.tracking), 120, c't.x == x + 16 && t.tracking')
	set_finger(&m[0], 1, 900, 0, 0)
	feed_message(&t,  &m[0] , n, 6)
	expect(!!(!t.tracking && t.x == x + 16), 122, c'!t.tracking && t.x == x + 16')

	}
}

pub fn test_buttons_and_snapshot() {
	unsafe {
	t := C.touchpad{}
	C.vinix_spi_core_tp_init(&t, 0)
	p := [10]i32{}
	for i := u32(0); i < 10; i++ {
		p[i] = 305419896
	}
	expect(!!(!C.vinix_spi_core_tp_snapshot(&t,  &p[0]  + 1)), 128, c'!tp_snapshot(&t, p + 1)')
	finger(&t, 0, 0, 1, 1)
	finger(&t, 0, 0, 0, 2)
	expect(!!(C.vinix_spi_core_tp_snapshot(&t,  &p[0]  + 1)), 130, c'tp_snapshot(&t, p + 1)')
	expect(!!(p[0] == 305419896 && p[9] == 305419896), 131, c'p[0] == 0x12345678 && p[9] == 0x12345678')
	expect(!!(p[5] == 0 && p[6] == 1 && p[7] == 1 && p[8] == 0), 132, c'p[5] == 0 && p[6] == 1 && p[7] == 1 && p[8] == 0')
	expect(!!(C.vinix_spi_core_tp_snapshot(&t,  &p[0]  + 1) && p[6] == 0 && p[7] == 0), 133, c'tp_snapshot(&t, p + 1) && p[6] == 0 && p[7] == 0')
	finger(&t, 0, 0, 1, 3)
	C.vinix_spi_core_tp_snapshot(&t,  &p[0]  + 1)
	C.vinix_spi_core_tp_tick(&t, 99999999)
	// Quiet stationary click must not be released.

	expect(!!(t.buttons == 1), 136, c't.buttons == 1')
	C.vinix_spi_core_tp_discontinuity(&t)
	expect(!!(C.vinix_spi_core_tp_snapshot(&t,  &p[0]  + 1)), 137, c'tp_snapshot(&t, p + 1)')
	expect(!!(p[5] == 0 && p[7] == 1 && t.present), 138, c'p[5] == 0 && p[7] == 1 && t.present')
	expect(!!(!C.vinix_spi_core_tp_snapshot(&t, (voidptr(0)))), 139, c'!tp_snapshot(&t, NULL)')

	}
}

pub fn test_boot_mouse_and_clamping() {
	unsafe {
	t := C.touchpad{}
	C.vinix_spi_core_tp_init(&t, 0)
	r := [u8(2), u8(7), u8(128), u8(127), u8(0), u8(0), u8(0), u8(0)]!

	x := t.x
	y := t.y
	expect(!!(C.vinix_spi_core_tp_report(&t,  &r[0] , sizeof([8]u8), 1)), 146, c'tp_report(&t, r, sizeof(r), 1)')
	expect(!!(t.x == x - 128 * 32 && t.y == y + 127 * 32), 147, c't.x == x - 128 * TP_BOOT_GAIN && t.y == y + 127 * TP_BOOT_GAIN')
	expect(!!(t.buttons == 7 && !t.mode_enabled && !t.tracking), 148, c't.buttons == 7 && !t.mode_enabled && !t.tracking')
	t.x = 1
	t.y = 40959 - 1
	expect(!!(C.vinix_spi_core_tp_report(&t,  &r[0] , sizeof([8]u8), 2) && t.x == 0 && t.y == 40959), 150, c'tp_report(&t, r, sizeof(r), 2) && t.x == 0 && t.y == TP_MAX_Y')
	finger(&t, -32768, -32768, 0, 3)
	finger(&t, -32767, -32767, 0, 4)
	expect(!!(t.x == 8 && t.y == 40959 - 8), 153, c't.x == TP_GAIN && t.y == TP_MAX_Y - TP_GAIN')
	finger(&t, 32767, 32767, 0, 5)
	expect(!!(t.x == 8 && t.y == 40959 - 8), 155, c't.x == TP_GAIN && t.y == TP_MAX_Y - TP_GAIN')
	// rebase, no overflow

	t.x = 65535 - 1
	t.y = 1
	finger(&t, 32766, 32766, 0, 6)
	expect(!!(t.x == 65535 - 1 - 8 && t.y == 1 + 8), 158, c't.x == TP_MAX_X - 1 - TP_GAIN && t.y == 1 + TP_GAIN')

	}
}

pub fn test_all_fragment_splits() {
	unsafe {
	m := [536]u8{}
	p := [256]u8{}
	k := [256]u8{}
	out := [128]u8{}

	n := make_message(&m[0], 1, 1, 1)
	set_finger(&m[0], 0, 200, 300, 40)
	for split := usize(1); split < n; split++ {
		t := C.touchpad{}
		C.vinix_spi_core_tp_init(&t, 0)
		d := C.decoder{}

		make_fragment(&p[0],  &m[0] , n, 0, split)
		C.vinix_spi_core_tp_decode(&t,  &p[0] , 256, 1)
		expect(!!(!t.present && t.used == split), 167, c'!t.present && t.used == split')
		keyboard_packet(&k[0], 4)
		C.vinix_spi_core_tp_decode(&t,  &k[0] , 256, 2)
		expect(!!(C.vinix_spi_core_decode_packet(&d,  &k[0] , 256, 2, 0, &out[0], 128) == 1 && out[0] == `a`), 170, c"decode_packet(&d, k, 256, 2, 0, out, 128) == 1 && out[0] == 'a'")
		k[0] = 64
		k[1] = 2
		seal(&k[0])
		C.vinix_spi_core_tp_decode(&t,  &k[0] , 256, 3)
		expect(!!(t.used == split), 172, c't.used == split')
		make_fragment(&p[0],  &m[0] , n, split, n - split)
		C.vinix_spi_core_tp_decode(&t,  &p[0] , 256, 4)
		expect(!!(t.present && t.buttons == 1 && t.used == 0 && t.reports == 1), 174, c't.present && t.buttons == 1 && t.used == 0 && t.reports == 1')
	}

	}
}

pub fn test_max_contacts_three_packets() {
	unsafe {
	t := C.touchpad{}
	C.vinix_spi_core_tp_init(&t, 0)
	m := [536]u8{}
	n := make_message(&m[0], 16, 16, 1)
	expect(!!(n == 536), 180, c'n == 536')
	for i := u32(0); i < 16; i++ {
		set_finger(&m[0], i, i32(i) * 100, 200, 10)
	}
	feed_message(&t,  &m[0] , n, 1)
	expect(!!(t.native_reports == 1 && !t.tracking && t.buttons == 1 && t.used == 0), 183, c't.native_reports == 1 && !t.tracking && t.buttons == 1 && t.used == 0')

	}
}

pub fn test_fragment_order_total_timeout() {
	unsafe {
	m := [536]u8{}
	p := [256]u8{}

	n := make_message(&m[0], 1, 1, 0)
	t := C.touchpad{}
	C.vinix_spi_core_tp_init(&t, 0)
	make_fragment(&p[0],  &m[0] , n, 10, n - 10)
	C.vinix_spi_core_tp_decode(&t,  &p[0] , 256, 1)
	expect(!!(!t.used), 189, c'!t.used')
	make_fragment(&p[0],  &m[0] , n, 0, 10)
	C.vinix_spi_core_tp_decode(&t,  &p[0] , 256, 2)
	make_fragment(&p[0],  &m[0] , n, 11, n - 11)
	C.vinix_spi_core_tp_decode(&t,  &p[0] , 256, 3)
	expect(!!(!t.used), 191, c'!t.used')
	make_fragment(&p[0],  &m[0] , n, 0, 10)
	C.vinix_spi_core_tp_decode(&t,  &p[0] , 256, 4)
	make_fragment(&p[0],  &m[0] , n, 10, n - 10)
	C.vinix_spi_core_tp_put16( &p[0]  + 4, 1)
	seal(&p[0])
	C.vinix_spi_core_tp_decode(&t,  &p[0] , 256, 5)
	expect(!!(!t.used && !t.present), 194, c'!t.used && !t.present')
	make_fragment(&p[0],  &m[0] , n, 0, 10)
	C.vinix_spi_core_tp_decode(&t,  &p[0] , 256, 6)
	make_fragment(&p[0],  &m[0] , n, 10, n - 10)
	C.vinix_spi_core_tp_decode(&t,  &p[0] , 256, 6 + 100000)
	expect(!!(!t.used && !t.present), 197, c'!t.used && !t.present')
	make_fragment(&p[0],  &m[0] , n, 0, 10)
	C.vinix_spi_core_tp_decode(&t,  &p[0] , 256, 200000)
	C.vinix_spi_core_tp_tick(&t, 200000 + 100000)
	expect(!!(!t.used), 199, c'!t.used')
	feed_message(&t,  &m[0] , n, 400000)
	expect(!!(t.present && t.reports == 1), 200, c't.present && t.reports == 1')

	}
}

pub fn test_bad_crc_lengths_and_identity() {
	unsafe {
	m := [536]u8{}
	p := [256]u8{}

	n := make_message(&m[0], 1, 1, 0)
	bad := [u32(0), u32(247), u32(255), u32(256), u32(65535)]!

	for field := u32(2); field <= 6; field += 2 {
		for i := u32(0); i < 5; i++ {
			if field != 6 && bad[i] == 0 {
				continue
			}
			t := C.touchpad{}
			C.vinix_spi_core_tp_init(&t, 0)
			make_fragment(&p[0],  &m[0] , n, 0, n)
			C.vinix_spi_core_tp_put16( &p[0]  + field, u16(bad[i]))
			seal(&p[0])
			C.vinix_spi_core_tp_decode(&t,  &p[0] , 256, 1)
			expect(!!(!t.present), 211, c'!t.present')
		}
	}
	for size := usize(0); size < 256; size++ {
		t := C.touchpad{}
		C.vinix_spi_core_tp_init(&t, 0)
		make_fragment(&p[0],  &m[0] , n, 0, n)
		C.vinix_spi_core_tp_decode(&t,  &p[0] , size, 1)
		expect(!!(!t.present), 216, c'!t.present')
	}
	for field := u32(0); field < 7; field++ {
		t := C.touchpad{}
		C.vinix_spi_core_tp_init(&t, 0)
		n = make_message(&m[0], 1, 1, 0)
		if field == 0 {
			m[0] = 82
		}
		if field == 1 {
			m[1] = 1
		}
		if field == 2 {
			m[2] = 1
		}
		if field == 3 {
			m[8] = 1
		}
		if field == 4 {
			m[8 + 30] = 2
		}
		if field == 5 {
			C.vinix_spi_core_tp_put16( &m[0]  + 6, u16((n - 11)))
		}
		seal_message(&m[0], n)
		if field == 6 {
			m[n - 1] ^= 128
		}
		// good outer, bad inner CRC

		feed_message(&t,  &m[0] , n, 1)
		expect(!!(!t.present), 228, c'!t.present')
	}
	t := C.touchpad{}
	C.vinix_spi_core_tp_init(&t, 0)
	n = make_message(&m[0], 1, 1, 0)
	make_fragment(&p[0],  &m[0] , n, 0, n)
	p[254] ^= 1
	C.vinix_spi_core_tp_decode(&t,  &p[0] , 256, 1)
	expect(!!(!t.present), 232, c'!t.present')
	make_fragment(&p[0],  &m[0] , n, 0, n)
	p[0] = 64
	seal(&p[0])
	C.vinix_spi_core_tp_decode(&t,  &p[0] , 256, 2)
	expect(!!(!t.present), 234, c'!t.present')
	// A malformed non-integral finger record length is not a valid report.

	C.vinix_spi_core_tp_put16( &m[0]  + 6, u16((n - 11)))
	seal_message(&m[0], n - 1)
	feed_message(&t,  &m[0] , n - 1, 3)
	expect(!!(!t.present), 237, c'!t.present')

	}
}

pub fn test_reset_and_retry_state() {
	unsafe {
	t := C.touchpad{}
	C.vinix_spi_core_tp_init(&t, 0)
	p := [256]u8{}
	m := [u8(16), u8(2), u8(0), u8(0), u8(0), u8(0), u8(1), u8(0), u8(96), u8(0), u8(0)]!

	expect(!!(!C.vinix_spi_core_tp_mode_due(&t, 9999999)), 242, c'!tp_mode_due(&t, 9999999)')
	t.requested = 1
	expect(!!(!C.vinix_spi_core_tp_mode_due(&t, 19999) && C.vinix_spi_core_tp_mode_due(&t, 20000)), 243, c'!tp_mode_due(&t, 19999) && tp_mode_due(&t, 20000)')
	for i := u32(0); i < 3; i++ {
		now := t.mode_at
		expect(!!(C.vinix_spi_core_tp_mode_due(&t, now)), 245, c'tp_mode_due(&t, now)')
		C.vinix_spi_core_tp_mode_packet(&t, &p[0], now)
		expect(!!(!C.vinix_spi_core_tp_mode_due(&t, now + 1)), 246, c'!tp_mode_due(&t, now + 1)')
	}
	expect(!!(!C.vinix_spi_core_tp_mode_due(&t, t.mode_at + 1000000)), 248, c'!tp_mode_due(&t, t.mode_at + TP_RETRY_US)')
	finger(&t, 0, 0, 1, 5000000)
	expect(!!(t.mode_enabled), 249, c't.mode_enabled')
	seal_message(&m[0], sizeof([11]u8))
	feed_message(&t,  &m[0] , sizeof([11]u8), 6000000)
	expect(!!(t.buttons == 0 && t.released == 1 && !t.mode_enabled && t.mode_attempts == 0), 251, c't.buttons == 0 && t.released == 1 && !t.mode_enabled && t.mode_attempts == 0')
	expect(!!(t.requested && C.vinix_spi_core_tp_mode_due(&t, 6010000)), 252, c't.requested && tp_mode_due(&t, 6010000)')

	}
}

struct Mock {
mut:
	regs         [92]u32
	enable       u32
	now          u64
	asserted     u64
	deasserted   u64
	last_clock   u64
	incoming     [256]u8
	status       [4]u8
	fifo         [16]u8
	sent         [32][256]u8
	lengths      [32]usize
	sent_n       [32]usize
	tx_level     u32
	rx_level     u32
	rx_head      u32
	cursor       u32
	stages       u32
	cs_down      u32
	cs_up        u32
	reads        u32
	selected     i32
	run          i32
	stall_length i32
	invalid_fifo i32
	frozen       i32
}

@[export: 'vsf_touchpad_mock_read']
pub fn mock_read(cookie voidptr, addr u64) u32 {
	unsafe {
	m := &Mock(cookie)
	m.reads++
	if !m.frozen {
		m.now++
	}
	if addr == 2097152 {
		return m.enable
	}
	expect(!!(addr >= 1048576 && addr < 1048576 + sizeof([92]u32) && !(addr & 3)), 270, c'addr >= BASE && addr < BASE + sizeof(m->regs) && !(addr & 3)')
	off := u32((addr - 1048576))
	if off == 268 {
		if m.invalid_fifo {
			return if m.invalid_fifo == 1 { 17 << 24 } else { 17 << 8 }
		}
		length := m.regs[76 / 4]
		if m.run && m.stall_length != i32(length) && m.tx_level && m.rx_level < 16 && m.cursor < length {
			m.tx_level--
			source := if length == 4 {  &m.status[0]  } else {  &m.incoming[0]  }
			m.fifo[(m.rx_head + m.rx_level++) % 16] = source[m.cursor++]
			m.last_clock = m.now
		}
		return (m.rx_level << 24) | (m.tx_level << 8)
	}
	if off == 32 {
		expect(!!(m.rx_level), 285, c'm->rx_level')
		m.rx_level--
		value := m.fifo[m.rx_head]
		m.rx_head = (m.rx_head + 1) % 16
		return u32(value)
	}
	return m.regs[off / 4]

	}
}

@[export: 'vsf_touchpad_mock_write']
pub fn mock_write(cookie voidptr, addr u64, value u32) {
	unsafe {
	m := &Mock(cookie)
	if !m.frozen {
		m.now++
	}
	if addr == 2097152 {
		m.enable = value
		return
	}
	expect(!!(addr >= 1048576 && addr < 1048576 + sizeof([92]u32) && !(addr & 3)), 295, c'addr >= BASE && addr < BASE + sizeof(m->regs) && !(addr & 3)')
	off := u32((addr - 1048576))
	if off == 12 && value == 0 {
		expect(!!(!m.selected), 298, c'!m->selected')
		if m.cs_down && !m.frozen {
			expect(!!(m.now - m.deasserted >= 250), 299, c'm->now - m->deasserted >= 250')
		}
		m.selected = 1
		m.cs_down++
		m.asserted = m.now
	}
	if off == 12 && value == 2 && m.selected {
		if !m.frozen {
			expect(!!(m.now - m.last_clock >= 100), 303, c'm->now - m->last_clock >= 100')
		}
		m.selected = 0
		m.cs_up++
		m.deasserted = m.now
	}
	if off == 0 {
		m.run = !!(value & 1)
		if value & 12 {
			m.cursor = 0
			m.rx_head = m.cursor
			m.rx_level = m.rx_head
			m.tx_level = m.rx_level
		}
	}
	if off == 76 {
		expect(!!(m.selected && m.stages < 32), 311, c'm->selected && m->stages < 32')
		if value == 4 && !m.frozen {
			expect(!!(m.now - m.last_clock >= 200), 312, c'm->now - m->last_clock >= 200')
		}
		m.lengths[m.stages++] = value
	}
	if off == 16 {
		expect(!!(m.selected && m.tx_level < 16 && m.stages), 316, c'm->selected && m->tx_level < 16 && m->stages')
		if !m.frozen {
			expect(!!(m.now - m.asserted >= 100), 317, c'm->now - m->asserted >= 100')
		}
		used :=  &m.sent_n[0] + (m.stages - 1)
		expect(!!(( *used ) < m.lengths[m.stages - 1] && value <= 255), 319, c'*used < m->lengths[m->stages - 1] && value <= 255')
		 m.sent[m.stages - 1][(*used)++] = u8(value)
		m.tx_level++
	}
	m.regs[off / 4] = value

	}
}

@[export: 'vsf_touchpad_mock_now']
pub fn mock_now(cookie voidptr) u64 {
	unsafe {
	m := &Mock(cookie)
	if !m.frozen {
		m.now++
	}
	return u64(m.now)

	}
}

@[export: 'vsf_touchpad_mock_delay']
pub fn mock_delay(cookie voidptr, us u32) {
	unsafe {
	(&Mock(cookie)).now += us

	}
}

pub fn setup(m &Mock) C.spi_keyboard {
	unsafe {
	C.memset(voidptr(m), 0, sizeof(Mock))
	m.regs[12 / 4] = 2
	m.status[0] = 172
	m.status[1] = 39
	m.status[2] = 104
	m.status[3] = 213
	k := C.spi_keyboard{}

	k.io = C.io_ops{
		read32:   C.vsf_touchpad_mock_read
		write32:  C.vsf_touchpad_mock_write
		now_us:   C.vsf_touchpad_mock_now
		delay_us: C.vsf_touchpad_mock_delay
	}

	k.cookie = m
	k.spi = 1048576
	k.enable = 2097152
	expect(!!(C.vinix_spi_core_start_keyboard(&k, 120000000, 8000000)), 337, c'start_keyboard(&k, 120000000, 8000000)')
	k.touchpad.requested = 1
	return k

	}
}

pub fn poll_next(k &C.spi_keyboard, out &u8) i32 {
	unsafe {
	m := &Mock(k.cookie)
	if m.now < k.next_poll {
		m.now = k.next_poll
	}
	if m.now < k.next_transfer {
		m.now = k.next_transfer
	}
	return C.vinix_spi_core_poll_keyboard(k, out, 128, 0)

	}
}

pub fn test_spi_write_status_cs() {
	unsafe {
	m := Mock{}
	k := setup(&m)
	out := [128]u8{}
	m.now = k.touchpad.mode_at
	expect(!!(poll_next(&k, &out[0]) == 0 && k.active && k.errors == 0), 352, c'poll_next(&k, out) == 0 && k.active && k.errors == 0')
	expect(!!(m.stages == 2 && m.lengths[0] == 256 && m.lengths[1] == 4), 353, c'm.stages == 2 && m.lengths[0] == 256 && m.lengths[1] == 4')
	expect(!!(m.sent_n[0] == 256 && m.sent_n[1] == 4), 354, c'm.sent_n[0] == 256 && m.sent_n[1] == 4')
	expect(!!(m.cs_down == 1 && m.cs_up == 1 && !m.selected && !m.run), 355, c'm.cs_down == 1 && m.cs_up == 1 && !m.selected && !m.run')
	expect(!!(m.sent[0][0] == 64 && m.sent[0][1] == 2 && C.vinix_spi_core_tp_crc( &m.sent[0][0] , 256) == 0), 356, c'm.sent[0][0] == 0x40 && m.sent[0][1] == 2 && tp_crc(m.sent[0], 256) == 0')
	expect(!!(k.touchpad.mode_errors == 0 && !k.touchpad.mode_enabled), 357, c'k.touchpad.mode_errors == 0 && !k.touchpad.mode_enabled')
	for i := u32(0); i < 4; i++ {
		expect(!!(m.sent[1][i] == 0), 358, c'm.sent[1][i] == 0')
	}

	}
}

pub fn test_spi_write_failures() {
	unsafe {
	for stage := i32(0); stage < 3; stage++ {
		m := Mock{}
		k := setup(&m)
		out := [128]u8{}
		if stage == 0 {
			m.status[0] ^= 1
		}
		if stage == 1 {
			m.stall_length = 256
		}
		if stage == 2 {
			m.stall_length = 4
		}
		m.now = k.touchpad.mode_at
		start := m.now
		expect(!!(poll_next(&k, &out[0]) == 0), 368, c'poll_next(&k, out) == 0')
		expect(!!(m.now - start < 2 * 5000 + 2000), 369, c'm.now - start < 2 * TRANSFER_US + 2000')
		expect(!!(k.active && !k.errors && k.touchpad.mode_errors == 1), 370, c'k.active && !k.errors && k.touchpad.mode_errors == 1')
		expect(!!(!m.run && !m.selected && m.cs_down == m.cs_up), 371, c'!m.run && !m.selected && m.cs_down == m.cs_up')
		expect(!!(m.stages == (if stage == 1 { 1 } else { 2 })), 372, c'm.stages == (stage == 1 ? 1u : 2u)')
		m.stall_length = 0
		keyboard_packet(&m.incoming[0], 4)
		expect(!!(poll_next(&k, &out[0]) == 1 && out[0] == `a`), 374, c"poll_next(&k, out) == 1 && out[0] == 'a'")
	}

	}
}

pub fn test_spi_bad_fifo_and_frozen_clock() {
	unsafe {
	for invalid := i32(1); invalid <= 2; invalid++ {
		m := Mock{}
		k := setup(&m)
		out := [128]u8{}
		m.invalid_fifo = invalid
		m.now = k.touchpad.mode_at
		expect(!!(poll_next(&k, &out[0]) == 0 && k.touchpad.mode_errors == 1), 382, c'poll_next(&k, out) == 0 && k.touchpad.mode_errors == 1')
		expect(!!(!m.selected && !m.run && k.active), 383, c'!m.selected && !m.run && k.active')
	}
	m := Mock{}
	k := setup(&m)
	out := [128]u8{}
	m.now = k.touchpad.mode_at
	m.frozen = 1
	m.stall_length = 256
	expect(!!(poll_next(&k, &out[0]) == 0 && k.touchpad.mode_errors == 1), 387, c'poll_next(&k, out) == 0 && k.touchpad.mode_errors == 1')
	expect(!!(m.reads < 250000 && !m.selected && !m.run), 388, c'm.reads < 250000 && !m.selected && !m.run')

	}
}

pub fn test_shared_poll_to_pointer() {
	unsafe {
	m := Mock{}
	k := setup(&m)
	out := [128]u8{}
	msg := [536]u8{}

	keyboard_packet(&m.incoming[0], 4)
	expect(!!(poll_next(&k, &out[0]) == 1 && out[0] == `a`), 394, c"poll_next(&k, out) == 1 && out[0] == 'a'")
	n := make_message(&msg[0], 1, 1, 1)
	set_finger(&msg[0], 0, 100, 300, 30)
	make_fragment(&m.incoming[0],  &msg[0] , n, 0, n)
	expect(!!(poll_next(&k, &out[0]) == 0 && k.touchpad.native_reports == 1), 397, c'poll_next(&k, out) == 0 && k.touchpad.native_reports == 1')
	set_finger(&msg[0], 0, 110, 320, 30)
	make_fragment(&m.incoming[0],  &msg[0] , n, 0, n)
	expect(!!(poll_next(&k, &out[0]) == 0), 399, c'poll_next(&k, out) == 0')
	p := [8]i32{}
	expect(!!(C.vinix_spi_core_tp_snapshot(&k.touchpad, &p[0])), 400, c'tp_snapshot(&k.touchpad, p)')
	expect(!!(p[0] == (65535 + 1) / 2 + 80 && p[1] == (40959 + 1) / 2 - 160), 401, c'p[0] == (TP_MAX_X + 1) / 2 + 80 && p[1] == (TP_MAX_Y + 1) / 2 - 160')
	expect(!!(p[4] == 1 && p[5] == 1 && k.decoder.reports == 1 && C.vinix_spi_core_has_key( &k.decoder.keys[0] , 4)), 402, c'p[4] == 1 && p[5] == 1 && k.decoder.reports == 1 && has_key(k.decoder.keys, 4)')
	keyboard_packet(&m.incoming[0], 0)
	expect(!!(poll_next(&k, &out[0]) == 0), 403, c'poll_next(&k, out) == 0')
	expect(!!(!k.decoder.repeat_key), 404, c'!k.decoder.repeat_key')

	}
}

pub fn test_feature_waits_for_fragments() {
	unsafe {
	m := Mock{}
	k := setup(&m)
	out := [128]u8{}
	msg := [536]u8{}

	n := make_message(&msg[0], 1, 1, 0)
	k.touchpad.fragment_at = k.touchpad.mode_at
	k.touchpad.used = 10
	k.touchpad.total = n
	C.memcpy(k.touchpad.message, voidptr( &msg[0] ), 10)
	make_fragment(&m.incoming[0],  &msg[0] , n, 10, n - 10)
	m.now = k.touchpad.mode_at
	expect(!!(poll_next(&k, &out[0]) == 0 && k.touchpad.reports == 1), 414, c'poll_next(&k, out) == 0 && k.touchpad.reports == 1')
	expect(!!(m.sent[0][0] == 0 && k.touchpad.mode_attempts == 0), 415, c'm.sent[0][0] == 0 && k.touchpad.mode_attempts == 0')
	// Likewise for an incomplete keyboard report: a release is not stolen.

	k.touchpad.mode_enabled = 0
	k.touchpad.mode_at = m.now
	keyboard_packet(&m.incoming[0], 4)
	C.memcpy(k.decoder.message, voidptr( &m.incoming[0]  + 8), 10)
	k.decoder.message_used = 10
	k.decoder.fragment_at = m.now
	key_msg := [20]u8{}
	C.memcpy(voidptr( &key_msg[0] ), voidptr( &m.incoming[0]  + 8), 20)
	make_fragment(&m.incoming[0],  &key_msg[0] , 20, 10, 10)
	m.incoming[1] = 1
	seal(&m.incoming[0])
	expect(!!(poll_next(&k, &out[0]) == 1 && out[0] == `a`), 423, c"poll_next(&k, out) == 1 && out[0] == 'a'")
	expect(!!(k.touchpad.mode_attempts == 0), 424, c'k.touchpad.mode_attempts == 0')

	}
}

pub fn test_disable_preserves_release() {
	unsafe {
	m := Mock{}
	k := setup(&m)
	out := [128]u8{}
	finger(&k.touchpad, 0, 0, 1, 1)
	p := [8]i32{}
	C.vinix_spi_core_tp_snapshot(&k.touchpad, &p[0])
	m.stall_length = 256
	for i := u32(1); i <= 3; i++ {
		expect(!!(poll_next(&k, &out[0]) == (if i == 3 { -2 } else { -1 })), 432, c'poll_next(&k, out) == (i == 3 ? -2 : -1)')
	}
	expect(!!(!k.active && C.vinix_spi_core_tp_snapshot(&k.touchpad, &p[0]) && p[4] == 0 && p[6] == 1), 433, c'!k.active && tp_snapshot(&k.touchpad, p) && p[4] == 0 && p[6] == 1')
	expect(!!(C.vinix_spi_core_tp_snapshot(&k.touchpad, &p[0]) && p[6] == 0), 434, c'tp_snapshot(&k.touchpad, p) && p[6] == 0')

	}
}

pub fn test_boot_notification_dispatch() {
	unsafe {
	m := Mock{}
	k := setup(&m)
	out := [128]u8{}
	finger(&k.touchpad, 0, 0, 1, 1)
	keyboard_packet(&m.incoming[0], 4)
	expect(!!(poll_next(&k, &out[0]) == 1), 440, c'poll_next(&k, out) == 1')
	C.memset(m.incoming, 0, 256)
	m.incoming[0] = 32
	m.incoming[6] = 4
	m.incoming[8] = 160
	m.incoming[9] = 128
	seal(&m.incoming[0])
	expect(!!(poll_next(&k, &out[0]) == 0), 443, c'poll_next(&k, out) == 0')
	expect(!!(k.touchpad.resets == 1 && !k.touchpad.buttons && !k.decoder.repeat_key), 444, c'k.touchpad.resets == 1 && !k.touchpad.buttons && !k.decoder.repeat_key')
	expect(!!(!k.touchpad.mode_enabled && k.touchpad.requested), 445, c'!k.touchpad.mode_enabled && k.touchpad.requested')

	}
}

__global rng = u32(306738091)

pub fn random32() u32 {
	unsafe {
	rng ^= rng << 13
	rng ^= rng >> 17
	rng ^= rng << 5
	return rng

	}
}

pub fn test_mutation_fuzz() {
	unsafe {
	t := C.touchpad{}
	C.vinix_spi_core_tp_init(&t, 0)
	m := [536]u8{}
	p := [256]u8{}

	for i := u32(0); i < 100000; i++ {
		slots := random32() % 17
		n := make_message(&m[0], slots, slots, random32() & 1)
		for j := u32(0); j < slots; j++ {
			set_finger(&m[0], j, i32((random32() & 65535)) - 32768, i32((random32() & 65535)) - 32768, i32((random32() & 32767)))
		}
		edits := random32() % 5
		for edits-- {
			m[random32() % n] ^= u8(random32())
		}
		if i & 1 {
			seal_message(&m[0], n)
		}
		for off := usize(0); off < n; {
			len := if n - off > 246 { 246 } else { n - off }
			make_fragment(&p[0],  &m[0] , n, off, len)
			changes := random32() % 4
			for changes-- {
				p[random32() % 256] ^= u8(random32())
			}
			if i & 2 {
				seal(&p[0])
			}
			size := if i % 7 { 256 } else { random32() % 256 }
			C.vinix_spi_core_tp_decode(&t,  &p[0] , size, u64(i) * 4000)
			expect(!!(t.used <= (10 + 46 + 30 * 16) && t.total <= (10 + 46 + 30 * 16)), 469, c't.used <= TP_MESSAGE_MAX && t.total <= TP_MESSAGE_MAX')
			expect(!!(t.x >= 0 && t.x <= 65535 && t.y >= 0 && t.y <= 40959), 470, c't.x >= 0 && t.x <= TP_MAX_X && t.y >= 0 && t.y <= TP_MAX_Y')
			expect(!!(t.buttons <= 7 && t.pressed <= 7 && t.released <= 7), 471, c't.buttons <= 7 && t.pressed <= 7 && t.released <= 7')
			off += len
		}
		C.vinix_spi_core_tp_tick(&t, u64(i) * 4000)
		state := [8]i32{}
		C.vinix_spi_core_tp_snapshot(&t, &state[0])
	}

	}
}

pub fn run(test fn (), name &char) {
	unsafe {
	test()
	groups++
	C.printf(c'ok %u - %s\n', groups, name)

	}
}

@[export: 'vinix_spi_touchpad_fixture']
pub fn suite() i32 {
	unsafe {
	run(test_mode_wire_packet, c'golden mode command, both CRCs, sequence wrap')
	run(test_relative_native_motion, c'signed native coordinates, relative motion, inverted Y')
	run(test_lifts_stale_and_jumps, c'lift, stale frame and jump rebasing')
	run(test_contacts_and_padding, c'multiple contacts, zero area and padded slots')
	run(test_buttons_and_snapshot, c'click edges, stationary hold, release and snapshot bounds')
	run(test_boot_mouse_and_clamping, c'boot mouse fallback, signed extremes and clamping')
	run(test_all_fragment_splits, c'all 85 splits with keyboard and write-response interleaving')
	run(test_max_contacts_three_packets, c'16 contacts reassembled across three SPI packets')
	run(test_fragment_order_total_timeout, c'fragment order, total consistency and expiry')
	run(test_bad_crc_lengths_and_identity, c'malformed lengths, CRCs and report identities')
	run(test_reset_and_retry_state, c'opt-in mode request, bounded retries and reset recovery')
	run(test_spi_write_status_cs, c'PIO command plus four-byte status with continuous CS')
	run(test_spi_write_failures, c'bad status and write/status timeouts preserve keyboard')
	run(test_spi_bad_fifo_and_frozen_clock, c'invalid FIFO counts and stalled counter are bounded')
	run(test_shared_poll_to_pointer, c'shared SPI poll to keyboard and pointer snapshots')
	run(test_feature_waits_for_fragments, c"mode writes do not interrupt either device's fragments")
	run(test_disable_preserves_release, c'transport disable preserves final button release')
	run(test_boot_notification_dispatch, c'boot notification resets both input paths')
	run(test_mutation_fuzz, c'100000 deterministic mutated touchpad messages')
	C.printf(c'PASS: %u touchpad test groups\n', groups)
	return 0

	}
}
