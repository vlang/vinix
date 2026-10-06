@[translated]
module spicore

#include "apple_spi_keyboard.h"
#include "apple_platform_io.h"

// SPDX-License-Identifier: GPL-2.0-or-later

// Called only after the V platform layer has validated and mapped the DT
// *resources, enabled their power domains, and configured the SPI pinmux.
// *All addresses are mapped virtual addresses, not physical addresses.
// *ready_reg == 0 selects timer-only polling. A successful init does not
// *establish that a spi_controller has actually returned a valid input report.

// Non-reentrant: the V wrapper serializes calls. At most one bounded SPI
// *transaction per call (a feature write includes its 4-byte status stage).
// *Returns bytes produced, -1 for a recoverable transfer/protocol error, -2
// *when repeated errors temporarily disable the device, or -3 after it has
// *been reset and recovered.

// Whether Caps Lock is on; the console answers KDGETLED with it.

// Request touchpad mode, then snapshot: no SPI access in this function.
// *The shared poller performs mode setup. Eight words in /dev/pointer order.
// *Returns 0 until a valid touchpad report has arrived, 1 thereafter. This
// *consumes button edges; serialize with keyboard_poll using the V lock.

// SPDX-License-Identifier: GPL-2.0-or-later
// *Apple SPI touchpad protocol and relative-pointer decoder.
// * *Protocol references: Asahi Linux spi-hid-apple-core.c (The Asahi Linux
// *Contributors) and hid-magicmouse.c (Michael Poole, Chase Douglas and
// *contributors). This is a bounded, allocation-free implementation, not a
// *Linux input-layer port. See docs/apple-spi-touchpad.md for references.
// Internal to the shared V SPI core: one owner, one lock, one controller.
// Host fixtures link this production implementation through its C ABI.

// 8-byte mouse prefix + 38-byte vendor header

// Logical 16:10 pointer space, NOT a claim about sensor dimensions. The
// *desktop scales this range to its framebuffer. Integer subpixel positions
// *retain slow motion between frames without floating point.

pub struct Touchpad {
pub mut:
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

@[export: 'vinix_spi_core_tp_le16']
pub fn tp_le16(p &u8) u16 {
	unsafe {
		return u16((i32(u16(p[0])) | i32(u16((i32(u16(p[1])) << 8)))))
	}
}

@[export: 'vinix_spi_core_tp_s16']
pub fn tp_s16(p &u8) i32 {
	unsafe {
		n := u32(tp_le16(p))
		return if n < 32768 { i32(n) } else { i32(n) - 65536 }
	}
}

@[export: 'vinix_spi_core_tp_s8']
pub fn tp_s8(n u8) i32 {
	unsafe {
		return if u32(n) < 128 { i32(n) } else { i32(n) - 256 }
	}
}

@[export: 'vinix_spi_core_tp_put16']
pub fn tp_put16(p &u8, n u16) {
	unsafe {
		p[0] = u8(n)
		p[1] = u8((i32(n) >> 8))
	}
}

@[export: 'vinix_spi_core_tp_crc']
pub fn tp_crc(p &u8, n usize) u16 {
	unsafe {
		mut crc := u16(0)
		for i := usize(0); i < n; i++ {
			crc ^= u16(p[i])
			for b := u32(0); b < 8; b++ {
				crc = (crc >> 1) ^ if crc & 1 != 0 { u16(0xa001) } else { u16(0) }
			}
		}
		return crc
	}
}

@[export: 'vinix_spi_core_tp_buttons']
pub fn tp_buttons(t &Touchpad, buttons u32) {
	unsafe {
		buttons &= 7
		t.pressed |= buttons & ~t.buttons
		t.released |= t.buttons & ~buttons
		t.buttons = buttons
	}
}

// On a known discontinuity, discard the motion baseline and release buttons.
// *Keep position and accumulated edges, including a release owed to userspace.
// *Do not release a stationary held click merely because the device is quiet.

@[export: 'vinix_spi_core_tp_discontinuity']
pub fn tp_discontinuity(t &Touchpad) {
	unsafe {
		t.used = usize(0)
		t.total = usize(0)
		t.tracking = 0
		tp_buttons(t, u32(0))
	}
}

@[export: 'vinix_spi_core_tp_bad']
pub fn tp_bad(t &Touchpad) {
	unsafe {
		t.bad_packets++
		tp_discontinuity(t)
	}
}

@[export: 'vinix_spi_core_tp_restart']
pub fn tp_restart(t &Touchpad, now u64) {
	unsafe {
		tp_discontinuity(t)
		t.mode_enabled = 0
		t.mode_attempts = u32(0)
		t.mode_at = now + u64(10000)
		t.resets++
	}
}

@[export: 'vinix_spi_core_tp_init']
pub fn tp_init(t &Touchpad, first_poll u64) {
	unsafe {
		*t = Touchpad{}

		t.x = (65535 + 1) / 2
		t.y = (40959 + 1) / 2
		// First drain the boot notification instead of writing during startup.

		t.mode_at = first_poll + u64(20000)
	}
}

@[export: 'vinix_spi_core_tp_tick']
pub fn tp_tick(t &Touchpad, now u64) {
	unsafe {
		if t.used && now - t.fragment_at >= u64(100000) {
			tp_bad(t)
		}
	}
}

@[export: 'vinix_spi_core_tp_mode_due']
pub fn tp_mode_due(t &Touchpad, now u64) i32 {
	unsafe {
		return i32(t.requested && !t.mode_enabled && !t.used && t.mode_attempts < 3 && now >= t.mode_at)
	}
}

// SET_REPORT(HID_FEATURE_REPORT), report 2, payload {2, 1}. Framed reply
// *length is 2. The 4-byte SPI status is a separate stage under the SAME CS.
// *A valid input report, not the SPI status alone, confirms native mode.

@[export: 'vinix_spi_core_tp_mode_packet']
pub fn tp_mode_packet(t &Touchpad, p &u8, now u64) {
	unsafe {
		for i := usize(0); i < usize(256); i++ {
			p[i] = u8(0)
		}
		p[0] = u8(64)
		p[1] = u8(2)
		tp_put16(p + 6, u16(12))
		p[8] = u8(82)
		p[9] = u8(2)
		mut __c2v_postfix_value_0 := t.next_id
		t.next_id++
		p[11] = __c2v_postfix_value_0
		tp_put16(p + 12, u16(2))
		tp_put16(p + 14, u16(2))
		p[16] = u8(2)
		p[17] = u8(1)
		tp_put16(p + 18, tp_crc(p + 8, usize(10)))
		tp_put16(p + 254, tp_crc(p, usize(254)))
		t.mode_attempts++
		t.mode_at = now + u64(1000000)
	}
}

@[export: 'vinix_spi_core_tp_clamp']
pub fn tp_clamp(value i32, maximum i32) i32 {
	unsafe {
		return if value < 0 {
			0
		} else {
			if value > maximum { maximum } else { value }
		}
	}
}

@[export: 'vinix_spi_core_tp_move']
pub fn tp_move(t &Touchpad, dx i32, dy i32, gain i32) {
	unsafe {
		// Callers bound deltas to signed 16-bit differences or signed 8 bits.

		t.x = tp_clamp(t.x + dx * gain, 65535)
		t.y = tp_clamp(t.y + dy * gain, 40959)
	}
}

@[export: 'vinix_spi_core_tp_report']
pub fn tp_report(t &Touchpad, r &u8, n usize, now u64) i32 {
	unsafe {
		if n == usize(0) {
			return 0
		}
		if i32(r[0]) == 96 {
			tp_restart(t, now)
			return 1
		}
		if i32(r[0]) != 2 {
			return 0
		}
		// Boot mouse reports use signed relative bytes. Native reports contain
		//     *this same prefix, but its deltas MUST NOT be added to finger motion.

		if n == usize(8) {
			t.tracking = 0
			t.present = 1
			t.reports++
			tp_buttons(t, u32(r[1]))
			tp_move(t, tp_s8(r[2]), tp_s8(r[3]), 32)
			t.report_at = now
			return 1
		}
		if n < usize(46) || (n - usize(46)) % usize(30) != usize(0) {
			return 0
		}
		slots := (n - usize(46)) / usize(30)
		fingers := u32(r[30])
		if slots > usize(16) || usize(fingers) > slots {
			return 0
		}
		contacts := u32(0)
		x := i32(0)
		y := i32(0)

		for i := u32(0); i < fingers; i++ {
			f := r + 46 + (i * 30)
			if tp_s16(f + 18) <= 0 {
				continue
			}
			// touch_major: actual contact

			x = tp_s16(f + 4)
			y = -tp_s16(f + 6)
			// Apple's sensor Y axis points upwards.

			contacts++
		}
		t.present = 1
		t.mode_enabled = 1
		t.reports++
		t.native_reports++
		tp_buttons(t, u32(r[31]) & 1)
		if contacts == u32(1) {
			if t.tracking && now - t.report_at < u64(100000) {
				dx := x - t.previous_x
				dy := y - t.previous_y
				// There is no documented stable contact ID in these records.
				//             *Rebase on implausible jumps instead of moving across the screen.

				if dx >= -2048 && dx <= 2048 && dy >= -2048 && dy <= 2048 {
					tp_move(t, dx, dy, 8)
				}
			}
			t.previous_x = x
			t.previous_y = y
			t.tracking = 1
		} else {
			// Zero fingers = lift. Multiple fingers = no cursor motion. Never
			//         *choose an arbitrary array slot as a persistent tracking identity.

			t.tracking = 0
		}
		t.report_at = now
		return 1
	}
}

@[export: 'vinix_spi_core_tp_decode']
pub fn tp_decode(t &Touchpad, p &u8, size usize, now u64) {
	unsafe {
		if size != usize(256) {
			tp_bad(t)
			return
		}
		// Keyboard and write responses cannot mutate pointer/fragment state.

		if i32(p[0]) != 32 || i32(p[1]) != 2 {
			return
		}
		if i32(tp_crc(p, size)) != 0 {
			tp_bad(t)
			return
		}
		offset := usize(tp_le16(p + 2))
		remaining := usize(tp_le16(p + 4))
		n := usize(tp_le16(p + 6))
		if !n || n > usize(246) || offset > usize((10 + 46 + 30 * 16)) || n > usize((10 + 46 + 30 * 16)) - offset || remaining > usize((10 + 46 + 30 * 16)) - offset - n {
			tp_bad(t)
			return
		}
		total := offset + n + remaining
		if total < usize(11) {
			tp_bad(t)
			return
		}
		if offset == usize(0) {
			if t.used {
				tp_discontinuity(t)
			}
			// missing end of previous report

			t.total = total
			t.fragment_at = now
		} else if !t.used || now - t.fragment_at >= u64(100000) {
			tp_bad(t)
			return
		}
		if offset != t.used || total != t.total {
			tp_bad(t)
			return
		}
		for i := usize(0); i < n; i++ {
			t.message[offset + i] = p[usize(8) + i]
		}
		t.used += n
		if remaining {
			return
		}
		t.used = usize(0)
		t.total = usize(0)
		m := &u8(&t.message[0])
		if i32(tp_crc(m, total)) || usize(tp_le16(m + 6)) != total - usize(10) || i32(m[0]) != 16 || i32(m[2]) != 0 || (i32(m[8]) != 96 && i32(m[1]) != 2) {
			tp_bad(t)
			return
		}
		if !tp_report(t, m + 8, total - usize(10), now) {
			tp_bad(t)
		}
	}
}

// Plain 32-bit words avoid coupling the C decoder to a V struct layout.
// *Called under the same lock as poll. Edges are consumed exactly once.

@[export: 'vinix_spi_core_tp_snapshot']
pub fn tp_snapshot(t &Touchpad, out &i32) i32 {
	unsafe {
		if (usize(out) == 0) || !t.present {
			return 0
		}
		out[0] = t.x
		out[1] = t.y
		out[2] = 65535
		out[3] = 40959
		out[4] = i32(t.buttons)
		out[5] = i32(t.pressed)
		out[6] = i32(t.released)
		out[7] = 0
		// Wheel/gesture synthesis is deliberately not implemented.

		t.pressed = u32(0)
		t.released = u32(0)
		return 1
	}
}

// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.
// SPDX-License-Identifier: GPL-2.0-or-later
// * *Apple SPI shared spi_controller/touchpad transport and console decoder.
// *Register/protocol reference: U-Boot drivers/spi/apple_spi.c and
// *drivers/input/apple_spi_kbd.c, Copyright (C) 2021 Mark Kettenis and
// *Copyright The Asahi Linux Contributors, GPL-2.0-or-later.
// *Message/packet CRC framing is also documented by the Asahi Linux
// *drivers/hid/spi-hid/spi-hid-apple-core.c transport.
// * *No allocation, DMA, firmware upload, interrupt handler, or USB dependency.
// *The small I/O interface is used unchanged by the production driver and the
// *host tests. DT discovery and locking belong to apple.spi_keyboard in V.
//

// 8-byte header + 10-byte report + 2-byte CRC

// How long the transport stays down before it is brought back up. Long enough
// *that genuinely dead hardware is not hammered, short enough that a user who
// *looked away does not come back to a machine that takes no input.

pub struct Key_bytes {
	// Long enough for the longest sequence a key can produce, which is the
	//     *report that Cmd has been let go rather than anything on a keycap.

pub mut:
	data [16]u8
	len  usize
}

pub struct Decoder {
pub mut:
	keys       [6]u8
	modifiers  u8
	fn_        u8
	caps       u8
	repeat_key u8
	// Whether a chord was sent while Cmd was down. The desktop's window
	//     *switcher is drawn for as long as Cmd is held, so unlike every other
	//     *modifier this one's release has to be reported -- but only to someone
	//     *who asked, which is what pressing Cmd-Tab counts as.
	gui_chorded  u8
	alt_tab_chorded u8
	repeat_at    u64
	message      [20]u8
	message_used usize
	fragment_at  u64
	reports      u64
}

pub struct Io_ops {
pub mut:
	read32   fn (voidptr, u64) u32
	write32  fn (voidptr, u64, u32)
	now_us   fn (voidptr) u64
	delay_us fn (voidptr, u32)
}

pub struct Spi_keyboard {
pub mut:
	io         Io_ops
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
	decoder       Decoder
	touchpad      Touchpad
}

@[export: 'vinix_spi_core_read_le16']
pub fn read_le16(p &u8) u16 {
	unsafe {
		return u16((i32(u16(p[0])) | (i32(u16(p[1])) << 8)))
	}
}

// CRC-16/ARC: reflected polynomial 0xa001, initial value 0. Appending the
// *little-endian CRC makes the CRC of the complete packet/message zero.

@[export: 'vinix_spi_core_crc16']
pub fn crc16(p &u8, n usize) u16 {
	unsafe {
		mut crc := u16(0)
		for i := usize(0); i < n; i++ {
			crc ^= u16(p[i])
			for b := u32(0); b < 8; b++ {
				crc = (crc >> 1) ^ if crc & 1 != 0 { u16(0xa001) } else { u16(0) }
			}
		}
		return crc
	}
}

@[export: 'vinix_spi_core_has_key']
pub fn has_key(keys &u8, key u8) i32 {
	unsafe {
		for i := u32(0); i < u32(6); i++ {
			if i32(keys[i]) == i32(key) {
				return 1
			}
		}
		return 0
	}
}

@[export: 'vinix_spi_core_cancel_repeat']
pub fn cancel_repeat(d &Decoder) {
	unsafe {
		d.repeat_at = u64(0)
		d.message_used = usize(0)
	}
}

@[export: 'vinix_spi_core_reset_input']
pub fn reset_input(d &Decoder) {
	unsafe {
		cancel_repeat(d)
		d.repeat_key = u8(0)
		d.gui_chorded = u8(0)
		d.alt_tab_chorded = u8(0)
		d.modifiers = u8(0)
		d.fn_ = u8(0)
		for i := u32(0); i < u32(6); i++ {
			d.keys[i] = u8(0)
		}
		// Caps Lock is logical console state, not a physically held key.
	}
}

@[export: 'vinix_spi_core_sequence']
pub fn sequence(out &Key_bytes, s &char) {
	unsafe {
		mut i := usize(0)
		for s[i] != 0 && out.len < sizeof(out.data) {
			out.data[out.len++] = u8(s[i])
			i++
		}
	}
}

@[export: 'vinix_spi_core_decimal']
pub fn decimal(out &Key_bytes, value u32) {
	unsafe {
		divisor := u32(1)
		for divisor <= value / u32(10) {
			divisor *= u32(10)
		}
		for {
			if out.len >= sizeof([16]u8) {
				return
			}
			out.data[out.len++] = u8((u32(`0`) + value / divisor % u32(10)))
			divisor /= u32(10)
			// while()
			if !divisor {
				break
			}
		}
	}
}

@[export: 'vinix_spi_core_csi_u']
pub fn csi_u(out &Key_bytes, codepoint u32, modifiers u32) {
	unsafe {
		sequence(out, c'\033[')
		decimal(out, codepoint)
		sequence(out, c';')
		decimal(out, u32(1) + modifiers)
		sequence(out, c'u')
	}
}

@[export: 'vinix_spi_core_modified_arrow']
pub fn modified_arrow(out &Key_bytes, final i8, modifiers u32) {
	unsafe {
		sequence(out, c'\033[1;')
		decimal(out, u32(1) + modifiers)
		if out.len < sizeof([16]u8) {
			out.data[out.len++] = u8(final)
		}
	}
}

@[export: 'vinix_spi_core_encode_key']
pub fn encode_key(key u8, modifiers u8, caps i32, fn_ i32, application_cursor i32) Key_bytes {
	unsafe {
		out := Key_bytes{}

		shift := i32(!!(u32(modifiers) & 34))
		ctrl := i32(!!(u32(modifiers) & 17))
		alt := i32(!!(u32(modifiers) & 68))
		gui := i32(!!(u32(modifiers) & 136))
		c := u8(0)
		printable := i32(0)
		s := &char(nil)
		// Fn is an extra byte in Apple's report, not a HID modifier bit.

		if fn_ {
			match i32(key) {
				42 {
					key = u8(76)

					// Fn-Backspace: forward delete
				}
				79 {
					key = u8(77)

					// Fn-Right: End
				}
				80 {
					key = u8(74)

					// Fn-Left: Home
				}
				81 {
					key = u8(78)

					// Fn-Down: Page Down
				}
				82 {
					key = u8(75)

					// Fn-Up: Page Up
				}
				else {
				}
			}
		}
		// Preserve GUI chords in the console stream for graphical compositors.

		if gui && i32(key) == 43 {
			csi_u(&out, u32(9), 8 | u32(shift))
			return out
		}
		if alt && !gui && !ctrl && i32(key) == 43 {
			csi_u(&out, u32(9), 2 | u32(shift))
			return out
		}
		if alt && !gui && !ctrl && !shift && i32(key) == 61 {
			sequence(&out, c'\033[1;3S')
			return out
		}
		if gui && i32(key) >= 79 && i32(key) <= 82 {
			encode_key_finals := [i8(`C`), i8(`D`), i8(`B`), i8(`A`)]!

			mods := 8 | u32(shift) | (u32(alt) << 1) | (u32(ctrl) << 2)
			modified_arrow(&out, i8(encode_key_finals[i32(key) - 79]), mods)
			return out
		}
		if i32(key) >= 4 && i32(key) <= 29 {
			c = u8(((if shift ^ i32(!!caps) { `A` } else { `a` }) + i32(key) - 4))
			printable = 1
		} else if i32(key) >= 30 && i32(key) <= 39 {
			c = if shift { u8(c'!@#$%^&*()'[i32(key) - 30]) } else { u8(c'1234567890'[i32(key) - 30]) }
			printable = 1
		} else {
			match i32(key) {
				40, 88 {
					c = u8(`\r`)
				}
				41 {
					c = u8(27)
				}
				42 {
					c = u8(`\b`)

					// Vinix's current canonical erase byte
				}
				43 {
					if shift {
						s = c'\033[Z'
					} else {
						c = u8(`\t`)
					}
				}
				44 {
					c = u8(` `)
					printable = 1
				}
				45 {
					c = u8(if shift { `_` } else { `-` })
					printable = 1
				}
				46 {
					c = u8(if shift { `+` } else { `=` })
					printable = 1
				}
				47 {
					c = u8(if shift { `{` } else { `[` })
					printable = 1
				}
				48 {
					c = u8(if shift { `}` } else { `]` })
					printable = 1
				}
				49 {
					c = u8(if shift { `|` } else { `\\` })
					printable = 1

					// The ISO key has no US character. It types the § and ± Apple's US
					//         *layout prints on it, which name it uniquely for the desktop's
					//         *keyboard layouts to put their own characters on.
				}
				100 {
					if gui {
						return out
					}
					s = if shift { c'\302\261' } else { c'\302\247' }
				}
				50 {
					c = u8(if shift { `~` } else { `#` })
					printable = 1
				}
				51 {
					c = u8(if shift { `:` } else { `;` })
					printable = 1
				}
				52 {
					c = u8(if shift { `\"` } else { `\'` })
					printable = 1
				}
				53 {
					c = u8(if shift { `~` } else { u8(96) })
					printable = 1
				}
				54 {
					c = u8(if shift { `<` } else { `,` })
					printable = 1
				}
				55 {
					c = u8(if shift { `>` } else { `.` })
					printable = 1
				}
				56 {
					c = u8(if shift { `?` } else { `/` })
					printable = 1
				}
				58 {
					s = c'\033OP'
				}
				59 {
					s = c'\033OQ'
				}
				60 {
					s = c'\033OR'
				}
				61 {
					s = c'\033OS'
				}
				62 {
					s = c'\033[15~'
				}
				63 {
					s = c'\033[17~'
				}
				64 {
					s = c'\033[18~'
				}
				65 {
					s = c'\033[19~'
				}
				66 {
					s = c'\033[20~'
				}
				67 {
					s = c'\033[21~'
				}
				68 {
					s = c'\033[23~'
				}
				69 {
					s = c'\033[24~'
				}
				73 {
					s = c'\033[2~'
				}
				74 {
					s = if application_cursor { c'\033OH' } else { c'\033[H' }
				}
				75 {
					s = c'\033[5~'
				}
				76 {
					s = c'\033[3~'
				}
				77 {
					s = if application_cursor { c'\033OF' } else { c'\033[F' }
				}
				78 {
					s = c'\033[6~'
				}
				79 {
					s = if application_cursor { c'\033OC' } else { c'\033[C' }
				}
				80 {
					s = if application_cursor { c'\033OD' } else { c'\033[D' }
				}
				81 {
					s = if application_cursor { c'\033OB' } else { c'\033[B' }
				}
				82 {
					s = if application_cursor { c'\033OA' } else { c'\033[A' }

					// Unknown/reserved/lock/media keys
				}
				else {
					return out
				}
			}
		}
		if gui && i32(c) {
			mods := 8 | u32(shift) | (u32(alt) << 1) | (u32(ctrl) << 2)
			csi_u(&out, u32(c), mods)
			return out
		}
		if alt {
			out.data[out.len++] = u8(27)
		}
		if s {
			sequence(&out, s)
			return out
		}
		if ctrl && printable {
			if (i32(c) >= `@` && i32(c) <= `_`) || (i32(c) >= `a` && i32(c) <= `z`) {
				c &= 31
			} else if i32(c) == ` ` || i32(c) == `2` {
				c = u8(0)
			} else if i32(c) == `6` {
				c = u8(30)
			} else if i32(c) == `-` {
				c = u8(31)
			} else if i32(c) == `?` || i32(c) == `8` {
				c = u8(127)
			}
		}
		out.data[out.len++] = c
		return out
	}
}

@[export: 'vinix_spi_core_append_key']
pub fn append_key(out &u8, capacity usize, used &usize, key Key_bytes) i32 {
	unsafe {
		// Drop a whole sequence rather than leaving a partial terminal escape.

		if key.len == usize(0) || (*used) > capacity || key.len > capacity - (*used) {
			return 0
		}
		for i := usize(0); i < key.len; i++ {
			out[(*used)++] = key.data[i]
		}
		return 1
	}
}

@[export: 'vinix_spi_core_accept_report']
pub fn accept_report(d &Decoder, report &u8, now u64, app i32, out &u8, capacity usize) usize {
	unsafe {
		keys := [6]u8{}
		used := usize(0)
		d.modifiers = report[1]
		d.fn_ = u8(!!report[9])
		d.reports++
		// Cmd let go. Nothing on a terminal has ever wanted to hear about a
		//     *modifier's release, so this only goes out when a chord was sent while it
		//     *was down. It is the left Super key in the CSI-u functional encoding,
		//     *with an event type of 3, "released".

		if i32(d.gui_chorded) && !(u32(d.modifiers) & 136) {
			release := Key_bytes{}

			d.gui_chorded = u8(0)
			sequence(&release, c'\033[57444;1:3u')
			append_key(out, capacity, &used, release)
		}
		if i32(d.alt_tab_chorded) && !(u32(d.modifiers) & 68) {
			release := Key_bytes{}
			d.alt_tab_chorded = u8(0)
			sequence(&release, c'\033[57443;1:3u')
			append_key(out, capacity, &used, release)
		}
		for i := u32(0); i < u32(6); i++ {
			key := report[i + u32(3)]
			// ErrorRollOver, POSTFail, ErrorUndefined are not key releases.
			//         *Keep the last good set but suppress repeat until a good report.

			if i32(key) >= 1 && i32(key) <= 3 {
				d.repeat_at = u64(0)
				return usize(0)
			}
			if i32(key) && !has_key(&keys[0], key) {
				keys[i] = key
			}
		}
		if has_key(&keys[0], u8(57)) && !has_key(&d.keys[0], u8(57)) {
			d.caps = u8(!d.caps)
		}
		if i32(d.repeat_key) && !has_key(&keys[0], d.repeat_key) {
			d.repeat_key = u8(0)
			d.repeat_at = u64(0)
		}
		for i := u32(0); i < u32(6); i++ {
			key := keys[i]
			if !key || i32(key) == 57 || has_key(&d.keys[0], key) {
				continue
			}
			bytes := encode_key(key, d.modifiers, i32(d.caps), i32(d.fn_), app)
			if append_key(out, capacity, &used, bytes) {
				d.repeat_key = key
				d.repeat_at = now + u64(500000)
				if u32(d.modifiers) & 136 {
					d.gui_chorded = u8(1)
				}
				if key == u8(43) && u32(d.modifiers) & 68 != 0
					&& u32(d.modifiers) & 153 == 0 {
					d.alt_tab_chorded = u8(1)
				}
			}
		}
		for i := u32(0); i < u32(6); i++ {
			d.keys[i] = keys[i]
		}
		if i32(d.repeat_key) && d.repeat_at == u64(0) {
			d.repeat_at = now + u64(500000)
		}
		return usize(used)
	}
}

// Returns bytes produced. Touchpad, management, boot status and write
// *responses never become keystrokes. Only the known 20-byte spi_controller message
// *is reassembled; arbitrary-sized HID descriptors/reports are out of scope.

@[export: 'vinix_spi_core_decode_packet']
pub fn decode_packet(d &Decoder, packet &u8, length usize, now u64, app i32, out &u8, capacity usize) usize {
	unsafe {
		if length != usize(256) {
			cancel_repeat(d)
			return usize(0)
		}
		if i32(packet[0]) != 32 || i32(packet[1]) != 1 {
			return usize(0)
		}
		if i32(crc16(packet, usize(256))) != 0 {
			cancel_repeat(d)
			return usize(0)
		}
		offset := usize(read_le16(packet + 2))
		remaining := usize(read_le16(packet + 4))
		n := usize(read_le16(packet + 6))
		if !n || n > usize(20) || offset > usize(20) || remaining > usize(20) || offset + n + remaining != usize(20) {
			cancel_repeat(d)
			return usize(0)
		}
		if offset == usize(0) {
			d.message_used = usize(0)
			d.fragment_at = now
		} else if d.message_used == usize(0) || now - d.fragment_at >= u64(100000) {
			cancel_repeat(d)
			return usize(0)
		}
		if offset != d.message_used || n > usize(20) - offset {
			cancel_repeat(d)
			return usize(0)
		}
		for i := usize(0); i < n; i++ {
			d.message[offset + i] = packet[usize(8) + i]
		}
		d.message_used += n
		if remaining {
			d.repeat_at = u64(0)
			return usize(0)
		}
		d.message_used = usize(0)
		m := &u8(&d.message[0])
		if i32(crc16(m, usize(20))) || i32(m[0]) != 16 || i32(m[1]) != 1 || i32(read_le16(m + 6)) != 10 || i32(m[8]) != 1 {
			cancel_repeat(d)
			return usize(0)
		}
		return usize(accept_report(d, m + 8, now, app, out, capacity))
	}
}

@[export: 'vinix_spi_core_repeat_key']
pub fn repeat_key(d &Decoder, now u64, app i32, out &u8, capacity usize) usize {
	unsafe {
		used := usize(0)
		if !d.repeat_at || now < d.repeat_at || d.message_used {
			return usize(0)
		}
		if !d.repeat_key || !has_key(&d.keys[0], d.repeat_key) {
			d.repeat_at = u64(0)
			return usize(0)
		}
		append_key(out, capacity, &used, encode_key(d.repeat_key, d.modifiers, i32(d.caps), i32(d.fn_), app))
		// Modifiers can change while Tab is already repeating. Arm the
		// release whenever the Alt chord was actually delivered.
		if used != 0 && d.repeat_key == u8(43) && u32(d.modifiers) & 68 != 0
			&& u32(d.modifiers) & 153 == 0 {
			d.alt_tab_chorded = u8(1)
		}
		// Never emit an unbounded catch-up burst after a scheduler stall.

		d.repeat_at = now + u64(33333)
		return usize(used)
	}
}

@[export: 'vinix_spi_core_reg_read']
pub fn reg_read(k &Spi_keyboard, offset u32) u32 {
	unsafe {
		return k.io.read32(voidptr(k.cookie), k.spi + u64(offset))
	}
}

@[export: 'vinix_spi_core_reg_write']
pub fn reg_write(k &Spi_keyboard, offset u32, value u32) {
	unsafe {
		k.io.write32(voidptr(k.cookie), k.spi + u64(offset), value)
	}
}

@[export: 'vinix_spi_core_set_enable']
pub fn set_enable(k &Spi_keyboard, enabled i32) {
	unsafe {
		v := k.io.read32(voidptr(k.cookie), k.enable)
		// GPIO MODE=OUT(1), PERIPH=0. Preserve pull/drive and unrelated bits.

		v &= ~(1 | (7 << 1) | (3 << 5))
		v |= 2 | u32((i32(!!enabled) ^ i32(!!k.enable_low)))
		k.io.write32(voidptr(k.cookie), k.enable, v)
	}
}

@[export: 'vinix_spi_core_start_keyboard']
pub fn start_keyboard(k &Spi_keyboard, input_hz u32, maximum_hz u32) i32 {
	unsafe {
		if !input_hz || !maximum_hz || maximum_hz > 8000000 {
			return 0
		}
		k.input_hz = input_hz
		k.maximum_hz = maximum_hz
		divider := (u64(input_hz) + u64(maximum_hz) - u64(1)) / u64(maximum_hz)
		if divider < u64(2) {
			divider = u64(2)
		}
		if divider > u64(2047) {
			return 0
		}
		// Do not silently exceed the DT maximum.

		k.active = 0
		reg_write(k, u32(0), u32(0))
		reg_write(k, u32(12), 2)
		reg_write(k, u32(304), u32(0))
		reg_write(k, u32(312), u32(0))
		reg_write(k, u32(336), reg_read(k, u32(336)) & ~(1 << 24))
		reg_write(k, u32(340), (reg_read(k, u32(340)) & ~(1 << 9)) | (1 << 1))
		reg_write(k, u32(0), 12)
		// Match Apple's/U-Boot's PIO FIFO configuration: mode 1, 8-bit words,
		//     *8-byte threshold, mode-0 clock. No interrupt-enable bits are set.

		reg_write(k, u32(4), 1 << 5)
		reg_write(k, u32(48), u32(divider))
		reg_write(k, u32(56), u32(0))
		reg_write(k, u32(8), u32(7))
		reg_write(k, u32(308), u32(3))
		reg_write(k, u32(316), u32(197424))
		reg_write(k, u32(0), u32(0))
		set_enable(k, 1)
		k.io.delay_us(voidptr(k.cookie), u32(5000))
		set_enable(k, 0)
		k.io.delay_us(voidptr(k.cookie), u32(5000))
		set_enable(k, 1)
		// Let the controller boot without a 50-ms busy wait in kernel init.

		k.next_poll = k.io.now_us(voidptr(k.cookie)) + u64(50000)
		k.next_transfer = k.next_poll
		k.errors = u32(0)
		reset_input(&k.decoder)
		tp_init(&k.touchpad, k.next_poll)
		k.active = 1
		return 1
	}
}

// A single FIFO stage. CS belongs to the caller so a write and its status
// *read can share one selection, with the required direction-change delay.

@[export: 'vinix_spi_core_transfer_bytes']
pub fn transfer_bytes(k &Spi_keyboard, output &u8, input &u8, length usize) i32 {
	unsafe {
		tx := usize(0)
		rx := usize(0)

		ok := i32(0)
		if !length || length > usize(256) {
			return 0
		}
		reg_write(k, u32(0), 12)
		reg_write(k, u32(76), u32(length))
		reg_write(k, u32(52), u32(length))
		for ; tx < usize(16) && tx < length; tx++ {
			reg_write(k, u32(16), u32(if output { i32(output[tx]) } else { 0 }))
		}
		start := k.io.now_us(voidptr(k.cookie))
		reg_write(k, u32(0), 1)
		for spins := u32(0); spins < u32(100000); spins++ {
			status := reg_read(k, u32(268))
			n := (status >> 24) & 255
			if n > 16 || usize(n) > length - rx {
				break
			}
			for n-- {
				byte_ := u8(reg_read(k, u32(32)))
				if input {
					input[rx] = byte_
				}
				rx++
			}
			status = reg_read(k, u32(268))
			level := (status >> 8) & 255
			if level > 16 {
				break
			}
			n = 16 - level
			for n-- && tx < length {
				reg_write(k, u32(16), u32(if output { i32(output[tx]) } else { 0 }))
				tx++
			}
			if rx == length && tx == length {
				ok = 1
				break
			}
			if k.io.now_us(voidptr(k.cookie)) - start >= u64(5000) {
				break
			}
		}
		reg_write(k, u32(0), u32(0))
		return ok
	}
}

@[export: 'vinix_spi_core_end_transfer']
pub fn end_transfer(k &Spi_keyboard, ok i32) {
	unsafe {
		reg_write(k, u32(0), u32(0))
		k.io.delay_us(voidptr(k.cookie), u32(100))
		reg_write(k, u32(12), 2)
		k.next_transfer = k.io.now_us(voidptr(k.cookie)) + u64(250)
		if !ok {
			reg_write(k, u32(0), 12)
		}
	}
}

@[export: 'vinix_spi_core_read_packet']
pub fn read_packet(k &Spi_keyboard, packet &u8) i32 {
	unsafe {
		reg_write(k, u32(12), u32(0))
		k.io.delay_us(voidptr(k.cookie), u32(100))
		ok := transfer_bytes(k, (voidptr(0)), packet, usize(256))
		end_transfer(k, ok)
		return ok
	}
}

@[export: 'vinix_spi_core_enable_touchpad']
pub fn enable_touchpad(k &Spi_keyboard, now u64) {
	unsafe {
		packet := [256]u8{}
		status := [4]u8{}
		tp_mode_packet(&k.touchpad, &packet[0], now)
		reg_write(k, u32(12), u32(0))
		k.io.delay_us(voidptr(k.cookie), u32(100))
		ok := transfer_bytes(k, &packet[0], (voidptr(0)), usize(256))
		if ok {
			// No CS edge here: Asahi's write and status are one SPI message.

			k.io.delay_us(voidptr(k.cookie), u32(200))
			ok = transfer_bytes(k, (voidptr(0)), &status[0], sizeof([4]u8))
		}
		end_transfer(k, ok)
		if !ok || i32(status[0]) != 172 || i32(status[1]) != 39 || i32(status[2]) != 104 || i32(status[3]) != 213 {
			k.touchpad.mode_errors++
		}
		// A failed feature write does NOT disable spi_controller reads. Retries are
		//     *bounded independently and native reports can arrive despite bad status.
	}
}

@[export: 'vinix_spi_core_boot_packet']
pub fn boot_packet(p &u8) i32 {
	unsafe {
		return i32(i32(read_le16(p + 2)) == 0 && i32(read_le16(p + 4)) == 0 && i32(read_le16(p + 6)) == 4 && i32(p[8]) == 160 && i32(p[9]) == 128 && i32(p[10]) == 0 && i32(p[11]) == 0 && i32(crc16(p, usize(256))) == 0)
	}
}

@[export: 'vinix_spi_core_packet_envelope_valid']
pub fn packet_envelope_valid(p &u8) i32 {
	unsafe {
		// A completed PIO transaction is not necessarily a packet: an idle or
		//     *wedged HID controller can clock a buffer full of zeroes. Keep unknown
		//     *device/report IDs forward-compatible, but require the Apple read flag,
		//     *a payload that fits this packet and a valid outer CRC.

		n := usize(read_le16(p + 6))
		return i32(i32(p[0]) == 32 && n != usize(0) && n <= usize(256 - u32(10)) && i32(crc16(p, usize(256))) == 0)
	}
}

@[export: 'vinix_spi_core_read_error']
pub fn read_error(k &Spi_keyboard) i32 {
	unsafe {
		reset_input(&k.decoder)
		tp_discontinuity(&k.touchpad)
		k.errors++
		if k.errors >= u32(3) {
			// Down, but not for good: both devices share this transport.

			k.active = 0
			k.revive_at = k.io.now_us(voidptr(k.cookie)) + u64(2000000)
			return -2
		}
		k.next_poll = k.io.now_us(voidptr(k.cookie)) + u64(20000)
		return -1
	}
}

@[export: 'vinix_spi_core_poll_keyboard']
pub fn poll_keyboard(k &Spi_keyboard, out &u8, capacity usize, application_cursor i32) i32 {
	unsafe {
		if (usize(out) == 0) || capacity == usize(0) {
			return 0
		}
		if !k.active {
			// Bring it back when the cool-off has passed. Re-running the start
			//         *sequence reprograms a controller that may itself have reset.

			if !k.revive_at || k.io.now_us(voidptr(k.cookie)) < k.revive_at {
				return 0
			}
			if !start_keyboard(k, k.input_hz, k.maximum_hz) {
				k.revive_at = k.io.now_us(voidptr(k.cookie)) + u64(2000000)
				return 0
			}
			k.revive_at = u64(0)
			return -3
		}
		used := usize(0)
		now := k.io.now_us(voidptr(k.cookie))
		tp_tick(&k.touchpad, now)
		if k.decoder.message_used && now - k.decoder.fragment_at >= u64(100000) {
			cancel_repeat(&k.decoder)
		}
		if now >= k.next_poll && now >= k.next_transfer {
			k.next_poll = now + u64(2000)
			// Do not insert a feature command in the middle of either report.
			if !k.errors && !k.decoder.message_used && tp_mode_due(&k.touchpad, now) {
				enable_touchpad(k, now)
				now = k.io.now_us(voidptr(k.cookie))
				return i32(repeat_key(&k.decoder, now, application_cursor, out, capacity))
			}
			ready := i32(1)
			if k.ready {
				v := k.io.read32(voidptr(k.cookie), k.ready)
				ready = i32(!!(v & 1)) ^ i32(!!k.ready_low)
			}
			// The ready line is the HID interrupt. Do not periodically clock the
			//         *controller while it is inactive; timer-only polling is reserved for
			//         *device trees that do not supply the line at all.

			if ready {
				packet := [256]u8{}
				if !read_packet(k, &packet[0]) {
					return read_error(k)
				}
				// With a ready line, a successful transfer that did not return a
				//             *valid packet is a transport failure too. Previously all-zero
				//             *reads cleared the error count and left input dead indefinitely.

				if k.ready && !packet_envelope_valid(&packet[0]) {
					return read_error(k)
				}
				k.errors = u32(0)
				now = k.io.now_us(voidptr(k.cookie))
				if boot_packet(&packet[0]) {
					reset_input(&k.decoder)
					tp_restart(&k.touchpad, now)
				} else {
					tp_decode(&k.touchpad, &packet[0], sizeof([256]u8), now)
					used = decode_packet(&k.decoder, &packet[0], sizeof([256]u8), now, application_cursor, out, capacity)
				}
			}
		}
		used += repeat_key(&k.decoder, now, application_cursor, out + used, capacity - used)
		return i32(used)
	}
}

// Use the same width-exact MMIO routines as aarch64.kio; ordinary volatile
// *pointer accesses used to produce invalid paired/64-bit accesses on M1.

fn C.vinix_mmio_read32(arg voidptr) u32

fn C.vinix_mmio_write32(arg voidptr, arg_2 u32)

__global spi_controller Spi_keyboard

__global spi_counter_frequency u64

@[export: 'vinix_spi_core_kernel_read32']
pub fn kernel_read32(cookie voidptr, address u64) u32 {
	unsafe {
		v := C.vinix_mmio_read32(voidptr(usize(address)))
		asm volatile aarch64 {
		dmb ish
		; ; ; memory
	}
		return v
	}
}

@[export: 'vinix_spi_core_kernel_write32']
pub fn kernel_write32(cookie voidptr, address u64, value u32) {
	unsafe {
		asm volatile aarch64 {
		dmb ish
		; ; ; memory
	}
		C.vinix_mmio_write32(voidptr(usize(address)), value)
	}
}

@[export: 'vinix_spi_core_kernel_now_us']
pub fn kernel_now_us(cookie voidptr) u64 {
	unsafe {
		mut count := u64(0)
		// CNTVCT, not CNTPCT: the latter may trap under the M1 EL2 handoff.

		asm volatile aarch64 { mrs count, cntvct_el0 ; =r (count) }
		return (count / spi_counter_frequency) * u64(1000000) + (count % spi_counter_frequency) * u64(1000000) / spi_counter_frequency
	}
}

@[export: 'vinix_spi_core_kernel_delay_us']
pub fn kernel_delay_us(cookie voidptr, us u32) {
	unsafe {
		start := kernel_now_us(voidptr(cookie))
		for kernel_now_us(voidptr(cookie)) - start < u64(us) {
			asm volatile aarch64 {
		yield
		; ; ; memory
	}
		}
	}
}

@[export: 'vinix_apple_spi_keyboard_init']
pub fn vinix_apple_spi_keyboard_init(spi_base u64, enable_reg u64, enable_active_low i32, ready_reg u64, ready_active_low i32, input_hz u32, maximum_hz u32) i32 {
	unsafe {
		if spi_controller.active || !spi_base || !enable_reg || (spi_base & u64(3)) || (enable_reg & u64(3)) || (ready_reg & u64(3)) {
			return 0
		}
		mut frequency := u64(0)
		asm volatile aarch64 { mrs frequency, cntfrq_el0 ; =r (frequency) }
		spi_counter_frequency = frequency
		if !spi_counter_frequency || spi_counter_frequency > u64(u32(4294967295)) {
			return 0
		}
		spi_controller = Spi_keyboard{}

		spi_controller.io = Io_ops{
			read32:   kernel_read32
			write32:  kernel_write32
			now_us:   kernel_now_us
			delay_us: kernel_delay_us
		}

		spi_controller.spi = spi_base
		spi_controller.enable = enable_reg
		spi_controller.enable_low = enable_active_low
		spi_controller.ready = ready_reg
		spi_controller.ready_low = ready_active_low
		return start_keyboard(&spi_controller, input_hz, maximum_hz)
	}
}

@[export: 'vinix_apple_spi_keyboard_poll']
pub fn vinix_apple_spi_keyboard_poll(out &u8, capacity usize, app i32) i32 {
	unsafe {
		return poll_keyboard(&spi_controller, out, capacity, app)
	}
}

@[export: 'vinix_apple_spi_keyboard_reports']
pub fn vinix_apple_spi_keyboard_reports() u64 {
	unsafe {
		return spi_controller.decoder.reports
	}
}

@[export: 'vinix_apple_spi_keyboard_caps_lock']
pub fn vinix_apple_spi_keyboard_caps_lock() i32 {
	unsafe {
		return i32(spi_controller.decoder.caps)
	}
}

@[export: 'vinix_apple_spi_touchpad_reports']
pub fn vinix_apple_spi_touchpad_reports() u64 {
	unsafe {
		return spi_controller.touchpad.reports
	}
}

@[export: 'vinix_apple_spi_touchpad_read']
pub fn vinix_apple_spi_touchpad_read(out &i32) i32 {
	unsafe {
		if out {
			spi_controller.touchpad.requested = 1
		}
		return tp_snapshot(&spi_controller.touchpad, out)
	}
}

// __AARCH64__

// __AARCH64__ || VINIX_APPLE_SPI_TEST
