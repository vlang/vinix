// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os

struct IdentityImageProbe {
	image macho.Image
	path string
mut:
	result int = -1
}

fn identity_image_worker(context voidptr) voidptr {
	mut probe := unsafe { &IdentityImageProbe(context) }
	assert darwin_pthread_main_np() == 0
	probe.result = execute(probe.image, [probe.path, '--worker-entry']) or { -1 }
	return unsafe { nil }
}

fn test_pthread_identity_macho_unload_and_worker_entry() {
	path := os.getenv('VINIX_IOS_PTHREAD_IDENTITY_FIXTURE')
	if path == '' { return }
	data := os.read_bytes(path)!
	defer { unsafe { data.free() } }
	image := macho.parse(data)!
	defer { module_image_free(image) }
	assert darwin_pthread_main_np() == 1
	for _ in 0 .. 2 {
		assert execute(image, [path])! == 0
		assert ios_runtime.live == 0
		assert system_data == unsafe { nil }
	}
	mut probe := IdentityImageProbe{image: image, path: path}
	mut handle := u64(0)
	assert C.ios_thread_create(unsafe { &handle }, 524288, 0, 16384, 0,
		unsafe { voidptr(identity_image_worker) }, unsafe { &probe }) == 0
	assert C.ios_thread_join(handle, unsafe { nil }) == 0
	assert probe.result == 0
	assert ios_runtime.live == 0
	assert system_data == unsafe { nil }
	assert darwin_pthread_main_np() == 1
}
