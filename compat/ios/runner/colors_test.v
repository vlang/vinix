// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os

fn test_native_colors_and_borrowed_components_lifecycle() {
	path := os.getenv('VINIX_IOS_COLORS_FIXTURE')
	if path == '' { return }
	data := os.read_bytes(path)!
	defer { unsafe { data.free() } }
	image := macho.parse(data)!
	defer { module_image_free(image) }
	for _ in 0 .. 2 {
		assert execute(image, [path])! == 0
		assert ios_runtime.live == 0
	}
}

fn test_color_create_copies_components_and_owns_space() {
	objc_start()
	defer { objc_stop() }
	gray := cg_gray_space()
	assert cg_bitmap_create(unsafe { nil }, 4, 2, 8, 16, gray, 1) == 0
	objc_release(gray)
	for _ in 0 .. 200 {
		space := cg_rgb_space()
		mut values := [f64(0.2), 0.4, 0.6, 0.5]!
		color := cg_color_create(space, unsafe { &values[0] })
		objc_release(space)
		values[0] = 0.9
		assert unsafe { cg_color_components(color)[0] } == 0.2
		assert cg_color_space(color) == space && cg_space_model(space) == 1
		alpha := cg_color_copy_alpha(color, 0.75)
		objc_release(color)
		assert cg_color_alpha(alpha) == 0.75
		assert unsafe { cg_color_components(alpha)[0] } == 0.2
		objc_release(alpha)
		assert ios_runtime.live == 0
	}
}
