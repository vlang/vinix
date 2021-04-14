module drawing

import stivale2
import lib

pub fn new_fb(tag stivale2.FBTag) FB {
	return FB{
		addr: &u32(tag.addr)
		height: int(tag.height)
		width: int(tag.width)
		pitch: int(tag.pitch)
	}
}

pub struct FB {
mut:
	addr  &u32
	pitch int
pub:
	height int // int because most people use int
	width  int
}

[inline]
pub fn (mut fb FB) set(x int, y int, color u32) {
	if x > fb.width || x < 0 {
		lib.kprint('x out of bounds')
		for {}
	}
	if y > fb.height || y < 0 {
		lib.kprint('y out of bounds')
		for {}
	}
	unsafe {
		fb.addr[(fb.pitch / 4) * y + x] = color
	}
}

// rect draws a rectangle on fb.
// `x` and `y` are the position of the upper-left corner of the rectangle relative to the upper-left corner of the screen
pub fn (mut fb FB) rect(x int, y int, width int, height int, color u32) {
	// if width > 8 {
	// asm amd64 {
	// 	vpbroadcastd ymm1, color
	// 	; ; r (color)
	// 	; ymm1
	// }
	// } else {
	for i := x; i < x + width; i++ {
		for j := y; j < y + height; j++ {
			fb.set(i, j, color)
		}
	}
	// }
}

pub fn (mut fb FB) horizontal_line(_x int, y int, x2 int, color u32) {
	mut x := _x
	for {
		fb.set(x, y, color)
		if x == x2 {
			return
		}
		if _x > x2 {
			x--
		} else {
			x++
		}
	}
}

pub fn (mut fb FB) vertical_line(x int, _y int, y2 int, color u32) {
	mut y := _y
	for {
		fb.set(x, y, color)
		if y == y2 {
			return
		}
		if _y > y2 {
			y--
		} else {
			y++
		}
	}
}

pub fn (mut fb FB) line_thick(x1 int, y1 int, x2 int, y2 int, thickness int, color u32) {
	for i in 0 .. thickness {
		fb.line(x1 + i, y1, x2 + i, y2, color)
	}
}

pub fn (mut fb FB) line(_x1 int, _y1 int, x2 int, y2 int, color u32) {
	mut x1 := _x1
	mut y1 := _y1
	if y1 == y2 {
		fb.horizontal_line(x1, y1, x2, color)
		return
	}
	if x1 == x2 {
		fb.vertical_line(x1, y1, y2, color)
		return
	}
	dx := abs(x2 - x1)
	sx := if x1 < x2 { 1 } else { -1 }
	dy := -abs(y2 - y1)
	sy := if y1 < y2 { 1 } else { -1 }
	mut err := dx + dy // error value e_xy
	for {
		// loop
		fb.set(x1, y1, color)
		if x1 == x2 && y1 == y2 {
			break
		}
		e2 := 2 * err
		if e2 >= dy {
			// e_xy+e_x > 0
			err += dy
			x1 += sx
		}
		if e2 <= dx {
			// e_xy+e_y < 0
			err += dx
			y1 += sy
		}
	}
}

fn abs(x int) int {
	return if x >= 0 { x } else { -x }
}

// Function for circle-generation using Bresenham's algorithm
// Stolen from: https://www.geeksforgeeks.org/bresenhams-circle-drawing-algorithm/
pub fn (mut fb FB) circle(xc int, yc int, r int, color u32) {
	mut x := 0
	mut y := r
	mut d := 3 - 2 * r
	fb.circle_util(xc, yc, x, y, color)
	for y >= x {
		// for each pixel we will
		// draw all eight pixels
		x++
		// check for decision parameter
		// and correspondingly
		// update d, x, y
		if d > 0 {
			y--
			d = d + 4 * (x - y) + 10
		} else {
			d = d + 4 * x + 6
		}
		fb.circle_util(xc, yc, x, y, color)
	}
}

fn (mut fb FB) circle_util(xc int, yc int, x int, y int, color u32) {
	fb.horizontal_line(xc - x, yc + y, xc + x, color)
	fb.horizontal_line(xc - x, yc - y, xc + x, color)
	fb.horizontal_line(xc - y, yc + x, xc + y, color)
	fb.horizontal_line(xc - y, yc - x, xc + y, color)
}
