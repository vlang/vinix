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

	println('shared AGX VM contract tests passed')
}
