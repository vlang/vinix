// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
module main

import drm.ioctl
import gpu.agx.vm as agxvm

fn bind_request() ioctl.DrmAsahiGemBind {
	return ioctl.DrmAsahiGemBind{
		op: ioctl.asahi_bind_op_bind
		flags: ioctl.asahi_bind_read | ioctl.asahi_bind_write
		handle: 7
		vm_id: 1
		offset: agxvm.page_size
		range: agxvm.page_size
		addr: agxvm.user_start
	}
}

fn main() {
	mut identities := agxvm.IdentityPool{}
	for expected := u64(1); expected < 10001; expected++ {
		assert (identities.allocate() or { panic('identity') }) == expected
	}
	mut final_identities := agxvm.IdentityPool{ next: ~u64(0) - 1 }
	assert (final_identities.allocate() or { panic('penultimate identity') }) == ~u64(0) - 1
	assert (final_identities.allocate() or { panic('final identity') }) == ~u64(0)
	for _ in 0 .. 10 {
		if _ := final_identities.allocate() { panic('identity reused after exhaustion') }
	}
	kernel_start := u64(0x100000000)
	kernel_end := kernel_start + agxvm.kernel_min_size
	assert agxvm.valid_window(kernel_start, kernel_end)
	assert !agxvm.valid_window(kernel_start + 1, kernel_end)
	assert !agxvm.valid_window(kernel_start, kernel_start + agxvm.kernel_min_size - agxvm.page_size)
	assert !agxvm.valid_window(kernel_start, agxvm.user_end + agxvm.page_size)

	mut test_request := bind_request()
	assert agxvm.valid_bind_request(&test_request, kernel_start, kernel_end)
	test_request.addr = kernel_start
	assert !agxvm.valid_bind_request(&test_request, kernel_start, kernel_end)
	test_request = bind_request()
	test_request.flags = 4
	assert !agxvm.valid_bind_request(&test_request, kernel_start, kernel_end)
	test_request = bind_request()
	test_request.offset++
	assert !agxvm.valid_bind_request(&test_request, kernel_start, kernel_end)

	test_request = ioctl.DrmAsahiGemBind{
		op: ioctl.asahi_bind_op_unbind
		vm_id: 1
		range: agxvm.page_size
		addr: agxvm.user_start
	}
	assert agxvm.valid_bind_request(&test_request, kernel_start, kernel_end)
	test_request.handle = 7
	assert !agxvm.valid_bind_request(&test_request, kernel_start, kernel_end)

	test_request = ioctl.DrmAsahiGemBind{
		op: ioctl.asahi_bind_op_unbind_all
		handle: 7
		vm_id: 1
	}
	assert agxvm.valid_bind_request(&test_request, kernel_start, kernel_end)
	test_request.range = agxvm.page_size
	assert !agxvm.valid_bind_request(&test_request, kernel_start, kernel_end)
	test_request.range = 0
	test_request.addr = agxvm.user_start
	assert !agxvm.valid_bind_request(&test_request, kernel_start, kernel_end)
	test_request.addr = 0
	test_request.handle = 0
	assert !agxvm.valid_bind_request(&test_request, kernel_start, kernel_end)

	println('AGX VM identities: 10000 ordered identities, final two identities, permanent exhaustion without wrap or reuse passed')
	println('shared AGX VM contract tests passed')
}
