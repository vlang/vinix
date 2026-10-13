// SPDX-License-Identifier: GPL-2.0-or-later
// Independent persisted-fixture oracle; does not import volumecli crypto.
module main

import os
import crypto.hmac
import crypto.sha256
import crypto.aes
import encoding.hex

fn put(mut bytes []u8, at int, count int, value u64) {
	for i in 0 .. count { bytes[at + i] = u8(value >> u32(i * 8)) }
}

fn header(bytes []u8, backup bool, readonly bool) {
	assert bytes.len == 320
	magic := if backup { 'VINIXVR1' } else { 'VINIXVC1' }
	mut expected := []u8{len: 192}; copy(mut expected, magic.bytes())
	for field in [[8, 4, 1], [12, 4, 1], [16, 4, 320], [20, 4, 64],
		[80, 8, 16777216], [88, 8, 512], [96, 4, 1], [104, 4, 0x12345678],
		[120, 4, 1], [124, 4, 60], [128, 8, 15728640], [136, 8, 4096]] {
		put(mut expected, field[0], field[1], u64(field[2]))
	}
	put(mut expected, 144, 8, u64(readonly))
	if !backup {
		put(mut expected, 24, 8, 32768); put(mut expected, 32, 4, 8); put(mut expected, 36, 4, 3)
		for i in 40 .. 56 { expected[i] = bytes[i] }
	}
	for i in 56 .. 68 { expected[i] = bytes[i] }
	assert bytes[..192] == expected
	for value in bytes[256..288] { assert value == 0 }
}

fn unwrap(bytes []u8, wrapping []u8, key []u8, output string, openssl string) ! {
	mut authenticated := wrapping[..32].clone(); authenticated << bytes[..288]
	assert bytes[288..] == hmac.new(wrapping[32..], authenticated, sha256.sum256, 64)
	mut iv := []u8{len: 16}; iv[0] = 1; for i in 0 .. 12 { iv[i + 4] = bytes[i + 56] }
	os.write_file_array(output + '.cipher', bytes[192..256])!
	r := os.exec([openssl, 'enc', '-chacha20', '-d', '-K', hex.encode(wrapping[..32]), '-iv', hex.encode(iv), '-in', output + '.cipher', '-out', output + '.key'])
	assert r.exit_code == 0 && os.read_bytes(output + '.key')! == key, r.output
}

fn xts(key []u8) ![]u8 {
	data := aes.new_cipher(key[..32])!; tweak_key := aes.new_cipher(key[32..])!
	mut tweak := []u8{len: 16}; tweak_key.encrypt(mut tweak, []u8{len: 16})
	mut result := []u8{len: 512}
	for at := 0; at < 512; at += 16 {
		mut plain := []u8{len: 16}; mut cipher := []u8{len: 16}
		for i in 0 .. 16 { plain[i] = 0x73 ^ tweak[i] }
		data.encrypt(mut cipher, plain); for i in 0 .. 16 { result[at + i] = cipher[i] ^ tweak[i] }
		mut shifted := [17]u8{}
		for i in 0 .. 16 { shifted[i] |= tweak[i] << 1; shifted[i + 1] |= tweak[i] >> 7 }
		if shifted[16] != 0 { shifted[0] ^= 0x87 }; for i in 0 .. 16 { tweak[i] = shifted[i] }
	}
	return result
}

fn main() {
	assert os.args.len == 3 || (os.args.len == 4 && os.args[3] == '--recovery-unlock'), 'Usage: volume_recovery_artifacts.v COMPLETED_GUEST_WORK NEW_OUTPUT [--recovery-unlock]'
	unlock := os.args.len == 4
	work := os.abs_path(os.args[1]); output := os.abs_path(os.args[2])
	assert !os.exists(output)
	os.mkdir(output)!; os.chmod(output, 0o700)!
	for marker in ['first-boot.log', 'second-boot.log'] { assert os.read_file(work + '/' + marker)!.contains('PLAN DONE') }
	debugfs := os.getenv_opt('VINIX_DEBUGFS') or { '/opt/homebrew/opt/e2fsprogs/sbin/debugfs' }
	openssl := os.getenv_opt('VINIX_OPENSSL') or { '/opt/homebrew/opt/openssl@3/bin/openssl' }
	names := if unlock { ['volume.vrecover', 'volume-ro.vrecover', 'recovery.key'] } else { ['volume.vrecover', 'volume-ro.vrecover', 'recovered.vcrypt', 'recovered-ro.vcrypt', 'recovery.key', 'next.pass'] }
	for name in names {
		r := os.exec([debugfs, '-R', 'dump /root/' + name + ' ' + output + '/' + name, work + '/config.ext2']); assert r.exit_code == 0, r.output
	}
	if !unlock { for name in ['boot-volume.vcrypt', 'boot-volume.pass'] {
		r := os.exec([debugfs, '-R', 'dump /etc/vinix/' + name + ' ' + output + '/' + name, work + '/config.ext2']); assert r.exit_code == 0, r.output
	} }
	key := []u8{len: 64, init: u8(index * 13 + 7)}
	recovery := os.read_bytes(output + '/recovery.key')!
	password := if unlock { []u8{} } else { os.read_bytes(output + '/next.pass')! }
	assert recovery == []u8{len: 64, init: u8(index * 29 + 41)}
	if !unlock { assert password == [u8(0), 10, 0xfe, 0x17, 13, 0x7f, 0, 42] }
	mut evidence := ''
	for readonly in [false, true] {
		name := if readonly { 'volume-ro' } else { 'volume' }; restored := if readonly { 'recovered-ro' } else { 'recovered' }
		backup := os.read_bytes(output + '/' + name + '.vrecover')!
		header(backup, true, readonly)
		unwrap(backup, recovery, key, output + '/' + name, openssl)!
		if unlock { evidence += name + ': independent canonical metadata, complete HMAC and ChaCha20 recovery key verified\n'; continue }
		sealed := os.read_bytes(output + '/' + restored + '.vcrypt')!
		header(sealed, false, readonly); assert backup[80..192] == sealed[80..192]
		r := os.exec([openssl, 'kdf', '-keylen', '64', '-binary', '-out', output + '/' + restored + '.wrapping',
			'-kdfopt', 'hexpass:' + hex.encode(password), '-kdfopt', 'hexsalt:' + hex.encode(sealed[40..56]),
			'-kdfopt', 'n:32768', '-kdfopt', 'r:8', '-kdfopt', 'p:3', '-kdfopt', 'maxmem_bytes:67108864', 'SCRYPT'])
		assert r.exit_code == 0, r.output
		wrapping := os.read_bytes(output + '/' + restored + '.wrapping')!; assert wrapping.len == 64
		unwrap(sealed, wrapping, key, output + '/' + restored, openssl)!
		evidence += name + ': independent canonical metadata, complete HMAC, ChaCha20 key recovery and production scrypt rewrap verified\n'
	}
	if !unlock {
		assert os.read_bytes(output + '/boot-volume.vcrypt')! == os.read_bytes(output + '/recovered-ro.vcrypt')!
		assert os.read_bytes(output + '/boot-volume.pass')! == password
	}
	mut disk := os.open(work + '/volume.raw')!; disk.seek(15728640, .start)!
	mut ciphertext := []u8{len: 512}; assert disk.read(mut ciphertext)! == 512; disk.close()
	assert ciphertext == xts(key)!; os.write_file_array(output + '/xts.bin', ciphertext)!
	evidence += 'AES-XTS ciphertext sha256=' + sha256.hexhash(ciphertext.bytestr()) + '\nPASS: independent persisted configuration recovery, sealed key and ciphertext oracle\n'
	os.write_file(output + '/oracle.log', evidence)!
	mut manifest := ''; for name in os.ls(output)! { if name == 'SHA256SUMS' { continue }; manifest += sha256.hexhash(os.read_file(output + '/' + name)!) + '  ' + name + '\n'; os.chmod(output + '/' + name, 0o600)! }
	os.write_file(output + '/SHA256SUMS', manifest)!; os.chmod(output + '/SHA256SUMS', 0o600)!
	print(evidence)
}
