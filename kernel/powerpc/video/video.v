// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module video

import powerpc.boot
import powerpc.mmio

__global surface u32
__global width u32
__global height u32
__global stride u32
__global column u32
__global row u32
__global columns u32
__global rows u32
__global cells [16384]u8
__global mouse_x int
__global mouse_y int
__global mouse_buttons u8
__global mouse_visible bool
__global mouse_enabled bool
__global mouse_saved [384]u32

const background = u32(0x15212e)
const foreground = u32(0xdce9f2)

pub fn pixel(x u32, y u32, color u32) {
	if surface == 0 || x >= width || y >= height { return }
	mmio.write_be32(surface + y * stride + x * 4, color)
}

fn rectangle(x u32, y u32, w u32, h u32, color u32) {
	for yy := y; yy < y + h && yy < height; yy++ {
		for xx := x; xx < x + w && xx < width; xx++ { pixel(xx, yy, color) }
	}
}

fn character(x u32, y u32, byte u8, color u32, bg u32) {
	bits := glyph(byte)
	for yy := u32(0); yy < 16; yy++ {
		pattern := if yy < 14 { u32(bits >> (48 - (yy / 2) * 8)) } else { u32(0) }
		for xx := u32(0); xx < 12; xx++ {
			pixel(x + xx, y + yy, if xx < 10 && pattern & (16 >> (xx / 2)) != 0 { color } else { bg })
		}
	}
}

fn label(x u32, y u32, text &char, color u32, bg u32) {
	unsafe { for i := u32(0); text[i] != 0; i++ { character(x + i * 12, y, u8(text[i]), color, bg) } }
}

pub fn init(info &boot.Info) bool {
	if info.framebuffer == 0 || info.depth != 32 || info.width < 320 || info.width > 1920
		|| info.height < 240 || info.height > 1200 || info.pitch < info.width * 4
		|| info.pitch > (0xffffffff - info.framebuffer) / info.height { return false }
	surface = info.framebuffer
	width = info.width
	height = info.height
	stride = info.pitch
	columns = (width - 32) / 12
	rows = (height - 96) / 18
	if columns * rows > 16384 { surface = 0; return false }
	rectangle(0, 0, width, height, background)
	rectangle(0, 0, width, 40, 0x256a83)
	label(16, 12, c'Vinix / PowerPC', 0xffffff, 0x256a83)
	label(16, height - 24, c'PPC32 development console', 0x82a1b5, background)
	// Independent RGB swatches expose incorrect framebuffer byte order.
	rectangle(width - 80, 12, 16, 16, 0xff0000)
	rectangle(width - 56, 12, 16, 16, 0x00ff00)
	rectangle(width - 32, 12, 16, 16, 0x0000ff)
	for i := u32(0); i < 16384; i++ { cells[i] = ` ` }
	return true
}

fn draw_cell(x u32, y u32) {
	character(16 + x * 12, 56 + y * 18, cells[y * columns + x], foreground, background)
}

pub fn put(byte u8) {
	if surface == 0 { return }
	hide_pointer()
	defer { show_pointer() }
	if byte == `\r` { column = 0; return }
	if byte == 8 {
		if column > 0 { column-- }
		return
	}
	if byte == `\n` {
		column = 0
		row++
	} else if byte >= 32 && byte <= 126 {
		cells[row * columns + column] = byte
		draw_cell(column, row)
		column++
		if column == columns { column = 0; row++ }
	}
	if row == rows {
		for y := u32(0); y < rows; y++ {
			for x := u32(0); x < columns; x++ {
				cells[y * columns + x] = if y + 1 < rows { cells[(y + 1) * columns + x] } else { u8(` `) }
				draw_cell(x, y)
			}
		}
		row--
	}
}

fn hide_pointer() {
	if !mouse_visible { return }
	for y in 0 .. 24 {
		for x in 0 .. 16 { pixel(u32(mouse_x + x), u32(mouse_y + y), mouse_saved[y * 16 + x]) }
	}
	mouse_visible = false
}

fn show_pointer() {
	if !mouse_enabled || mouse_visible || surface == 0 { return }
	for y in 0 .. 24 {
		for x in 0 .. 16 {
			address := surface + u32(mouse_y + y) * stride + u32(mouse_x + x) * 4
			mouse_saved[y * 16 + x] = mmio.read_be32(address)
			if y < 20 && x <= y / 2 {
				color := if x == 0 || x == y / 2 || y == 19 { u32(0x000000) } else if mouse_buttons & 1 != 0 { u32(0xffb454) } else { u32(0xffffff) }
				pixel(u32(mouse_x + x), u32(mouse_y + y), color)
			}
		}
	}
	mouse_visible = true
}

pub fn pointer(dx int, dy int, buttons u8) {
	if surface == 0 { return }
	hide_pointer()
	if !mouse_enabled { mouse_x = int(width / 2); mouse_y = int(height / 2); mouse_enabled = true }
	mouse_x += dx
	mouse_y += dy
	if mouse_x < 0 { mouse_x = 0 }
	if mouse_y < 0 { mouse_y = 0 }
	if mouse_x > int(width) - 16 { mouse_x = int(width) - 16 }
	if mouse_y > int(height) - 24 { mouse_y = int(height) - 24 }
	mouse_buttons = buttons
	show_pointer()
}
