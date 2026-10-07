// SPDX-License-Identifier: MIT
// All gameplay and drawing run on the emulated R4300, using native MMIO.
@[translated; has_globals]
module paddlecore

#include <native-abi.h>

struct C.n64_volatile_word { mut: value u32 }
struct C.n64_volatile_byte { mut: value u8 }
struct C.n64_volatile_half { mut: value u16 }
fn C.n64_sync()

@[inline]
fn read32(address u32) u32 {
	return unsafe { (&C.n64_volatile_word(usize(address))).value }
}

@[inline]
fn write32(address u32, value u32) {
	unsafe { (&C.n64_volatile_word(usize(address))).value = value }
}

@[inline]
fn read8(address u32) u8 {
	return unsafe { (&C.n64_volatile_byte(usize(address))).value }
}

@[inline]
fn write8(address u32, value u8) {
	unsafe { (&C.n64_volatile_byte(usize(address))).value = value }
}

@[inline]
fn write16(address u32, value u16) {
	unsafe { (&C.n64_volatile_half(usize(address))).value = value }
}

__global (
	pixels u32
	best u32
	games u32
	score u32
	lives u32
	mode u32
	flying u32
	age u32
	buffer u32
	paddle i32 = 136
	ball_x i32 = 160
	ball_y i32 = 199
	dx i32 = 2
	dy i32 = -2
	bricks [40]u32
)

const characters = [u8(48), 49, 50, 51, 52, 53, 54, 55, 56, 57,
	65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79,
	80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 0]!
const font = [u8(7),5,5,5,7, 2,6,2,2,7, 7,1,7,4,7, 7,1,7,1,7, 5,5,7,1,1,
	7,4,7,1,7, 7,4,7,5,7, 7,1,2,2,2, 7,5,7,5,7, 7,5,7,1,7,
	2,5,7,5,5, 6,5,6,5,6, 7,4,4,4,7, 6,5,5,5,6, 7,4,6,4,7,
	7,4,6,4,4, 7,4,5,5,7, 5,5,7,5,5, 7,2,2,2,7, 1,1,1,5,7,
	5,5,6,5,5, 4,4,4,4,7, 5,7,7,5,5, 5,7,7,7,5, 7,5,5,5,7,
	7,5,7,4,4, 7,5,5,7,1, 6,5,6,5,5, 7,4,7,1,7, 7,2,2,2,2,
	5,5,5,5,7, 5,5,5,5,2, 5,5,7,7,5, 5,5,2,5,5, 5,5,2,2,2,
	7,1,2,4,7]!
const colors = [u32(0xff6978), 0xffa85c, 0xffdb72, 0x63d9bc, 0x739cff]!

struct Digits { mut: bytes [8]char }

fn pi_transfer(reading u32) {
	for read32(0xa4600010) & 3 != 0 { continue }
	write32(0xa4600000, 0x002f0100)
	write32(0xa4600004, 0x08000000)
	write32(if reading != 0 { u32(0xa460000c) } else { u32(0xa4600008) }, 15)
	for read32(0xa4600010) & 3 != 0 { continue }
	write32(0xa4600010, 2)
}

fn save() {
	write32(0xa02f0100, 0x4e504144)
	write32(0xa02f0104, best)
	write32(0xa02f0108, games)
	write32(0xa02f010c, read32(0xa02f0100) ^ read32(0xa02f0104) ^ read32(0xa02f0108))
	C.n64_sync()
	pi_transfer(0)
}

fn input(stick &i32) u32 {
	for read32(0xa4800018) & 3 != 0 { continue }
	for i := u32(0); i < 64; i++ { write8(0xa02f0000 + i, 0) }
	write8(0xa02f0000, 1)
	write8(0xa02f0001, 4)
	write8(0xa02f0002, 1)
	write8(0xa02f0007, 0xfe)
	write8(0xa02f003f, 1)
	C.n64_sync()
	write32(0xa4800000, 0x002f0000)
	write32(0xa4800010, 0x1fc007c0)
	for read32(0xa4800018) & 3 != 0 { continue }
	write32(0xa4800018, 0)
	write32(0xa4800000, 0x002f0000)
	write32(0xa4800004, 0x1fc007c0)
	for read32(0xa4800018) & 3 != 0 { continue }
	write32(0xa4800018, 0)
	unsafe { *stick = i32(i8(read8(0xa02f0005))) }
	return u32(read8(0xa02f0003)) << 8 | u32(read8(0xa02f0004))
}

fn color(value u32) u16 {
	return u16(((value >> 8) & 0xf800) | ((value >> 5) & 0x7c0) | ((value >> 2) & 0x3e) | 1)
}

fn clear(origin u32) {
	ink := u32(color(0x0b1025))
	write32(0xa02f0200, 0xff100000 | (320 - 1))
	write32(0xa02f0204, origin)
	write32(0xa02f0208, 0xed000000)
	write32(0xa02f020c, (320 * 4 << 12) | (240 * 4))
	write32(0xa02f0210, 0xef300000)
	write32(0xa02f0214, 0)
	write32(0xa02f0218, 0xf7000000)
	write32(0xa02f021c, ink | (ink << 16))
	write32(0xa02f0220, 0xf6000000 | ((320 - 1) * 4 << 12) | ((240 - 1) * 4))
	write32(0xa02f0224, 0)
	write32(0xa02f0228, 0xe9000000)
	write32(0xa02f022c, 0)
	C.n64_sync()
	write32(0xa4300000, 0x800)
	write32(0xa410000c, 0x15)
	write32(0xa4100000, 0x002f0200)
	write32(0xa4100004, 0x002f0230)
	for read32(0xa4300008) & 0x20 == 0 { continue }
}

fn rectangle(x i32, y i32, width i32, height i32, value u32) {
	ink := color(value)
	for row := y; row < y + height; row++ {
		for col := x; col < x + width; col++ {
			write16(pixels + u32(row * 320 + col) * 2, ink)
		}
	}
}

fn text(x_start i32, y i32, value_start &char, scale i32, ink u32) {
	unsafe {
		mut x := x_start
		mut value := &char(usize(value_start))
		for *value != 0 {
			mut glyph := u32(0)
			for glyph < 36 && characters[glyph] != u8(*value) { glyph++ }
			if glyph != 36 {
				for row := u32(0); row < 5; row++ {
					for col := u32(0); col < 3; col++ {
						if u32(font[glyph * 5 + row]) & (4 >> col) != 0 {
							rectangle(x + i32(col) * scale, y + i32(row) * scale, scale, scale, ink)
						}
					}
				}
			}
			value++
			x += 4 * scale
		}
	}
}

fn number(x i32, y i32, value u32, ink u32) {
	unsafe {
		mut storage := Digits{}
		digits := &storage.bytes[0]
		mut amount := value
		mut n := u32(0)
		for {
			digits[n] = char(u32(48) + amount % 10)
			n++
			amount /= 10
			if amount == 0 || n >= 7 { break }
		}
		for i := u32(0); i < n / 2; i++ {
			c := digits[i]
			digits[i] = digits[n - i - 1]
			digits[n - i - 1] = c
		}
		digits[n] = 0
		text(x, y, &digits[0], 2, ink)
	}
}

fn restart() {
	unsafe {
		paddle = 136; ball_x = 160; ball_y = 199; dx = 2; dy = -2
		score = 0; lives = 3; mode = 1; flying = 1
		for i := u32(0); i < 40; i++ { bricks[i] = 1 }
		games++
		save()
	}
}

fn update(buttons u32, stick i32) {
	unsafe {
		age++
		if mode == 0 || mode == 2 {
			if buttons & 0x9000 != 0 { restart() }
			return
		}
		if buttons & 0x0200 != 0 || stick < -16 { paddle -= 4 }
		if buttons & 0x0100 != 0 || stick > 16 { paddle += 4 }
		if paddle < 12 { paddle = 12 }
		if paddle > 260 { paddle = 260 }
		if flying == 0 {
			ball_x = paddle + 24
			if buttons & 0x8000 != 0 { flying = 1 }
			return
		}
		ball_x += dx; ball_y += dy
		if ball_x < 14 || ball_x > 304 { dx = -dx }
		if ball_y < 29 { dy = -dy }
		if dy > 0 && ball_y >= 198 && ball_y <= 203 && ball_x >= paddle - 4 && ball_x <= paddle + 52 {
			dy = -2; dx = if ball_x < paddle + 24 { -2 } else { 2 }
		}
		if ball_y > 221 {
			flying = 0; ball_y = 199; dx = 2; dy = -2
			lives--
			if lives == 0 { mode = 2 }
		}
		mut remaining := u32(0)
		for i := u32(0); i < 40; i++ {
			if bricks[i] == 0 { continue }
			remaining++
			x := 16 + i32(i % 8) * 36; y := 44 + i32(i / 8) * 15
			if ball_x >= x - 3 && ball_x <= x + 34 && ball_y >= y - 3 && ball_y <= y + 12 {
				bricks[i] = 0; score += 10; dy = -dy
				if score > best { best = score; save() }
				break
			}
		}
		if remaining == 0 {
			for i := u32(0); i < 40; i++ { bricks[i] = 1 }
			flying = 0; ball_y = 199; dx = 2; dy = -2
		}
	}
}

fn draw() {
	unsafe {
		origin := if buffer != 0 { u32(0x00140000) } else { u32(0x00100000) }
		pixels = 0xa0000000 | origin
		clear(origin)
		for i := u32(0); i < 38; i++ {
			x := 13 + i32((i * 67) % 290); y := 28 + i32((i * 39 + age / 3) % 188)
			rectangle(x, y, 1, 1, 0x455170)
		}
		rectangle(9, 25, 2, 197, 0x314572)
		rectangle(309, 25, 2, 197, 0x314572)
		rectangle(9, 25, 302, 2, 0x314572)
		text(13, 10, c'SCORE', 2, 0x91a2c9)
		number(58, 10, score, 0xffffff)
		text(125, 10, c'BEST', 2, 0x91a2c9)
		number(161, 10, best, 0xffdb72)
		text(238, 10, c'LIVES', 2, 0x91a2c9)
		number(283, 10, lives, 0xffffff)
		for i := u32(0); i < 40; i++ {
			if mode != 0 && bricks[i] == 0 { continue }
			x := 16 + i32(i % 8) * 36; y := 44 + i32(i / 8) * 15
			rectangle(x, y, 33, 11, colors[i / 8])
			rectangle(x + 2, y + 2, 29, 2, 0xffffff)
		}
		rectangle(paddle, 205, 48, 6, 0x63d9bc)
		rectangle(paddle + 3, 206, 42, 2, 0xc4ffee)
		rectangle(ball_x - 2, ball_y - 2, 5, 5, 0xffffff)
		text(20, 224, c'DPAD OR STICK MOVE  A LAUNCH', 2, 0x91a2c9)
		if mode == 0 || mode == 2 {
			rectangle(54, 117, 212, 69, 0x182443)
			rectangle(54, 117, 212, 2, 0x739cff)
			text(if mode != 0 { 80 } else { 112 }, 130, if mode != 0 { &char(c'GAME OVER') } else { &char(c'PADDLE') }, 4, 0xffffff)
			text(94, 163, c'PRESS START', 3, 0x63d9bc)
		}
		C.n64_sync()
		write32(0xa4400004, origin)
		buffer ^= 1
	}
}

@[export: 'game_main']
pub fn game_main() {
	write32(0xa4400000, 0x3202)
	write32(0xa4400004, 0x00100000)
	write32(0xa4400008, 320)
	write32(0xa440000c, 2)
	write32(0xa4400014, 0x03e52239)
	write32(0xa4400018, 525)
	write32(0xa440001c, 0x00000c15)
	write32(0xa4400020, 0x0c150c15)
	write32(0xa4400024, 0x006c02ec)
	write32(0xa4400028, 0x002501ff)
	write32(0xa440002c, 0x000e0204)
	write32(0xa4400030, 0x00000200)
	write32(0xa4400034, 0x00000400)
	write32(0xa4600024, 0x40)
	write32(0xa4600028, 0x12)
	write32(0xa460002c, 7)
	write32(0xa4600030, 3)
	pi_transfer(1)
	if read32(0xa02f0100) == 0x4e504144 && read32(0xa02f010c) == (read32(0xa02f0100) ^ read32(0xa02f0104) ^ read32(0xa02f0108)) {
		best = read32(0xa02f0104); games = read32(0xa02f0108)
	}
	lives = 3
	for {
		draw()
		for read32(0xa4400010) < 480 { continue }
		for read32(0xa4400010) >= 480 { continue }
		mut stick := i32(0)
		buttons := input(&stick)
		update(buttons, stick)
	}
}
