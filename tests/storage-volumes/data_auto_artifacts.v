// SPDX-License-Identifier: GPL-2.0-or-later
// Independent persisted plain-data oracle; imports no production volume codec.
module main

import os
import crypto.sha256

fn auto_data_put(mut bytes []u8, at int, size int, value u64) {
	for i in 0 .. size { bytes[at + i] = u8(value >> u32(i * 8)) }
}

fn auto_data_crc(bytes []u8, field int) u32 {
	mut value := u32(0xffffffff)
	for i, byte in bytes {
		value ^= if i >= field && i < field + 4 { u32(0) } else { u32(byte) }
		for _ in 0 .. 8 { value = (value >> 1) ^ if value & 1 != 0 { u32(0xedb88320) } else { u32(0) } }
	}
	return value ^ u32(0xffffffff)
}

fn auto_data_plan(disk int) []u8 {
	count := if disk == 0 { 2 } else { 1 }; mut bytes := []u8{len: 64 + count * 32}
	copy(mut bytes, 'VINIXVM1'.bytes())
	for field in [[8, 4, 1], [12, 4, count], [16, 8, 16777216], [24, 8, 512], [32, 4, 1], [40, 4, 0x12345678 + disk]] {
		auto_data_put(mut bytes, field[0], field[1], u64(field[2]))
	}
	for i in 0 .. count {
		at := 64 + i * 32
		slot := if disk == 1 { 9 } else if i == 1 { 5 } else { 2 }
		for field in [[0, 4, 1], [4, 4, slot], [8, 8, if i == 1 { 2097152 } else { 1048576 }], [16, 8, if i == 1 { 12288 } else { 8192 }], [24, 8, i]] {
			auto_data_put(mut bytes, at + field[0], field[1], u64(field[2]))
		}
	}
	auto_data_put(mut bytes, 36, 4, u64(auto_data_crc(bytes, 36))); return bytes
}

fn auto_data_extent(path string, offset int, length int) ![]u8 {
	mut file := os.open(path)!; defer { file.close() }; file.seek(offset, .start)!
	mut bytes := []u8{len: length}; mut done := 0
	for done < length { n := file.read(mut bytes[done..])!; assert n > 0; done += n }
	return bytes
}

fn auto_data_digest(output string, name string, bytes []u8, openssl string) ![]u8 {
	os.write_file_array(output + '/' + name + '.bin', bytes)!
	r := os.exec([openssl, 'dgst', '-sha256', '-binary', '-out', output + '/' + name + '.sha256', output + '/' + name + '.bin'])
	assert r.exit_code == 0, r.output
	digest := os.read_bytes(output + '/' + name + '.sha256')!; assert digest.len == 32 && digest == sha256.sum(bytes)[..]
	return digest
}

fn auto_data_report(reference []u8, expected [][]u8, observed [][]u8, changed bool) string {
	mut text := 'format=VINIXSR1 operation=scrubbed-data disks=2 mappings=3 matched=${if changed { 1 } else { 3 }} changed=${if changed { 2 } else { 0 }} algorithm=sha256 reference_sha256=${sha256.hexhash(reference.bytestr())}\n'
	for i in 0 .. 3 {
		disk := if i == 2 { 1 } else { 0 }; slot := [2, 5, 9][i]
		offset := if i == 1 { 2097152 } else { 1048576 }; length := if i == 1 { 12288 } else { 8192 }
		text += 'disk=${disk} slot=${slot} offset=${offset} bytes=${length} readonly=${if i == 1 { 1 } else { 0 }} result=${if changed && i != 1 { 'changed' } else { 'match' }} expected_sha256=${expected[i].hex()} actual_sha256=${observed[i].hex()}\n'
	}
	return text
}

fn main() {
	assert os.args.len == 3, 'Usage: data_auto_artifacts.v COMPLETED_GUEST_WORK NEW_OUTPUT'
	work := os.abs_path(os.args[1]); output := os.abs_path(os.args[2]); assert !os.exists(output)
	os.mkdir(output)!; os.chmod(output, 0o700)!
	for marker in ['first-boot.log', 'second-boot.log'] {
		text := os.read_file(work + '/' + marker)!; assert text.contains('PLAN DONE') && !text.contains('PLAN FAIL') && !text.contains('KERNEL PANIC')
	}
	debugfs := os.getenv_opt('VINIX_DEBUGFS') or { '/opt/homebrew/opt/e2fsprogs/sbin/debugfs' }
	openssl := os.getenv_opt('VINIX_OPENSSL') or { '/opt/homebrew/opt/openssl@3/bin/openssl' }
	mut bundle := []u8{len: 64}; copy(mut bundle, 'VINIXVS1'.bytes()); bundle << auto_data_plan(0); bundle << auto_data_plan(1)
	for field in [[8, 4, 1], [12, 4, 2], [16, 4, 288], [20, 4, 3]] { auto_data_put(mut bundle, field[0], field[1], u64(field[2])) }
	auto_data_put(mut bundle, 24, 4, u64(auto_data_crc(bundle, 24)))
	mut expected := [][]u8{}; mut observed := [][]u8{}; mut evidence := ''
	for i in 0 .. 3 {
		path := work + if i == 2 { '/wrong.raw' } else { '/volume.raw' }
		identity := auto_data_extent(path, 0, 512)!; assert identity[510..512] == [u8(0x55), 0xaa]
		assert identity[440..444] == if i == 2 { [u8(0x79), 0x56, 0x34, 0x12] } else { [u8(0x78), 0x56, 0x34, 0x12] }
		bytes := auto_data_extent(path, if i == 1 { 2097152 } else { 1048576 }, if i == 1 { 12288 } else { 8192 })!
		assert bytes.all(it == if i == 0 { u8(0x6d) } else if i == 1 { u8(0) } else { u8(0x9c) })
		digest := auto_data_digest(output, 'extent-' + i.str(), bytes, openssl)!; expected << digest
		mut changed := bytes.clone(); if i != 1 { changed[if i == 0 { 17 } else { 93 }] ^= if i == 0 { u8(1) } else { u8(3) } }
		observed << auto_data_digest(output, 'changed-' + i.str(), changed, openssl)!
		evidence += 'extent=${i} bytes=${bytes.len} restored_sha256=${digest.hex()} changed_sha256=${observed[i].hex()}\n'
	}
	mut reference := []u8{len: 64}; copy(mut reference, 'VINIXDH1'.bytes()); reference << bundle
	for i in 0 .. 3 {
		mut record := []u8{len: 40}; auto_data_put(mut record, 0, 4, if i == 2 { u64(1) } else { u64(0) })
		auto_data_put(mut record, 4, 4, u64([2, 5, 9][i])); copy(mut record[8..], expected[i]); reference << record
	}
	for field in [[8, 4, 1], [12, 4, 64], [16, 4, 472], [20, 4, 288], [24, 4, 3]] { auto_data_put(mut reference, field[0], field[1], u64(field[2])) }
	auto_data_put(mut reference, 28, 4, u64(auto_data_crc(reference, 28)))
	clean := auto_data_report(reference, expected, expected, false); changed := auto_data_report(reference, expected, observed, true)
	for name in ['auto-data.vset', 'manual-data.vhash', 'auto-data.vhash', 'manual-data.txt', 'auto-data.txt', 'auto-data-clean.txt', 'auto-data-changed.txt'] {
		r := os.exec([debugfs, '-R', 'dump /root/' + name + ' ' + output + '/' + name, work + '/config.ext2']); assert r.exit_code == 0, r.output
		actual := os.read_bytes(output + '/' + name)!
		wanted := if name.ends_with('.vset') { bundle } else if name.ends_with('.vhash') { reference } else if name == 'auto-data-changed.txt' { changed.bytes() } else { clean.bytes() }
		assert actual == wanted, name
		evidence += name + ' sha256=' + sha256.hexhash(actual.bytestr()) + ' exact independently constructed bytes\n'
	}
	auto_data_digest(output, 'reference', reference, openssl)!
	evidence += 'PASS: independent persisted complete plain multi-disk bundle, manual/automatic VINIXDH1 and clean/changed VINIXSR1 artifacts; exact geometry/reserved fields/CRC and V/OpenSSL full-extent/reference SHA-256\n'
	os.write_file(output + '/oracle.log', evidence)!
	mut manifest := ''; mut names := os.ls(output)!; names.sort()
	for name in names { manifest += sha256.hexhash(os.read_file(output + '/' + name)!) + '  ' + name + '\n'; os.chmod(output + '/' + name, 0o600)! }
	os.write_file(output + '/SHA256SUMS', manifest)!; print(evidence)
}
