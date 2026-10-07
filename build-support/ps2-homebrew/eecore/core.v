// SPDX-License-Identifier: MIT
// Bare-metal PADDLE gameplay and drawing on the emulated Emotion Engine.
@[has_globals; translated]
module eecore

#include <native-abi.h>

struct C.ps2_volatile_word {
mut:
	value u32
}

struct C.ps2_volatile_byte {
mut:
	value u8
}

struct C.ps2_volatile_quad {
mut:
	value u64
}

@[c_extern]
__global C.iop_image &u8

fn C.ps2_ee_sync()

@[inline]
fn read32(address u32) u32 { return unsafe { (&C.ps2_volatile_word(usize(address))).value } }

@[inline]
fn write32(address u32, value u32) {
	unsafe { (&C.ps2_volatile_word(usize(address))).value = value }
}

@[inline]
fn write8(address u32, value u8) {
	unsafe { (&C.ps2_volatile_byte(usize(address))).value = value }
}

@[inline]
fn read64(address u32) u64 { return unsafe { (&C.ps2_volatile_quad(usize(address))).value } }

@[inline]
fn write64(address u32, value u64) {
	unsafe { (&C.ps2_volatile_quad(usize(address))).value = value }
}

@[inline]
fn saved(index u32) u32 { return read32(0x1c000800 + index * 4) }

@[inline]
fn save_word(index u32, value u32) { write32(0x1c000800 + index * 4, value) }

@[aligned: 16]
struct Packet {
mut:
	data u64
	reg  u64
}

struct Digits {
mut:
	bytes [8]char
}

__global (
	packet   [8192]Packet
	used     u32
	sequence u32
	paddle   i32 = 274
	ball_x   i32 = 320
	ball_y   i32 = 397
	dx       i32 = 3
	dy       i32 = -4
	score    u32
	lives    u32 = 3
	mode     u32
	flying   u32
	age      u32
	bricks   [40]u32
)

const characters = [u8(48), 49, 50, 51, 52, 53, 54, 55, 56, 57, 65, 66, 67, 68, 69, 70, 71, 72,
	73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 0]!
const font = [u8(7), 5, 5, 5, 7, 2, 6, 2, 2, 7, 7, 1, 7, 4, 7, 7, 1, 7, 1, 7, 5, 5, 7, 1, 1, 7,
	4, 7, 1, 7, 7, 4, 7, 5, 7, 7, 1, 2, 2, 2, 7, 5, 7, 5, 7, 7, 5, 7, 1, 7, 2, 5, 7, 5, 5, 6, 5,
	6, 5, 6, 7, 4, 4, 4, 7, 6, 5, 5, 5, 6, 7, 4, 6, 4, 7, 7, 4, 6, 4, 4, 7, 4, 5, 5, 7, 5, 5, 7,
	5, 5, 7, 2, 2, 2, 7, 1, 1, 1, 5, 7, 5, 5, 6, 5, 5, 4, 4, 4, 4, 7, 5, 7, 7, 5, 5, 5, 7, 7, 7,
	5, 7, 5, 5, 5, 7, 7, 5, 7, 4, 4, 7, 5, 5, 7, 1, 6, 5, 6, 5, 5, 7, 4, 7, 1, 7, 7, 2, 2, 2, 2,
	5, 5, 5, 5, 7, 5, 5, 5, 5, 2, 5, 5, 7, 7, 5, 5, 5, 2, 5, 5, 5, 5, 2, 2, 2, 7, 1, 2, 4, 7]!
const colors = [u32(0xff6978), 0xffa85c, 0xffdb72, 0x63d9bc, 0x739cff]!

fn reg(id u32, value u64) {
	unsafe {
		packet[used].data = value
		packet[used].reg = id
		used++
	}
}

fn rgb(value u32) u64 {
	unsafe {
		return u64((value >> 16) & 255) | u64(value & 0xff00) | (u64(value & 255) << 16) | 0x80000000
	}
}

fn rectangle(x i32, y i32, width i32, height i32, color u32) {
	unsafe {
		reg(0x00, 6)
		reg(0x01, rgb(color))
		reg(0x05, (u64(u32(y)) << 20) | u64(u32(x) << 4))
		reg(0x05, (u64(u32(y + height)) << 20) | u64(u32(x + width) << 4))
	}
}

fn text(origin i32, y i32, value &char, scale i32, color u32) {
	unsafe {
		mut x := origin
		mut cursor := &char(usize(value))
		for *cursor != 0 {
			mut glyph := u32(0)
			for glyph < 36 && characters[glyph] != u8(*cursor) { glyph++ }
			if glyph != 36 {
				for row := u32(0); row < 5; row++ {
					for col := u32(0); col < 3; col++ {
						if u32(font[glyph * 5 + row]) & (u32(4) >> col) != 0 {
							rectangle(x + i32(col) * scale, y + i32(row) * scale, scale, scale, color)
						}
					}
				}
			}
			cursor++
			x += 4 * scale
		}
	}
}

fn number(x i32, y i32, original u32, color u32) {
	unsafe {
		mut digits := Digits{}
		mut value := original
		mut n := u32(0)
		for {
			digits.bytes[n] = char(u32(48) + value % 10)
			n++
			value /= 10
			if value == 0 || n >= 7 { break }
		}
		for i := u32(0); i < n / 2; i++ {
			c := digits.bytes[i]
			digits.bytes[i] = digits.bytes[n - i - 1]
			digits.bytes[n - i - 1] = c
		}
		digits.bytes[n] = 0
		text(x, y, &digits.bytes[0], 3, color)
	}
}

fn send() {
	unsafe {
		packet[0].data = u64(used - 1) | (u64(7) << 28)
		packet[0].reg = 0
		packet[1].data = u64(used - 2) | 0x8000 | (u64(1) << 60)
		packet[1].reg = 0x0e
		C.ps2_ee_sync()
		write32(0x1000a030, u32(usize(&packet[0])))
		write32(0x1000a020, 0)
		write32(0x1000a000, 0x105)
		for read32(0x1000a000) & 0x100 != 0 { continue }
	}
}

fn input(save u32) u32 {
	unsafe {
		sequence = (sequence + 1) & 0x7fff
		command := (sequence << 16) | if save != 0 { u32(0x80000000) } else { u32(0) }
		write32(0x1000f200, command)
		for read32(0x1000f210) & 0xffff0000 != command { continue }
		return ~read32(0x1000f210) & 0xffff
	}
}

fn restart() {
	unsafe {
		paddle = 274
		ball_x = 320
		ball_y = 397
		dx = 3
		dy = -4
		score = 0
		lives = 3
		mode = 1
		flying = 1
		for i := u32(0); i < 40; i++ { bricks[i] = 1 }
		save_word(1, saved(1) + 1)
		input(1)
	}
}

fn update(buttons u32) {
	unsafe {
		age++
		if mode == 0 || mode == 2 {
			if buttons & (0x0008 | 0x4000) != 0 { restart() }
			return
		}
		if buttons & 0x80 != 0 { paddle -= 6 }
		if buttons & 0x20 != 0 { paddle += 6 }
		if paddle < 24 { paddle = 24 }
		if paddle > 520 { paddle = 520 }
		if flying == 0 {
			ball_x = paddle + 46
			if buttons & 0x4000 != 0 { flying = 1 }
			return
		}
		ball_x += dx
		ball_y += dy
		if ball_x < 28 || ball_x > 608 { dx = -dx }
		if ball_y < 58 { dy = -dy }
		if dy > 0 && ball_y >= 394 && ball_y <= 405 && ball_x >= paddle - 8 && ball_x <= paddle + 100 {
			dy = -4
			dx = if ball_x < paddle + 46 { i32(-3) } else { i32(3) }
		}
		if ball_y > 442 {
			flying = 0
			ball_y = 397
			dx = 3
			dy = -4
			lives--
			if lives == 0 { mode = 2 }
		}
		mut remaining := u32(0)
		for i := u32(0); i < 40; i++ {
			if bricks[i] == 0 { continue }
			remaining++
			x := 32 + i32(i % 8) * 72
			y := 88 + i32(i / 8) * 29
			if ball_x >= x - 6 && ball_x <= x + 68 && ball_y >= y - 6 && ball_y <= y + 24 {
				bricks[i] = 0
				score += 10
				dy = -dy
				if score > saved(0) {
					save_word(0, score)
					input(1)
				}
				break
			}
		}
		if remaining == 0 {
			for i := u32(0); i < 40; i++ { bricks[i] = 1 }
			flying = 0
			ball_y = 397
			dx = 3
			dy = -4
		}
	}
}

fn draw() {
	unsafe {
		used = 2
		reg(0x4c, u64(10) << 16)
		reg(0x4e, u64(1) << 32)
		reg(0x40, (u64(639) << 16) | (u64(479) << 48))
		reg(0x18, 0)
		reg(0x47, 0)
		reg(0x1a, 1)
		rectangle(0, 0, 640, 480, 0x0b1025)
		for i := u32(0); i < 38; i++ {
			x := 26 + i32((i * 137) % 580)
			y := 55 + i32((i * 79 + age / 3) % 382)
			rectangle(x, y, 2, 2, 0x455170)
		}
		rectangle(18, 50, 4, 394, 0x314572)
		rectangle(618, 50, 4, 394, 0x314572)
		rectangle(18, 50, 604, 4, 0x314572)
		text(26, 20, c'SCORE', 3, 0x91a2c9)
		number(98, 20, score, 0xffffff)
		text(242, 20, c'BEST', 3, 0x91a2c9)
		number(302, 20, saved(0), 0xffdb72)
		text(480, 20, c'LIVES', 3, 0x91a2c9)
		number(558, 20, lives, 0xffffff)
		for i := u32(0); i < 40; i++ {
			if mode != 0 && bricks[i] == 0 { continue }
			x := 32 + i32(i % 8) * 72
			y := 88 + i32(i / 8) * 29
			rectangle(x, y, 66, 22, colors[i / 8])
			rectangle(x + 3, y + 3, 60, 3, 0xffffff)
		}
		rectangle(paddle, 410, 96, 12, 0x63d9bc)
		rectangle(paddle + 5, 412, 86, 3, 0xc4ffee)
		rectangle(ball_x - 5, ball_y - 5, 10, 10, 0xffffff)
		text(82, 455, c'LEFT RIGHT MOVE   CROSS LAUNCH', 3, 0x91a2c9)
		if mode == 0 || mode == 2 {
			rectangle(108, 234, 424, 139, 0x182443)
			rectangle(108, 234, 424, 4, 0x739cff)
			text(if mode != 0 { i32(148) } else { i32(200) }, 257,
				if mode != 0 { c'GAME OVER' } else { c'PADDLE' }, if mode != 0 {
					i32(9)
				} else {
					i32(10)
				}, 0xffffff)
			text(182, 324, c'PRESS START', 6, 0x63d9bc)
		}
		send()
	}
}

@[export: 'game_main'; noreturn]
pub fn run() {
	unsafe {
		for i := u32(0); i < u32(C.VINIX_IOP_IMAGE_BYTES); i++ {
			write8(0x1c001000 + i, C.iop_image[i])
		}
		C.ps2_ee_sync()
		write32(0x1c000000, 0x08000400)
		input(0)
		write64(0x12000000, 1)
		write64(0x12000020, 0)
		write64(0x12000070, u64(10) << 9)
		write64(0x12000080, (u64(639) << 32) | (u64(479) << 44))
		write32(0x1000e000, 1)
		for {
			draw()
			write64(0x12001000, 8)
			for read64(0x12001000) & 8 == 0 { continue }
			update(input(0))
		}
	}
}
