// SPDX-License-Identifier: GPL-2.0-or-later
module releaseasset

import crypto.sha256
import os

fn fixture() []u8 {
	mut data := []u8{len: 128}
	for index, byte in [u8(127), `E`, `L`, `F`, 2, 1, 1] { data[index] = byte }
	data[16] = 2
	data[18] = 183
	data[32] = 64
	data[54] = 56
	data[56] = 1
	data[64] = 1
	return data
}

fn test_runtime_refuses_changed_wrong_architecture_and_dynamic_assets() {
	for damage in 0 .. 4 {
		mut data := fixture()
		if damage == 1 { data[18] = 62 }
		if damage == 2 { data[64] = 3 }
		if damage == 3 { data[32] = 255 }
		digest := if damage == 0 { '0'.repeat(64) } else { sha256.sum(data).hex() }
		mut refused := false
		validate(data, digest) or { refused = true }
		assert refused
	}
}

fn test_staging_preserves_previous_output_when_verification_fails() {
	root := os.join_path(os.temp_dir(), 'vinix-release-runtime-${os.getpid()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	data := fixture()
	os.write_file_array(root + '/source', data)!
	stage(root + '/source', root + '/runtime', sha256.sum(data).hex())!
	assert os.read_bytes(root + '/runtime')! == data
	mut refused := false
	stage(root + '/source', root + '/runtime', '0'.repeat(64)) or { refused = true }
	assert refused && os.read_bytes(root + '/runtime')! == data
}
