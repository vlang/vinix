// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os

fn test_pthread_rwlock_macho_unload() {
	path := os.getenv('VINIX_IOS_RWLOCK_FIXTURE')
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

fn test_pthread_rwlock_pinned_lifetime_and_shutdown() {
	system_data_start()!
	mut object := []u64{len: 25}
	object[0] = 0x2da8b3b4
	defer { system_data_stop(); unsafe { object.free() } }
	address := u64(unsafe { &object[0] })
	darwin_set_errno(177)
	mut state := pthread_rwlock_pin(address, false)!
	assert state.calls == 1
	assert darwin_rwlock_destroy(address) == 16
	assert state.calls == 1 && system_data.rwlocks.len == 1
	pthread_rwlock_unpin(mut state)
	assert darwin_rwlock_destroy(address) == 0 && system_data.rwlocks.len == 0
	for _ in 0 .. 32 {
		assert darwin_rwlock_init(address, 0) == 0
		assert darwin_rwlock_write(address) == 0
		assert darwin_rwlock_tryread(address) == 11
		assert darwin_rwlock_destroy(address) == 16
		assert darwin_rwlock_unlock(address) == 0 && darwin_rwlock_destroy(address) == 0
	}
	// Leave a quiescent initialized lock for image shutdown to reclaim.
	assert darwin_rwlock_init(address, 0) == 0
	assert unsafe { *C.ios_errno_address() } == 177
}

fn test_pthread_rwlock_shared_init_preserves_object() {
	mut attributes := [u64(0x52574c41), u64(1), u64(0)]!
	mut object := [u64(0x12345678), u64(0)]!
	address := u64(unsafe { &attributes[0] })
	darwin_set_errno(177)
	assert darwin_rwlock_init(u64(unsafe { &object[0] }), address) == 45
	assert object[0] == 0x12345678 && unsafe { *C.ios_errno_address() } == 177
	assert darwin_rwlockattr_getshared(address, unsafe { nil }) == 22
	assert darwin_rwlock_init(0, 0) == 22
	assert darwin_rwlockattr_init(0) == 22
	assert darwin_rwlockattr_destroy(0) == 22
}
