// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os

fn test_native_game_constants_and_string_ownership() {
	path := os.getenv('VINIX_IOS_GAME_CONSTANTS_FIXTURE')
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
