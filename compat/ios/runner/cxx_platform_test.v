// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn test_darwin_random_device_storage_and_native_entropy() {
	mut storage := [u32(0x01234567), 0x89abcdef, 0xfedcba98]!
	object := u64(unsafe { &storage[1] })
	cxx_random_init(object, 0)
	assert cxx_random_entropy(object) == 32.0
	mut different := false
	first := cxx_random_value(object)
	for _ in 0 .. 128 { different = different || cxx_random_value(object) != first }
	assert different
	cxx_random_destroy(object)
	assert storage == [u32(0x01234567), 0x89abcdef, 0xfedcba98]!
}
