// SPDX-License-Identifier: GPL-2.0-only
module tarcore

fn test_ustar_prefix_byte_limits_and_device_fields() {
	name := 'a'.repeat(90) + '/' + 'b'.repeat(20) + '/' + 'c'.repeat(10)
	data := header(Member{ name: name, kind: `3`, major: 42, minor: 17 })!
	assert data[..100].bytestr().all_before('\x00') == 'b'.repeat(20) + '/' + 'c'.repeat(10)
	assert data[345..500].bytestr().all_before('\x00') == 'a'.repeat(90)
	assert data[329..337].bytestr() == '0000052\x00'
	assert data[337..345].bytestr() == '0000021\x00'
	assert header(Member{ name: 'é'.repeat(50) })![..100].bytestr() == 'é'.repeat(50)
	for member in [Member{ name: 'x'.repeat(101) }, Member{ name: 'file', linkname: 'é'.repeat(51) },
		Member{ name: 'file', uid: -1 }, Member{ name: 'file', gid: 0o10000000 },
		Member{ name: 'file', size: i64(0o100000000000) }] {
		header(member) or { continue }
		assert false
	}
}
