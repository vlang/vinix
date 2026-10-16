module main
import crypto.sha256
import os
fn main() {
	path := os.real_path(os.dir(@FILE)) + '/hash-payload'
	defer { os.rm(path) or {} }
	for length in [0, 1, 63, 64, 65, 1048575, 1048576, 1048577, 2097189]! {
		mut bytes := []u8{len: length}
		for i in 0 .. length { bytes[i] = u8(i % 251) }
		os.write_file_array(path, bytes)!
		actual := native_artifact('fixture', path)!
		mut expected := sha256.sum(bytes)
		assert actual.role == 'fixture' && actual.bytes == u64(length) && actual.sha256 == expected.hex()
		unsafe { bytes.free(); expected.free(); actual.sha256.free() }
	}
	os.rm(path)!
	mut refused := false
	native_artifact('missing', path) or { refused = true }
	assert refused
	println('PACKAGE RECEIPT stream SHA-256 empty block chunk boundary multi-chunk exact bytes and missing-file refusal PASS')
}
