// SPDX-License-Identifier: GPL-2.0-or-later
module drm

import drm.ioctl
import errno
import memory
import usercopy

fn check_agx_version() {
	assert sizeof(ioctl.DrmVersion) == 64
	// libdrm first queries the lengths, then supplies userspace buffers.
	request := u64(0xc0406400)
	memory.fail_next(true)
	for index, chip in [u32(0x8103), 0x6050]! {
		driver := agx_metadata(chip)
		dev := DrmDevice{driver: unsafe { &driver }}
		mut node := DrmNode{dev: unsafe { &dev }}
		expected_date := ['0', '20260905']![index]
		expected_desc := ['Apple AGX Graphics', 'Apple AGX GPU']![index]
		mut version := ioctl.DrmVersion{version_major: -1, version_minor: -1, version_patchlevel: -1}
		assert (node.ioctl(voidptr(1), request, unsafe { &version }) or { panic('VERSION length query') }) == 0
		assert version.version_major == index && version.version_minor == 0 && version.version_patchlevel == 0
		assert version.name_len == 5 && version.date_len == u64(expected_date.len)
		assert version.desc_len == u64(expected_desc.len)
		// The pinned Mesa comparison sets its high resource-specifier capability.
		assert (version.version_major > 0 || version.version_minor >= 2) == (index != 0)
		mut name := [8]u8{init: 0xab}
		mut date := [16]u8{init: 0xab}
		mut desc := [32]u8{init: 0xab}
		version.name = unsafe { u64(&name[0]) }
		version.date = unsafe { u64(&date[0]) }
		version.desc = unsafe { u64(&desc[0]) }
		assert (node.ioctl(voidptr(1), request, unsafe { &version }) or { panic('VERSION text query') }) == 0
		for offset, byte in 'asahi' { assert name[offset] == byte }
		for offset, byte in expected_date { assert date[offset] == byte }
		for offset, byte in expected_desc { assert desc[offset] == byte }
		assert name[5] == 0xab && date[expected_date.len] == 0xab && desc[expected_desc.len] == 0xab
		version.desc_len = 5
		desc = [32]u8{init: 0xab}
		assert (node.ioctl(voidptr(1), request, unsafe { &version }) or { panic('VERSION short text query') }) == 0
		assert version.desc_len == u64(expected_desc.len)
		for offset in 0 .. 5 { assert desc[offset] == expected_desc[offset] }
		assert desc[5] == 0xab
	}
	memory.fail_next(false)
	assert memory.outstanding() == 0
	println('DRM VERSION: M1 and G17 length and text queries, bounded writes and the Mesa capability predicate passed')
}

fn check_core_query_transport() {
	driver := DrmDriver{
		name: 'wire'
		major: 1
		minor: 2
		patchlevel: 3
		features: driver_dumb_buffer
	}
	dev := DrmDevice{driver: &driver}
	mut node := DrmNode{dev: &dev}
	mut numbers := [4]i32{init: -1}
	assert (node.ioctl(unsafe { nil }, u64(0x800c6400), unsafe { &numbers[0] }) or {
		panic('short read-only VERSION')
	}) == 0
	assert numbers[0] == 1 && numbers[1] == 2 && numbers[2] == 3 && numbers[3] == -1

	version_request := u64(0xc0406400)
	mut version := ioctl.DrmVersion{name_len: 1, date_len: 2, desc_len: 3}
	assert (node.ioctl(unsafe { nil }, version_request, unsafe { &version }) or {
		panic('VERSION null string pointers')
	}) == 0
	assert version.name_len == 4 && version.date_len == u64(default_driver_date.len) && version.desc_len == 0

	mut name := [4]u8{init: 0xab}
	version = ioctl.DrmVersion{
		name: unsafe { u64(&name[0]) }
		name_len: 1
		date_len: 2
		desc_len: 3
	}
	usercopy.fail_at(version.name)
	expect_error(mut node, version_request, unsafe { &version }, errno.efault)
	usercopy.fail_at(0)
	assert version.version_major == 1 && version.version_minor == 2 && version.version_patchlevel == 3
	assert version.name_len == 4 && version.date_len == 2 && version.desc_len == 3 && name[0] == 0xab

	mut cap := [u64(ioctl.drm_cap_dumb_buffer), 99, 0x1234, 0x5678]!
	assert (node.ioctl(unsafe { nil }, u64(0xc008640c), unsafe { &cap[0] }) or {
		panic('short GET_CAP')
	}) == 0
	assert cap[0] == ioctl.drm_cap_dumb_buffer && cap[1] == 99
	assert (node.ioctl(unsafe { nil }, u64(0x4008640c), unsafe { &cap[0] }) or {
		panic('write-only GET_CAP')
	}) == 0
	assert cap[0] == ioctl.drm_cap_dumb_buffer && cap[1] == 99
	assert (node.ioctl(unsafe { nil }, u64(0xc018640c), unsafe { &cap[0] }) or {
		panic('extended GET_CAP')
	}) == 0
	assert cap[1] == 1 && cap[2] == 0x1234 && cap[3] == 0x5678
	cap[0] = ~u64(0)
	expect_error(mut node, u64(0xc018640c), unsafe { &cap[0] }, errno.einval)
	assert cap[0] == ~u64(0) && cap[1] == 0 && cap[2] == 0x1234 && cap[3] == 0x5678
	expect_error(mut node, u64(0x8010640c), unsafe { &cap[0] }, errno.einval)
	assert cap[0] == 0 && cap[1] == 0 && cap[2] == 0x1234
	println('DRM core queries: short, extended and one-way wire requests, bounded copies and error replies passed')
}
