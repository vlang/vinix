// SPDX-License-Identifier: GPL-2.0-or-later
module drm

import drm.ioctl
import memory

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
