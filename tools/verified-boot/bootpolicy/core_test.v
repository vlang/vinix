// SPDX-License-Identifier: GPL-2.0-or-later
module bootpolicy

fn assert_invalid(operation fn () !) {
	mut rejected := false
	operation() or {
		assert err is InvalidBundle
		rejected = true
	}
	assert rejected
}

fn put16(mut data []u8, offset int, value u16) {
	for index in 0 .. 2 { data[offset + index] = u8(value >> (index * 8)) }
}

fn put32(mut data []u8, offset int, value u32) {
	for index in 0 .. 4 { data[offset + index] = u8(value >> (index * 8)) }
}

fn fixture_pe(arch string) []u8 {
	mut data := []u8{len: 2048}
	data[0], data[1] = `M`, `Z`
	put32(mut data, 0x3c, 128)
	data[128], data[129] = `P`, `E`
	put16(mut data, 132, (architecture(arch) or { panic(err) }).pe_machine)
	put16(mut data, 134, 1)
	put16(mut data, 148, 240)
	put16(mut data, 152, 0x20b)
	put16(mut data, 220, 10)
	put32(mut data, 260, 16)
	put32(mut data, 408, 1024)
	put32(mut data, 412, 512)
	for index, value in config_marker.bytes() { data[512 + index] = value }
	for index in 0 .. 128 { data[512 + config_marker.len + index] = `0` }
	label := 'Limine 12.8.0 (${if arch == 'x86_64' { 'x86-64' } else { arch }}, UEFI)'
	for index, value in label.bytes() { data[800 + index] = value }
	return data
}

fn test_disk_selectors_and_substring_bypasses() {
	for selector in disk_options {
		for prefix in ['', 'x=', 'quiet x='] {
			assert_invalid(fn [selector, prefix] () ! {
				check_cmdline(prefix + selector + 'auto', '')!
			})
		}
	}
}

fn test_commandline_injection() {
	for value in ['quiet\n    cmdline: vinix.disk=auto', 'quiet\rhidden', '\${ARCH}', 'quiet\x00hidden',
		'é', 'a'.repeat(2049), 'vinix.verity=1,/dev/vda,2,' + '0'.repeat(64),
		'x=vinix.verity=1,/dev/vda,2,' + '0'.repeat(64)] {
		assert_invalid(fn [value] () ! { check_cmdline(value, '')! })
	}
	assert check_cmdline(' vinix.qemu_platform=1 quiet ', '')! == 'vinix.qemu_platform=1 quiet'
}

fn test_pe_architecture_field_and_signed_section() {
	for arch in ['x86_64', 'aarch64'] {
		data := fixture_pe(arch)
		info := pe_info(data, arch)!
		assert info.signature_size == 0
		assert data[int(info.field)..int(info.field) + 128] == '0'.repeat(128).bytes()
		other := if arch == 'x86_64' { 'aarch64' } else { 'x86_64' }
		assert_invalid(fn [data, other] () ! { pe_info(data, other)! })
	}
	mut malformed := fixture_pe('x86_64')
	malformed[512] = 0
	assert_invalid(fn [malformed] () ! { pe_info(malformed, 'x86_64')! })
	malformed = fixture_pe('x86_64')
	put32(mut malformed, 408, 32)
	put32(mut malformed, 412, 512)
	assert_invalid(fn [malformed] () ! { pe_info(malformed, 'x86_64')! })
	malformed = fixture_pe('x86_64')
	put32(mut malformed, 296, 512)
	put32(mut malformed, 300, 1536)
	assert_invalid(fn [malformed] () ! { pe_info(malformed, 'x86_64')! })
}
