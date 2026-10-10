// SPDX-License-Identifier: GPL-2.0-or-later
module screenshotcore

import compress.zlib
import os
import strconv

pub struct Image {
pub:
	width    int
	height   int
	channels int
	pixels   []u8
}

fn geometry(width i64, height i64, channels int) !int {
	if width < 0 || height < 0 || width > 0x7fffffff || height > 0x7fffffff
		|| width * height > i64(0x7fffffff) / channels {
		return error('image dimensions are too large or negative')
	}
	return int(width * height) * channels
}

fn space(value u8) bool {
	return value in [u8(9), 10, 11, 12, 13, 32]
}

pub fn ppm(data []u8) !Image {
	mut fields := []string{}
	mut pos := 0
	for fields.len < 4 {
		for pos < data.len && space(data[pos]) { pos++ }
		if pos == data.len { return error('incomplete PPM header') }
		if data[pos] == `#` {
			for pos < data.len && data[pos] != `\n` { pos++ }
			continue
		}
		start := pos
		for pos < data.len && !space(data[pos]) { pos++ }
		if pos == data.len { return error('incomplete PPM header') }
		fields << data[start..pos].bytestr()
	}
	if fields[0] != 'P6' || strconv.parse_int(fields[3], 10, 64)! != 255 {
		return error('only 8-bit binary PPM is supported')
	}
	width := strconv.parse_int(fields[1], 10, 64)!
	height := strconv.parse_int(fields[2], 10, 64)!
	size := geometry(width, height, 3)!
	// P6 has one separator byte after maxval; further whitespace is pixel data.
	pos++
	if size > data.len - pos { return error('truncated PPM pixels') }
	return Image{int(width), int(height), 3, data[pos..pos + size].clone()}
}

fn be32(data []u8, pos int) u32 {
	return u32(data[pos]) << 24 | u32(data[pos + 1]) << 16 | u32(data[pos + 2]) << 8 | u32(data[pos + 3])
}

fn paeth(a int, b int, c int) int {
	p := a + b - c
	pa := if p >= a { p - a } else { a - p }
	pb := if p >= b { p - b } else { b - p }
	pc := if p >= c { p - c } else { c - p }
	return if pa <= pb && pa <= pc {
		a
	} else if pb <= pc {
		b
	} else {
		c
	}
}

pub fn png(data []u8) !Image {
	if data.len < 8 || data[..8].bytestr() != '\x89PNG\r\n\x1a\n' { return error('not a PNG') }
	mut pos := 8
	mut idat := []u8{}
	mut width := 0
	mut height := 0
	mut channels := 0
	mut size := 0
	mut header := false
	for pos < data.len {
		if data.len - pos < 12 { return error('truncated PNG chunk') }
		length := u64(be32(data, pos))
		if length > u64(data.len - pos - 12) { return error('truncated PNG chunk') }
		kind := data[pos + 4..pos + 8].bytestr()
		body := data[pos + 8..pos + 8 + int(length)]
		pos += 12 + int(length)
		match kind {
			'IHDR' {
				if body.len != 13 { return error('invalid PNG header') }
				if body[8] != 8 || body[12] != 0 || body[9] !in [u8(2), 6] {
					return error('only 8-bit non-interlaced RGB(A) PNG is supported')
				}
				channels = if body[9] == 2 { 3 } else { 4 }
				size = geometry(i64(be32(body, 0)), i64(be32(body, 4)), channels)!
				width = int(be32(body, 0))
				height = int(be32(body, 4))
				header = true
			}
			'IDAT' { idat << body }
			'IEND' { break }
			else {}
		}
	}
	if !header { return error('missing PNG header') }
	if u64(size) + u64(height) > 0x7fffffff { return error('image dimensions are too large') }
	raw := zlib.decompress(idat)!
	stride := width * channels
	if u64(raw.len) < u64(size) + u64(height) { return error('truncated PNG pixels') }
	mut out := []u8{len: size}
	for y in 0 .. height {
		source := y * (stride + 1)
		filter := raw[source]
		for x in 0 .. stride {
			index := y * stride + x
			a := if x >= channels { int(out[index - channels]) } else { 0 }
			b := if y > 0 { int(out[index - stride]) } else { 0 }
			c := if y > 0 && x >= channels { int(out[index - stride - channels]) } else { 0 }
			predictor := match filter {
				1 { a }
				2 { b }
				3 { (a + b) >> 1 }
				4 { paeth(a, b, c) }
				else { 0 } // Retain the previous decoder's treatment of unknown filters.
			}
			out[index] = u8(int(raw[source + 1 + x]) + predictor)
		}
	}
	return Image{width, height, channels, out}
}

pub fn read(path string) !Image {
	data := os.read_bytes(path)!
	return if data.len >= 2 && data[..2].bytestr() == 'P6' { ppm(data)! } else { png(data)! }
}

pub fn differences(before Image, after Image) !int {
	if before.width != after.width || before.height != after.height {
		return error('different dimensions')
	}
	mut count := 0
	for pixel in 0 .. before.width * before.height {
		if before.pixels[pixel * before.channels..pixel * before.channels + 3] !=
			after.pixels[pixel * after.channels..pixel * after.channels + 3] {
			count++
		}
	}
	return count
}

pub fn verdict(image Image) (string, int) {
	total := image.width * image.height
	if total == 0 { return 'empty image', 1 }
	mut lit := 0
	mut colours := map[u32]bool{}
	for pixel in 0 .. total {
		index := pixel * image.channels
		r, g, b := int(image.pixels[index]), int(image.pixels[index + 1]), int(image.pixels[index + 2])
		if r + g + b > 48 { lit++ }
		if pixel % 7 == 0 { colours[u32(r >> 3) << 10 | u32(g >> 3) << 5 | u32(b >> 3)] = true }
	}
	share := f64(lit) / total
	// The previous percentage formatter rounds exact halves to an even integer.
	scaled := share * 100
	mut percent := int(scaled)
	if scaled - percent > 0.5 || (scaled - percent == 0.5 && percent % 2 == 1) { percent++ }
	desktop := share >= 0.5 && colours.len >= 24
	label := if desktop { 'desktop' } else { 'no desktop' }
	return '${image.width}x${image.height}, ${percent}% lit, ${colours.len} colours: ${label}', if desktop {
		0
	} else {
		1
	}
}

pub fn run(args []string) int {
	if args.len == 4 && args[0] == '--changed' {
		minimum := strconv.parse_int(args[3], 10, 64) or {
			eprintln('invalid minimum pixel count: ${args[3]}')
			return 2
		}
		before := read(args[1]) or {
			println('cannot read the screenshots: ${err}')
			return 2
		}
		after := read(args[2]) or {
			println('cannot read the screenshots: ${err}')
			return 2
		}
		if before.width != after.width || before.height != after.height {
			println('the screen changed size: ${before.width}x${before.height} -> ${after.width}x${after.height}')
			return 0
		}
		count := differences(before, after) or { return 2 }
		println('${count} pixels changed')
		return if count >= minimum { 0 } else { 1 }
	}
	if args.len != 1 {
		eprintln('check-screenshot SHOT.{ppm,png}\ncheck-screenshot --changed BEFORE AFTER MIN_PIXELS')
		return 2
	}
	image := read(args[0]) or {
		println('cannot read ${args[0]}: ${err}')
		return 2
	}
	message, code := verdict(image)
	println(message)
	return code
}
