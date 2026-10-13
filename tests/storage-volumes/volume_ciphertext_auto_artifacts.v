// SPDX-License-Identifier: GPL-2.0-or-later
// Independent persisted reference oracle; imports no production volume codec.
module main

import os
import crypto.sha256

fn ciphertext_auto_put(mut bytes []u8, at int, size int, value u64) {
	for i in 0 .. size { bytes[at + i] = u8(value >> u32(i * 8)) }
}

fn ciphertext_auto_crc(bytes []u8) u32 {
	mut value := u32(0xffffffff)
	for i, byte in bytes {
		value ^= if i >= 124 && i < 128 { u32(0) } else { u32(byte) }
		for _ in 0 .. 8 { value = (value >> 1) ^ if value & 1 != 0 { u32(0xedb88320) } else { u32(0) } }
	}
	return value ^ u32(0xffffffff)
}

fn main() {
	assert os.args.len == 3, 'Usage: volume_ciphertext_auto_artifacts.v COMPLETED_GUEST_WORK NEW_OUTPUT'
	work := os.abs_path(os.args[1]); output := os.abs_path(os.args[2]); assert !os.exists(output)
	os.mkdir(output)!; os.chmod(output, 0o700)!
	for marker in ['first-boot.log', 'second-boot.log'] { assert os.read_file(work + '/' + marker)!.contains('PLAN DONE') }
	debugfs := os.getenv_opt('VINIX_DEBUGFS') or { '/opt/homebrew/opt/e2fsprogs/sbin/debugfs' }
	openssl := os.getenv_opt('VINIX_OPENSSL') or { '/opt/homebrew/opt/openssl@3/bin/openssl' }
	mut physical := os.open(work + '/volume.raw')!; physical.seek(15728640, .start)!
	mut bytes := []u8{len: 4096}; assert physical.read(mut bytes)! == 4096; physical.close()
	assert sha256.hexhash(bytes[..512].bytestr()) == '58d4a23c8dc7380e7069da904b7be35a5a844a9d6d1c744d531c960258cbbd22'
	assert bytes[512..].all(it == 0); os.write_file_array(output + '/ciphertext.bin', bytes)!
	r := os.exec([openssl, 'dgst', '-sha256', '-binary', '-out', output + '/ciphertext.sha256', output + '/ciphertext.bin'])
	assert r.exit_code == 0, r.output
	digest := os.read_bytes(output + '/ciphertext.sha256')!; assert digest.len == 32 && digest == sha256.sum(bytes)[..]
	mut evidence := ''
	for readonly in [false, true] {
		mut expected := []u8{len: 128}; copy(mut expected, 'VINIXCH1'.bytes())
		for field in [[8, 4, 1], [12, 4, 128], [16, 8, 16777216], [24, 8, 512], [32, 4, 1], [36, 4, 60], [40, 8, 15728640], [48, 8, 4096], [64, 4, 0x12345678]] {
			ciphertext_auto_put(mut expected, field[0], field[1], u64(field[2]))
		}
		ciphertext_auto_put(mut expected, 56, 8, u64(readonly)); copy(mut expected[80..112], digest)
		ciphertext_auto_put(mut expected, 124, 4, u64(ciphertext_auto_crc(expected)))
		for domain in ['volume', 'recovery'] {
			for prefix in ['', 'auto-'] {
				name := prefix + domain + if readonly { '-ro.vchash' } else { '.vchash' }
				extracted := os.exec([debugfs, '-R', 'dump /root/' + name + ' ' + output + '/' + name, work + '/config.ext2']); assert extracted.exit_code == 0, extracted.output
				assert os.read_bytes(output + '/' + name)! == expected
				evidence += name + ': exact independent VINIXCH1 geometry/reserved bytes/CRC and full physical extent OpenSSL SHA-256 verified\n'
			}
		}
	}
	evidence += 'ciphertext extent sha256=' + sha256.hexhash(bytes.bytestr()) + '\nPASS: independent persisted manual/automatic ciphertext references and full-extent digest oracle\n'
	os.write_file(output + '/oracle.log', evidence)!
	mut manifest := ''; mut names := os.ls(output)!; names.sort()
	for name in names { manifest += sha256.hexhash(os.read_file(output + '/' + name)!) + '  ' + name + '\n'; os.chmod(output + '/' + name, 0o600)! }
	os.write_file(output + '/SHA256SUMS', manifest)!; print(evidence)
}
