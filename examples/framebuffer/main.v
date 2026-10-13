// SPDX-License-Identifier: MIT
// A GUI application with no ui2 dependency. Paint a gradient and a cursor.
module main

import desktop.windowfb

fn paint(mut window windowfb.Window, x int, y int) {
	for row in 0 .. window.surface.height {
		for column in 0 .. window.surface.width {
			red := u32(column * 255 / window.surface.width)
			green := u32(row * 255 / window.surface.height)
			color := if column >= x - 8 && column <= x + 8 && row >= y - 8 && row <= y + 8 {
				u32(0xffffff)
			} else {
				red << 16 | green << 8 | 0x60
			}
			unsafe { window.surface.back[row * window.surface.width + column] = color }
		}
	}
}

fn main() {
	mut window := windowfb.open('Framebuffer demo', 640, 480) or {
		eprintln(err)
		exit(1)
	}
	defer { window.close() }
	mut x := 320
	mut y := 240
	mut dirty := true
	mut event := windowfb.Message{}
	for {
		if dirty && !window.frame_pending {
			paint(mut window, x, y)
			window.present() or { break }
			dirty = false
		}
		window.connection.wait(-1) or { break }
		for window.receive(unsafe { &event }) or { return } {
			match event.kind {
				.close { return }
				.configure { dirty = true }
				.motion, .button_down {
					x = int(event.x)
					y = int(event.y)
					dirty = true
				}
				.keys {
					if event.text() == 'q' || event.text() == '\x1b' || event.text() == '\x1b[113;1:1;113u' || event.text() == '\x1b[27;1:1u' { return }
				}
				else {}
			}
		}
	}
}
