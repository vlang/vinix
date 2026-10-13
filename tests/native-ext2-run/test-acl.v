// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import encoding.binary
import os
import sourcecommand
import xtcontroller

fn run() ! {
	if os.args.len != 2 || os.exists(os.args[1]) { return error('expected new evidence directory') }
	work := os.args[1]
	os.mkdir_all(work + '/seed')!
	os.write_file(work + '/seed/file', 'original ACL fixture\n')!
	os.mkdir(work + '/seed/directory')!
	disk := work + '/root.ext2'
	mut file := os.create(disk)!
	assert C.ftruncate(file.fd, 64 * 1024 * 1024) == 0
	file.close()
	tools := '/opt/homebrew/opt/e2fsprogs/sbin'
	xtcontroller.command([tools + '/mke2fs', '-q', '-F', '-t', 'ext2', '-b', '4096', '-I', '128',
		'-O',
		'filetype,sparse_super,^has_journal,^resize_inode,^dir_index,^extent,^64bit,^metadata_csum',
		'-d', work + '/seed', disk], os.environ())!
	assert xtcontroller.acl_value().hex() == '0200000001000600ffffffff02000400e803000004000000ffffffff10000400ffffffff20000000ffffffff'
	for path in ['/file', '/directory'] {
		value := work + '/acl.bin'
		xtcontroller.seed_acl(tools + '/debugfs', disk, path, value)!
		block := xtcontroller.acl_block(xtcontroller.output([tools + '/debugfs', '-R', 'stat ' + path,
			disk], os.environ())!)!
		mut image := os.open(disk)!
		image.seek(i64(block * 4096), .start)!
		mut before := []u8{len: 4096}
		assert image.read(mut before)! == before.len
		image.close()
		offset := xtcontroller.acl_offset(before)!
		assert binary.little_endian_u32_at(before, offset) == 1
		xtcontroller.corrupt_acl(tools + '/debugfs', disk, path, value)!
		image = os.open(disk)!
		image.seek(i64(block * 4096), .start)!
		mut after := []u8{len: 4096}
		assert image.read(mut after)! == after.len
		image.close()
		for index in offset .. offset + 4 { before[index] = 0 }
		assert after == before // Only the original on-disk ACL version changed.
	}
	for text in ['none', 'File ACL: 0', 'File ACL: x'] {
		mut failed := false
		xtcontroller.acl_block(text) or {
			failed = true
			u64(0)
		}
		assert failed
	}
	for raw in [[]u8{}, []u8{len: 35}, []u8{len: 4096}] {
		mut failed := false
		xtcontroller.acl_offset(raw) or {
			failed = true
			0
		}
		assert failed
	}
	assert xtcontroller.acl_block('File ACL: \t 123\n')! == 123
	result := sourcecommand.capture_full([tools + '/e2fsck', '-fn', disk], os.environ(), -1, 4 * 1024 * 1024, cachecli.cancelled)!
	assert result.status != 0 // The real host tools also detect the corruption.
	os.write_file(work + '/passed', 'PASS\n')!
	println('PASS actual file/directory ext2 ACL translation and exact four-byte corruption, independent e2fsck and malformed bounds')
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	run() or {
		eprintln(err)
		exit(1)
	}
}
