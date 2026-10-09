// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os

fn test_native_libsystem_safety_abi() {
	path := os.getenv('VINIX_IOS_LIBSYSTEM_SAFETY_FIXTURE')
	if path == '' { return }
	data := os.read_bytes(path)!
	defer { unsafe { data.free() } }
	image := macho.parse(data)!
	defer { module_image_free(image) }
	mode := os.getenv('VINIX_IOS_LIBSYSTEM_SAFETY_MODE')
	arguments := if mode == '' { [path] } else { [path, mode] }
	for _ in 0 .. 2 {
		assert execute(image, arguments)! == 0
		assert ios_runtime.live == 0
	}
}
