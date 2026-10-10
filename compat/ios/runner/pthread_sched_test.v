// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os

fn test_pthread_sched_macho_unload() {
	path := os.getenv('VINIX_IOS_PTHREAD_SCHED_FIXTURE')
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

fn test_pthread_sched_errors_preserve_errno_and_outputs() {
	mut policy := i32(-17)
	mut parameters := [u32(0xa5a5a5a5), u32(0xa5a5a5a5)]!
	darwin_set_errno(177)
	assert darwin_pthread_getschedparam(0, unsafe { &policy }, u64(unsafe { &parameters[0] })) == 3
	assert policy == -17
	assert parameters[0] == 0xa5a5a5a5 && parameters[1] == 0xa5a5a5a5
	assert darwin_pthread_setschedparam(u64(C.pthread_self()), 1, 0) == 22
	assert unsafe { *C.ios_errno_address() } == 177
}
