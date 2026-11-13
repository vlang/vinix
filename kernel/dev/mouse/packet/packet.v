// SPDX-License-Identifier: GPL-2.0-or-later
module packet

pub struct Report {
pub:
	flags   u8
	x       i32
	y       i32
	buttons u32
	scroll  i32
}

pub struct Decoder {
mut:
	bytes [4]u8
	used  int
}

// The sign bits belong to the header, not the low eight bits of each axis.
fn axis(value u8, negative bool) i32 {
	return i32(value) - if negative { i32(256) } else { i32(0) }
}

pub fn (mut d Decoder) push(value u8, size int, explorer bool) ?Report {
	if d.used == 0 && value & 8 == 0 {
		// Retry at the very next byte; consuming a whole packet here keeps
		// an otherwise valid stream permanently out of alignment.
		return none
	}
	d.bytes[d.used] = value
	d.used++
	if d.used < size {
		return none
	}
	d.used = 0
	flags := d.bytes[0]
	if flags & 0xc0 != 0 {
		// Consume all bytes of an overflow packet before resynchronising.
		return none
	}
	mut buttons := u32(flags & 7)
	mut wheel := i32(0)
	if size == 4 {
		extra := d.bytes[3]
		if explorer {
			// Explorer uses a signed nibble; bits 4 and 5 are side buttons.
			if extra & 0xc0 == 0 {
				wheel = i32(extra & 15) - if extra & 8 != 0 { i32(16) } else { i32(0) }
				buttons |= u32((extra >> 4) & 3) << 3
			}
		} else {
			wheel = i32(i8(extra))
		}
	}
	return Report{
		flags:   flags
		x:       axis(d.bytes[1], flags & 0x10 != 0)
		y:       axis(d.bytes[2], flags & 0x20 != 0)
		buttons: buttons
		// /dev/pointer and USB use positive for scrolling upwards.
		scroll:  -wheel
	}
}
