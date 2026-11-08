// SPDX-License-Identifier: GPL-2.0-or-later
// Inspect only disposable GUI-test disks with the fixed fixture credentials.
module main

import crypto.scrypt
import encoding.hex
import os
import powerpc.ext2

#include <unistd.h>
#include <fcntl.h>
fn C.open(&char, i32, ...voidptr) i32
fn C.pread(i32, voidptr, uint, i64) i64
fn C.close(i32) i32
__global account_check_fd i32

fn read_sector(lba u32, p &u8) bool { return C.pread(account_check_fd, p, 512, i64(lba) * 512) == 512 }
fn no_write(_ u32, _ &u8) bool { return false }
fn no_flush() bool { return false }

fn main() {
	if os.args.len != 2 { eprintln('Usage: accountcheck DISPOSABLE_GUI_TEST_DISK'); exit(2) }
	account_check_fd = unsafe { C.open(&char(os.args[1].str), C.O_RDONLY) }
	assert account_check_fd >= 0
	defer { C.close(account_check_fd) }
	mut volume := ext2.Volume{}
	assert volume.mount(ext2.Device{read: read_sector, write: no_write, flush: no_flush, sectors: u32(os.file_size(os.args[1]) / 512)})
	path := '/root/.vinix-user'
	id := volume.walk(path.str, u32(path.len), false)
	assert id > 0
	mut node := ext2.Node{}
	assert volume.inode(u32(id), mut node)
	assert node.mode() == 0x8180 && node.links() == 1 && ext2.le16(&node.raw[0], 2) == 0
	assert node.size() > 0 && node.size() < 1024
	mut bytes := []u8{len: int(node.size())}
	assert volume.read(u32(id), 0, bytes.data, node.size()) == bytes.len
	lines := bytes.bytestr().split_into_lines()
	assert lines.len == 8
	assert lines[..6] == ['version=1', 'name=76696e6978', 'kdf=scrypt', 'n=16384', 'r=8', 'p=1']
	salt := hex.decode(lines[6].all_after('salt=')) or { panic(err) }
	digest := hex.decode(lines[7].all_after('hash=')) or { panic(err) }
	assert salt.len == 16 && digest.len == 32
	actual := scrypt.scrypt('test123'.bytes(), salt, 16384, 8, 1, 32) or { panic(err) }
	assert actual == digest
	for folder in ['', '/Desktop', '/Documents', '/Downloads', '/Music', '/Pictures', '/Videos'] {
		p := '/root/home/vinix' + folder
		dir := volume.walk(p.str, u32(p.len), true)
		assert dir > 0 && volume.inode(u32(dir), mut node)
		assert node.mode() == if folder == '' { u32(0x41c0) } else { u32(0x41ed) }
	}
	println('PASS GUI account: private root-owned profile, scrypt verification, persistent home folders')
}
