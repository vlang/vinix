// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import powerpc.ext2

#include <unistd.h>
#include <fcntl.h>
fn C.open(&char, i32, ...voidptr) i32
fn C.pread(i32, voidptr, usize, i64) i64
fn C.pwrite(i32, voidptr, usize, i64) i64
fn C.fsync(i32) i32
fn C.close(i32) i32

__global fixture_disk_fd i32

fn read_sector(lba u32, p &u8) bool { return C.pread(fixture_disk_fd, p, 512, i64(lba) * 512) == 512 }
fn write_sector(lba u32, p &u8) bool { return C.pwrite(fixture_disk_fd, p, 512, i64(lba) * 512) == 512 }
fn flush_disk() bool { return C.fsync(fixture_disk_fd) == 0 }

fn main() {
	if os.args.len != 2 { eprintln('Usage: ext2host DISPOSABLE_EXT2_IMAGE'); exit(2) }
	fixture_disk_fd = unsafe { C.open(&char(os.args[1].str), C.O_RDWR) }
	assert fixture_disk_fd >= 0
	defer { C.close(fixture_disk_fd) }
	device := ext2.Device{read: read_sector, write: write_sector, flush: flush_disk, sectors: u32(os.file_size(os.args[1]) / 512)}
	mut volume := ext2.Volume{}
	assert volume.mount(device)
	mut super_before := [512]u8{}
	assert read_sector(2, &super_before[0])
	root := volume.walk(c'/root', 5, true)
	assert root > 0
	mut dir := ext2.Node{}
	assert volume.inode(u32(root), mut dir) && dir.mode() == 0x41c0
	newdir := volume.create(u32(root), c'persist', 7, 0x41c0)
	assert newdir > 0
	file := volume.create(u32(newdir), c'profile.new', 11, 0x8180)
	assert file > 0
	assert volume.create(u32(newdir), c'profile.new', 11, 0x8180) == -17
	mut bytes := []u8{len: 60 * 1024 + 7, init: u8(index * 19 + 3)}
	assert volume.write(u32(file), 0, bytes.data, u32(bytes.len)) == bytes.len
	assert volume.chmod(u32(file), 0o600) == 0
	assert volume.rename(u32(newdir), c'profile.new', 11, u32(newdir), c'profile', 7, false) == 0
	assert volume.sync()
	// Reopen all metadata and read across the direct/single-indirect boundary.
	assert volume.mount(device)
	assert volume.walk(c'/root/persist/profile', 21, true) == file
	mut result := []u8{len: bytes.len}
	assert volume.read(u32(file), 0, result.data, u32(result.len)) == result.len
	assert result == bytes
	assert volume.symlink(u32(root), c'link', 4, c'/root/persist', 13) == 0
	assert volume.walk(c'/root/link/profile', 18, true) == file
	assert volume.walk(c'/root/persist/profile/no', 24, true) == -20
	assert volume.symlink(u32(root), c'loop', 4, c'loop', 4) == 0
	assert volume.walk(c'/root/loop', 10, true) == -40
	assert volume.unlink(u32(root), c'loop', 4, false, false) == 0
	assert volume.write(u32(file), 1036 * 4096, c'x', 1) == -27
	// Replacing a different inode must preserve an open target until close.
	replaced := volume.create(u32(newdir), c'replaced', 8, 0x8180)
	assert replaced > 0
	assert volume.write(u32(replaced), 0, c'old', 3) == 3
	assert volume.symlink(u32(newdir), c'replacement', 11, c'profile', 7) == 0
	assert volume.rename(u32(newdir), c'replacement', 11, u32(newdir), c'replaced', 8, true) == 0
	assert volume.read(u32(replaced), 0, result.data, 3) == 3
	assert result[..3].bytestr() == 'old'
	assert volume.reap(u32(replaced))
	assert volume.walk(c'/root/persist/replaced', 22, true) == file
	assert volume.unlink(u32(newdir), c'replaced', 8, false, false) == 0
	assert volume.unlink(u32(root), c'persist', 7, true, false) == -39
	for i in 0 .. 60 {
		name := 'entry-${i}'
		id := volume.create(u32(newdir), name.str, u32(name.len), 0x8180)
		assert id > 0
		assert volume.write(u32(id), 5000, c'x', 1) == 1
		assert volume.truncate(u32(id)) == 0
		assert volume.unlink(u32(newdir), name.str, u32(name.len), false, false) == 0
	}
	assert volume.unlink(u32(newdir), c'profile', 7, false, true) == 0
	assert volume.read(u32(file), 0, result.data, u32(result.len)) == result.len
	assert volume.reap(u32(file))
	assert volume.unlink(u32(root), c'link', 4, false, false) == 0
	assert volume.unlink(u32(root), c'persist', 7, true, false) == 0
	assert volume.sync()
	assert volume.mount(device)
	assert volume.walk(c'/root/persist', 13, true) == -2
	mut super_after := [512]u8{}
	assert read_sector(2, &super_after[0])
	assert super_before[12..20] == super_after[12..20] // every block and inode reclaimed
	println('PASS ext2 host: creation, modes, indirect IO, rename, symlink, unlink-open, allocation reuse, remount')
}
