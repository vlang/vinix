// SPDX-License-Identifier: GPL-2.0-or-later
module keyboard

// Allocation-free physical events for the compositor's console input mode.
// CSI ? linux-keycode ; value k, where value is 0 up, 1 down, 2 repeat.
pub fn event_bytes(code u16, value u32, out &u8) u64 {
	if code == 0 || code > 255 || value > 2 { return 0 }
	unsafe {
		out[0] = 27
		out[1] = `[`
		out[2] = `?`
		mut n := 3
		if code >= 100 {
			out[n] = u8(`0`) + u8(code / 100)
			n++
		}
		if code >= 10 {
			out[n] = u8(`0`) + u8(code / 10 % 10)
			n++
		}
		out[n] = u8(`0`) + u8(code % 10)
		out[n + 1] = `;`
		out[n + 2] = u8(`0`) + u8(value)
		out[n + 3] = `k`
		return u64(n + 4)
	}
}
