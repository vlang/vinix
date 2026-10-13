// SPDX-License-Identifier: GPL-2.0-or-later
// Independent persisted scrub/reference oracle; no production codec imports.
module main

import os
import crypto.sha256

fn scrub_put(mut bytes []u8, at int, size int, value u64) { for i in 0 .. size { bytes[at + i] = u8(value >> u32(i * 8)) } }

fn scrub_crc(bytes []u8, skipped int) u32 {
	mut value := u32(0xffffffff)
	for i, byte in bytes {
		value ^= if i >= skipped && i < skipped + 4 { u32(0) } else { u32(byte) }
		for _ in 0 .. 8 { value = (value >> 1) ^ if value & 1 != 0 { u32(0xedb88320) } else { u32(0) } }
	}; return value ^ u32(0xffffffff)
}

fn main() {
	assert os.args.len == 3, 'Usage: volume_ciphertext_scrub_artifacts.v COMPLETED_GUEST_WORK NEW_OUTPUT'
	work := os.abs_path(os.args[1]); output := os.abs_path(os.args[2]); assert !os.exists(output)
	os.mkdir(output)!; os.chmod(output, 0o700)!
	for marker in ['first-boot.log', 'second-boot.log'] { assert os.read_file(work + '/' + marker)!.contains('PLAN DONE') }
	debugfs := os.getenv_opt('VINIX_DEBUGFS') or { '/opt/homebrew/opt/e2fsprogs/sbin/debugfs' }
	openssl := os.getenv_opt('VINIX_OPENSSL') or { '/opt/homebrew/opt/openssl@3/bin/openssl' }
	mut physical := os.open(work + '/volume.raw')!; physical.seek(15728640, .start)!
	mut raw := []u8{len: 4096}; assert physical.read(mut raw)! == 4096; physical.close()
	assert sha256.hexhash(raw[..512].bytestr()) == '58d4a23c8dc7380e7069da904b7be35a5a844a9d6d1c744d531c960258cbbd22' && raw[512..].all(it == 0)
	mut sums := [][]u8{}
	for changed in [false, true] {
		mut bytes := raw.clone(); if changed { bytes[0] ^= 1 }
		name := if changed { 'changed' } else { 'clean' }; os.write_file_array(output + '/' + name + '.bin', bytes)!
		r := os.exec([openssl, 'dgst', '-sha256', '-binary', '-out', output + '/' + name + '.sha256', output + '/' + name + '.bin']); assert r.exit_code == 0, r.output
		digest := os.read_bytes(output + '/' + name + '.sha256')!; assert digest.len == 32 && digest == sha256.sum(bytes)[..]; sums << digest
	}
	mut evidence := ''
	for readonly in [false, true] {
		mut reference := []u8{len: 128}; copy(mut reference, 'VINIXCH1'.bytes())
		for field in [[8, 4, 1], [12, 4, 128], [16, 8, 16777216], [24, 8, 512], [32, 4, 1], [36, 4, 60], [40, 8, 15728640], [48, 8, 4096], [64, 4, 0x12345678]] { scrub_put(mut reference, field[0], field[1], u64(field[2])) }
		scrub_put(mut reference, 56, 8, u64(readonly)); copy(mut reference[80..112], sums[0]); scrub_put(mut reference, 124, 4, u64(scrub_crc(reference, 124)))
		ref_name := if readonly { 'volume-ro.vchash' } else { 'volume.vchash' }
		extracted := os.exec([debugfs, '-R', 'dump /root/' + ref_name + ' ' + output + '/' + ref_name, work + '/config.ext2']); assert extracted.exit_code == 0, extracted.output
		assert os.read_bytes(output + '/' + ref_name)! == reference
		fp := sha256.sum(reference)
		os.write_file_array(output + '/' + ref_name + '.reference', reference)!
		r := os.exec([openssl, 'dgst', '-sha256', '-binary', '-out', output + '/' + ref_name + '.fingerprint', output + '/' + ref_name + '.reference']); assert r.exit_code == 0 && os.read_bytes(output + '/' + ref_name + '.fingerprint')! == fp[..]
		for changed in [false, true] { for domain in ['volume', 'recovery'] {
			mut expected := []u8{len: 224}; copy(mut expected, 'VINIXCS1'.bytes())
			scrub_put(mut expected, 8, 4, 1); scrub_put(mut expected, 12, 4, 224); scrub_put(mut expected, 16, 4, u64(changed)); scrub_put(mut expected, 20, 4, 1)
			copy(mut expected[32..160], reference); copy(mut expected[160..192], sums[int(changed)]); copy(mut expected[192..224], fp[..]); scrub_put(mut expected, 28, 4, u64(scrub_crc(expected, 28)))
			name := (if changed { 'changed-' } else { 'clean-' }) + domain + if readonly { '-ro.vcscrub' } else { '.vcscrub' }
			found := os.exec([debugfs, '-R', 'dump /root/' + name + ' ' + output + '/' + name, work + '/config.ext2']); assert found.exit_code == 0, found.output
			assert os.read_bytes(output + '/' + name)! == expected
			evidence += name + ': exact independent public header, nested reference/CRC, observed SHA, reference fingerprint, result consistency and full report CRC verified\n'
		} }
	}
	evidence += 'PASS: independent persisted ciphertext scrub reports, references and OpenSSL clean/changed/fingerprint oracles\n'
	os.write_file(output + '/oracle.log', evidence)!
	mut manifest := ''; mut names := os.ls(output)!; names.sort()
	for name in names { manifest += sha256.hexhash(os.read_file(output + '/' + name)!) + '  ' + name + '\n'; os.chmod(output + '/' + name, 0o600)! }; os.write_file(output + '/SHA256SUMS', manifest)!; print(evidence)
}
