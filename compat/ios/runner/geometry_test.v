// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os

fn test_native_geometry_hfa_and_constants_lifecycle() {
	path := os.getenv('VINIX_IOS_GEOMETRY_FIXTURE')
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
