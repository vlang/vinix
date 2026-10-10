// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os

fn test_pthread_mutexattr_macho_unload() {
	path := os.getenv('VINIX_IOS_MUTEXATTR_FIXTURE')
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

fn test_pthread_mutexattr_rejects_before_native_allocation() {
	mut attributes := [u64(0x4d545841), u64(0x6000000000)]!
	mut object := [u64(0x12345678), u64(0), u64(0), u64(0), u64(0), u64(0), u64(0), u64(0)]!
	address := u64(unsafe { &attributes[0] })
	darwin_set_errno(177)
	assert darwin_mutex_init(u64(unsafe { &object[0] }), address) == 45
	assert object[0] == 0x12345678
	assert unsafe { *C.ios_errno_address() } == 177
	assert darwin_mutexattr_getpolicy(address, unsafe { nil }) == 22
	assert darwin_mutexattr_type(0, 0) == 22
	assert darwin_mutexattr_init(0) == 22
	assert darwin_mutexattr_destroy(0) == 22
	assert darwin_mutex_init(0, 0) == 22
}
