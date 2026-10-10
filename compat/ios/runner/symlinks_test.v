// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os

fn test_darwin_readlink_macho_unload() {
	path := os.getenv('VINIX_IOS_READLINK_FIXTURE')
	if path == '' { return }
	data := os.read_bytes(path)!
	defer { unsafe { data.free() } }
	image := macho.parse(data)!
	defer { module_image_free(image) }
	for _ in 0 .. 2 {
		assert execute(image, [path])! == 0
		assert ios_runtime.live == 0
		assert system_data == unsafe { nil }
	}
}

fn test_darwin_readlink_count_validation() {
	darwin_set_errno(177)
	assert darwin_readlink(unsafe { nil }, unsafe { nil }, usize(0x80000000)) == -1
	assert unsafe { *C.ios_errno_address() } == 22
}
