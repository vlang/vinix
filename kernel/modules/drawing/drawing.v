module drawing

import stivale2

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

pub fn (mut fb FB) set(x int, y int, color u32) {
	if x > fb.width || x < 0 {
		// 'x out of bounds'
		for {}
	}
	if y > fb.height || y < 0 {
		// 'y out of bounds'
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
	// asm i386 {
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

pub fn (mut fb FB) line(x1 int, y1 int, x2 int, y2 int, color u32) {
}
