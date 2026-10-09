// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os

fn test_native_provider_images_and_callbacks_lifecycle() {
	path := os.getenv('VINIX_IOS_PROVIDER_IMAGES_FIXTURE')
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

fn test_raw_images_reject_unimplemented_formats_and_invalid_sizes() {
	objc_start()
	defer { objc_stop() }
	mut pixels := [u8(255), 0, 0, 255, 0, 255, 0, 255]!
	provider := cg_provider_create(unsafe { nil }, unsafe { &pixels[0] }, 8, 0)
	space := cg_rgb_space()
	gray := cg_gray_space()
	assert cg_image_create(2, 1, 8, 32, 8, gray, 1, provider, unsafe { nil }, false, 0) == 0
	assert cg_image_create(2, 1, 16, 32, 8, space, 1, provider, unsafe { nil }, false, 0) == 0
	assert cg_image_create(2, 1, 8, 32, 8, space, 0x101, provider, unsafe { nil }, false, 0) == 0
	assert cg_image_create(2, 1, 8, 32, 8, space, 0x10001, provider, unsafe { nil }, false, 0) == 0
	assert cg_image_create(2, 1, 8, 32, 8, space, 0x1001, provider, unsafe { nil }, false, 0) == 0
	assert cg_image_create(2, 1, 8, 32, ~u64(0), space, 1, provider, unsafe { nil }, false, 0) == 0
	assert cg_provider_create(unsafe { nil }, unsafe { &pixels[0] }, ~u64(0), 0) == 0
	objc_release(provider)
	objc_release(space)
	objc_release(gray)
	assert ios_runtime.live == 0
}
