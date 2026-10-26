// SPDX-License-Identifier: GPL-2.0-or-later
module mapsaccountstage

import crypto.sha256
import os

fn hash_chunks(bytes []u8, chunk int, portable bool) !string {
	mut state := if portable { new_portable_host_sha256() } else { new_host_sha256()! }
	defer { state.close() }
	state.update([]u8{})!
	mut offset := 0
	for offset < bytes.len {
		end := int_min(offset + chunk, bytes.len)
		state.update(bytes[offset..end])!
		offset = end
	}
	return state.finish()
}

fn test_host_sha256_standard_vectors() ! {
	vectors := {
		'': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
		'abc': 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
		'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq': '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1'
	}
	for portable in [false, true] {
		for message, expected in vectors {
			for chunk in [1, 7, 64] { assert hash_chunks(message.bytes(), chunk, portable)! == expected }
		}
		mut state := if portable { new_portable_host_sha256() } else { new_host_sha256()! }
		defer { state.close() }
		chunk := []u8{len: 1000, init: `a`}
		for _ in 0 .. 1000 { state.update(chunk)! }
		assert state.finish()! == 'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0'
	}
}

fn test_host_sha256_binary_padding_and_media_buffer_boundaries() ! {
	for size in [55, 56, 63, 64, 65, 119, 120, 127, 128, 129, 1024 * 1024 - 1, 1024 * 1024, 1024 * 1024 + 1] {
		bytes := []u8{len: size, init: u8(index * 131 + 17)}
		expected := sha256.sum(bytes).hex()
		for portable in [false, true] {
			for chunk in [63, 64, 65, 1024 * 1024] {
				assert hash_chunks(bytes, chunk, portable)! == expected, 'size=${size}, chunk=${chunk}, portable=${portable}'
			}
		}
	}
}

fn test_host_sha256_rejects_finished_or_closed_state() ! {
	for portable in [false, true] {
		mut state := if portable { new_portable_host_sha256() } else { new_host_sha256()! }
		assert state.finish()! == 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
		if _ := state.update('later'.bytes()) { assert false, 'update after finish accepted' }
		if _ := state.finish() { assert false, 'second finish accepted' }
		state.close()
		mut closed := if portable { new_portable_host_sha256() } else { new_host_sha256()! }
		closed.close()
		closed.close()
		if _ := closed.update([]u8{}) { assert false, 'update after close accepted' }
		if _ := closed.finish() { assert false, 'finish after close accepted' }
	}
}

fn test_media_file_hash_preserves_binary_digest() ! {
	path := os.join_path(os.real_path(os.temp_dir()), 'maps-host-sha-test-' + os.getpid().str())
	assert !os.exists(path)
	defer { os.rm(path) or {} }
	for size in [0, 1, 1024 * 1024 + 17] {
		bytes := []u8{len: size, init: u8(index * 67)}
		os.write_file_array(path, bytes)!
		assert hash(path)! == sha256.sum(bytes).hex()
	}
}
