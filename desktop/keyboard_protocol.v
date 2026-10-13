// SPDX-License-Identifier: GPL-2.0-or-later
// Kitty keyboard protocol, all five progressive enhancements (flags 31).
// Physical input stays distinct from the legacy stream used by ui2 and the
// desktop's shortcuts. Buffers and decimal/UTF-8 encoding allocate nothing.
module main

const physical_layout_keys = [41, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 16, 17, 18, 19, 20, 21,
	22, 23, 24, 25, 26, 27, 43, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 44, 45, 46, 47, 48,
	49, 50, 51, 52, 53, 86]!

// USB boot keyboard usages, also used by the Apple SPI keyboard.
const physical_hid_codes = [0, 0, 0, 0, 30, 48, 46, 32, 18, 33, 34, 35, 23, 36, 37, 38, 50, 49,
	24, 25, 16, 19, 31, 20, 22, 47, 17, 45, 21, 44, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 28, 1, 14,
	15, 57, 12, 13, 26, 27, 43, 43, 39, 40, 41, 51, 52, 53, 58, 59, 60, 61, 62, 63, 64, 65, 66,
	67, 68, 87, 88, 99, 70, 119, 110, 102, 104, 111, 107, 109, 106, 105, 108, 103, 69, 98, 55,
	74, 78, 96, 79, 80, 81, 75, 76, 77, 71, 72, 73, 82, 83, 86, 127, 116, 117, 183, 184, 185, 186,
	187, 188, 189, 190, 191, 192, 193, 194, 134, 138, 130, 132, 128, 129, 131, 137, 133, 135, 136,
	113, 115, 114]!

struct KeyEncoding {
mut:
	bytes  [512]u8
	length int
}

fn (mut out KeyEncoding) byte(b u8) {
	if out.length < out.bytes.len {
		out.bytes[out.length] = b
		out.length++
	}
}

fn (mut out KeyEncoding) decimal(number int) {
	mut digits := [10]u8{}
	mut value := number
	mut count := 0
	for {
		digits[count] = u8(`0`) + u8(value % 10)
		count++
		value /= 10
		if value == 0 { break }
	}
	for count > 0 {
		count--
		out.byte(digits[count])
	}
}

fn (out &KeyEncoding) text() string { return unsafe { tos(&out.bytes[0], out.length) } }

struct PhysicalIdentity {
mut:
	code     int
	shifted  int
	base     int
	number   int
	final    u8 = `u`
	modifier bool
}

fn physical_identity(key int, layout KeyboardLayout) PhysicalIdentity {
	for slot, code in physical_layout_keys {
		if code != key { continue }
		mut result := PhysicalIdentity{ code: int(keymap_us_lower[slot]), shifted: int(keymap_us_upper[slot]), base: int(keymap_us_lower[slot]) }
		if table := keymap_for(layout) {
			result.code = int(table.lower[slot])
			result.shifted = int(table.upper[slot])
		}
		result.number = result.code
		return result
	}
	mut result := PhysicalIdentity{}
	result.code = match key {
		1 { 27 }
		14 { 127 }
		15 { 9 }
		28 { 13 }
		57 { 32 }
		58 { 57358 }
		70 { 57359 }
		69 { 57360 }
		99 { 57361 }
		119 { 57362 }
		127, 139 { 57363 }
		42 { 57441 }
		29 { 57442 }
		56 { 57443 }
		125 { 57444 }
		54 { 57447 }
		97 { 57448 }
		100 { 57449 }
		126 { 57450 }
		82 { 57399 }
		79 { 57400 }
		80 { 57401 }
		81 { 57402 }
		75 { 57403 }
		76 { 57404 }
		77 { 57405 }
		71 { 57406 }
		72 { 57407 }
		73 { 57408 }
		83 { 57409 }
		98 { 57410 }
		55 { 57411 }
		74 { 57412 }
		78 { 57413 }
		96 { 57414 }
		117 { 57415 }
		121 { 57416 }
		164 { 57430 }
		166 { 57432 }
		208 { 57433 }
		168 { 57434 }
		163 { 57435 }
		165 { 57436 }
		167 { 57437 }
		114 { 57438 }
		115 { 57439 }
		113 { 57440 }
		else {
			if key >= 183 && key <= 194 { 57376 + key - 183 } else { 0 }
		}
	}
	result.modifier = key in [42, 29, 56, 125, 54, 97, 100, 126]
	result.number = result.code
	match key {
		103 {
			result.number = 1
			result.final = `A`
		}
		108 {
			result.number = 1
			result.final = `B`
		}
		106 {
			result.number = 1
			result.final = `C`
		}
		105 {
			result.number = 1
			result.final = `D`
		}
		102 {
			result.number = 1
			result.final = `H`
		}
		107 {
			result.number = 1
			result.final = `F`
		}
		110 {
			result.number = 2
			result.final = `~`
		}
		111 {
			result.number = 3
			result.final = `~`
		}
		104 {
			result.number = 5
			result.final = `~`
		}
		109 {
			result.number = 6
			result.final = `~`
		}
		59 {
			result.number = 1
			result.final = `P`
		}
		60 {
			result.number = 1
			result.final = `Q`
		}
		61 {
			result.number = 13
			result.final = `~`
		}
		62 {
			result.number = 1
			result.final = `S`
		}
		63, 64, 65, 66, 67, 68, 87, 88 {
			result.number = match key {
				63 { 15 }
				64 { 17 }
				65 { 18 }
				66 { 19 }
				67 { 20 }
				68 { 21 }
				87 { 23 }
				else { 24 }
			}
			result.final = `~`
		}
		else {}
	}
	return result
}

fn kitty_key(key int, modifiers int, value int, layout KeyboardLayout, text string) KeyEncoding {
	mut info := physical_identity(key, layout)
	if modifiers & 128 == 0 {
		info.number = match key {
			82 { 57425 }
			79 { 57424 }
			80 { 57420 }
			81 { 57422 }
			75 { 57417 }
			77 { 57418 }
			71 { 57423 }
			72 { 57419 }
			73 { 57421 }
			83 { 57426 }
			else { info.number }
		}
		if key == 76 {
			info.number = 1
			info.final = `E`
		}
	}
	mut out := KeyEncoding{}
	if info.number == 0 { return out }
	out.byte(27)
	out.byte(`[`)
	out.decimal(info.number)
	if info.final == `u` && info.base != 0 {
		shifted := modifiers & 1 != 0 && info.shifted != info.code
		base := info.base != info.code
		if shifted || base {
			out.byte(`:`)
			if shifted { out.decimal(info.shifted) }
			if base {
				out.byte(`:`)
				out.decimal(info.base)
			}
		}
	}
	out.byte(`;`)
	out.decimal(modifiers + 1)
	out.byte(`:`)
	out.decimal(if value == 0 {
		3
	} else if value == 2 {
		2
	} else {
		1
	})
	// Associated text belongs only to press/repeat events that produce text.
	// Decode UTF-8 directly to avoid allocating a rune array for every key.
	if value != 0 && info.final == `u` && !info.modifier && modifiers & 12 == 0 {
		mut at := if text.len > 1 && text[0] == 27 && (info.base != 0 || key == 57) { 1 } else { 0 }
		mut first := true
		for at < text.len {
			point, width := keyboard_text_point(text, at)
			at += width
			if point < 32 || (point >= 127 && point <= 159) { continue }
			out.byte(if first { u8(`;`) } else { u8(`:`) })
			out.decimal(point)
			first = false
		}
	}
	out.byte(info.final)
	return out
}

fn keyboard_text_point(text string, at int) (int, int) {
	b := text[at]
	if b < 128 { return int(b), 1 }
	if b < 194 || b > 244 { return 0, 1 }
	width := if b < 224 {
		2
	} else if b < 240 {
		3
	} else {
		4
	}
	if at + width > text.len { return 0, 1 }
	mut point := u32(b & if width == 2 {
		u8(31)
	} else if width == 3 {
		u8(15)
	} else {
		u8(7)
	})
	for i in 1 .. width {
		if text[at + i] & 192 != 128 { return 0, 1 }
		point = point << 6 | u32(text[at + i] & 63)
	}
	if (width == 3 && point < 2048) || (width == 4 && point < 65536) || point > 0x10ffff || (point >= 0xd800 && point <= 0xdfff) {
		return 0, 1
	}
	return int(point), width
}

fn (kbd &Keyboard) modifiers() int {
	return (if kbd.held[42] || kbd.held[54] { 1 } else { 0 }) |
		(if kbd.held[56] || kbd.held[100] { 2 } else { 0 }) |
		(if kbd.held[29] || kbd.held[97] { 4 } else { 0 }) |
		(if kbd.held[125] || kbd.held[126] { 8 } else { 0 }) |
		(if kbd.caps { 64 } else { 0 }) | (if kbd.num { 128 } else { 0 })
}

fn legacy_physical_key(key int, modifiers int, value int) KeyEncoding {
	mut out := KeyEncoding{}
	if value != 0 {
		if key == 96 { return legacy_physical_key(28, modifiers, value) }
		if key in [82, 79, 80, 81, 75, 76, 77, 71, 72, 73, 83] && modifiers & 128 == 0 {
			alias := match key {
				82 { 110 }
				79 { 107 }
				80 { 108 }
				81 { 109 }
				75 { 105 }
				77 { 106 }
				71 { 102 }
				72 { 103 }
				73 { 104 }
				83 { 111 }
				else { 0 }
			}
			if alias > 0 { return legacy_physical_key(alias, modifiers, value) }
			return out
		}
		point := keypad_text(key, modifiers)
		if point > 0 {
			if modifiers & 2 != 0 { out.byte(27) }
			out.byte(u8(point))
			return out
		}
	}
	info := physical_identity(key, .us)
	mods := modifiers & 63
	if value == 0 {
		if (key == 125 || key == 126) && mods & 8 == 0 { return kitty_key(125, 0, 0, .us, '') }
		if (key == 56 || key == 100) && mods & 2 == 0 { return kitty_key(56, 0, 0, .us, '') }
		return out
	}
	if info.modifier { return out }
	if mods & 8 != 0 || (key == 15 && mods & 2 != 0) || info.code > 255 && info.base == 0 && info.final == `u` {
		return kitty_key(key, mods, 1, .us, '')
	}
	if info.final != `u` {
		out.byte(27)
		if mods == 0 && info.final in [u8(`P`), `Q`, `S`] {
			out.byte(`O`)
			out.byte(info.final)
			return out
		}
		out.byte(`[`)
		if info.final == `~` || mods != 0 { out.decimal(info.number) }
		if mods != 0 {
			out.byte(`;`)
			out.decimal(mods + 1)
		}
		out.byte(info.final)
		return out
	}
	if info.code == 0 { return out }
	if mods & 2 != 0 { out.byte(27) }
	mut code := info.code
	if info.base != 0 {
		letter := info.code >= `a` && info.code <= `z`
		shift := mods & 1 != 0
		if shift != (letter && modifiers & 64 != 0) { code = info.shifted }
	}
	if mods & 4 != 0 {
		code = match code {
			32, 64, 50 { 0 }
			51, 91 { 27 }
			52, 92 { 28 }
			53, 93 { 29 }
			54, 94 { 30 }
			55, 47, 95 { 31 }
			56, 63 { 127 }
			else {
				if code >= `a` && code <= `z` {
					code - 96
				} else if code >= `A` && code <= `Z` {
					code - 64
				} else {
					code
				}
			}
		}
	}
	if key == 28 { code = 10 }
	if code < 128 {
		out.byte(u8(code))
	} else if code < 2048 {
		out.byte(u8(192 | code >> 6))
		out.byte(u8(128 | code & 63))
	}
	return out
}

fn keypad_text(key int, modifiers int) int {
	return match key {
		98 { `/` }
		55 { `*` }
		74 { `-` }
		78 { `+` }
		117 { `=` }
		121 { `,` }
		else {
			if modifiers & 128 == 0 {
				0
			} else {
				match key {
					82 { `0` }
					79 { `1` }
					80 { `2` }
					81 { `3` }
					75 { `4` }
					76 { `5` }
					77 { `6` }
					71 { `7` }
					72 { `8` }
					73 { `9` }
					83 { `.` }
					else { 0 }
				}
			}
		}
	}
}

fn physical_packet(bytes &u8, length int) (int, int) {
	unsafe {
		if length < 7 || bytes[0] != 27 || bytes[1] != `[` || bytes[2] != `?` { return 0, -1 }
		mut at := 3
		mut key := 0
		for at < length && bytes[at] >= `0` && bytes[at] <= `9` {
			key = key * 10 + int(bytes[at] - `0`)
			if key > 255 { return 0, -1 }
			at++
		}
		if key > 255 || at + 3 != length || bytes[at] != `;` || bytes[at + 1] > `2` || bytes[at + 1] < `0` {
			return 0, -1
		}
		if bytes[at + 2] == `h` {
			key = if key == 255 {
				255
			} else if key >= 224 && key <= 231 {
				[29, 42, 56, 125, 97, 54, 100, 126]![key - 224]
			} else if key < physical_hid_codes.len {
				physical_hid_codes[key]
			} else {
				0
			}
		} else if bytes[at + 2] != `k` {
			return 0, -1
		}
		return key, int(bytes[at + 1] - `0`)
	}
}
