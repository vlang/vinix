// SPDX-License-Identifier: GPL-2.0-or-later
module hwhost

import os

fn test_native_fixtures_refuse_the_wrong_target_before_installing() {
	state := os.join_path(os.vtmp_dir(), 'hwhost-native-target-${os.getpid()}')
	os.mkdir_all(state)!
	defer { os.rmdir_all(state) or {} }
	mut header := []u8{len: 64}
	for index, byte in [u8(0x7f), `E`, `L`, `F`, 2, 1] { header[index] = byte }
	header[18] = 183
	source := os.join_path(state, 'native')
	os.write_file_array(source, header)!
	suite := Suite{ binaries: [RootBinary{ source: source, path: 'usr/bin/native' }] }
	for arch in ['x86_64', 'unknown'] {
		mut refused := false
		build_extras(Host{ arch: arch }, suite, os.join_path(state, arch)) or {
			refused = true
		}
		assert refused
		assert !os.exists(os.join_path(state, arch, 'root/usr/bin/native'))
	}
	root := build_extras(Host{ arch: 'aarch64' }, suite, os.join_path(state, 'arm'))!
	assert os.read_bytes(os.join_path(root, 'usr/bin/native'))! == header
	assert os.is_executable(os.join_path(root, 'usr/bin/native'))
	for invalid in [header[..19], []u8{len: 64}, [u8(0x7f), `E`, `L`, `F`, 1, 1]] {
		os.write_file_array(source, invalid)!
		mut refused := false
		build_extras(Host{ arch: 'aarch64' }, suite, os.join_path(state, 'invalid')) or {
			refused = true
		}
		assert refused
		assert !os.exists(os.join_path(state, 'invalid/root/usr/bin/native'))
	}
}
