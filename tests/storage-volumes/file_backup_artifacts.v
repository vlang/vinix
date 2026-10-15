// SPDX-License-Identifier: GPL-2.0-or-later
// Independent persisted file-version oracle; imports no production codec.
module main
import os
import crypto.sha256

fn backup_put(mut bytes []u8, at int, width int, value u64) { for i in 0 .. width { bytes[at + i] = u8(value >> (8 * i)) } }
fn backup_archive(data []u8, changed bool, base []u8) []u8 {
	mut body := []u8{}; count := if changed { 1 } else { 3 }
	for index in 0 .. count {
		at := index * 65536; n := if data.len - at < 65536 { data.len - at } else { 65536 }
		mut record := []u8{len: 16}; backup_put(mut record, 0, 8, u64(index)); backup_put(mut record, 8, 4, u64(n)); body << record; body << data[at..at + n]
	}
	mut header := []u8{len: 256}; copy(mut header, 'VINIXBK1'.bytes())
	for field in [[8, 4, 1], [12, 4, int(changed)], [16, 4, 65536], [24, 8, 131089], [32, 4, if changed { 0o604 } else { 0o640 }], [48, 8, if changed { 1700002345 } else { 1700001234 }], [128, 8, count]] { backup_put(mut header, field[0], field[1], u64(field[2])) }
	content := sha256.sum(data); digest := sha256.sum(body); for i in 0 .. 32 { header[64 + i] = content[i]; header[136 + i] = digest[i] }
	if changed { sum := sha256.sum(base); for i in 0 .. 32 { header[96 + i] = sum[i] } }
	sum := sha256.sum(header[..224]); for i in 0 .. 32 { header[224 + i] = sum[i] }; header << body; return header
}
fn main() {
	assert os.args.len == 3, 'Usage: file_backup_artifacts.v COMPLETED_GUEST_WORK NEW_OUTPUT'
	work := os.abs_path(os.args[1]); output := os.abs_path(os.args[2]); assert !os.exists(output); os.mkdir(output)!; os.chmod(output, 0o700)!
	for pair in [['first-boot.log', 'PLAN FILE BACKUP PASSED'], ['second-boot.log', 'PLAN FILE BACKUP REBOOT PRESERVED']] { log := os.read_file(work + '/' + pair[0])!; assert log.contains(pair[1]) && log.contains('PLAN DONE') && !log.contains('PLAN FAIL') && !log.contains('KERNEL PANIC') }
	original := []u8{len: 131089, init: u8(0x31 + index / 65536)}; mut changed := original.clone(); changed[0] = 0x77
	full := backup_archive(original, false, []u8{}); delta := backup_archive(changed, true, full)
	assert full.len == 131393 && delta.len == 65808
	debugfs := os.getenv_opt('VINIX_DEBUGFS') or { '/opt/homebrew/opt/e2fsprogs/sbin/debugfs' }
	mut manifest := ''; names := ['file-source', 'file-full.vbackup', 'file-delta.vbackup', 'file-restored-full', 'file-restored-delta', 'file-boot-full', 'file-boot-delta']
	for name in names {
		r := os.exec([debugfs, '-R', 'dump /root/' + name + ' ' + output + '/' + name, work + '/config.ext2']); assert r.exit_code == 0, r.output
		expected := if name == 'file-full.vbackup' { full } else if name == 'file-delta.vbackup' { delta } else if name in ['file-restored-full', 'file-boot-full'] { original } else { changed }
		actual := os.read_bytes(output + '/' + name)!; assert actual == expected, name
		sum := sha256.hexhash(actual.bytestr()); r2 := os.exec(['/opt/homebrew/opt/openssl@3/bin/openssl', 'dgst', '-sha256', output + '/' + name]); assert r2.exit_code == 0 && r2.output.trim_space().ends_with(sum), r2.output
		manifest += sum + '  ' + name + '\n'; os.chmod(output + '/' + name, 0o600)!
	}
	os.write_file(output + '/SHA256SUMS', manifest)!
	os.write_file(output + '/oracle.log', 'PASS independent7-file persisted full/delta archive and restored-version oracle, exact headers/records/body/content/base SHA-256, standard V/OpenSSL and reordered reboot\n')!
	println(os.read_file(output + '/oracle.log')!)
}
