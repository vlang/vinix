// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os

fn test_pthread_attr_macho_unload() {
	path := os.getenv('VINIX_IOS_PTHREAD_ATTR_FIXTURE')
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

fn test_pthread_attr_rejects_foreign_scheduling() {
	mut object := [8]u64{}
	address := u64(unsafe { &object[0] })
	assert darwin_attr_init(address) == 0
	object[4] = 1 // Non-default Darwin scheduling fields.
	mut handle := u64(0x12345678)
	darwin_set_errno(177)
	assert darwin_pthread_create(unsafe { &handle }, unsafe { voidptr(address) }, unsafe { voidptr(image_atfork_parent) }, unsafe { nil }) == 45
	assert handle == 0x12345678
	assert unsafe { *C.ios_errno_address() } == 177
	assert darwin_attr_destroy(address) == 0
}
