// SPDX-License-Identifier: GPL-2.0-or-later
module compactui

import json2
import os
import screenshotcore

fn fixture(width int, height int) screenshotcore.Image {
	mut pixels := []u8{len: 1024 * 768 * 3}
	for y in 68 .. 68 + height {
		for x in 120 .. 120 + width {
			index := (y * 1024 + x) * 3
			pixels[index] = 0xfb
			pixels[index + 1] = 0xfc
			pixels[index + 2] = 0xfe
		}
	}
	return screenshotcore.Image{1024, 768, 3, pixels}
}

fn refuse(image screenshotcore.Image, width int, height int, name string) ! {
	geometry(image, width, height) or { return }
	return error('compact geometry control accepted: ' + name)
}

pub fn run_controls(output string) ! {
	need(os.is_abs_path(output) && os.real_path(os.dir(output)) == os.dir(output)
		&& !os.exists(output) && !os.is_link(output), 'compact UI controls require fresh canonical external output')!
	mut refused := 0
	for width in [180, 320] {
		height := if width == 180 { 220 } else { 240 }
		good := fixture(width, height)
		geometry(good, width, height)!
		refuse(screenshotcore.Image{1023, 768, 3, good.pixels}, width, height, 'framebuffer-width')!
		refuse(screenshotcore.Image{1024, 767, 3, good.pixels}, width, height, 'framebuffer-height')!
		refuse(screenshotcore.Image{1024, 768, 4, good.pixels}, width, height, 'channels')!
		refuse(screenshotcore.Image{1024, 768, 3, good.pixels[..good.pixels.len - 1]}, width, height, 'pixel-count')!
		refuse(good, 319, height, 'unsupported-width')!
		refuse(good, width, height + 1, 'unsupported-height')!
		refused += 6
		for coordinate in [[120, 70]!, [120 + width - 1, 70]!, [120 + width / 2, 68 + height - 1]!] {
			x := coordinate[0]
			y := coordinate[1]
			mut changed := good.pixels.clone()
			changed[(y * 1024 + x) * 3] = 0
			refuse(screenshotcore.Image{1024, 768, 3, changed}, width, height, 'missing-inner-edge')!
			refused++
		}
		for coordinate in [[119, 70]!, [120 + width, 70]!, [120 + width / 2, 68 + height]!] {
			x := coordinate[0]
			y := coordinate[1]
			mut changed := good.pixels.clone()
			index := (y * 1024 + x) * 3
			changed[index] = 0xfb
			changed[index + 1] = 0xfc
			changed[index + 2] = 0xfe
			refuse(screenshotcore.Image{1024, 768, 3, changed}, width, height, 'oversized-outer-edge')!
			refused++
		}
	}
	need(refused == 24 && frames().len == 8, 'compact geometry control count differs')!
	os.mkdir(output, mode: 0o700)!
	os.write_file(output + '/result.json', json2.encode({'outcome': 'PASS',
		'accepted': '2', 'refused': refused.str(),
		'scope': 'Synthetic geometry-reader controls only; no compositor, QMP, image evidence or guest acceptance.'}) + '\n')!
	println('COMPACTUI two geometries and24 explicit refusals PASS')
}
