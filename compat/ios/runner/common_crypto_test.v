// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os

fn test_native_common_crypto_buffers_and_abi() {
	path := os.getenv('VINIX_IOS_COMMON_CRYPTO_FIXTURE')
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

fn test_common_crypto_rejects_unimplemented_ciphers_and_invalid_buffers() {
	mut key := [32]u8{}
	mut bytes := [64]u8{}
	mut moved := u64(0x1234)
	assert cc_crypt(0, 1, 0, unsafe { &key[0] }, 16, unsafe { nil }, unsafe { &bytes[0] }, 16,
		unsafe { &bytes[32] }, 32, &moved) == -4305
	assert moved == 0x1234
	assert cc_crypt(7, 0, 0, unsafe { &key[0] }, 16, unsafe { nil }, unsafe { &bytes[0] }, 16,
		unsafe { &bytes[32] }, 32, &moved) == -4300
	assert cc_crypt(0, 0, 0, unsafe { &key[0] }, 16, unsafe { nil }, unsafe { &bytes[0] }, 32,
		unsafe { &bytes[1] }, 32, &moved) == -4300
	assert cc_crypt(0, 0, 0, unsafe { &key[0] }, 16, unsafe { nil }, unsafe { &bytes[0] }, ~u64(0),
		unsafe { &bytes[32] }, 32, &moved) == -4300
}
