// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import os
import encoding.hex
import crypto.hmac
import crypto.sha256

fn scrypt_oracle(password []u8, salt []u8, n int, r int, p int) []u8 {
	openssl := os.getenv_opt('VINIX_OPENSSL') or {
		if os.exists('/opt/homebrew/opt/openssl@3/bin/openssl') { '/opt/homebrew/opt/openssl@3/bin/openssl' }
		else { os.find_abs_path_of_executable('openssl') or { panic('OpenSSL 3 is required for the independent scrypt oracle') } }
	}
	result := os.exec([openssl, 'kdf', '-keylen', '64',
		'-kdfopt', 'hexpass:' + hex.encode(password), '-kdfopt', 'hexsalt:' + hex.encode(salt),
		'-kdfopt', 'n:' + n.str(), '-kdfopt', 'r:' + r.str(), '-kdfopt', 'p:' + p.str(),
		'-kdfopt', 'maxmem_bytes:67108864', 'SCRYPT'])
	assert result.exit_code == 0, result.output
	return hex.decode(result.output.replace(':', '').trim_space()) or { panic(err) }
}

fn test_scrypt_standard_vectors_and_independent_parameter_password_boundaries() {
	// RFC 7914 section 12: complete 64-byte output, including empty inputs.
	mut vector := []u32{len: 512}; mut output := [66]u8{init: 0xa1}
	assert scrypt_core(unsafe { nil }, 0, unsafe { nil }, 0, 16, 1, 1, vector.data, usize(vector.len * 4), &output[1])
	expected := hex.decode('77d6576238657b203b19ca42c18a0497f16b4844e3074ae8dfdffa3fede21442' +
		' fcd0069ded0948f8326a753a0fc81f17e8d3e0fb2e0d3628cf35e20c38d18906'.replace(' ', ''))!
	assert output[0] == 0xa1 && output[65] == 0xa1
	for i in 0 .. 64 { assert output[i + 1] == expected[i] }
	for parameters in [[16, 1, 1], [32, 2, 3], [64, 3, 2], [128, 8, 1], [1024, 8, 16]] {
		for size in [1, 32, 63, 64, 65, 127, 1024] {
			password := []u8{len: size, init: u8(index * 17 + size)}
			salt := []u8{len: 16, init: u8(index * 11 + size)}
			vector = []u32{len: parameters[0] * 32 * parameters[1]}
			assert scrypt_core(password.data, size, salt.data, 16, parameters[0], parameters[1], parameters[2], vector.data, usize(vector.len * 4), &output[1])
			oracle := scrypt_oracle(password, salt, parameters[0], parameters[1], parameters[2])
			for i in 0 .. 64 { assert output[i + 1] == oracle[i] }
		}
	}
	// The second RFC vector exercises sixteen independently mixed lanes.
	vector = []u32{len: 1024 * 32 * 8}
	assert scrypt_core(c'password', 8, c'NaCl', 4, 1024, 8, 16, vector.data, usize(vector.len * 4), &output[1])
	expected2 := hex.decode('fdbabe1c9d3472007856e7190d01e9fe7c6ad7cbc8237830e77376634b373162' +
		'2eaf30d92e22a3886ff109279d9830dac727afb94a83ee6d8360cbdfa2cc0640')!
	for i in 0 .. 64 { assert output[i + 1] == expected2[i] }
	output = [66]u8{init: 0xa1}
	for n in [0, 1, 3, 32769, 65536] { assert !scrypt_core(c'x', 1, c'y', 1, n, 8, 3, vector.data, usize(vector.len * 4), &output[1]) }
	for r in [0, 9] { assert !scrypt_core(c'x', 1, c'y', 1, 16, r, 3, vector.data, usize(vector.len * 4), &output[1]) }
	for p in [0, 17] { assert !scrypt_core(c'x', 1, c'y', 1, 16, 8, p, vector.data, usize(vector.len * 4), &output[1]) }
	assert !scrypt_core(c'x', 1, c'y', 1, 16, 8, 3, vector.data, 16383, &output[1])
	assert !scrypt_core(unsafe { nil }, 1, c'y', 1, 16, 8, 3, vector.data, usize(vector.len * 4), &output[1])
	for value in output { assert value == 0xa1 }
}

fn test_sealed_default_work_profile_matches_openssl_and_authenticates_complete_format() {
	password := 'sealed passphrase with a binary suffix'.bytes()
	mut salt_nonce := [28]u8{}; mut wrapping := [64]u8{}
	for i in 0 .. 28 { salt_nonce[i] = u8(i * 11 + 3) }
	assert sealed_derive(password.data, password.len, &salt_nonce[0], &wrapping[0])
	assert wrapping[..] == scrypt_oracle(password, salt_nonce[..16], 32768, 8, 3)
	mut key := [64]u8{}; for i in 0 .. 64 { key[i] = u8(i * 13 + 7) }
	mut bytes := [192]u8{}; mut output := [66]u8{init: 0xa1}
	assert encode_sealed_key(&key[0], &wrapping[0], &salt_nonce[0], &bytes[0])
	assert sealed_header(&bytes[0], 192)
	mut transcript := wrapping[..32].clone(); transcript << bytes[..160]
	assert bytes[160..] == hmac.new(wrapping[32..], transcript, sha256.sum256, 64)
	assert decode_sealed_key(&bytes[0], 192, &wrapping[0], &output[1])
	for i in 0 .. 64 { assert output[i + 1] == key[i] }
	for bit in 0 .. 1536 {
		mut corrupt := bytes; corrupt[bit / 8] ^= u8(1 << (bit % 8)); output = [66]u8{init: 0xa1}
		assert !decode_sealed_key(&corrupt[0], 192, &wrapping[0], &output[1])
		for value in output { assert value == 0xa1 }
	}
	for bit in 0 .. 512 {
		mut wrong := wrapping; wrong[bit / 8] ^= u8(1 << (bit % 8))
		assert !decode_sealed_key(&bytes[0], 192, &wrong[0], &output[1])
		for value in output { assert value == 0xa1 }
	}
	for size in -1 .. 194 { if size != 192 { assert !decode_sealed_key(&bytes[0], size, &wrapping[0], &output[1]) } }
	// Authenticated invalid plaintext keys and reserved metadata still reject.
	for invalid in [false, true] {
		mut bad := bytes; mut tag := [32]u8{}
		if invalid {
			for i in 0 .. 64 { bad[i + 96] = 7 }
			recovery_chacha(&wrapping[0], &bad[56], &bad[96])
		} else { bad[68] = 1 }
		assert sealed_tag(&wrapping[0], &bad[0], unsafe { &tag })
		for i in 0 .. 32 { bad[i + 160] = tag[i] }
		assert !decode_sealed_key(&bad[0], 192, &wrapping[0], &output[1])
	}
}

fn test_passphrase_reader_binary_boundaries_private_policy_and_exact_rechecks() {
	work := os.join_path(os.temp_dir(), 'vinix-sealed-input-${os.getpid()}')
	os.mkdir(work)!; os.chmod(work, 0o700)!; defer { os.rmdir_all(work) or {} }
	path := work + '/pass'; mut output := [1026]u8{init: 0xa1}
	assert !read_recovery_file(path.str, &output[1], 0)
	assert !read_recovery_file(path.str, &output[1], -1)
	for size in [1, 63, 64, 65, 1024] {
		password := []u8{len: size, init: u8(index * 13)}
		os.write_file_array(path, password)!; os.chmod(path, 0o600)!
		assert read_private_key_file(path.str, &output[1], 1, 1024) == size
		for i in 0 .. size { assert output[i + 1] == password[i] }
		assert output[0] == 0xa1 && output[1025] == 0xa1
	}
	for size in [0, 1025] { os.write_file_array(path, []u8{len: size})!; assert read_private_key_file(path.str, &output[1], 1, 1024) == 0 }
	os.write_file(path, 'private passphrase')!; os.chmod(path, 0o600)!
	os.symlink(path, work + '/link')!
	assert os.exec(['mkfifo', work + '/fifo']).exit_code == 0
	for name in ['link', 'fifo'] { assert read_private_key_file((work + '/' + name).str, &output[1], 1, 1024) == 0 }
	for mode in [0o644, 0o620, 0o601] { os.chmod(path, mode)!; assert read_private_key_file(path.str, &output[1], 1, 1024) == 0 }
}

fn test_sealed_file_roundtrip_wrong_passphrase_fresh_salt_and_no_replacement() {
	work := os.join_path(os.temp_dir(), 'vinix-sealed-files-${os.getpid()}')
	os.mkdir(work)!; os.chmod(work, 0o700)!; defer { os.rmdir_all(work) or {} }
	key := []u8{len: 64, init: u8(index * 13 + 7)}
	for pair in [['key', hex.encode(key)], ['pass', hex.encode('a long private fixture passphrase'.bytes())], ['wrong', hex.encode('another private fixture passphrase'.bytes())]] {
		os.write_file_array(work + '/' + pair[0], hex.decode(pair[1])!)!; os.chmod(work + '/' + pair[0], 0o600)!
	}
	assert sealed_key_file((work + '/key').str, (work + '/pass').str, (work + '/sealed').str, true) == 0
	assert sealed_key_file((work + '/key').str, (work + '/pass').str, (work + '/sealed2').str, true) == 0
	assert os.read_bytes(work + '/sealed')! != os.read_bytes(work + '/sealed2')!
	assert sealed_key_file((work + '/sealed').str, (work + '/wrong').str, (work + '/restored').str, false) == 1
	assert !os.exists(work + '/restored')
	assert sealed_key_file((work + '/sealed').str, (work + '/pass').str, (work + '/restored').str, false) == 0
	assert os.read_bytes(work + '/restored')! == key
	mut info := C.stat{}; assert unsafe { C.stat((work + '/restored').str, &info) } == 0 && info.st_mode & 0o777 == 0o600
	assert sealed_key_file((work + '/sealed').str, (work + '/pass').str, (work + '/restored').str, false) == 1
	assert sealed_key_file((work + '/key').str, (work + '/pass').str, (work + '/sealed').str, true) == 1
	assert os.read_bytes(work + '/key')! == key && os.read_bytes(work + '/restored')! == key
	assert os.ls(work)!.all(!it.starts_with('.vinix-key-'))
}

fn test_sealed_cli_syntax_without_input_io() {
	unsafe {
		mut args := [&char(c'vinix-volume'), &char(c'open-sealed'), &char(c'/unused'), &char(c'0'), &char(c'0'), &char(c'512'), &char(c'/unused'), &char(c'/unused'), &char(c'ro'), &char(nil)]!
		assert run(7, &args[0]) == 2 && run(10, &args[0]) == 2
		args[3] = &char(c'64'); assert run(8, &args[0]) == 2
		args[3] = &char(c'0'); args[5] = &char(c'0'); assert run(8, &args[0]) == 2
		args[5] = &char(c'512'); args[8] = &char(c'rw'); assert run(9, &args[0]) == 2
		for at in [2, 6, 7] { args[at] = &char(c''); assert run(8, &args[0]) == 2; args[at] = &char(c'/unused') }
		for command in [c'seal-key', c'unseal-key'] {
			args[1] = command; assert run(4, &args[0]) == 2 && run(6, &args[0]) == 2
			for at in 2 .. 5 { args[at] = &char(c''); assert run(5, &args[0]) == 2; args[at] = &char(c'/unused') }
		}
	}
}
