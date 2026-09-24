// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// Catalina's black arrow pointer, reconstructed as separate white-outline and
// black-fill masks. The 2x masks are native-resolution artwork: scaling the 1x
// capture made the pointer visibly soft on HiDPI displays.
module main

const catalina_cursor_width = 14
const catalina_cursor_height = 21

// Mask characters are four-bit alpha values. Keeping every scanline separate
// makes a missing pixel impossible to shift the following rows (the old flat
// alpha table did exactly that and painted a vertical line beside the cursor).
const catalina_cursor_white_1x = [
	'13            ',
	'1e3           ',
	'1fe3          ',
	'1e5e3         ',
	'1e 5e3        ',
	'1e  5e3       ',
	'1e   5e3      ',
	'1e    5e3     ',
	'1e     5e3    ',
	'1e      5e3   ',
	'1e    1116e3  ',
	'1e  4 5feeec2 ',
	'1e 9e  e2     ',
	'1eabc5 89     ',
	'1fb15b 2e1    ',
	'1a   d2 b6    ',
	'     793bc    ',
	'     1ee92    ',
	'      41      ',
	'              ',
	'              ',
]

const catalina_cursor_black_1x = [
	'              ',
	'              ',
	' 31           ',
	' 5c1          ',
	' 5fc1         ',
	' 5ffc1        ',
	' 5fffc1       ',
	' 5ffffc1      ',
	' 5fffffc1     ',
	' 5ffffffc1    ',
	' 5fffffffc1   ',
	' 5ffefb3331   ',
	' 5fa3ff1      ',
	' 59  cf7      ',
	' 1   6fd      ',
	'     1ef4     ',
	'      9fa     ',
	'      3a3     ',
	'              ',
	'              ',
	'              ',
]

const catalina_cursor_white_2x = [
	' 1                          ',
	' 3a                         ',
	' 3fa                        ',
	' 3ffa                       ',
	' 3fffa                      ',
	' 3feefa                     ',
	' 3fc3efa                    ',
	' 3fc 3efa                   ',
	' 3fc  3efa                  ',
	' 3fc   3efa                 ',
	' 3fc    3efa                ',
	' 3fc     3efa               ',
	' 3fc      3efa              ',
	' 3fc       3efa             ',
	' 3fc        3efa            ',
	' 3fc         3efa           ',
	' 3fc          3efa          ',
	' 3fc           3efa         ',
	' 3fc            3efa        ',
	' 3fc             3efa       ',
	' 3fc              3efa      ',
	' 3fc         3333336ffa     ',
	' 3fc         dfffffffffa    ',
	' 3fc    a4   8ffcccccccc7   ',
	' 3fc  1bfa   2ff2           ',
	' 3fc 1bfff2   af8           ',
	' 3fc1cfecf7   4fe           ',
	' 3fdcfe25fd    df5          ',
	' 3fffd2  df5   7fc          ',
	' 3ffd2   7fb   1ff3         ',
	' 3fd2    1ef2   af9         ',
	' 3d1      9f8   4fe1        ',
	' 11       2fe   2ef7        ',
	'           bf53afffc        ',
	'           4fefffd71        ',
	'            dffc5           ',
	'            6a4             ',
	'                            ',
	'                            ',
	'                            ',
	'                            ',
	'                            ',
]

const catalina_cursor_black_2x = [
	'                            ',
	'                            ',
	'                            ',
	'                            ',
	'   1                        ',
	'   a4                       ',
	'   ae4                      ',
	'   afe4                     ',
	'   affe4                    ',
	'   afffe4                   ',
	'   affffe4                  ',
	'   afffffe4                 ',
	'   affffffe4                ',
	'   afffffffe4               ',
	'   affffffffe4              ',
	'   afffffffffe4             ',
	'   affffffffffe4            ',
	'   afffffffffffe4           ',
	'   affffffffffffe4          ',
	'   afffffffffffffe4         ',
	'   affffffffffffffe4        ',
	'   afffffffffffffffe4       ',
	'   afffffffff76666665       ',
	'   affffcffff8              ',
	'   afffc19fffe              ',
	'   affb1 3ffff5             ',
	'   afb1   cfffb             ',
	'   ab     6ffff2            ',
	'   6      1efff8            ',
	'           9fffe1           ',
	'           3ffff6           ',
	'            cfffc           ',
	'            6ffff3          ',
	'            1efff9          ',
	'             9ffa3          ',
	'             392            ',
	'                            ',
	'                            ',
	'                            ',
	'                            ',
	'                            ',
	'                            ',
]

@[inline]
fn catalina_cursor_alpha(value u8) u32 {
	if value >= `1` && value <= `9` {
		return u32(value - `0`) * 17
	}
	if value >= `a` && value <= `f` {
		return u32(value - `a` + 10) * 17
	}
	return 0
}

fn (mut d Desktop) draw_catalina_cursor_mask(rows []string, color u32) {
	physical_x := d.pointer_x * d.canvas.scale
	physical_y := d.pointer_y * d.canvas.scale
	for y, row in rows {
		for x := 0; x < row.len; x++ {
			d.canvas.blend_physical_pixel(physical_x + x, physical_y + y, color,
				catalina_cursor_alpha(row[x]))
		}
	}
}

fn (mut d Desktop) draw_catalina_cursor() {
	// The outline is the bottom layer of the AppKit pointer; its white edge
	// keeps the black fill visible over both dark and light windows.
	if d.canvas.scale == desktop_scale_200 {
		d.draw_catalina_cursor_mask(catalina_cursor_white_2x, 0xffffff)
		d.draw_catalina_cursor_mask(catalina_cursor_black_2x, 0x000000)
		return
	}
	d.draw_catalina_cursor_mask(catalina_cursor_white_1x, 0xffffff)
	d.draw_catalina_cursor_mask(catalina_cursor_black_1x, 0x000000)
}
