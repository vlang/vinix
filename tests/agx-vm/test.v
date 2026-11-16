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

fn check_bind_shapes() {
	mut repeated := bind_request()
	repeated.flags |= ioctl.asahi_bind_single_page
	repeated.range = 17 * agxvm.page_size
	assert agxvm.valid_bind_header(&repeated) && agxvm.valid_bind_shape(&repeated)
	assert agxvm.bind_backing_size(&repeated) == agxvm.page_size
	repeated.flags = ioctl.asahi_bind_single_page
	assert agxvm.valid_bind_header(&repeated) && !agxvm.valid_bind_shape(&repeated)
	repeated.flags = ioctl.asahi_bind_read
	assert agxvm.bind_backing_size(&repeated) == repeated.range
	mut header := bind_request()
	assert agxvm.valid_bind_header(&header)
	header.flags = 0
	assert agxvm.valid_bind_header(&header) && !agxvm.valid_bind_shape(&header)
	header = bind_request(); header.addr = agxvm.address_space_end
	assert agxvm.valid_bind_header(&header) && !agxvm.valid_bind_shape(&header)
	for invalid in 0 .. 5 {
		header = bind_request()
		match invalid {
			0 { header.extensions = 1 }
			1 { header.op = ioctl.asahi_bind_op_unbind }
			2 { header.flags = ~u32(0) }
			3 { header.addr++ }
			else { header.offset++ }
		}
		assert !agxvm.valid_bind_header(&header)
	}
	for base in [bind_request(), ioctl.DrmAsahiGemBind{ op: ioctl.asahi_bind_op_unbind, addr: agxvm.user_start, range: agxvm.page_size },
		ioctl.DrmAsahiGemBind{ op: ioctl.asahi_bind_op_unbind_all, handle: 7 }] {
		assert agxvm.valid_bind_shape(&base)
		mut request := base; request.vm_id = ~u32(0)
		assert agxvm.valid_bind_shape(&request)
		request.extensions = 1; assert !agxvm.valid_bind_shape(&request)
		request = base; request.op = ~u32(0); assert !agxvm.valid_bind_shape(&request)
		request = base; request.addr = agxvm.address_space_end; assert !agxvm.valid_bind_shape(&request)
		request = base; request.range = ~u64(0); assert !agxvm.valid_bind_shape(&request)
		if base.op != ioctl.asahi_bind_op_unbind_all {
			request = base; request.addr = 0x100000000
			assert agxvm.valid_bind_shape(&request)
			assert !agxvm.valid_bind_request(&request, 0x100000000, 0x120000000)
		}
	}
	println('AGX bind shapes: VM-independent operation/global-range checks and deferred private-hole validation passed')
}

fn main() {
	check_bind_shapes()
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
	// Independent division-based oracle covers both 16 KiB edge parities,
	// odd 32 KiB spans and the final legal reservation near the user limit.
	for index in 0 .. 1000 {
		start := if index == 0 { agxvm.user_start }
			else if index < 500 { kernel_start + u64(index % 64) * agxvm.page_size }
			else { agxvm.user_end - agxvm.kernel_min_size - u64(index - 500) * agxvm.page_size }
		end := if index < 500 { start + agxvm.kernel_min_size + u64((index * 37) % 257) * agxvm.page_size }
			else { agxvm.user_end }
		window := agxvm.driver_window(start, end) or { panic('driver window') }
		expected_start := (start + 32767) / 32768 * 32768
		expected_end := end / 32768 * 32768
		expected_mid := expected_start + (expected_end - expected_start) / 65536 * 32768
		assert window.start == expected_start && window.end == expected_end && window.midpoint == expected_mid
		assert window.start >= start && window.end <= end && window.start < window.midpoint && window.midpoint < window.end
		assert agxvm.valid_user_range(window.start - agxvm.page_size, agxvm.page_size, window.start, window.end)
		assert agxvm.valid_user_range(window.end, agxvm.page_size, window.start, window.end) == (window.end < agxvm.user_end)
		assert !agxvm.valid_user_range(window.midpoint, agxvm.page_size, window.start, window.end)
	}
	for pair in [[u64(0), agxvm.kernel_min_size], [kernel_start + 1, kernel_end],
		[kernel_start, kernel_end - agxvm.page_size], [kernel_end, kernel_start],
		[kernel_start, agxvm.user_end + agxvm.page_size], [~u64(0) - 0x7fff, ~u64(0)]] {
		if _ := agxvm.driver_window(pair[0], pair[1]) { panic('invalid reservation normalized') }
	}

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
	println('AGX driver VM geometry: 1000 independent boundary/split oracles, normalized edge permissions and invalid reservations passed')
	println('shared AGX VM contract tests passed')
}
