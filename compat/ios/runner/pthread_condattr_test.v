// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os

fn test_pthread_condattr_macho_unload() {
	path := os.getenv('VINIX_IOS_CONDATTR_FIXTURE')
	if path == '' { return }
	data := os.read_bytes(path)!
	defer { unsafe { data.free() } }
	image := macho.parse(data)!
	defer { module_image_free(image) }
	for _ in 0 .. 2 {
		assert execute(image, [path, '--adapter'])! == 0
		assert ios_runtime.live == 0
		assert system_data == unsafe { nil }
	}
}

fn test_pthread_condattr_shared_init_does_not_touch_object() {
	mut attributes := [u64(0), u64(1)]!
	mut object := [u64(0x12345678), u64(0), u64(0), u64(0), u64(0), u64(0)]!
	darwin_set_errno(177)
	assert darwin_cond_init(u64(unsafe { &object[0] }), u64(unsafe { &attributes[0] })) == 45
	assert object[0] == 0x12345678
	assert unsafe { *C.ios_errno_address() } == 177
	assert darwin_condattr_getshared(u64(unsafe { &attributes[0] }), unsafe { nil }) == 22
}
