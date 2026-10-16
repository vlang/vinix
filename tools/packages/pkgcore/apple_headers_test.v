// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time
import tests.packages.applefixture

fn apple_put(mut bytes []u8, at int, value u64, width int) { for i in 0 .. width { bytes[at + i] = u8(value >> (8 * i)) } }

fn test_apple_macho_admission_refuses_wrong_targets_platforms_mapping_entry_commands_and_encryption() {
	work := os.real_path(os.temp_dir()) + '/vinix-apple-headers-' + time.now().unix_micro().str()
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	root := capture_prepared_root(work, 'Apple header tests')!
	defer { C.close(root) }
	os.write_file_array(work + '/image', applefixture.framework_image(23))!; profile_apple_image(root, 'image')!
	for row in [[0, u64(0xcafebabe), 4], [4, 0x1000007, 4], [8, 2, 4], [12, 6, 4], [24, 0, 4],
		[16, 0, 4], [16, 4097, 4], [20, 0, 4], [20, 1048577, 4], [36, 64, 4], [36, 73, 4],
		[56, 0xffffffffffffffff, 8], [64, 0xffffffffffffffff, 8], [72, 16384, 8], [80, 16385, 8],
		[88, 0, 4], [92, 7, 4], [92, 8, 4], [96, 1, 4], [100, 1, 4],
		[112, 0, 8], [112, 513, 8], [112, 16384, 8], [120, 1, 8], [136, 1, 4], [136, 7, 4]] {
		mut bytes := applefixture.image(23); apple_put(mut bytes, int(row[0]), u64(row[1]), int(row[2]))
		os.write_file_array(work + '/image', bytes)!
		mut denied := false; profile_apple_image(root, 'image') or { denied = true }
		assert denied, 'invalid field accepted at ' + row[0].str()
	}
	for size in [0, 31, 32, 71, 151, 512, 16383] {
		bytes := applefixture.image(23); os.write_file_array(work + '/image', bytes[..size])!
		mut denied := false; profile_apple_image(root, 'image') or { denied = true }; assert denied
	}
	// Additional load commands must be complete and nonconflicting. An explicit
	// unencrypted command is allowed; encrypted and required-unknown ones are not.
	for command in [u64(0x2c), 0x80000028, 0x32, 0x8000ffff] {
		mut bytes := applefixture.image(23); apple_put(mut bytes, 16, 4, 4); apple_put(mut bytes, 20, 144, 4)
		apple_put(mut bytes, 152, command, 4); apple_put(mut bytes, 156, 24, 4)
		if command == 0x2c { os.write_file_array(work + '/image', bytes)!; profile_apple_image(root, 'image')! }
		apple_put(mut bytes, 168, 1, 4); os.write_file_array(work + '/image', bytes)!
		mut denied := false; profile_apple_image(root, 'image') or { denied = true }; assert denied
	}
	mut oversized := os.open_file(work + '/image', 'w')!; assert C.ftruncate(oversized.fd, i64(512 * 1024 * 1024 + 1)) == 0; oversized.close()
	mut limit := false; profile_apple_image(root, 'image') or { limit = err.msg().contains('512 MiB') }; assert limit
	println('APPLE-HEADERS: thin ARM64/iOS admission; malformed/truncated/oversized, ARM64e/x86/simulator/macOS, encrypted, segment and entry refusals PASS')
}

fn apple_binary_info() []u8 {
	mut bytes := 'bplist00'.bytes(); mut offsets := [u8(8)]
	bytes << [u8(0xd3), 1, 2, 3, 4, 5, 6]
	for text in ['CFBundleIdentifier', 'CFBundleExecutable', 'CFBundlePackageType', 'org.example.apple', 'Example', 'APPL'] {
		offsets << u8(bytes.len)
		if text.len < 15 { bytes << u8(0x50 | text.len) } else { bytes << [u8(0x5f), 0x10, u8(text.len)] }
		bytes << text.bytes()
	}
	table := bytes.len; bytes << offsets; bytes << []u8{len: 32}
	trailer := bytes.len - 32; bytes[trailer + 6] = 1; bytes[trailer + 7] = 1
	bytes[trailer + 15] = 7; bytes[trailer + 31] = u8(table)
	return bytes
}

fn test_apple_bundle_xml_and_binary_plist_identity_and_kind_admission() {
	work := os.real_path(os.temp_dir()) + '/vinix-apple-plist-' + time.now().unix_micro().str()
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	root := capture_prepared_root(work, 'Apple plist tests')!
	defer { C.close(root) }
	p := Package{ id: 'org.example.apple', arguments: ['@APP@/Example.app/Example'] }
	good := '<plist><dict><key>CFBundleIdentifier</key><string>org.example.apple</string><key>CFBundleExecutable</key><string>Example</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>'
	for bytes in [good.bytes(), apple_binary_info()] { os.write_file_array(work + '/Info', bytes)!; apple_profile_plist(root, 'Info', p)! }
	for text in ['', '<plist><array/></plist>', '<plist><dict/></plist>', good.replace('org.example.apple', 'another.app'),
		good.replace('<string>Example</string>', '<string>../Example</string>'), good.replace('APPL', 'FMWK'),
		good.replace('<string>Example</string>', '<integer>1</integer>'), good.replace('</dict>', '<key>CFBundleIdentifier</key><string>forged.app</string></dict>')] {
		os.write_file(work + '/Info', text)!
		mut denied := false; apple_profile_plist(root, 'Info', p) or { denied = true }; assert denied
	}
	mut oversized := os.open_file(work + '/Info', 'w')!; assert C.ftruncate(oversized.fd, 1024 * 1024 + 1) == 0; oversized.close()
	mut limit := false; apple_profile_plist(root, 'Info', p) or { limit = err.msg().contains('1 MiB') }; assert limit
	println('APPLE-PLIST: XML/binary bundle identity/executable/type, duplicate/type/missing/malformed and size refusals PASS')
}
