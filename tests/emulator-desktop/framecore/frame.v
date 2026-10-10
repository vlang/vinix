// SPDX-License-Identifier: GPL-2.0-or-later
module framecore

import compress.zlib
import encoding.hex
import encoding.utf8
import hash.crc32
import os
import regex
import strconv

// Unicode 13 decimal digits used by the original Python 3.9 host parser.
// Only header numbers accept these digits; RGB rows remain lowercase ASCII hex.
const decimal_zeros = [0x30, 0x660, 0x6f0, 0x7c0, 0x966, 0x9e6, 0xa66, 0xae6, 0xb66, 0xbe6, 0xc66,
	0xce6, 0xd66, 0xde6, 0xe50, 0xed0, 0xf20, 0x1040, 0x1090, 0x17e0, 0x1810, 0x1946, 0x19d0, 0x1a80,
	0x1a90, 0x1b50, 0x1bb0, 0x1c40, 0x1c50, 0xa620, 0xa8d0, 0xa900, 0xa9d0, 0xa9f0, 0xaa50, 0xabf0,
	0xff10, 0x104a0, 0x10d30, 0x11066, 0x110f0, 0x11136, 0x111d0, 0x112f0, 0x11450, 0x114d0, 0x11650,
	0x116c0, 0x11730, 0x118e0, 0x11950, 0x11c50, 0x11d50, 0x11da0, 0x16a60, 0x16b50, 0x1d7ce, 0x1d7d8,
	0x1d7e2, 0x1d7ec, 0x1d7f6, 0x1e140, 0x1e2f0, 0x1e950, 0x1fbf0]

struct Header {
	start  int
	end    int
	width  int
	height int
}

fn decimal(text string, start int) (int, int) {
	mut end := start
	mut value := 0
	for end < text.len {
		character := utf8.get_rune(text, end)
		mut digit := -1
		for zero in decimal_zeros {
			if character >= zero && character < zero + 10 {
				digit = int(character) - zero
				break
			}
		}
		if digit < 0 {
			break
		}
		// Consume all digits without integer overflow. Invalid dimensions are
		// still headers and therefore still separate consecutive frames.
		value = if value > 8192 { 8193 } else { value * 10 + digit }
		end += character.str().len
	}
	return value, end
}

fn frame_headers(text string, prefix string) []Header {
	marker := prefix + '-FRAME: '
	mut headers := []Header{}
	mut cursor := 0
	for cursor < text.len {
		start := text.index_after(marker, cursor) or { break }
		cursor = start + marker.len
		width, separator := decimal(text, cursor)
		if separator == cursor || separator >= text.len || text[separator] != ` ` {
			continue
		}
		height, end := decimal(text, separator + 1)
		if end == separator + 1 {
			continue
		}
		headers << Header{start, end, width, height}
		cursor = end
	}
	return headers
}

pub enum Emulator {
	n64
	ps1
	ps2
	ios
}

fn (kind Emulator) prefix() string {
	return match kind {
		.n64 { 'N64' }
		.ps1 { 'PS1' }
		.ps2 { 'PS2' }
		.ios { 'IOS-PPSSPP' }
	}
}

fn (kind Emulator) description() string {
	return match kind {
		.n64 { 'Nintendo 64' }
		.ps1 { 'PlayStation' }
		.ps2 { 'PlayStation 2' }
		.ios { 'native' }
	}
}

fn put_u32(mut output []u8, value u32) {
	output << [u8(value >> 24), u8(value >> 16), u8(value >> 8), u8(value)]
}

fn chunk(mut output []u8, kind string, body []u8) {
	put_u32(mut output, u32(body.len))
	start := output.len
	output << kind.bytes()
	output << body
	put_u32(mut output, crc32.sum(output[start..]))
}

// extract bounds each frame by the next header, so rows from a later frame
// cannot complete an incomplete earlier capture. Only the selected frame's
// dimensions and rows are validated, just as in the original extractors.
pub fn extract(text string, kind Emulator, frame i64) ![]u8 {
	prefix := kind.prefix()
	headers := frame_headers(text, prefix)
	count := headers.len
	if count == 0 {
		return error('No ${kind.description()} framebuffer in this log')
	}
	if frame < -i64(count) || frame >= count {
		return error('Frame index out of range: this log has ${count} frame(s)')
	}
	index := int((frame + count) % count)
	width := headers[index].width
	height := headers[index].height
	if width <= 0 || width > 8192 || height <= 0 || height > 8192 {
		return error('Incomplete ${kind.description()} framebuffer in this log')
	}
	end := if index + 1 < count { headers[index + 1].start } else { text.len }
	mut rows := regex.regex_opt(prefix + r'-ROW: ([0-9a-f]+)')!
	body := text[headers[index].end..end]
	row_bounds := rows.find_all(body)
	if row_bounds.len / 2 != height {
		return error('Incomplete ${kind.description()} framebuffer in this log')
	}
	mut raw := []u8{cap: int(height * (width * 3 + 1))}
	for row in 0 .. int(height) {
		entry := body[row_bounds[row * 2]..row_bounds[row * 2 + 1]]
		pixels := entry[prefix.len + 6..]
		if pixels.len != width * 6 {
			return error('Incomplete ${kind.description()} framebuffer in this log')
		}
		raw << u8(0) // PNG filter: None.
		raw << hex.decode(pixels)!
	}
	mut png := [u8(137), 80, 78, 71, 13, 10, 26, 10]
	mut ihdr := []u8{cap: 13}
	put_u32(mut ihdr, u32(width))
	put_u32(mut ihdr, u32(height))
	ihdr << [u8(8), 2, 0, 0, 0] // Eight-bit RGB, standard compression/filtering.
	chunk(mut png, 'IHDR', ihdr)
	chunk(mut png, 'IDAT', zlib.compress(raw)!)
	chunk(mut png, 'IEND', [])
	return png
}

fn usage() {
	println('Usage: frame LOG OUTPUT [--frame INDEX]')
	println('Extract a guest framebuffer as PNG. Default: last frame; negative indices count from the end.')
}

pub fn run(kind Emulator) {
	mut paths := []string{}
	mut frame := i64(-1)
	mut options := true
	mut i := 1
	for i < os.args.len {
		arg := os.args[i]
		if options && arg in ['-h', '--help'] {
			usage()
			return
		} else if options && arg == '--' {
			options = false
		} else if options && (arg == '--frame' || arg.starts_with('--frame=')) {
			value := if arg == '--frame' {
				i++
				if i >= os.args.len {
					eprintln('frame: --frame requires an integer')
					exit(2)
				}
				os.args[i]
			} else {
				arg.all_after('=')
			}
			frame = strconv.parse_int(value, 10, 64) or {
				eprintln('frame: invalid frame index: ${value}')
				exit(2)
			}
		} else if options && arg.starts_with('-') {
			eprintln('frame: unknown option: ${arg}')
			exit(2)
		} else {
			paths << arg
		}
		i++
	}
	if paths.len != 2 {
		usage()
		exit(2)
	}
	text := os.read_file(paths[0]) or {
		eprintln(err)
		exit(1)
	}
	png := extract(text, kind, frame) or {
		eprintln(err)
		exit(1)
	}
	os.mkdir_all(os.dir(paths[1])) or {
		eprintln(err)
		exit(1)
	}
	os.write_file_array(paths[1], png) or {
		eprintln(err)
		exit(1)
	}
	println(paths[1])
}
