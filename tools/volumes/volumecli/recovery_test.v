// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

import os
import encoding.hex
import crypto.hmac
import crypto.sha256

fn test_recovery_chacha_rfc8439_block_and_openssl_oracle() {
	// RFC 8439 section 2.3.2 (https://www.rfc-editor.org/rfc/rfc8439).
	mut key := [32]u8{}; mut nonce := [12]u8{}; mut block := [64]u8{}
	for i in 0 .. 32 { key[i] = u8(i) }
	nonce[3] = 9; nonce[7] = 0x4a
	recovery_chacha(&key[0], &nonce[0], &block[0])
	expected := hex.decode('10f1e7e4d13b5915500fdd1fa32071c4c7d1f4c733c068030422aa9ac3d46c4e' +
		'd2826446079faa0914c2d705d98b02a2b5129cd1de164eb9cbd083e8a2503c4e')!
	for i in 0 .. 64 { assert block[i] == expected[i] }
	work := os.join_path(os.temp_dir(), 'vinix-recovery-oracle-${os.getpid()}')
	os.mkdir(work)!; defer { os.rmdir_all(work) or {} }
	for variant in 0 .. 16 {
		mut data := []u8{len: 64}; mut iv := []u8{len: 16}; iv[0] = 1
		for i in 0 .. 32 { key[i] = u8(i * 17 + variant * 29) }
		for i in 0 .. 12 { nonce[i] = u8(i * 11 + variant * 7); iv[i + 4] = nonce[i] }
		for i in 0 .. 64 { data[i] = u8(i * 13 + variant); block[i] = data[i] }
		os.write_file_array(work + '/in', data)!
		result := os.exec(['openssl', 'enc', '-chacha20', '-K', hex.encode(key[..]),
			'-iv', hex.encode(iv), '-in', work + '/in', '-out', work + '/out'])
		assert result.exit_code == 0, result.output
		recovery_chacha(&key[0], &nonce[0], &block[0])
		oracle := os.read_bytes(work + '/out')!
		assert oracle.len == 64
		for i in 0 .. 64 { assert block[i] == oracle[i] }
		recovery_chacha(&key[0], &nonce[0], &block[0])
		for i in 0 .. 64 { assert block[i] == data[i] }
	}
}

fn test_recovery_hmac_rfc4231_and_independent_streaming_boundaries() {
	// RFC 4231 cases 1..4. Short keys are zero padded to this API's 32 bytes.
	keys := [ []u8{len: 20, init: 0x0b}, 'Jefe'.bytes(), []u8{len: 20, init: 0xaa},
		[]u8{len: 25, init: u8(index + 1)} ]
	data := [ 'Hi There'.bytes(), 'what do ya want for nothing?'.bytes(),
		[]u8{len: 50, init: 0xdd}, []u8{len: 50, init: 0xcd} ]
	digests := [ 'b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7',
		'5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843',
		'773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe',
		'82558a389a443c0ea4cc819899f2083a85f0faa3e578f8077a2e3ff46729665b' ]
	mut key := [32]u8{}; mut tag := [32]u8{}
	for case in 0 .. 4 {
		key = [32]u8{}
		for i in 0 .. keys[case].len { key[i] = keys[case][i] }
		assert recovery_hmac(&key[0], data[case].data, usize(data[case].len), unsafe { &tag })
		assert hex.encode(tag[..]) == digests[case]
	}
	for size in 0 .. 1024 {
		for i in 0 .. 32 { key[i] = u8(i * 19 + size) }
		message := []u8{len: size, init: u8(index * 23 + size)}
		assert recovery_hmac(&key[0], message.data, usize(size), unsafe { &tag })
		assert tag[..] == hmac.new(key[..], message, sha256.sum256, 64)
	}
	tag = [32]u8{init: 0xa1}
	assert !recovery_hmac(&key[0], unsafe { nil }, 1, unsafe { &tag })
	for value in tag { assert value == 0xa1 }
}

fn test_recovery_envelope_all_corruption_and_wrong_key_preserve_output() {
	mut key := [64]u8{}; mut recovery := [64]u8{}; mut nonce := [12]u8{}
	for i in 0 .. 64 { key[i] = u8(i * 13 + 7); recovery[i] = u8(i * 29 + 41) }
	for i in 0 .. 12 { nonce[i] = u8(i * 3 + 1) }
	mut envelope := [160]u8{}; mut output := [66]u8{init: 0xa1}
	assert encode_recovery(&key[0], &recovery[0], &nonce[0], &envelope[0])
	// Independent SHA/HMAC implementation checks the complete format transcript.
	mut message := recovery[..32].clone(); message << envelope[..128]
	assert envelope[128..] == hmac.new(recovery[32..], message, sha256.sum256, 64)
	assert decode_recovery(&envelope[0], 160, &recovery[0], &output[1])
	assert output[0] == 0xa1 && output[65] == 0xa1
	for i in 0 .. 64 { assert output[i + 1] == key[i] }
	for bit in 0 .. 1280 {
		mut corrupt := envelope; corrupt[bit / 8] ^= u8(1 << (bit % 8))
		output = [66]u8{init: 0xa1}
		assert !decode_recovery(&corrupt[0], 160, &recovery[0], &output[1])
		for value in output { assert value == 0xa1 }
	}
	for size in -1 .. 162 {
		if size == 160 { continue }
		assert !decode_recovery(&envelope[0], size, &recovery[0], &output[1])
	}
	for bit in 0 .. 512 {
		mut wrong := recovery; wrong[bit / 8] ^= u8(1 << (bit % 8))
		assert !decode_recovery(&envelope[0], 160, &wrong[0], &output[1])
		for value in output { assert value == 0xa1 }
	}
	// A caller able to authenticate malformed canonical metadata is rejected too.
	for at in [8, 12, 16, 20, 36, 63] {
		mut corrupt := envelope; corrupt[at] ^= 1; mut tag := [32]u8{}
		assert recovery_tag(&recovery[0], &corrupt[0], unsafe { &tag })
		for i in 0 .. 32 { corrupt[i + 128] = tag[i] }
		assert !decode_recovery(&corrupt[0], 160, &recovery[0], &output[1])
	}
	assert !encode_recovery(&key[0], &key[0], &nonce[0], &envelope[0])
	mut equal := [64]u8{init: 7}
	assert !encode_recovery(&equal[0], &recovery[0], &nonce[0], &envelope[0])
	assert !encode_recovery(&key[0], &equal[0], &nonce[0], &envelope[0])
	// Even an authenticated envelope must contain a valid, independent XTS key.
	for candidate in [equal, recovery] {
		mut corrupt := envelope; mut tag := [32]u8{}
		for i in 0 .. 64 { corrupt[i + 64] = candidate[i] }
		recovery_chacha(&recovery[0], &corrupt[24], &corrupt[64])
		assert recovery_tag(&recovery[0], &corrupt[0], unsafe { &tag })
		for i in 0 .. 32 { corrupt[i + 128] = tag[i] }
		assert !decode_recovery(&corrupt[0], 160, &recovery[0], &output[1])
		for value in output { assert value == 0xa1 }
	}
}

fn test_recovery_commands_private_files_fresh_nonce_and_no_overwrite() {
	work := os.join_path(os.temp_dir(), 'vinix-recovery-files-${os.getpid()}')
	os.mkdir(work)!; os.chmod(work, 0o700)!; defer { os.rmdir_all(work) or {} }
	key := []u8{len: 64, init: u8(index * 13 + 7)}
	recovery := []u8{len: 64, init: u8(index * 29 + 41)}
	for pair in [ ['key', hex.encode(key)], ['recovery', hex.encode(recovery)] ] {
		os.write_file_array(work + '/' + pair[0], hex.decode(pair[1])!)!; os.chmod(work + '/' + pair[0], 0o600)!
	}
	keypath := work + '/key'; recoverypath := work + '/recovery'; envelope := work + '/backup'; restored := work + '/restored'
	assert recovery_key_file(keypath.str, recoverypath.str, envelope.str, true) == 0
	assert recovery_key_file(keypath.str, recoverypath.str, (work + '/backup2').str, true) == 0
	assert os.read_bytes(envelope)! != os.read_bytes(work + '/backup2')!
	assert recovery_key_file(envelope.str, recoverypath.str, restored.str, false) == 0
	assert os.read_bytes(restored)! == key && os.file_size(envelope) == 160
	mut info := C.stat{}
	assert unsafe { C.stat(restored.str, &info) } == 0 && info.st_mode & 0o777 == 0o600 && info.st_uid == C.geteuid()
	assert recovery_key_file(envelope.str, recoverypath.str, restored.str, false) == 1
	assert recovery_key_file(keypath.str, recoverypath.str, envelope.str, true) == 1
	assert recovery_key_file(keypath.str, keypath.str, (work + '/reused').str, true) == 1
	assert !os.exists(work + '/reused')
	os.symlink(restored, work + '/link')!
	os.symlink(work + '/absent', work + '/dangling')!
	os.mkdir(work + '/directory')!
	assert os.exec(['mkfifo', work + '/fifo']).exit_code == 0
	for name in ['key', 'recovery', 'link', 'dangling', 'fifo', 'directory'] {
		assert recovery_key_file(envelope.str, recoverypath.str, (work + '/' + name).str, false) == 1
	}
	for name in ['link', 'fifo'] {
		assert recovery_key_file((work + '/' + name).str, recoverypath.str, (work + '/absent').str, false) == 1
	}
	for mode in [0o644, 0o620, 0o601] {
		os.chmod(recoverypath, mode)!
		assert recovery_key_file(envelope.str, recoverypath.str, (work + '/absent').str, false) == 1
	}
	os.chmod(recoverypath, 0o600)!
	for size in [0, 63, 65] {
		os.write_file_array(work + '/invalid', []u8{len: size})!; os.chmod(work + '/invalid', 0o600)!
		assert recovery_key_file(keypath.str, (work + '/invalid').str, (work + '/absent').str, true) == 1
	}
	for size in [0, 159, 161] {
		os.write_file_array(work + '/invalid', []u8{len: size})!
		assert recovery_key_file((work + '/invalid').str, recoverypath.str, (work + '/absent').str, false) == 1
	}
	mut damaged := os.read_bytes(envelope)!; damaged[65] ^= 1
	os.write_file_array(work + '/invalid', damaged)!
	assert recovery_key_file((work + '/invalid').str, recoverypath.str, (work + '/absent').str, false) == 1
	assert !os.exists(work + '/absent')
	os.chmod(work, 0o777)!
	assert recovery_key_file(envelope.str, recoverypath.str, (work + '/absent').str, false) == 1
	os.chmod(work, 0o700)!
	assert os.read_bytes(keypath)! == key && os.read_bytes(recoverypath)! == recovery && os.read_bytes(restored)! == key
	assert os.ls(work)!.all(!it.starts_with('.vinix-key-'))
}

fn test_recovery_cli_syntax_before_io() {
	unsafe {
		mut args := [&char(c'vinix-volume'), &char(c'backup-key'), &char(c'/unused'), &char(c'/unused'), &char(c'/unused'), &char(nil)]!
		for command in [c'backup-key', c'recover-key'] {
			args[1] = command
			assert run(4, &args[0]) == 2 && run(6, &args[0]) == 2
			for at in 2 .. 5 { args[at] = &char(c''); assert run(5, &args[0]) == 2; args[at] = &char(c'/unused') }
		}
	}
}
