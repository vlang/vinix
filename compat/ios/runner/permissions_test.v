// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os

fn test_darwin_permission_abi() {
	path := os.getenv('VINIX_IOS_PERMISSIONS_FIXTURE')
	if path == '' { return }
	loop := os.getenv('VINIX_IOS_PERMISSIONS_LOOP')
	data := os.read_bytes(path)!
	defer { unsafe { data.free() } }
	image := macho.parse(data)!
	defer { module_image_free(image) }
	for _ in 0 .. 2 {
		assert execute(image, if loop == '' { [path] } else { [path, loop] })! == 0
		assert ios_runtime.live == 0
	}
}
