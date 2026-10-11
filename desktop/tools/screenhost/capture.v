// SPDX-License-Identifier: GPL-2.0-or-later
module screenhost

import compress.zlib
import emulatorhost
import hash.crc32
import hosttest
import json2
import os
import policyhost
import screenshotcore

fn integer(mut bytes []u8, value u32) {
	bytes << [u8(value >> 24), u8(value >> 16), u8(value >> 8), u8(value)]
}

fn chunk(mut bytes []u8, name string, data []u8) {
	integer(mut bytes, u32(data.len))
	start := bytes.len
	bytes << name.bytes()
	bytes << data
	integer(mut bytes, crc32.sum(bytes[start..]))
}

pub fn png(image screenshotcore.Image) ![]u8 {
	if image.width <= 0 || image.height <= 0 || image.channels != 3 || i64(image.width) * image.height * 3 != image.pixels.len {
		return error('Invalid RGB screenshot')
	}
	mut raw := []u8{cap: image.pixels.len + image.height}
	for row in 0 .. image.height {
		raw << u8(0)
		raw << image.pixels[row * image.width * 3..(row + 1) * image.width * 3]
	}
	mut header := []u8{}
	integer(mut header, u32(image.width))
	integer(mut header, u32(image.height))
	header << [u8(8), 2, 0, 0, 0]
	mut result := '\x89PNG\r\n\x1a\n'.bytes()
	chunk(mut result, 'IHDR', header)
	chunk(mut result, 'IDAT', zlib.compress(raw)!)
	chunk(mut result, 'IEND', [])
	return result
}

pub fn capture(socket string, target string) ! {
	work := hosttest.work_dir('', 'vinix-screen-')!
	defer { hosttest.remove_work_dir(work) or {} }
	ppm := work + '/screen.ppm'
	mut qmp := emulatorhost.qmp_connect_timeout(socket, 30)!
	defer { qmp.close() }
	qmp.call('screendump', {
		'filename': json2.Any(ppm)
	})!
	if !os.is_file(ppm) || os.file_size(ppm) == 0 { return error('screendump produced nothing') }
	image := screenshotcore.ppm(os.read_bytes(ppm)!)!
	if target.to_lower().ends_with('.ppm') {
		os.cp(ppm, target)!
	} else if target.to_lower().ends_with('.png') {
		os.write_file_array(target, png(image)!)!
	} else {
		format := os.file_ext(target).trim_left('.').to_lower()
		if format == '' || !format.bytes().all(it.is_alnum()) {
			return error('Unknown screenshot output format')
		}
		converter := os.find_abs_path_of_executable('magick') or { return error('Install ImageMagick for screenshot formats other than PNG or PPM') }
		mut arguments := [converter, ppm]
		if format in ['jpg', 'jpeg', 'jpe'] { arguments << ['-quality', '75'] }
		arguments << format + ':' + hosttest.module_resolve(target)!
		policyhost.inherited(arguments)!
	}
}
