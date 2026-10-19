// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Small, shaded XP-style destination artwork, drawn on a 32-unit grid. These
// are compositor primitives: no decoded images or per-frame allocations.
struct LunaMenuArt {
	x    int
	y    int
	size int
mut:
	canvas &Canvas = unsafe { nil }
}

fn (mut a LunaMenuArt) rect(x int, y int, w int, h int, color u32) {
	left := a.x + x * a.size / 32
	top := a.y + y * a.size / 32
	a.canvas.fill_rect(left, top, (x + w) * a.size / 32 - x * a.size / 32,
		(y + h) * a.size / 32 - y * a.size / 32, color)
}

fn (mut a LunaMenuArt) line(x0 int, y0 int, x1 int, y1 int, color u32, thickness int) {
	a.canvas.draw_line(a.x + x0 * a.size / 32, a.y + y0 * a.size / 32,
		a.x + x1 * a.size / 32, a.y + y1 * a.size / 32, color,
		if thickness * a.size / 32 > 0 { thickness * a.size / 32 } else { 1 })
}

fn (mut a LunaMenuArt) circle(x int, y int, radius int, color u32) {
	a.canvas.fill_circle(a.x + x * a.size / 32, a.y + y * a.size / 32,
		radius * a.size / 32, color)
}

fn (mut a LunaMenuArt) quad(points [8]int, light u32, dark u32) {
	mut top := 32
	mut bottom := 0
	for i in 0 .. 4 {
		if points[i * 2 + 1] < top { top = points[i * 2 + 1] }
		if points[i * 2 + 1] > bottom { bottom = points[i * 2 + 1] }
	}
	for y in top .. bottom {
		mut left := 32
		mut right := 0
		for i in 0 .. 4 {
			next := (i + 1) % 4
			x0, y0 := points[i * 2], points[i * 2 + 1]
			x1, y1 := points[next * 2], points[next * 2 + 1]
			if y0 == y1 || y < (if y0 < y1 { y0 } else { y1 }) || y >= (if y0 > y1 {
				y0
			} else {
				y1
			}) {
				continue
			}
			x := x0 + (x1 - x0) * (y - y0) / (y1 - y0)
			if x < left { left = x }
			if x > right { right = x }
		}
		if right > left {
			a.rect(left, y, right - left, 1, mix(light, dark, u32((y - top) * 255 / (bottom - top))))
		}
	}
}

fn (mut a LunaMenuArt) folder() {
	a.quad([3, 12, 23, 7, 28, 25, 6, 30]!, 0x9b914f, 0x8b8041)
	a.quad([3, 12, 9, 7, 15, 9, 7, 18]!, 0xffffcd, 0xd9b947)
	a.quad([4, 14, 23, 9, 27, 25, 7, 29]!, 0xffffc5, 0xe6bd48)
	a.quad([7, 18, 30, 13, 25, 27, 6, 30]!, 0xfff7aa, 0xe9c959)
	a.line(7, 18, 29, 13, 0xfffee6, 1)
	a.line(7, 29, 25, 26, 0xbd9f48, 1)
}

fn (mut a LunaMenuArt) paper() {
	a.quad([7, 2, 23, 3, 27, 24, 9, 29]!, 0x748ca3, 0x617d93)
	a.quad([8, 3, 21, 4, 25, 23, 10, 27]!, 0xffffff, 0xc5e1ed)
	a.line(11, 10, 21, 9, 0x87aaca, 1)
	a.line(12, 14, 22, 13, 0x87aaca, 1)
	a.line(12, 18, 22, 17, 0x87aaca, 1)
}

fn (mut a LunaMenuArt) monitor(x int, y int) {
	a.quad([x, y + 2, x + 17, y, x + 17, y + 17, x, y + 19]!, 0xc5d8e4, 0x6d839c)
	a.quad([x + 2, y + 4, x + 14, y + 2, x + 14, y + 13, x + 2, y + 15]!, 0xc5f7ff, 0x328dd8)
	a.quad([x + 17, y, x + 21, y + 3, x + 21, y + 17, x + 17, y + 17]!, 0xb6c6da, 0x6681a3)
	a.rect(x + 7, y + 18, 5, 4, 0x8597ac)
	a.quad([x + 4, y + 23, x + 11, y + 21, x + 17, y + 23, x + 9, y + 25]!, 0xdde9ef, 0x8095af)
}

fn (mut a LunaMenuArt) globe() {
	a.circle(13, 12, 11, 0x527e9a)
	a.circle(12, 11, 10, 0x2466bd)
	a.circle(10, 8, 7, 0x3c9cda)
	a.quad([5, 4, 10, 2, 13, 6, 7, 11]!, 0xadd958, 0x579d32)
	a.quad([13, 12, 21, 9, 19, 18, 16, 22]!, 0x81c341, 0x387c33)
	a.line(6, 3, 4, 8, 0xd5f6d6, 1)
}

fn (mut d Desktop) draw_luna_menu_icon(name string, x int, y int, w int, h int) {
	size := if w < h { w } else { h }
	mut a := LunaMenuArt{ x: x + (w - size) / 2, y: y + (h - size) / 2, size: size, canvas: &d.canvas }
	match name {
		'luna_documents', 'luna_pictures', 'luna_music' {
			a.folder()
			if name == 'luna_documents' {
				a.quad([14, 2, 25, 6, 20, 17, 10, 13]!, 0xf7ffff, 0x9dc5de)
				a.line(15, 6, 22, 8, 0x7a9ebd, 1)
				a.line(14, 9, 21, 11, 0x7a9ebd, 1)
			} else if name == 'luna_pictures' {
				a.quad([14, 3, 27, 7, 23, 19, 10, 15]!, 0xffffff, 0x87a8c4)
				a.quad([15, 5, 25, 8, 22, 16, 12, 14]!, 0xb0e7f2, 0x40904d)
				a.circle(20, 9, 2, 0xffffb0)
			} else {
				a.line(20, 2, 20, 15, 0x344c9c, 3)
				a.line(20, 3, 27, 7, 0x5b71b6, 3)
				a.circle(17, 15, 4, 0x4766af)
			}
		}
		'luna_recent' {
			a.paper()
			a.circle(23, 21, 9, 0x6e889d)
			a.circle(22, 20, 8, 0xd1e4e4)
			a.circle(22, 20, 6, 0xf3ffff)
			a.line(22, 15, 22, 20, 0x427689, 2)
			a.line(22, 20, 26, 22, 0x427689, 2)
		}
		'luna_computer' {
			a.quad([22, 1, 29, 3, 29, 23, 22, 22]!, 0xe3e6f3, 0x8090ad)
			a.rect(24, 5, 4, 2, 0x617591)
			a.monitor(2, 4)
		}
		'luna_network', 'luna_connect' {
			a.globe()
			a.monitor(11, 9)
		}
		'luna_defaults' {
			a.globe()
			a.circle(24, 22, 7, 0xeac93e)
			a.line(24, 16, 24, 28, 0x63a63a, 3)
			a.line(18, 22, 29, 22, 0x63a63a, 3)
		}
		'luna_control' {
			a.quad([4, 5, 23, 1, 26, 26, 7, 30]!, 0x568db5, 0x194784)
			a.quad([7, 8, 21, 5, 23, 23, 9, 27]!, 0xffffff, 0xd2e9ed)
			a.line(11, 17, 15, 21, 0x729649, 2)
			a.line(15, 21, 25, 11, 0x729649, 3)
			a.line(25, 11, 30, 10, 0xb68d56, 3)
		}
		'luna_printer' {
			a.quad([9, 2, 23, 4, 23, 14, 9, 12]!, 0xffffff, 0xdce6ed)
			a.quad([3, 15, 18, 10, 30, 17, 14, 24]!, 0xf8f9ed, 0xb9c4c5)
			a.quad([3, 15, 14, 22, 14, 29, 3, 23]!, 0xd0d7cf, 0x839797)
			a.quad([14, 22, 30, 17, 30, 25, 14, 29]!, 0xc4d4c8, 0x728d89)
			a.quad([11, 20, 22, 18, 25, 26, 14, 29]!, 0xffffff, 0xe4e9dd)
			a.circle(25, 17, 1, 0x48a84d)
		}
		'luna_help' {
			a.circle(16, 17, 14, 0x7899ae)
			a.circle(15, 15, 14, 0xffffff)
			a.circle(15, 15, 11, 0x3a78ca)
			a.circle(13, 12, 8, 0x6ca9eb)
			a.line(11, 9, 14, 7, 0xffffff, 2)
			a.line(14, 7, 19, 9, 0xffffff, 2)
			a.line(19, 9, 19, 13, 0xffffff, 2)
			a.line(19, 13, 15, 16, 0xffffff, 2)
			a.line(15, 16, 15, 19, 0xffffff, 2)
			a.circle(15, 24, 1, 0xffffff)
		}
		'luna_search' {
			a.line(5, 28, 15, 17, 0x9e7934, 6)
			a.line(4, 26, 13, 17, 0xf2cf68, 3)
			a.circle(21, 11, 10, 0x6d939f)
			a.circle(20, 10, 8, 0xeaffff)
			a.circle(21, 11, 6, 0xc6e7ee)
			a.line(15, 7, 18, 4, 0xffffff, 2)
		}
		'luna_run' {
			a.quad([4, 11, 28, 11, 24, 26, 1, 26]!, 0x70889b, 0x7b8f9d)
			a.quad([5, 13, 26, 13, 22, 23, 3, 23]!, 0xffffff, 0xe1e5de)
			a.line(6, 13, 25, 13, 0x4572b1, 2)
			a.line(2, 10, 10, 10, 0x9ca7af, 1)
			a.line(0, 15, 5, 15, 0x9ca7af, 1)
		}
		else {}
	}
}
