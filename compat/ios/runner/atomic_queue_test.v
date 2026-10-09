// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os

fn test_native_atomic_queue_concurrency_and_lifetimes() {
	path := os.getenv('VINIX_IOS_ATOMIC_QUEUE_FIXTURE')
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

fn test_atomic_pair_exchange_rejects_aba_and_returns_current_pair() {
	// calloc supplies the required 16-byte head alignment on both hosts.
	head := C.calloc(1, 16)
	assert head != unsafe { nil }
	defer { C.free(head) }
	C.ios_store_pointer(head, 0x1234)
	C.ios_store_pointer(unsafe { &u64(u64(head) + 8) }, 42)
	mut expected := [u64(0x1234), 41]!
	mut desired := [u64(0x5678), 43]!
	assert C.ios_atomic_pair_exchange(head, unsafe { &expected[0] }, unsafe { &desired[0] }) == 0
	assert expected == [u64(0x1234), 42]!
	assert C.ios_atomic_pair_exchange(head, unsafe { &expected[0] }, unsafe { &desired[0] }) == 1
	mut observed := [u64(0), 0]!
	C.ios_atomic_pair_load(head, unsafe { &observed[0] })
	assert observed == desired
}
