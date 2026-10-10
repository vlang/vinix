// SPDX-License-Identifier: GPL-2.0-or-later
module screenshotcore

import compress.zlib
import hash.crc32
import os

#include <stdlib.h>

fn C.mkdtemp(&char) &char

fn temporary_directory() !string {
	mut pattern := (os.temp_dir() + '/vinix-screenshot-XXXXXX\x00').bytes()
	unsafe {
		path := C.mkdtemp(&char(pattern.data))
		if path == nil { return error('cannot create test directory') }
		return path.vstring().clone()
	}
}

fn append32(mut out []u8, value u32) {
	out << [u8(value >> 24), u8(value >> 16), u8(value >> 8), u8(value)]
}

fn chunk(mut out []u8, kind string, body []u8) {
	append32(mut out, u32(body.len))
	mut checked := kind.bytes()
	checked << body
	out << checked
	append32(mut out, crc32.sum(checked))
}

// Encode known pixels with each of the five PNG scanline filters. The
// predictor reads the original row, independent of the decoder's output.
fn encoded_png(width int, height int, channels int, pixels []u8, filter int) ![]u8 {
	mut out := '\x89PNG\r\n\x1a\n'.bytes()
	mut header := []u8{}
	append32(mut header, u32(width))
	append32(mut header, u32(height))
	header << [u8(8), u8(if channels == 3 { 2 } else { 6 }), 0, 0, 0]
	chunk(mut out, 'IHDR', header)
	mut raw := []u8{}
	stride := width * channels
	for y in 0 .. height {
		raw << u8(filter)
		for x in 0 .. stride {
			index := y * stride + x
			a := if x >= channels { int(pixels[index - channels]) } else { 0 }
			b := if y > 0 { int(pixels[index - stride]) } else { 0 }
			c := if y > 0 && x >= channels { int(pixels[index - stride - channels]) } else { 0 }
			mut predictor := 0
			match filter {
				1 { predictor = a }
				2 { predictor = b }
				3 { predictor = (a + b) / 2 }
				4 {
					p := a + b - c
					mut distance := 0x7fffffff
					for value in [a, b, c] {
						delta := if p > value { p - value } else { value - p }
						if delta < distance {
							predictor = value
							distance = delta
						}
					}
				}
				else {}
			}
			raw << u8(int(pixels[index]) - predictor)
		}
	}
	compressed := zlib.compress(raw)!
	chunk(mut out, 'IDAT', compressed[..compressed.len / 2])
	chunk(mut out, 'tEXt', 'ignored metadata'.bytes())
	chunk(mut out, 'IDAT', compressed[compressed.len / 2..])
	chunk(mut out, 'IEND', []u8{})
	return out
}

fn test_rgb_and_rgba_all_filters_decode_known_pixels() {
	for channels in [3, 4] {
		for width in [1, 2, 7, 31] {
			for height in [1, 2, 9] {
				pixels := []u8{len: width * height * channels, init: u8(index * 73 + index / 3 * 19)}
				for filter in [0, 1, 2, 3, 4, 9] {
					image := png(encoded_png(width, height, channels, pixels, filter)!)!
					assert image.width == width && image.height == height && image.channels == channels
					assert image.pixels == pixels
				}
			}
		}
	}
}

fn test_ppm_comments_one_separator_and_extra_bytes() {
	mut data := 'P6\n# screen\n2 \t1\n# maximum\n255\n'.bytes()
	data << [u8(10), 32, 13, 255, 0, 254, 99]
	image := ppm(data)!
	assert image.width == 2 && image.height == 1 && image.channels == 3
	assert image.pixels == [u8(10), 32, 13, 255, 0, 254]
	assert ppm('P6 0 9 255\n'.bytes())!.pixels.len == 0
	for bad in ['P6', 'P6\n# missing newline', 'P6 1 1 255', 'P6 1 1 255\nxx', 'P6 -1 2 255\n',
		'P6 1 1 256\nxxx', 'P6 2147483647 2 255\n'] {
		ppm(bad.bytes()) or { continue }
		assert false, bad
	}
}

fn test_png_rejects_truncation_and_unsupported_geometry() {
	valid := encoded_png(2, 2, 3, []u8{len: 12}, 4)!
	for count in [0, 2, 7, 9, 20, valid.len - 1] {
		png(valid[..count]) or { continue }
		assert false
	}
	for offset, value in {
		24: u8(16)
		25: u8(3)
		28: u8(1)
	} {
		mut bad := valid.clone()
		bad[offset] = value
		png(bad) or {
			assert err.msg() == 'only 8-bit non-interlaced RGB(A) PNG is supported'
			continue
		}
		assert false
	}
	mut bad := valid.clone()
	for pos in 16 .. 20 { bad[pos] = 255 }
	png(bad) or {
		assert err.msg().contains('dimensions')
		return
	}
	assert false
}

fn desktop_pixels() []u8 {
	mut pixels := []u8{len: 168 * 3}
	for pixel in 0 .. 168 {
		pixels[pixel * 3] = u8(pixel / 7 * 8)
		pixels[pixel * 3 + 1] = 64
		pixels[pixel * 3 + 2] = 128
	}
	return pixels
}

fn test_desktop_threshold_palette_and_percentage() {
	check_verdict(Image{0, 1, 3, []u8{}}, 'empty image', 1)
	check_verdict(Image{1, 1, 3, [u8(16), 16, 16]}, '1x1, 0% lit, 1 colours: no desktop', 1)
	check_verdict(Image{1, 1, 3, [u8(16), 16, 17]}, '1x1, 100% lit, 1 colours: no desktop', 1)
	check_verdict(Image{168, 1, 3, desktop_pixels()}, '168x1, 100% lit, 24 colours: desktop', 0)
	mut pixels := desktop_pixels()
	for pixel in 0 .. 85 {
		if pixel % 7 == 0 { continue }
		for channel in 0 .. 3 { pixels[pixel * 3 + channel] = 0 }
	}
	check_verdict(Image{168, 1, 3, pixels}, '168x1, 57% lit, 24 colours: desktop', 0)
	for lit in [99, 101] {
		mut grey := []u8{len: 200 * 3}
		for index in 0 .. lit * 3 { grey[index] = 64 }
		message, code := verdict(Image{200, 1, 3, grey})
		assert message == '200x1, 50% lit, 2 colours: no desktop'
		assert code == 1
	}
}

fn check_verdict(image Image, expected string, status int) {
	message, code := verdict(image)
	assert message == expected
	assert code == status
}

fn test_difference_ignores_alpha_and_counts_pixels() {
	rgb := Image{2, 1, 3, [u8(10), 20, 30, 40, 50, 60]}
	rgba := Image{2, 1, 4, [u8(10), 20, 30, 0, 40, 50, 60, 255]}
	assert differences(rgb, rgba)! == 0
	assert differences(rgb, Image{2, 1, 4, [u8(10), 21, 30, 99, 41, 50, 60, 0]})! == 2
}

struct Result {
	code int
	out  string
	err  string
}

fn invoke(tool string, args []string) Result {
	mut process := os.new_process(tool)
	process.set_args(args)
	process.set_redirect_stdio()
	process.run()
	process.wait()
	out := process.stdout_slurp()
	err := process.stderr_slurp()
	code := process.code
	process.close()
	return Result{code, out, err}
}

// Run against each separately built host executable without compiling in a test.
fn test_command_exit_codes_and_output() {
	tool := os.getenv('VINIX_SCREENSHOT_TOOL')
	if tool == '' { return }
	work := temporary_directory()!
	defer { os.rmdir_all(work) or { panic(err) } }
	ppm_path := work + '/before.ppm'
	png_path := work + '/after.png'
	mut before := 'P6\n168 1\n255\n'.bytes()
	before << desktop_pixels()
	os.write_file_array(ppm_path, before)!
	os.write_file_array(png_path, encoded_png(168, 1, 3, desktop_pixels(), 4)!)!
	assert invoke(tool, [ppm_path]) == Result{0, '168x1, 100% lit, 24 colours: desktop\n', ''}
	assert invoke(tool, [png_path]) == Result{0, '168x1, 100% lit, 24 colours: desktop\n', ''}
	assert invoke(tool, ['--changed', ppm_path, png_path, '1']) == Result{1, '0 pixels changed\n', ''}
	assert invoke(tool, ['--changed', ppm_path, png_path, '0']) == Result{0, '0 pixels changed\n', ''}
	mut changed := desktop_pixels()
	changed[0]++
	os.write_file_array(png_path, encoded_png(168, 1, 3, changed, 2)!)!
	assert invoke(tool, ['--changed', ppm_path, png_path, '1']) == Result{0, '1 pixels changed\n', ''}
	assert invoke(tool, ['--changed', ppm_path, png_path, '2']) == Result{1, '1 pixels changed\n', ''}
	os.write_file_array(png_path, encoded_png(1, 1, 3, [u8(1), 2, 3], 0)!)!
	assert invoke(tool, ['--changed', ppm_path, png_path, '120']) == Result{0, 'the screen changed size: 168x1 -> 1x1\n', ''}
	os.write_file(ppm_path, 'P6')!
	assert invoke(tool, [ppm_path]) == Result{2, 'cannot read ${ppm_path}: incomplete PPM header\n', ''}
	assert invoke(tool, ['--changed', ppm_path, png_path, '1']) == Result{2, 'cannot read the screenshots: incomplete PPM header\n', ''}
	assert invoke(tool, []) == Result{2, '', 'check-screenshot SHOT.{ppm,png}\ncheck-screenshot --changed BEFORE AFTER MIN_PIXELS\n'}
}
