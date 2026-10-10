// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// What was on the machine's screen.
//
// QEMU writes a picture of the screen when asked (`screendump`), as a
// portable pixmap: a short text header and three bytes for each pixel. A
// scenario that says the screen must be dark at some moment, or must show
// something, has an action take the picture then and lists it here; the
// pictures are looked at once the machine has ended.
module hwhost

import os

// A picture a scenario's action wrote into the state directory, and what it
// must show.
pub struct Screen {
pub:
	file string
	// Every pixel black; otherwise, enough pixels not black for something
	// to be on the screen.
	dark bool
	// Another of the scenario's pictures this one must be the size of: the
	// display is in the mode it was in when that one was taken.
	like string
	// With a value, the top-left `pattern` by `pattern` pixels must be what
	// a guest draws there with its screen pattern (guest/framebuffer.v): in
	// column x of row y red is x, green is y and blue their sum, each as a
	// byte. That is a picture nothing but the guest's drawing puts there.
	pattern int
}

pub struct Picture {
pub:
	width  int
	height int
	// How many pixels are not black.
	lit int
	// Three bytes a pixel: red, green, blue.
	pixels []u8
}

// The colour the guest's pattern gives the pixel in column x of row y.
pub fn screen_pattern(x int, y int) (u8, u8, u8) {
	return u8(x), u8(y), u8(x + y)
}

// What is wrong with the top-left `size` by `size` pixels as the guest's
// pattern; '' if nothing.
pub fn (p &Picture) judge_pattern(size int) string {
	if p.width < size || p.height < size {
		return 'it is ${p.width} by ${p.height}, smaller than the ${size} by ${size} pattern'
	}
	for y in 0 .. size {
		for x in 0 .. size {
			red, green, blue := screen_pattern(x, y)
			at := (y * p.width + x) * 3
			if p.pixels[at] != red || p.pixels[at + 1] != green || p.pixels[at + 2] != blue {
				return 'the pixel in column ${x} of row ${y} is (${p.pixels[at]}, ${p.pixels[at + 1]}, ${p.pixels[at + 2]}), not the (${red}, ${green}, ${blue}) the guest drew'
			}
		}
	}
	return ''
}

// A screen with a console's text on it has a few pixels in a hundred lit;
// one in a thousand is asked for, which noise in an otherwise black frame
// would not reach.
pub const lit_per_mille = 1

// The next number of a pixmap's header, and where reading goes on. Comments
// run from a `#` to the end of the line.
fn pixmap_number(data []u8, start int) !(int, int) {
	mut at := start
	for at < data.len {
		c := data[at]
		if c == `#` {
			for at < data.len && data[at] != `\n` {
				at++
			}
		} else if c == ` ` || c == `\t` || c == `\r` || c == `\n` {
			at++
		} else {
			break
		}
	}
	mut value := 0
	mut digits := 0
	for at < data.len && data[at] >= `0` && data[at] <= `9` {
		if value > 100_000 {
			return error('a number in the header is absurd')
		}
		value = value * 10 + int(data[at] - `0`)
		digits++
		at++
	}
	if digits == 0 {
		return error('the header has something that is not a number')
	}
	return value, at
}

// Takes a binary pixmap apart and counts its lit pixels.
pub fn read_picture(data []u8) !Picture {
	if data.len < 2 || data[0] != `P` || data[1] != `6` {
		return error('not a binary pixmap')
	}
	width, after_width := pixmap_number(data, 2)!
	height, after_height := pixmap_number(data, after_width)!
	depth, after_depth := pixmap_number(data, after_height)!
	if width <= 0 || height <= 0 {
		return error('a picture of ${width} by ${height}')
	}
	if depth != 255 {
		return error('a pixmap with ${depth} levels, not 255')
	}
	// One white-space byte ends the header.
	pixels := after_depth + 1
	if data.len - pixels < width * height * 3 {
		return error('${width} by ${height} needs ${width * height * 3} bytes of pixels, and ${data.len - pixels} follow the header')
	}
	mut lit := 0
	for pixel in 0 .. width * height {
		at := pixels + pixel * 3
		if data[at] != 0 || data[at + 1] != 0 || data[at + 2] != 0 {
			lit++
		}
	}
	return Picture{
		width:  width
		height: height
		lit:    lit
		pixels: data[pixels..pixels + width * height * 3]
	}
}

// What is wrong with a picture, given what it was to show; '' if nothing.
pub fn judge_picture(picture Picture, dark bool) string {
	pixels := picture.width * picture.height
	if dark {
		if picture.lit != 0 {
			return '${picture.lit} of ${pixels} pixels are lit; the screen was to be dark'
		}
		return ''
	}
	if i64(picture.lit) * 1000 < i64(pixels) * lit_per_mille {
		return '${picture.lit} of ${pixels} pixels are lit; the screen was to show something'
	}
	return ''
}

pub fn check_screen(screen Screen, state string) ! {
	data := os.read_bytes(os.join_path(state, screen.file)) or {
		return error('${screen.file}: the picture was not taken')
	}
	picture := read_picture(data) or { return error('${screen.file}: ${err.msg()}') }
	problem := judge_picture(picture, screen.dark)
	if problem != '' {
		return error('${screen.file}: ${problem}')
	}
	if screen.like != '' {
		other_data := os.read_bytes(os.join_path(state, screen.like)) or {
			return error('${screen.like}: the picture was not taken')
		}
		other := read_picture(other_data) or { return error('${screen.like}: ${err.msg()}') }
		if other.width != picture.width || other.height != picture.height {
			return error('${screen.file} is ${picture.width} by ${picture.height}, but ${screen.like} was ${other.width} by ${other.height}: the display is in another mode')
		}
	}
	if screen.pattern > 0 {
		wrong := picture.judge_pattern(screen.pattern)
		if wrong != '' {
			return error('${screen.file}: ${wrong}')
		}
	}
}
