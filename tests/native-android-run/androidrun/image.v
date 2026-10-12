// SPDX-License-Identifier: GPL-2.0-or-later
module androidrun

import androidhost as ah
import androidtools
import cachecli
import os
import screenshotcore
import stbi

pub fn encode_screenshot(ppm string, destination string) ! {
	image := screenshotcore.ppm(os.read_bytes(ppm)!)!
	pixels := unsafe { &u8(image.pixels.data) }
	match path_suffix(destination).to_lower() {
		'.png' {
			stbi.stbi_write_png(destination, image.width, image.height, image.channels, pixels, image.width * image.channels)!
		}
		'.jpg', '.jpeg' {
			stbi.stbi_write_jpg(destination, image.width, image.height, image.channels, pixels, 75)!
		}
		'.bmp' {
			stbi.stbi_write_bmp(destination, image.width, image.height, image.channels, pixels)!
		}
		'.tga' {
			stbi.stbi_write_tga(destination, image.width, image.height, image.channels, pixels)!
		}
		'.ppm' { os.write_file_array(destination, os.read_bytes(ppm)!)! }
		else { return error('unsupported screenshot extension: ' + path_suffix(destination)) }
	}
}

pub fn screenshot(socket string, destination string) ! {
	ppm := with_suffix(destination, '.ppm')!
	qmp(socket, 'screendump', {
		'filename': ah.Value(ppm)
	})!
	encode_screenshot(ppm, destination)!
	if ppm != destination { os.rm(ppm)! }
}

pub fn screenshot_cli(argv []string) !int {
	args := cachecli.arguments(argv, ['--socket', '--destination'], [], [], 0, 0, 'Capture the guest framebuffer explicitly.\nUsage: screenshot --socket PATH --destination SHOT.png') or { return androidtools.InputError{err.msg()} }
	socket := args.required('--socket') or { return androidtools.InputError{err.msg()} }
	destination := args.required('--destination') or { return androidtools.InputError{err.msg()} }
	screenshot(socket, destination)!
	return 0
}
